import AppKit
import CoreBluetooth
import EventKit
import ServiceManagement
import SwiftUI
import EmperCore

/// Settings pages, in sidebar order (About sits after a gap).
enum SettingsPage: String, CaseIterable, Identifiable, Hashable {
    case general, music, islands, permissions, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .music: "Music"
        case .islands: "Empers"
        case .permissions: "Permissions"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .music: "music.note"
        case .islands: "capsule.fill"
        case .permissions: "hand.raised.fill"
        case .about: "info"
        }
    }

    var color: Color {
        switch self {
        case .general: Color(white: 0.55)
        case .music: Color(red: 1, green: 0.216, blue: 0.373)
        case .islands: Color(red: 0.749, green: 0.353, blue: 0.949)
        case .permissions: Color(red: 0.039, green: 0.518, blue: 1)
        case .about: Color(red: 0.388, green: 0.388, blue: 0.4)
        }
    }

    /// Words the sidebar search matches, besides the title.
    var keywords: String {
        switch self {
        case .general: "factory reset defaults startup login full screen style notch island theme dark light system mission control screenshots folder bluetooth device battery connect"
        case .music: "lyrics idle audio spotify apple"
        case .islands: "display edge top left right bottom size width height position opacity radius hitbox hover delay layout style notch island gap home placeholders features tabs modules calculator clipboard timer stats shelf screenshots music quick note reminder"
        case .permissions: "privacy permission access revoke reset reminders automation spotify music files folders desktop bluetooth"
        case .about: "version updates update download links licence license gpl"
        }
    }
}

/// Sidebar and page choice (a class, like the rest of Emper's view state).
@MainActor
final class SettingsNav: ObservableObject {
    @Published var page: SettingsPage? = .general
    @Published var search = ""
    @Published var edge: IslandEdge = .top
}

/// Settings palette: near-black surfaces, one blue accent. The window is always dark, whatever the
/// island theme is (the island theme only changes the islands).
enum SK {
    /// Settings keeps one width like System Settings; only the height changes.
    static let windowWidth: CGFloat = 880
    static let window = Color(red: 0.039, green: 0.039, blue: 0.043)    // #0A0A0B
    static let sidebar = Color(red: 0.055, green: 0.055, blue: 0.063)   // #0E0E10
    static let card = Color(red: 0.078, green: 0.078, blue: 0.086)      // #141416
    static let field = Color.white.opacity(0.06)
    static let line = Color.white.opacity(0.07)
    static let text = Color.white.opacity(0.92)
    static let muted = Color.white.opacity(0.56)
    static let faint = Color.white.opacity(0.38)
    static let accent = Color(red: 0.039, green: 0.518, blue: 1)        // #0A84FF
    static let windowNS = NSColor(red: 0.039, green: 0.039, blue: 0.043, alpha: 1)
}

struct SettingsView: View {
    @ObservedObject var store: ConfigStore
    @ObservedObject var dock: DockMonitor
    @StateObject private var nav: SettingsNav

    init(store: ConfigStore, dock: DockMonitor, page: SettingsPage = .general, nav: SettingsNav? = nil) {
        self.store = store
        self.dock = dock
        let n = nav ?? SettingsNav()
        if nav == nil { n.page = page }
        _nav = StateObject(wrappedValue: n)
    }

    private var pages: [SettingsPage] {
        let q = nav.search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return SettingsPage.allCases }
        return SettingsPage.allCases.filter { ($0.title + " " + $0.keywords).lowercased().contains(q) }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(SK.line).frame(width: 1)
            detail
        }
        .background(SK.window)
        .environment(\.colorScheme, .dark)
        .tint(SK.accent)
        .frame(width: SK.windowWidth)
        .frame(minHeight: 560, idealHeight: 720)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(SK.faint)
                TextField("Search", text: $nav.search).textFieldStyle(.plain).font(.system(size: 12))
            }
            .padding(.horizontal, 9).frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(SK.field))
            .padding(.bottom, 10)
            ForEach(pages.filter { $0 != .about }) { p in SidebarRow(page: p, nav: nav) }
            Spacer()
            if pages.contains(.about) { SidebarRow(page: .about, nav: nav) }
        }
        .padding(.horizontal, 10)
        .padding(.top, 44)   // clears the window buttons
        .padding(.bottom, 12)
        .frame(width: 210)
        .background(SK.sidebar)
    }

    private var detail: some View {
        let page = nav.page ?? .general
        return VStack(alignment: .leading, spacing: 0) {
            Text(page.title)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(SK.text)
                .padding(.horizontal, 28)
                .padding(.top, 38)
                .padding(.bottom, 14)
            Group {
                switch page {
                case .general: GeneralPage(store: store)
                case .music: MusicPage(store: store)
                case .islands: IslandsPage(store: store, dock: dock, nav: nav)
                case .permissions: PermissionsPage()
                case .about: AboutPage()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(SK.window)
    }
}

private struct SidebarRow: View {
    let page: SettingsPage
    @ObservedObject var nav: SettingsNav
    @StateObject private var hover = HoverFlag()
    @ObservedObject private var updates = UpdateChecker.shared

    var body: some View {
        let on = (nav.page ?? .general) == page
        let badge = page == .about && updates.available != nil
        Button { nav.page = page } label: {
            HStack(spacing: 9) {
                Image(systemName: page.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(page.color))
                Text(page.title).font(.system(size: 13, weight: on ? .medium : .regular))
                    .foregroundStyle(on ? SK.text : SK.muted)
                Spacer(minLength: 0)
                if badge {
                    Circle().fill(Color.red).frame(width: 8, height: 8)
                        .accessibilityLabel("Update available")
                }
            }
            .padding(.horizontal, 6)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(on ? 0.08 : (hover.on ? 0.04 : 0))))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover.on = $0 }
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Shared page look: scrolling column of cards on the near-black window.
private struct Page<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) { content }
                .frame(maxWidth: 620, alignment: .leading)
                .padding(.horizontal, 28)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .toggleStyle(RowToggleStyle())
    }
}

