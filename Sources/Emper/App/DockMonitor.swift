import AppKit
import Combine
import EmperCore

/// Reads (never writes) the Dock position. Polls every 2 s because macOS posts no public
/// notification when the Dock moves.
@MainActor
final class DockMonitor: ObservableObject {
    @Published private(set) var info: DockInfo
    private var timer: Timer?

    init() {
        info = Self.read()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func refresh() {
        let new = Self.read()
        if new != info { info = new }
    }

    static func read() -> DockInfo {
        let domain = "com.apple.dock" as CFString
        CFPreferencesAppSynchronize(domain)
        let o = CFPreferencesCopyAppValue("orientation" as CFString, domain) as? String
        let a = CFPreferencesCopyAppValue("autohide" as CFString, domain) as? Bool
        return DockInfo.parse(orientation: o, autohide: a)
    }
}
