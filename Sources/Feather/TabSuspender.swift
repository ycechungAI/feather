import Foundation
import WebKit

/// Puts idle background tabs to sleep: their web view (and its WebContent process, often
/// 100–500 MB) is released, and history is restored when you switch back to the tab.
/// Under system memory pressure, all hidden tabs sleep immediately.
/// When Eco Memory mode is on, background tabs sleep after 30 seconds, memory caches trim,
/// and any awake tab whose WebContent process exceeds 500 MB switches to its mobile version.
final class TabSuspender {
    static let shared = TabSuspender()
    /// Idle limit for background tabs while Eco Memory mode is on (seconds).
    static let ecoSuspendAfter: TimeInterval = 30
    /// Any awake tab whose WebContent process exceeds 500 MB in Eco Mode switches to mobile.
    static let ecoMobileMemoryLimitBytes: UInt64 = 500_000_000

    private var timer: Timer?
    private var pressure: DispatchSourceMemoryPressure?

    func start() {
        scheduleTimer()
        NotificationCenter.default.addObserver(self, selector: #selector(settingsChanged),
                                               name: Settings.changed, object: nil)

        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler {
            MainActor.assumeIsolated { Self.sweep(force: true) }
        }
        source.resume()
        pressure = source
    }

    @objc private func settingsChanged() {
        scheduleTimer()
    }

    private func scheduleTimer() {
        timer?.invalidate()
        let interval: TimeInterval = Settings.ecoMemory ? 15 : 60
        let t = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            MainActor.assumeIsolated { Self.sweep(force: false) }
        }
        t.tolerance = Settings.ecoMemory ? 5 : 15
        timer = t
    }

    @MainActor
    static func sweep(force: Bool) {
        let eco = Settings.ecoMemory
        let limit = eco ? Self.ecoSuspendAfter : Settings.suspendAfter
        guard force || limit > 0 else { return }
        let now = Date()
        for tab in BrowserWindowController.all {
            tab.suspendIfIdle(now: now, after: force ? 0 : limit)
            if eco { tab.switchToMobileIfHeavy(limitBytes: Self.ecoMobileMemoryLimitBytes) }
        }
        if force || eco {
            WKWebsiteDataStore.default().removeData(ofTypes: [WKWebsiteDataTypeMemoryCache],
                                                    modifiedSince: .distantPast) {}
        }
    }
}