/// A titled card. Its rows are split by hairlines; the footer sits under the card.
private struct Card<Content: View, Footer: View>: View {
    var title: String?
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title { SectionTitle(title).padding(.leading, 4) }
            _VariadicView.Tree(DividedRows()) { content }
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(SK.card))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(SK.line, lineWidth: 1))
            footer.padding(.horizontal, 4)
        }
    }
}

extension Card where Footer == EmptyView {
    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title: title, content: content, footer: { EmptyView() })
    }
}

extension Card {
    init(@ViewBuilder content: () -> Content, header: () -> SectionTitle, @ViewBuilder footer: () -> Footer) {
        self.init(title: header().title, content: content, footer: footer)
    }
}

private struct DividedRows: _VariadicView_MultiViewRoot {
    func body(children: _VariadicView.Children) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(children) { child in
                if child.id != children.first?.id {
                    Rectangle().fill(SK.line).frame(height: 1).padding(.leading, 14)
                }
                child
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
            }
        }
    }
}

/// Label on the left, control on the right.
private struct Row<Control: View>: View {
    let label: String
    @ViewBuilder var control: Control
    init(_ label: String, @ViewBuilder control: () -> Control) {
        self.label = label
        self.control = control()
    }
    var body: some View {
        HStack(spacing: 12) {
            Text(label).font(.system(size: 13)).foregroundStyle(SK.text)
            Spacer(minLength: 12)
            control
        }
    }
}

/// Settings switch: label left, small blue switch right.
private struct RowToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.label.font(.system(size: 13)).foregroundStyle(SK.text)
            Spacer(minLength: 12)
            EmperSwitch(isOn: configuration.$isOn)
        }
    }
}

/// Flat switch: blue when on, dim grey when off, whether or not the window is key.
struct EmperSwitch: View {
    @Binding var isOn: Bool
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule().fill(isOn ? SK.accent : Color.white.opacity(0.14))
            Circle().fill(Color.white).padding(2).shadow(color: .black.opacity(0.3), radius: 1, y: 0.5)
        }
        .frame(width: 34, height: 20)
        .opacity(enabled ? 1 : 0.4)
        .contentShape(Capsule())
        .onTapGesture { withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { isOn.toggle() } }
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

private func caption(_ s: String) -> some View {
    Text(s).font(.system(size: 11)).foregroundStyle(SK.muted)
        .fixedSize(horizontal: false, vertical: true)
        .lineSpacing(2)
}

// MARK: General

private struct GeneralPage: View {
    @ObservedObject var store: ConfigStore
    @StateObject private var login = LoginItem()
    @ObservedObject private var shelf = ScreenshotShelf.shared

    var body: some View {
        Page {
            Card("Startup") {
                Toggle("Launch at login", isOn: Binding(get: { login.enabled }, set: { login.set($0) }))
                if let e = login.error { caption(e) }
                Toggle("Show in full-screen apps", isOn: Binding(get: { store.config.showInFullScreen },
                                                                 set: { store.setShowInFullScreen($0) }))
            }
            Card("Appearance") {
                Row("Emper Styling") {
                    Picker("Emper Styling", selection: Binding(get: { store.config.style },
                                                       set: { v in store.setGlobal { $0.style = v } })) {
                        Text("Notch").tag(IslandStyle.notch)
                        Text("Island").tag(IslandStyle.island)
                    }
                    .segmentedRow(width: 180)
                }
                Row("Theme") {
                    Picker("Theme", selection: Binding(get: { store.config.theme },
                                                       set: { v in store.setGlobal { $0.theme = v } })) {
                        ForEach([IslandTheme.system, .dark, .light], id: \.self) { Text($0.name).tag($0) }
                    }
                    .segmentedRow(width: 220)
                }
            }
            Card("Mission Control") {
                Toggle("Hide Empers in Mission Control", isOn: Binding(
                    get: { store.config.hideInMissionControl },
                    set: { v in store.setGlobal { $0.hideInMissionControl = v } }))
            }
            Card("Bluetooth") {
                Toggle("Show when a Bluetooth device connects", isOn: Binding(get: { store.config.bluetoothToast },
                                                                              set: { v in store.setGlobal { $0.bluetoothToast = v } }))
            }
            Card {
                if shelf.needsAccess || shelf.denied {
                    HStack {
                        caption(shelf.denied ? "macOS blocked the \(shelf.folder.lastPathComponent) folder. Allow Emper in Privacy & Security › Files and Folders."
                                             : "The Screenshots tab needs access to the \(shelf.folder.lastPathComponent) folder. macOS asks once.")
                        Spacer()
                        Button(shelf.denied ? "Open Privacy Settings" : "Allow Access…") {
                            if shelf.denied { shelf.openPrivacySettings() } else { shelf.allowAccess() }
                        }
                        .controlSize(.small)
                    }
                }
                Toggle("Move new screenshots to a folder", isOn: Binding(
                    get: { store.config.screenshotFolder != nil },
                    set: { on in if on { chooseFolder() } else { store.setScreenshotFolder(nil) } }))
                if let path = store.config.screenshotFolder {
                    HStack {
                        Text((path as NSString).abbreviatingWithTildeInPath)
                            .lineLimit(1).truncationMode(.middle).foregroundStyle(SK.muted)
                        Spacer()
                        Button(ScreenshotShelf.systemFolder().lastPathComponent == "Desktop" ? "Reset to Desktop" : "Reset to macOS Folder") { store.setScreenshotFolder(nil) }
                            .controlSize(.small)
                            .help("Stop moving screenshots: they stay where macOS saves them (\((ScreenshotShelf.systemFolder().path as NSString).abbreviatingWithTildeInPath)).")
                        Button("Choose…") { chooseFolder() }.controlSize(.small)
                    }
                }
            } header: {
                SectionTitle("Screenshots")
            } footer: {
                caption("macOS keeps saving to \((ScreenshotShelf.systemFolder().path as NSString).abbreviatingWithTildeInPath); Emper moves each new screenshot from there while it runs. Your macOS setting is not changed, and older files are left alone.")
            }
            FactoryResetCard(store: store)
        }
    }

    private func chooseFolder() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.canCreateDirectories = true
        p.prompt = "Use Folder"
        p.message = "New screenshots will be moved here."
        if p.runModal() == .OK, let url = p.url { store.setScreenshotFolder(url.path) }
    }
}

