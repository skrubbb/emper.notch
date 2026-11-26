import AppKit
import Combine
import Sparkle

/// In-app updates through Sparkle. Emper itself probes the feed quietly (at launch and once a day) and only
/// shows a red dot. Nothing is downloaded or installed until the user clicks "Install Update…" in About;
/// Sparkle then downloads, checks the EdDSA signature against SUPublicEDKey in Info.plist, and relaunches.
@MainActor
final class UpdateChecker: NSObject, ObservableObject {
    static let shared = UpdateChecker()

    struct Release: Equatable {
        let version: String
    }

    enum Status: Equatable {
        case idle, checking, upToDate, failed(String)
    }

    /// Newer release than the running build, if one was found.
    @Published private(set) var available: Release?
    @Published private(set) var status: Status = .idle
    @Published private(set) var lastChecked: Date?

    private var controller: SPUStandardUpdaterController?
    private var timer: Timer?

    var current: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    private func updater() -> SPUUpdater {
        if let c = controller { return c.updater }
        // Sparkle's own scheduled checks are off (SUEnableAutomaticChecks NO in Info.plist); Emper probes itself.
        let c = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
        controller = c
        return c.updater
    }

    /// Called once at launch: a quiet check now, then every 24 hours. Always on (decision 2026-11-26).
    func start() {
        _ = updater()
        check()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 24 * 3600, repeats: true) { _ in
            Task { @MainActor in UpdateChecker.shared.check() }
        }
    }

    /// Quiet probe: reads the feed only, no window, no download.
    func check() {
        let u = updater()
        guard status != .checking, !u.sessionInProgress else { return }
        status = .checking
        u.checkForUpdateInformation()
    }

    /// User clicked "Install Update…" or "Check for Updates": Sparkle's own window takes over from here.
    func installOrCheck() {
        _ = updater()
        controller?.checkForUpdates(nil)
    }

    /// Local testing only: a feed on this Mac (http://localhost or 127.0.0.1) set with
    /// `defaults write com.skrubbb.emper updateFeedOverride <url>`. Anything else is ignored.
    nonisolated static func localFeedOverride() -> String? {
        guard let s = UserDefaults.standard.string(forKey: "updateFeedOverride"),
              let u = URL(string: s), u.scheme == "http" || u.scheme == "https",
              u.host == "localhost" || u.host == "127.0.0.1" else { return nil }
        return s
    }

    fileprivate func found(_ version: String?) {
        lastChecked = Date()
        available = version.map(Release.init(version:))
        status = .upToDate
    }

    fileprivate func failed(_ message: String) {
        lastChecked = Date()
        if status == .checking { status = .failed(message) }
    }
}

extension UpdateChecker: SPUUpdaterDelegate {
    nonisolated func feedURLString(for updater: SPUUpdater) -> String? {
        Self.localFeedOverride()
    }

    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let v = item.displayVersionString
        Task { @MainActor in UpdateChecker.shared.found(v) }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        Task { @MainActor in UpdateChecker.shared.found(nil) }
    }

    nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        // SUNoUpdateError (1001) is "no update", not a failure.
        let ns = error as NSError
        let m = ns.localizedDescription
        Task { @MainActor in
            if ns.code == 1001 { UpdateChecker.shared.found(nil) } else { UpdateChecker.shared.failed(m) }
        }
    }

    nonisolated func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        Task { @MainActor in
            let me = UpdateChecker.shared
            if me.status == .checking { me.status = error == nil ? .upToDate : .failed(error!.localizedDescription) }
        }
    }
}
