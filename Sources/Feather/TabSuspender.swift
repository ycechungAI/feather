import Foundation

/// Puts idle background tabs to sleep: their web view (and its WebContent process, often
/// 100–500 MB) is released, and history is restored when you switch back to the tab.
/// Under system memory pressure, all hidden tabs sleep immediately.
final class TabSuspender {
    static let shared = TabSuspender()

    private var timer: Timer?
    private var pressure: DispatchSourceMemoryPressure?

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            MainActor.assumeIsolated { Self.sweep(force: false) }
        }
        timer?.tolerance = 15

        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler {
            MainActor.assumeIsolated { Self.sweep(force: true) }
        }
        source.resume()
        pressure = source
    }

    @MainActor
    private static func sweep(force: Bool) {
        let limit = Settings.suspendAfter
        guard force || limit > 0 else { return }
        let now = Date()
        for tab in BrowserWindowController.all {
            tab.suspendIfIdle(now: now, after: force ? 0 : limit)
        }
    }
}