/// Factory reset with two confirmations: an alert that says what happens, then a sheet where the
/// user types RESET. Nothing changes until the second step.
@MainActor
private final class ResetFlow: ObservableObject {
    @Published var step1 = false
    @Published var step2 = false
    @Published var typed = ""
    @Published var done: String?
}

private struct FactoryResetCard: View {
    @ObservedObject var store: ConfigStore
    @StateObject private var m = ResetFlow()

    var body: some View {
        Card("Reset") {
            Row("Factory Reset") {
                Button("Reset All Settings…", role: .destructive) { m.step1 = true }
                    .controlSize(.small)
            }
            if let d = m.done { caption(d) }
        }
        .alert("Reset all Emper settings?", isPresented: $m.step1) {
            Button("Cancel", role: .cancel) {}
            Button("Continue…", role: .destructive) { m.typed = ""; m.step2 = true }
        } message: {
            Text("Every Emper on every display, its size, position, tabs and options go back to defaults. Your Quick Note, screenshots and macOS permissions are kept.")
        }
        .sheet(isPresented: $m.step2) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Confirm factory reset").font(.headline)
                Text("Type RESET to confirm. This is step 2 of 2.")
                    .font(.callout).foregroundStyle(SK.muted)
                TextField("RESET", text: $m.typed).textFieldStyle(.roundedBorder)
                    .onSubmit { if m.typed == "RESET" { run() } }
                HStack {
                    Spacer()
                    Button("Cancel", role: .cancel) { m.step2 = false }.keyboardShortcut(.cancelAction)
                    Button("Reset", role: .destructive) { run() }
                        .disabled(m.typed != "RESET")
                }
            }
            .padding(20)
            .frame(width: 340)
        }
    }

    private func run() {
        m.step2 = false
        let b = store.factoryReset()
        m.done = b.map { "Settings reset. Backup: \(($0.path as NSString).abbreviatingWithTildeInPath)" } ?? "Settings reset."
    }
}

/// Launch at login through the system's login items (System Settings › General › Login Items).
@MainActor
private final class LoginItem: ObservableObject {
    @Published private(set) var enabled = SMAppService.mainApp.status == .enabled
    @Published private(set) var error: String?

    func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            error = nil
        } catch {
            self.error = "Could not change the login item: \(error.localizedDescription)"
        }
        enabled = SMAppService.mainApp.status == .enabled
        if SMAppService.mainApp.status == .requiresApproval {
            error = "Allow Emper in System Settings › General › Login Items."
        }
    }
}

// MARK: Music

/// Music › Players: where Emper reads the track from (0.1.3, replaces two switches).
private enum PlayerMode: CaseIterable, Hashable {
    case any, anyDirect, directOnly

    init(system: Bool, direct: Bool) {
        self = system ? (direct ? .anyDirect : .any) : (direct ? .directOnly : .any)
    }
    var system: Bool { self != .directOnly }
    var direct: Bool { self != .any }
    var title: String {
        switch self {
        case .any: "Any app"
        case .anyDirect: "Any app + direct control"
        case .directOnly: "Spotify & Apple Music only"
        }
    }
}

private struct MusicPage: View {
    @ObservedObject var store: ConfigStore

    var body: some View {
        Page {
            Card {
                Toggle("Show synced lyrics", isOn: Binding(get: { store.config.lyricsEnabled },
                                                           set: { store.setLyricsEnabled($0) }))
                Toggle("Lyric line in the idle Emper", isOn: Binding(get: { store.config.idleLyrics },
                                                                      set: { store.setIdleLyrics($0) }))
                    .disabled(!store.config.lyricsEnabled)
            } header: {
                SectionTitle("Lyrics")
            } footer: {
                caption("Lyrics come from lrclib.net, looked up by title and artist.")
            }
            Card {
                // 0.1.3 (Pang): one choice instead of two switches that overlapped (any app already covers
                // Spotify and Apple Music). Both off was never useful; it reads as "Any app".
                Row("Players") {
                    Picker("Players", selection: Binding<PlayerMode>(
                        get: { PlayerMode(system: store.config.systemAudio, direct: store.config.musicAppControl) },
                        set: { m in store.setGlobal { $0.systemAudio = m.system; $0.musicAppControl = m.direct } })) {
                        ForEach(PlayerMode.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.menu).labelsHidden().fixedSize()
                }
            } header: {
                SectionTitle("Players")
            } footer: {
                caption("Any app: browsers, Spotify, Apple Music and other players through macOS's Now Playing, no permission needed. Any app + direct control: the same, and Emper also talks to Spotify and Apple Music themselves for steadier controls. Spotify & Apple Music only: other players are ignored. Both direct options need Automation permission; macOS asks once for each player the first time it plays (Permissions › Automation). After a pause, the idle Emper keeps the play button for a minute.")
            }
        }
    }
}

// MARK: About

private struct AboutPage: View {
    @ObservedObject private var updates = UpdateChecker.shared

    private var version: String {
        let i = Bundle.main.infoDictionary
        let v = i?["CFBundleShortVersionString"] as? String ?? "dev"
        let b = i?["CFBundleVersion"] as? String
        return b.map { "Version \(v) (\($0))" } ?? "Version \(v)"
    }

    private var logo: NSImage? {
        Bundle.main.url(forResource: "emper-symbol", withExtension: "png").flatMap { NSImage(contentsOf: $0) }
            ?? NSApp.applicationIconImage
    }

