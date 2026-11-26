import AppKit
import Combine
import EmperCore

/// Loads/saves ~/Library/Application Support/Emper/config.json. Config is per display UUID.
@MainActor
final class ConfigStore: ObservableObject {
    @Published private(set) var config: EmperConfig
    /// Transient (not saved): keep islands open while tuning in Settings.
    @Published var holdExpanded = false
    /// Transient: monitor picked in Settings.
    @Published var settingsScreenID = NSScreen.main?.emperID ?? ""
    /// Transient: which edge sections are unfolded in Settings.
    @Published var unfoldedEdges: Set<IslandEdge> = [.top]
    /// Transient: "displayID|edge" whose hover zone is drawn on screen while a margin is tuned.
    @Published private(set) var hitboxKey: String?
    private var hitboxWork: DispatchWorkItem?
    let isFirstLaunch: Bool
    private let url: URL
    private var pendingSave: DispatchWorkItem?

    nonisolated static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Emper/config.json")
    }

    init(url: URL = ConfigStore.defaultURL) {
        self.url = url
        if let data = try? Data(contentsOf: url),
           let c = try? JSONDecoder().decode(EmperConfig.self, from: data),
           c.version >= EmperConfig.oldestMigratable {
            var m = c.migrated()
            if c.version < 5 {
                // v5: a built-in notch screen's top Emper takes the notch look (round 15).
                for screen in NSScreen.screens where screen.notchSize != nil {
                    m.displays[screen.emperID]?.islands[.top]?.styleChoice = .notch
                }
            }
            if c.version < 6 {
                // v6: a notched top Emper starts flush with the screen top (gap 0) like the built-in notch;
                // only the untouched default gap is changed (round 17).
                for screen in NSScreen.screens where screen.notchSize != nil {
                    if m.displays[screen.emperID]?.islands[.top]?.islandGap == 6 { m.displays[screen.emperID]?.islands[.top]?.islandGap = 0 }
                }
            }
            config = m
            isFirstLaunch = false
        } else {
            config = EmperConfig()
            isFirstLaunch = true
        }
    }

    /// Stored config for a screen, or fresh defaults (sized to the notch or menu bar).
    func display(for screen: NSScreen) -> DisplayConfig {
        config.displays[screen.emperID] ?? DisplayConfig.defaults(notch: screen.notchSize, menuBarHeight: screen.menuBarHeight,
                                                                 isMain: screen == NSScreen.screens.first)
    }

    func update(_ screen: NSScreen, _ edge: IslandEdge, _ change: (inout IslandConfig) -> Void) {
        var d = display(for: screen)
        var i = d[edge]
        change(&i)
        d[edge] = i
        config.displays[screen.emperID] = d
        scheduleSave()
    }

    func reset(_ screen: NSScreen, _ edge: IslandEdge) {
        let enabled = display(for: screen)[edge].enabled
        update(screen, edge) {
            $0 = IslandConfig.defaults(for: edge, notch: screen.notchSize, menuBarHeight: screen.menuBarHeight)
            $0.enabled = enabled
        }
    }

    func setLyricsEnabled(_ on: Bool) {
        config.lyricsEnabled = on
        scheduleSave()
    }

    /// Draw this island's idle hover zone for a couple of seconds (called while a margin changes).
    func flashHitbox(_ screen: NSScreen, _ edge: IslandEdge) {
        let k = "\(screen.emperID)|\(edge.rawValue)"
        if hitboxKey != k { hitboxKey = k }
        hitboxWork?.cancel()
        let w = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.hitboxKey = nil } }
        hitboxWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: w)
    }

    func setShowInFullScreen(_ on: Bool) {
        config.showInFullScreen = on
        scheduleSave()
    }

    func setScreenshotFolder(_ path: String?) {
        config.screenshotFolder = path
        scheduleSave()
    }

    /// App-wide setting change (toggles in General).
    func setGlobal(_ change: (inout EmperConfig) -> Void) {
        change(&config)
        scheduleSave()
    }

    /// Factory reset: every Emper setting back to defaults. The old file is kept next to it as
    /// config.backup-<date>.json. The Quick Note text, screenshots and macOS permissions are not touched.
    @discardableResult
    func factoryReset() -> URL? {
        pendingSave?.cancel()
        var backup: URL?
        if FileManager.default.fileExists(atPath: url.path) {
            let f = DateFormatter()
            f.dateFormat = "yyyyMMdd-HHmmss"
            let b = url.deletingLastPathComponent().appendingPathComponent("config.backup-\(f.string(from: Date())).json")
            if (try? FileManager.default.copyItem(at: url, to: b)) != nil {
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: b.path)
                backup = b
            }
        }
        config = EmperConfig()
        holdExpanded = false
        unfoldedEdges = [.top]
        scheduleSave()
        return backup
    }

    func setIdleLyrics(_ on: Bool) {
        config.idleLyrics = on
        scheduleSave()
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        let snapshot = config, url = url
        let work = DispatchWorkItem {
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                let enc = JSONEncoder()
                enc.outputFormatting = [.prettyPrinted, .sortedKeys]
                try enc.encode(snapshot).write(to: url, options: .atomic)
                // Owner-only (0600): settings stay private to this account.
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            } catch {
                NSLog("Emper: could not save config: \(error)")
            }
        }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }
}
