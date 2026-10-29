import AppKit
import WebKit

/// One download, live or from the saved list.
final class DownloadItem {
    enum State: String, Codable { case active, finished, failed, cancelled }

    let id: UUID
    var filename: String
    var destination: URL?
    var source: URL?
    var date: Date
    var state: State
    var totalBytes: Int64
    var isPrivate = false
    var download: WKDownload? // held only while the download runs
    var progressObservation: NSKeyValueObservation?
    /// For saved video streams, which Feather downloads itself instead of WebKit.
    var streamProgress: Progress?
    var cancelStream: (() -> Void)?

    init(id: UUID = UUID(), filename: String, destination: URL? = nil, source: URL?, date: Date = Date(),
         state: State = .active, totalBytes: Int64 = 0) {
        self.id = id
        self.filename = filename
        self.destination = destination
        self.source = source
        self.date = date
        self.state = state
        self.totalBytes = totalBytes
    }

    var progress: Progress? { download?.progress ?? streamProgress }

    struct Record: Codable {
        var id: UUID
        var filename: String
        var destination: URL?
        var source: URL?
        var date: Date
        var state: State
        var totalBytes: Int64
    }

    var record: Record {
        Record(id: id, filename: filename, destination: destination, source: source, date: date,
               state: state, totalBytes: totalBytes)
    }

    convenience init(_ r: Record) {
        self.init(id: r.id, filename: r.filename, destination: r.destination, source: r.source, date: r.date,
                  state: r.state == .active ? .failed : r.state, totalBytes: r.totalBytes)
    }
}

/// Saves downloads to ~/Downloads and keeps the list shown in Window ▸ Downloads (⌥⌘L).
/// Files are quarantined (LSFileQuarantineEnabled in Info.plist), so Gatekeeper checks anything
/// you later open. Downloads from private windows are never written to the saved list.
final class Downloads: NSObject, WKDownloadDelegate {
    static let shared = Downloads()
    static let changed = Notification.Name("FeatherDownloadsChanged")
    private static let limit = 50

    private(set) var items: [DownloadItem] = []
    private let file = Settings.supportDirectory.appendingPathComponent("downloads.json")
    private var lastProgressPost = Date.distantPast

    var hasActive: Bool { items.contains { $0.state == .active } }

    private override init() {
        super.init()
        if let data = try? Data(contentsOf: file),
           let saved = try? JSONDecoder().decode([DownloadItem.Record].self, from: data) {
            items = saved.map(DownloadItem.init)
        }
    }

    /// Called when a navigation turns into a download.
    func track(_ download: WKDownload, isPrivate: Bool) {
        download.delegate = self
        let source = download.originalRequest?.url
        let item = DownloadItem(filename: source?.lastPathComponent ?? "Download", source: source)
        item.isPrivate = isPrivate
        item.download = download
        item.progressObservation = download.progress.observe(\.fractionCompleted) { [weak self] _, _ in
            DispatchQueue.main.async { self?.progressChanged() }
        }
        items.insert(item, at: 0)
        changed()
    }

    /// A video stream saved by StreamDownloader.
    func trackStream(filename: String, destination: URL, source: URL, progress: Progress, isPrivate: Bool,
                     cancel: @escaping () -> Void) -> DownloadItem {
        let item = DownloadItem(filename: filename, destination: destination, source: source)
        item.isPrivate = isPrivate
        item.streamProgress = progress
        item.cancelStream = cancel
        items.insert(item, at: 0)
        changed()
        return item
    }

    func finishStream(_ item: DownloadItem) {
        item.streamProgress = nil
        item.cancelStream = nil
        item.state = .finished
        if let url = item.destination,
           let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize { item.totalBytes = Int64(size) }
        if let url = item.destination {
            DistributedNotificationCenter.default().post(name: .init("com.apple.DownloadFileFinished"), object: url.path)
        }
        changed()
    }