    var body: some View {
        Page {
            Card {
                VStack(spacing: 8) {
                    if let logo {
                        Image(nsImage: logo).resizable().interpolation(.high)
                            .frame(width: 96, height: 96)
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                    Text("Emper").font(.title2.weight(.bold))
                    Text(version).font(.callout).foregroundStyle(SK.muted)
                    if let r = updates.available {
                        HStack(spacing: 6) {
                            Circle().fill(Color.red).frame(width: 8, height: 8)
                            Text("Update available").font(.callout.weight(.medium))
                        }
                        .padding(.top, 4)
                        .help("Version \(r.version)")
                        Button("Install Update…") { updates.installOrCheck() }
                            .buttonStyle(.borderedProminent)
                    } else {
                        Button(updates.status == .checking ? "Checking…" : "Check for Updates") { updates.installOrCheck() }
                            .buttonStyle(.borderedProminent)
                            .disabled(updates.status == .checking)
                        if let t = statusText { caption(t) }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            Card("What's new") {
                ForEach(Changelog.recent, id: \.version) { r in
                    ChangelogRow(release: r, current: r.version == updates.current)
                }
            }
            Card("Links") {
                LinkRow(title: "Licence", detail: "GPL-3.0")
                LinkRow(title: "Source code", detail: "github.com/skrubbb/emper.notch",
                        url: URL(string: "https://github.com/skrubbb/emper.notch"))
            }
        }
    }
}

extension AboutPage {
    /// 0.1.3: status only, no explanations.
    fileprivate var statusText: String? {
        switch updates.status {
        case .idle, .checking: return nil
        case .upToDate: return "Emper is up to date"
        case .failed: return "Couldn't check for updates"
        }
    }
}

/// One release in About › What's new: version row that folds open to its changes. The running version
/// starts open.
private struct ChangelogRow: View {
    let release: Changelog.Release
    let current: Bool
    @StateObject private var fold = FoldState()

    var body: some View {
        let isOpen = fold.open ?? current
        VStack(alignment: .leading, spacing: 8) {
            Button { withAnimation(.easeOut(duration: 0.18)) { fold.open = !isOpen } } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                        .foregroundStyle(SK.muted)
                    Text("Version \(release.version)").foregroundStyle(SK.text)
                    if current {
                        Text("Installed").font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Capsule().fill(SK.line))
                            .foregroundStyle(SK.muted)
                    }
                    Spacer()
                    Text(release.date).font(.system(size: 11)).foregroundStyle(SK.muted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if isOpen {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(release.changes, id: \.self) { c in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("•").foregroundStyle(SK.muted)
                            Text(c).font(.system(size: 12)).foregroundStyle(SK.text)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.leading, 18)
                .transition(.opacity)
            }
        }
    }
}

private final class FoldState: ObservableObject {
    @Published var open: Bool?
}

private struct LinkRow: View {
    let title: String
    let detail: String
    var url: URL? = nil
    var body: some View {
        HStack {
            Text(title).foregroundStyle(SK.text)
            Spacer()
            if let url {
                Button(detail) { NSWorkspace.shared.open(url) }.buttonStyle(.link)
            } else {
                Text(detail).foregroundStyle(SK.muted)
            }
        }
    }
}

// MARK: Shared header (display cards + edge)

private struct DisplayEdgeHeader: View {
    @ObservedObject var store: ConfigStore
    @ObservedObject var dock: DockMonitor
    @ObservedObject var nav: SettingsNav
    var edges: [IslandEdge] = IslandEdge.allCases

    var body: some View {
        VStack(spacing: 12) {
            if NSScreen.screens.count > 1 {
                HStack(spacing: 12) {
                    ForEach(NSScreen.screens, id: \.emperID) { s in
                        DisplayCard(screen: s, selected: s.emperID == store.settingsScreenID) {
                            store.settingsScreenID = s.emperID
                        }
                    }
                }
            }
            Picker("Edge", selection: $nav.edge) {
                ForEach(edges) { e in Text(e.settingsName).tag(e) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            HStack {
                HStack(spacing: 8) {
                    EmperSwitch(isOn: $store.holdExpanded)
                    Text("Keep Empers open (for tuning)").font(.system(size: 12)).foregroundStyle(SK.muted)
                }
                Spacer()
                Text("Dock: " + dock.info.edge.rawValue.capitalized + (dock.info.autohide ? ", auto-hide" : ""))
                    .font(.system(size: 11)).foregroundStyle(SK.faint)
            }
        }
        .frame(maxWidth: 620)
        .padding(.horizontal, 28)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { if !edges.contains(nav.edge) { nav.edge = edges.first ?? .top } }
    }
}

private struct DisplayCard: View {
    let screen: NSScreen
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                let f = screen.frame
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.accentColor.opacity(0.25))
                    .aspectRatio(f.width / max(f.height, 1), contentMode: .fit)
                    .frame(height: 40)
                Text(screen.localizedName).font(.caption).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 92)
            .background(RoundedRectangle(cornerRadius: 10).fill(SK.card))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .strokeBorder(selected ? SK.accent : SK.line, lineWidth: selected ? 2 : 1))
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor).padding(6)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Bindings into one edge of the display chosen in Settings.
@MainActor
private struct EdgeBinder {
    let store: ConfigStore
    let screen: NSScreen
    let edge: IslandEdge

    var config: IslandConfig { store.display(for: screen)[edge] }

    func bind<T>(_ kp: WritableKeyPath<IslandConfig, T>) -> Binding<T> {
        Binding(get: { store.display(for: screen)[edge][keyPath: kp] },
                set: { v in store.update(screen, edge) { $0[keyPath: kp] = v } })
    }

    /// 0.1.3 (Pang): the Hitbox rows show the area itself, so a smaller number is a smaller area.
    /// Stored as the old trims (`hoverInset` per side, `hoverInsetFar` on the inner edge), measured on the
    /// idle Emper; a live (wider/deeper) idle keeps the same trims.
    func hitLength(style: IslandStyle) -> (value: Binding<Double>, max: Double) {
        let c = config
        let flare = style == .island ? 0 : IslandConfig.notchFlare
        let full = max((c.edge.isVertical ? c.collapsedHeight : c.collapsedWidth) - 2 * flare, 8)
        let v = Binding<Double>(
            get: { max(full - 2 * store.display(for: screen)[edge].hoverInset, 8) },
            set: { n in
                store.update(screen, edge) { $0.hoverInset = max((full - min(max(n, 8), full)) / 2, 0) }
                store.flashHitbox(screen, edge)
            })
        return (v, full)
    }

    func hitDepth() -> (value: Binding<Double>, max: Double) {
        let c = config
        let full = max(c.edge.isVertical ? c.collapsedWidth : c.collapsedHeight, 4)
        let v = Binding<Double>(
            get: { max(full - store.display(for: screen)[edge].hoverInsetFar, 4) },
            set: { n in
                store.update(screen, edge) { $0.hoverInsetFar = full - min(max(n, 4), full) }
                store.flashHitbox(screen, edge)
            })
        return (v, full)
    }

    /// Same as `bind`, and flashes the hover zone on screen.
    func bindFlash(_ kp: WritableKeyPath<IslandConfig, Double>) -> Binding<Double> {
        Binding(get: { store.display(for: screen)[edge][keyPath: kp] },
                set: { v in
                    store.update(screen, edge) { $0[keyPath: kp] = v }
                    store.flashHitbox(screen, edge)
                })
    }
}

@MainActor private func selectedScreen(_ store: ConfigStore) -> NSScreen? {
    NSScreen.screens.first { $0.emperID == store.settingsScreenID } ?? NSScreen.screens.first
}

// MARK: Islands

private struct IslandsPage: View {
    @ObservedObject var store: ConfigStore
    @ObservedObject var dock: DockMonitor
    @ObservedObject var nav: SettingsNav

    var body: some View {
        VStack(spacing: 0) {
            DisplayEdgeHeader(store: store, dock: dock, nav: nav)
            if let screen = selectedScreen(store) {
                EdgePage(store: store, b: EdgeBinder(store: store, screen: screen, edge: nav.edge), dockEdge: dock.info.edge)
            }
        }
    }
}

/// One Emper: look, layout, Home, tabs, size, hitbox and timing in a single page.
private struct EdgePage: View {
    @ObservedObject var store: ConfigStore
    let b: EdgeBinder
    let dockEdge: IslandEdge
    @StateObject private var side = SideChoice()

    var body: some View {
        let cfg = b.config
        let edge = b.edge
        let dockHere = edge == dockEdge
        let along = edge.isVertical ? b.screen.frame.height : b.screen.frame.width
        let twoSides = edge == .bottom && cfg.bottomLayout == .twoSides
        let right = twoSides && side.right
        let style = cfg.styleChoice.resolve(store.config.style)
        let behindNotch = edge == .top && b.screen.notchSize != nil
        Page {
            Card {
                Toggle("Enable", isOn: b.bind(\.enabled)).disabled(dockHere && edge != .bottom)
                if dockHere {
                    caption(edge == .bottom
                        ? "The Dock is at the bottom. A centred Emper stays on but can't open while the Dock covers it (it works when the Dock hides automatically). 1 side or 2 sides sit beside the Dock."
                        : "The Dock is on this side, so this Emper is off.")
                }
            } header: {
                SectionTitle(edge.settingsName)
            } footer: {
                EmptyView()
            }
            if cfg.enabled, !dockHere || edge == .bottom {
                Card {
                    Row("Emper Styling") {
                        Picker("Emper Styling", selection: b.bind(\.styleChoice)) {
                            Text("General").tag(StyleChoice.general)
                            Text("Notch").tag(StyleChoice.notch)
                            Text("Island").tag(StyleChoice.island)
                        }
                        .segmentedRow(width: 240)
                    }
                    NumberRow(label: "Gap from edge", value: b.bind(\.islandGap), range: 0...60, unit: "pt")
                        .disabled(style == .notch)
                        .opacity(style == .notch ? 0.4 : 1)
                    if behindNotch {
                        // Round 23: this screen's built-in notch hides the centre; choose where the lyric goes.
                        Row("Idle lyric") {
                            Picker("Idle lyric", selection: b.bind(\.notchLyrics)) {
                                Text("General").tag(NotchLyrics.general)
                                Text("Under the notch").tag(NotchLyrics.below)
                            }
                            .segmentedRow(width: 240)
                        }
                    }
                } header: {
                    SectionTitle("Appearance")
                } footer: {
                    caption(style == .notch
                        ? "General follows the styling in General (now \(store.config.style == .notch ? "Notch" : "Island")). Gap from edge is for Island styling only."
                        : behindNotch
                            ? "Gap from edge is how far the island floats from the top. Under about 38 pt the island still wraps the notch and its content stays below it."
                            : "General follows the styling in General. Gap from edge is how far the island floats from the screen edge.")
                }
                if edge == .bottom {
                    Card("Layout") {
                        Row("Layout") {
                            Picker("Layout", selection: b.bind(\.bottomLayout)) {
                                Text("Centre").tag(BottomLayout.center)
                                Text("1 side").tag(BottomLayout.oneSide)
                                Text("2 sides").tag(BottomLayout.twoSides)
                            }
                            .segmentedRow(width: 240)
                        }
                        if cfg.bottomLayout == .oneSide {
                            Row("Side") {
                                Picker("Side", selection: b.bind(\.bottomSide)) {
                                    Text("Left").tag(IslandAnchor.leading)
                                    Text("Right").tag(IslandAnchor.trailing)
                                }
                                .segmentedRow(width: 160)
                            }
                        }
                        if twoSides {
                            Row("Edit features of") {
                                Picker("Edit features of", selection: $side.right) {
                                    Text("Left Emper").tag(false)
                                    Text("Right Emper").tag(true)
                                }
                                .segmentedRow(width: 200)
                            }
                        }
                        if cfg.bottomLayout != .center, dockEdge == .bottom {
                            caption("The Dock is at the bottom: side Empers sit beside it. Keep the idle width small so they don't overlap the Dock.")
                        }
                        if twoSides {
                            caption("Both sides share size, styling and Home on/off. Home placeholders and tabs are set per side.")
                        }
                    }
                }
                // Round 23: Home on every edge; left/right stack the placeholders in a column.
                Group {
                    Card {
                        Toggle("Home", isOn: b.bind(\.homeEnabled))
                        if cfg.homeEnabled {
                            HomeSlotsEditor(slots: right ? b.bind(\.rightHomeSlots) : b.bind(\.homeSlots),
                                            main: right ? b.bind(\.rightHomeMain) : b.bind(\.homeMain))
                        }
                    } header: {
                        SectionTitle("Home")
                    } footer: {
                        caption(cfg.homeEnabled
                            ? (edge.isVertical
                               ? "The Emper opens on Home: placeholders stacked top to bottom. The pencil in the Emper edits them too."
                               : "The Emper opens on Home and shows these placeholders right away. The pencil in the Emper edits them too.")
                            : "Off: the Emper opens on its first tab.")
                    }
                }
                Card {
                    ForEach(IslandConfig.features, id: \.self) { id in
                        if let d = ModuleRegistry.descriptor(id) {
                            Toggle(isOn: tabBinding(id, right: right)) { Label(d.name, systemImage: d.symbol) }
                        }
                    }
                } header: {
                    SectionTitle("Tabs")
                } footer: {
                    caption("Each switch adds the feature as a tab. Reorder tabs with the pencil in the Emper. Music shows in the idle Emper while it plays when Music is a tab or a Home placeholder.")
                }
                Card {
                    NumberRow(label: edge.isVertical ? "Idle length" : "Idle width",
                              value: b.bind(edge.isVertical ? \.collapsedHeight : \.collapsedWidth),
                              range: 2...Double(maxIdleLength(cfg)), unit: "pt")
                    NumberRow(label: edge.isVertical ? "Idle thickness" : "Idle height",
                              value: b.bind(edge.isVertical ? \.collapsedWidth : \.collapsedHeight), range: 2...200, unit: "pt")
                    NumberRow(label: "Position (from centre)", value: b.bind(\.offset),
                              range: Double(-along / 2)...Double(along / 2), unit: "pt")
                    NumberRow(label: "Idle opacity", value: b.bind(\.idleOpacity), range: 0...1, unit: "%", scale: 100)
                    NumberRow(label: "Corner radius", value: b.bind(\.cornerRadius), range: 0...40, unit: "pt")
                } header: {
                    SectionTitle("Size & Position")
                } footer: {
                    caption("The idle Emper can be at most as long as the open Emper.")
                }
                Card {
                    let len = b.hitLength(style: style), dep = b.hitDepth()
                    NumberRow(label: edge.isVertical ? "Height" : "Width", value: len.value, range: 8...len.max, unit: "pt")
                    NumberRow(label: "Depth", value: dep.value, range: 4...dep.max, unit: "pt")
                } header: {
                    SectionTitle("Hitbox")
                } footer: {
                    caption("Size of the area that opens the Emper, measured on the idle Emper: smaller numbers, smaller area. Depth is how far it reaches from the screen edge; the side touching the screen edge always counts. The green box on screen shows the area while you change these." + (behindNotch ? " Behind the built-in notch the box is hidden: a small depth opens only from the very top." : ""))
                }
                Card("Hover Timing") {
                    NumberRow(label: "Open delay", value: b.bind(\.openDelayMs), range: 0...1000, unit: "ms", step: 10)
                    NumberRow(label: "Close delay", value: b.bind(\.closeDelayMs), range: 0...1500, unit: "ms", step: 10)
                }
                Card {
                    Button("Reset \(edge.settingsName)") { store.reset(b.screen, edge) }
                }
            }
        }
    }

    /// Tab switch for one feature; the right bottom Emper keeps its own list.
    private func tabBinding(_ id: String, right: Bool) -> Binding<Bool> {
        Binding(get: { right ? b.config.rightModuleIDs.contains(id) : b.config.hasTab(id) },
                set: { v in
                    b.store.update(b.screen, b.edge) { c in
                        guard right else { c.setTab(id, v); return }
                        var t = c
                        t.moduleIDs = c.rightModuleIDs
                        t.setTab(id, v)
                        c.rightModuleIDs = t.moduleIDs
                    }
                })
    }

    /// Open island length along the edge, measured as if the idle island were tiny.
    private func maxIdleLength(_ c: IslandConfig) -> CGFloat {
        var t = c
        if c.edge.isVertical { t.collapsedHeight = 2 } else { t.collapsedWidth = 2 }
        let s = IslandGeometry.expandedSize(content: ModuleRegistry.single(t), config: t, tabBar: true,
                                            clearance: c.edge == .top ? (b.screen.notchSize?.height ?? 0) : 0)
        return c.edge.isVertical ? s.height : s.width
    }
}

@MainActor
private final class SideChoice: ObservableObject {
    @Published var right = false
}

// MARK: Controls

/// Label column, native slider, typed number field and stepper; all clamp to the range. ↑/↓ in the field
/// step by one unit (Shift: ten). `scale` shows a stored value in other units (0…1 stored, 0…100 % shown).
private struct NumberRow: View {
    let label: String
    let value: Binding<Double>
    let range: ClosedRange<Double>
    var unit = ""
    var scale: Double = 1
    var step: Double = 1

    var body: some View {
        let lo = range.lowerBound * scale, hi = range.upperBound * scale
        let shown = Binding<Double>(
            get: { (value.wrappedValue * scale).rounded() },
            set: { value.wrappedValue = min(max($0, lo), hi) / scale })
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label).font(.system(size: 13)).foregroundStyle(SK.text)
                Spacer()
                // Value badge (monospaced, editable; ↑/↓ nudge, ⇧ for ×10).
                HStack(spacing: 2) {
                    TextField("", value: shown, format: .number.precision(.fractionLength(0)))
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 40)
                        .onKeyPress(.upArrow, phases: .down) { press in
                            shown.wrappedValue += press.modifiers.contains(.shift) ? step * 10 : step
                            return .handled
                        }
                        .onKeyPress(.downArrow, phases: .down) { press in
                            shown.wrappedValue -= press.modifiers.contains(.shift) ? step * 10 : step
                            return .handled
                        }
                    if !unit.isEmpty { Text(unit).foregroundStyle(SK.muted) }
                }
                .font(.system(size: 12, design: .monospaced))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 7).fill(SK.field))
            }
            EmperSlider(value: shown, range: lo...hi)
        }
        .padding(.vertical, 1)
    }
}

