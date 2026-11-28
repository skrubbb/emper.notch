import AppKit
import ServiceManagement
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let selfTest: Bool
    let store: ConfigStore
    let dock = DockMonitor()
    private(set) lazy var islands = IslandManager(store: store, dock: dock, selfTest: selfTest)
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?

    init(selfTest: Bool) {
        self.selfTest = selfTest
        // Self-test writes to a temp file so it never touches the real settings.
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("emper-selftest-\(UUID().uuidString).json")
        // `--zones` works on a copy of the real settings (read-only diagnosis of hover areas).
        // `--bench <mode> --real` measures on a copy of the real settings (all the person's Empers).
        if CommandLine.arguments.contains("--zones") || CommandLine.arguments.contains("--real") {
            // EMPER_BENCH_CONFIG: bench a given settings file instead (bisecting a cost).
            let src = ProcessInfo.processInfo.environment["EMPER_BENCH_CONFIG"].map { URL(fileURLWithPath: $0) } ?? ConfigStore.defaultURL
            try? FileManager.default.copyItem(at: src, to: temp)
        }
        store = selfTest ? ConfigStore(url: temp) : ConfigStore()
        super.init()
    }

    /// Round 28: the Quick Note's last keys are written before quitting.
    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { QuickNote.shared.flush() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupMainMenu()
        IslandController.openSettings = { [weak self] in self?.openSettings() }
        IslandController.openAbout = { [weak self] in self?.openAbout() }
        IslandController.openEmperSettings = { [weak self] id, edge in
            guard let self else { return }
            self.store.settingsScreenID = id
            self.settingsNav.page = .islands
            self.settingsNav.edge = edge
            self.openSettings()
        }
        islands.start()
        if !selfTest && !CommandLine.arguments.contains(where: { ["--bench", "--render", "--zones"].contains($0) }) {
            UpdateChecker.shared.start()
        }
        if let i = CommandLine.arguments.firstIndex(of: "--bench") {
            // Idle cost check on a temp config: `--bench timer|music|both` keeps that live state on the idle island.
            SelfTest.bench(manager: islands, mode: CommandLine.arguments.count > i + 1 ? CommandLine.arguments[i + 1] : "timer")
        } else if let i = CommandLine.arguments.firstIndex(of: "--render"), CommandLine.arguments.count > i + 1 {
            let dir = URL(fileURLWithPath: CommandLine.arguments[i + 1])
            if CommandLine.arguments.count > i + 2, CommandLine.arguments[i + 2] == "music" {
                SelfTest.renderMusicCards(manager: islands, store: store, dock: dock, to: dir)
            } else {
                SelfTest.render(manager: islands, store: store, dock: dock, to: dir)
            }
        } else if CommandLine.arguments.contains("--zones") {
            SelfTest.dumpZones(manager: islands)
        } else if selfTest {
            SelfTest.run(manager: islands, store: store)
        } else if store.isFirstLaunch {
            // Launch at login is on by default; it can be turned off in Settings › General (a system
            // login item, so macOS may show its own "login item added" notice).
            try? SMAppService.mainApp.register()
            openSettings()
        }
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "Emper")
        let menu = NSMenu()
        let upd = NSMenuItem(title: "Update Available…", action: #selector(openAbout), keyEquivalent: "")
        upd.target = self
        upd.isHidden = true
        menu.addItem(upd)
        menu.addItem(withTitle: "Emper Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Emper", action: #selector(quit), keyEquivalent: "q").target = self
        item.menu = menu
        statusItem = item
        updateItem = upd
        updateSub = UpdateChecker.shared.$available.receive(on: RunLoop.main).sink { [weak self] r in
            self?.showUpdate(r)
        }
    }

    private var updateItem: NSMenuItem?
    private var updateSub: AnyCancellable?

    /// New release: a red dot on the menu bar icon and an "Update Available" item that opens About.
    private func showUpdate(_ r: UpdateChecker.Release?) {
        updateItem?.isHidden = r == nil
        if let r {
            let dot = NSAttributedString(string: "● ", attributes: [.foregroundColor: NSColor.systemRed])
            let t = NSMutableAttributedString(attributedString: dot)
            t.append(NSAttributedString(string: "Update Available: v\(r.version)…", attributes: [.font: NSFont.menuFont(ofSize: 0)]))
            updateItem?.attributedTitle = t
        }
        guard let base = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "Emper") else { return }
        guard r != nil else { statusItem?.button?.image = base; return }
        let size = NSSize(width: 18, height: 18)
        let img = NSImage(size: size, flipped: false) { rect in
            let tint = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor.white : NSColor.black
            let b = base.size
            let r0 = NSRect(x: (rect.width - b.width) / 2, y: (rect.height - b.height) / 2, width: b.width, height: b.height)
            let tinted = NSImage(size: b, flipped: false) { rr in
                base.draw(in: rr); tint.set(); rr.fill(using: .sourceAtop); return true
            }
            tinted.draw(in: r0)
            NSColor.systemRed.setFill()
            NSBezierPath(ovalIn: NSRect(x: rect.width - 7, y: rect.height - 7, width: 6, height: 6)).fill()
            return true
        }
        img.isTemplate = false
        img.accessibilityDescription = "Emper, update available"
        statusItem?.button?.image = img
    }

    @objc func openAbout() {
        settingsNav.page = .about
        openSettings()
    }

    /// Emper has no Dock icon, but the Settings window still needs an Edit menu: without one ⌘A / ⌘C /
    /// ⌘V / ⌘X / ⌘Z do nothing in its text fields.
    private func setupMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let app = NSMenu()
        app.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        app.addItem(withTitle: "Quit Emper", action: #selector(quit), keyEquivalent: "q").target = self
        appItem.submenu = app
        main.addItem(appItem)
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    /// Settings page choice, shared so a Emper's own button can jump to its page.
    let settingsNav = SettingsNav()

    @objc func openSettings() {
        if settingsWindow == nil {
            let host = NSHostingController(rootView: SettingsView(store: store, dock: dock, nav: settingsNav))
            let w = NSWindow(contentViewController: host)
            w.title = "Emper Settings"
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            // Dark, borderless-looking title bar: the near-black content runs under the window buttons.
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.appearance = NSAppearance(named: .darkAqua)
            w.backgroundColor = SK.windowNS
            w.setContentSize(NSSize(width: SK.windowWidth, height: 720))
            // Like System Settings: fixed width, only the height can change.
            w.contentMinSize = NSSize(width: SK.windowWidth, height: 560)
            w.contentMaxSize = NSSize(width: SK.windowWidth, height: .greatestFiniteMagnitude)
            w.standardWindowButton(.zoomButton)?.isEnabled = false
            w.isReleasedWhenClosed = false
            w.center()
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