    /// A stream that stopped early keeps the part already saved.
    func endStream(_ item: DownloadItem, cancelled: Bool, error: Error) {
        guard item.state == .active || cancelled else { return }
        item.streamProgress = nil
        item.cancelStream = nil
        item.state = cancelled ? .cancelled : .failed
        if !cancelled { NSLog("Feather: stream download failed: \(error.localizedDescription)") }
        changed()
    }

    private func item(for download: WKDownload) -> DownloadItem? {
        items.first { $0.download === download }
    }

    /// Progress fires constantly; the list only needs a few updates a second.
    func progressChanged() {
        let now = Date()
        guard now.timeIntervalSince(lastProgressPost) > 0.25 else { return }
        lastProgressPost = now
        NotificationCenter.default.post(name: Self.changed, object: nil)
    }

    // MARK: WKDownloadDelegate

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let url = Self.uniqueURL(in: folder, for: suggestedFilename)
        if let item = item(for: download) {
            item.filename = url.lastPathComponent
            item.destination = url
            item.totalBytes = max(response.expectedContentLength, 0)
            changed()
        }
        completionHandler(url)
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let item = item(for: download) else { return }
        item.state = .finished
        item.progressObservation = nil
        item.download = nil
        if let url = item.destination {
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize { item.totalBytes = Int64(size) }
            // Bounces the Downloads stack in the Dock, like Safari.
            DistributedNotificationCenter.default().post(name: .init("com.apple.DownloadFileFinished"),
                                                         object: url.path)
        }
        changed()
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        guard let item = item(for: download) else { return }
        let cancelled = (error as NSError).code == NSURLErrorCancelled
        item.state = cancelled ? .cancelled : .failed
        item.progressObservation = nil
        item.download = nil
        NSLog("Feather: download failed: \(error.localizedDescription)")
        changed()
    }

    // MARK: Actions

    func cancel(_ item: DownloadItem) {
        guard item.state == .active else { return }
        item.download?.cancel { _ in }
        item.download = nil
        item.cancelStream?()
        item.cancelStream = nil
        item.streamProgress = nil
        item.progressObservation = nil
        item.state = .cancelled
        changed()
    }

    func remove(_ item: DownloadItem) {
        guard item.state != .active else { return }
        items.removeAll { $0 === item }
        changed()
    }

    /// Removes finished, failed and cancelled entries (the files stay on disk).
    func clearList() {
        items.removeAll { $0.state != .active }
        changed()
    }

    func reveal(_ item: DownloadItem) {
        guard let url = item.destination, FileManager.default.fileExists(atPath: url.path) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func open(_ item: DownloadItem) {
        guard item.state == .finished, let url = item.destination,
              FileManager.default.fileExists(atPath: url.path) else { return }
        NSWorkspace.shared.open(url)
    }

    private func changed() {
        if items.count > Self.limit {
            let excess = items.enumerated().filter { $0.offset >= Self.limit && $0.element.state != .active }
            let drop = Set(excess.map { ObjectIdentifier($0.element) })
            items.removeAll { drop.contains(ObjectIdentifier($0)) }
        }
        let saved = items.filter { !$0.isPrivate && $0.state != .active }.map(\.record)
        if let data = try? JSONEncoder().encode(saved) { try? data.write(to: file, options: .atomic) }
        NotificationCenter.default.post(name: Self.changed, object: nil)
    }

    static func uniqueURL(in folder: URL, for suggestedFilename: String) -> URL {
        var name = (suggestedFilename as NSString).lastPathComponent
        if name.isEmpty || name == "." || name == ".." { name = "Download" }
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var url = folder.appendingPathComponent(name)
        var n = 1
        while FileManager.default.fileExists(atPath: url.path) {
            let candidate = ext.isEmpty ? "\(base) (\(n))" : "\(base) (\(n)).\(ext)"
            url = folder.appendingPathComponent(candidate)
            n += 1
        }
        return url
    }
}