/// Wide slider in the Emper settings style: a tall rounded track, a lighter filled part and a
/// rounded-rectangle knob. Click or drag anywhere on the track.
struct EmperSlider: View {
    let value: Binding<Double>
    let range: ClosedRange<Double>

    var body: some View {
        GeometryReader { g in
            let span = max(range.upperBound - range.lowerBound, 0.0001)
            let f = CGFloat((value.wrappedValue - range.lowerBound) / span).clamped01
            let knobW: CGFloat = 16
            let x = (g.size.width - knobW) * f
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 5, style: .continuous).fill(SK.field)
                RoundedRectangle(cornerRadius: 5, style: .continuous).fill(SK.accent.opacity(0.35))
                    .frame(width: x + knobW / 2)
                RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color(white: 0.9))
                    .frame(width: knobW, height: 12)
                    .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
                    .offset(x: x)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                let t = Double(((v.location.x - knobW / 2) / max(g.size.width - knobW, 1)).clamped01)
                value.wrappedValue = (range.lowerBound + t * span).rounded()
            })
        }
        .frame(height: 16)
    }
}

/// Section header in the Emper settings style: small uppercase tracked label.
struct SectionTitle: View {
    let title: String
    init(_ t: String) { title = t }
    var body: some View {
        Text(title.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(1.2)
            .foregroundStyle(SK.faint)
            .accessibilityAddTraits(.isHeader)
    }
}

private extension CGFloat {
    var clamped01: CGFloat { Swift.min(Swift.max(self, 0), 1) }
}

/// Home placeholders: count plus what each one shows (the pencil in the island does the same).
private struct HomeSlotsEditor: View {
    let slots: Binding<[String]>
    let main: Binding<Int?>

    /// Round 28: sides are free. One more goes on the side with fewer placeholders (right on a tie); one
    /// less comes off the outer end of the side with more.
    private func setCount(_ n: Int, _ v: [String], _ m: Int) {
        if n > v.count {
            let a = HomeLayout.adding(v, main: m, left: m < v.count - 1 - m)
            main.wrappedValue = a.main; slots.wrappedValue = a.slots
        } else if n < v.count {
            let a = HomeLayout.removing(v, main: m, at: m > v.count - 1 - m ? 0 : v.count - 1)
            main.wrappedValue = a.main; slots.wrappedValue = a.slots
        }
    }

    var body: some View {
        let v = slots.wrappedValue
        let m = HomeLayout.mainIndex(count: v.count, main: main.wrappedValue)
        Row("Placeholders") {
            HStack(spacing: 8) {
                Text("\(v.count)").font(.system(size: 12, design: .monospaced)).foregroundStyle(SK.text)
                    .frame(minWidth: 26).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 6).fill(SK.field))
                Stepper("Placeholders", value: Binding(get: { v.count }, set: { setCount($0, v, m) }),
                        in: 1...HomeLayout.maxSlots).labelsHidden()
            }
        }
        ForEach(Array(v.enumerated()), id: \.offset) { i, w in
            let name = i == m ? "Main" : (i < m ? "Left \(m - i)" : "Right \(i - m)")
            Row(name) {
            Picker(name, selection: Binding(
                get: { w },
                set: { new in
                    var s = slots.wrappedValue
                    // One placeholder per feature: taking it elsewhere empties its old spot.
                    if !new.isEmpty, let old = s.firstIndex(of: new) { s[old] = "" }
                    s[i] = new
                    slots.wrappedValue = s
                })) {
                ForEach(HomeLayout.widgets + [""], id: \.self) { id in
                    let d = ModuleRegistry.descriptor(id)
                    Label(d?.name ?? "Empty", systemImage: d?.symbol ?? "square.dashed").tag(id)
                }
            }
            .pickerStyle(.menu).labelsHidden().fixedSize()
            }
        }
    }
}

private extension View {
    /// Segmented picker sized for the right side of a row.
    func segmentedRow(width: CGFloat) -> some View {
        pickerStyle(.segmented).labelsHidden().frame(width: width)
    }
}

// MARK: Permissions (round 29)

/// One macOS permission Emper uses.
private struct PermissionItem: Identifiable {
    let id: String
    let name: String
    let use: String
    /// tccutil service names cleared by Reset.
    let services: [String]
    /// x-apple.systempreferences anchor.
    let pane: String
}

@MainActor
private final class PermissionsState: ObservableObject {
    @Published var status: [String: String] = [:]
    @Published var armed: String?
    @Published var note: [String: String] = [:]
    private var disarm: DispatchWorkItem?

    /// Reminders belongs to a feature hidden in this release.
    static var items: [PermissionItem] { all.filter { $0.id != "reminders" || ModuleRegistry.showExperimental } }
    private static let all: [PermissionItem] = [
        PermissionItem(id: "reminders", name: "Reminders", use: "Adds reminders from the Reminder placeholder.",
                       services: ["Reminders"], pane: "Privacy_Reminders"),
        PermissionItem(id: "automation", name: "Automation (Spotify, Music)", use: "Reads and controls what is playing.",
                       services: ["AppleEvents"], pane: "Privacy_Automation"),
        PermissionItem(id: "files", name: "Files and Folders", use: "Lists screenshots in a protected folder (Desktop, Documents, Downloads).",
                       services: ["SystemPolicyDesktopFolder", "SystemPolicyDocumentsFolder", "SystemPolicyDownloadsFolder"],
                       pane: "Privacy_FilesAndFolders"),
        PermissionItem(id: "bluetooth", name: "Bluetooth", use: "Shows a notice when a device connects.",
                       services: ["BluetoothAlways"], pane: "Privacy_Bluetooth"),
    ]

    func refresh() {
        var s: [String: String] = [:]
        s["reminders"] = switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess: "Allowed"
        case .writeOnly: "Add only"
        case .denied: "Denied"
        case .restricted: "Restricted"
        case .notDetermined: "Not asked yet"
        @unknown default: "Unknown"
        }
        s["automation"] = ["com.spotify.client": "Spotify", "com.apple.Music": "Music"]
            .sorted { $0.value > $1.value }
            .map { "\($0.value): \(Self.automation($0.key))" }.joined(separator: " · ")
        let shelf = ScreenshotShelf.shared
        let folders = [ScreenshotShelf.systemFolder()] + (shelf.destination.map { [$0] } ?? [])
        s["files"] = !folders.contains(where: ScreenshotShelf.isProtected) ? "Not needed (folder isn't protected)"
            : shelf.denied ? "Denied" : shelf.needsAccess ? "Not asked yet" : "Allowed"
        s["bluetooth"] = switch CBManager.authorization {
        case .allowedAlways: "Allowed"
        case .denied: "Denied"
        case .restricted: "Restricted"
        case .notDetermined: "Not asked yet"
        @unknown default: "Unknown"
        }
        status = s
    }

    /// Never asks: only reads the answer macOS has for that app (needs the app running).
    private static func automation(_ bundle: String) -> String {
        guard NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first != nil else { return "app not running" }
        var desc = NSAppleEventDescriptor(bundleIdentifier: bundle).aeDesc!.pointee
        let r = AEDeterminePermissionToAutomateTarget(&desc, typeWildCard, typeWildCard, false)
        switch r {
        case noErr: return "Allowed"
        case OSStatus(errAEEventNotPermitted): return "Denied"
        case OSStatus(errAEEventWouldRequireUserConsent): return "Not asked yet"
        default: return "Unknown"
        }
    }

    /// 0.1.3: "Allow" shows macOS's own prompt right away. macOS only prompts while the answer is
    /// "Not asked yet"; after Denied, System Settings is the only way back (Open).
    private var bluetooth: CBCentralManager?

    func canAsk(_ item: PermissionItem) -> Bool {
        guard let st = status[item.id] else { return false }
        return st.contains("Not asked yet")
    }

    func request(_ item: PermissionItem) {
        switch item.id {
        case "reminders":
            Task { @MainActor in
                _ = try? await EKEventStore().requestFullAccessToReminders()
                self.refresh()
            }
        case "automation":
            let running = ["com.spotify.client", "com.apple.Music"].filter {
                NSRunningApplication.runningApplications(withBundleIdentifier: $0).first != nil
            }
            guard !running.isEmpty else {
                note[item.id] = "Open Spotify or Music first, then click Allow."
                return
            }
            note[item.id] = nil
            DispatchQueue.global(qos: .userInitiated).async {
                // Blocks until the user answers macOS's prompt.
                for b in running {
                    var desc = NSAppleEventDescriptor(bundleIdentifier: b).aeDesc!.pointee
                    _ = AEDeterminePermissionToAutomateTarget(&desc, typeWildCard, typeWildCard, true)
                }
                DispatchQueue.main.async { MainActor.assumeIsolated { self.refresh() } }
            }
        case "files":
            let shelf = ScreenshotShelf.shared
            let folders = ([ScreenshotShelf.systemFolder()] + (shelf.destination.map { [$0] } ?? []))
                .filter(ScreenshotShelf.isProtected)
            shelf.allowAccess()
            DispatchQueue.global(qos: .userInitiated).async {
                // Listing a protected folder is what makes macOS ask.
                for f in folders { _ = try? FileManager.default.contentsOfDirectory(atPath: f.path) }
                DispatchQueue.main.async { MainActor.assumeIsolated { self.refresh() } }
            }
        case "bluetooth":
            // Creating a manager asks; it is dropped again once macOS has an answer.
            bluetooth = CBCentralManager(delegate: nil, queue: nil, options: [CBCentralManagerOptionShowPowerAlertKey: false])
            pollBluetooth(tries: 60)
        default:
            open(item)
        }
    }

    private func pollBluetooth(tries: Int) {
        refresh()
        guard tries > 0, CBManager.authorization == .notDetermined else { bluetooth = nil; return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            MainActor.assumeIsolated { self?.pollBluetooth(tries: tries - 1) }
        }
    }

    func open(_ item: PermissionItem) {
        if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(item.pane)") { NSWorkspace.shared.open(u) }
    }

    /// Two clicks: the first arms (3 s), the second clears Emper's answer so macOS asks again.
    func reset(_ item: PermissionItem) {
        disarm?.cancel()
        guard armed == item.id else {
            armed = item.id
            let w = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.armed = nil } }
            disarm = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: w)
            return
        }
        armed = nil
        let id = Bundle.main.bundleIdentifier ?? "com.skrubbb.emper"
        var failed: [String] = []
        for service in item.services {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            p.arguments = ["reset", service, id]
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            do { try p.run(); p.waitUntilExit() } catch { failed.append(service); continue }
            if p.terminationStatus != 0 { failed.append(service) }
        }
        note[item.id] = failed.isEmpty
            ? "Reset. macOS asks again the next time Emper needs it (some take effect after Emper restarts)."
            : "macOS refused the reset. Turn it off in System Settings instead."
        refresh()
    }
}

private struct PermissionsPage: View {
    @StateObject private var state = PermissionsState()

    var body: some View {
        Page {
            Card {
                ForEach(PermissionsState.items) { item in row(item) }
            } header: {
                SectionTitle("Privacy")
            } footer: {
                caption("Allow shows macOS's prompt here. Once a permission is denied, macOS only lets you change it in System Settings (Open). Reset makes macOS ask again.")
            }
        }
        .onAppear { state.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in state.refresh() }
    }

    private func row(_ item: PermissionItem) -> some View {
        let st = state.status[item.id] ?? "…"
        let good = st.hasPrefix("Allowed") || st.hasPrefix("Not needed")
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name).font(.system(size: 13)).foregroundStyle(SK.text)
                    Text(item.use).font(.system(size: 11)).foregroundStyle(SK.muted)
                }
                Spacer(minLength: 8)
                Text(st).font(.system(size: 11, weight: .medium))
                    .foregroundStyle(good ? Color(nsColor: .systemGreen) : SK.muted)
                    .lineLimit(2).multilineTextAlignment(.trailing)
                if state.canAsk(item) {
                    Button("Allow") { state.request(item) }.controlSize(.small)
                        .buttonStyle(.borderedProminent)
                        .help("macOS asks right here")
                } else {
                    Button("Open") { state.open(item) }.controlSize(.small)
                        .help("Open this permission in System Settings")
                }
                Button(state.armed == item.id ? "Reset?" : "Reset") { state.reset(item) }
                    .controlSize(.small)
                    .tint(state.armed == item.id ? .red : nil)
                    .help("Clear Emper's answer so macOS asks again")
            }
            if let n = state.note[item.id] { caption(n) }
        }
    }
}
