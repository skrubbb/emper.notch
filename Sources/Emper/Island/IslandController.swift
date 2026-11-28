import AppKit
import Combine
import SwiftUI
import EmperCore

struct ModuleEntry: Identifiable {
    let id: String
    let name: String
    let symbol: String
    let view: AnyView
    /// Side-placeholder view (nil = a tile that opens the full view in the main placeholder).
    var compact: AnyView? = nil
}

/// Short notice in the idle island (Bluetooth device connected).
struct IslandToast: Equatable {
    let id = UUID()
    let symbol: String
    let title: String
    /// 0...1, nil when macOS does not report it.
    let battery: Double?
}

/// Observable state the SwiftUI island view renders.
@MainActor
final class IslandModel: ObservableObject {
    @Published var config: IslandConfig
    @Published var isExpanded = false
    /// Music is playing and this island has music detection on.
    @Published var isLive = false
    @Published var tabs: [ModuleEntry] = []
    @Published var selectedID = ""
    /// Target size of the island shape; the view springs towards it.
    @Published var size: CGSize = .zero
    /// Screen frame of the panel window, so the view can place the island along the edge.
    @Published var panelFrame: CGRect = .null
    /// Width of the lyric line shown inside the live activity (nil = no lyric).
    @Published var lyricWidth: CGFloat?
    /// Round 24: the pointer is on the lyric strip under a built-in notch: the strip fades away so it
    /// never opens the Emper by accident and clicks reach what is behind it.
    @Published var lyricHidden = false
    /// Lyric width as drawn (nil while the strip is hidden by hover).
    var shownLyricWidth: CGFloat? { lyricHidden ? nil : lyricWidth }
    /// Round 25: under the notch the current line is empty (instrumental). The pill keeps its place and fades.
    @Published var lyricEmpty = false
    /// Round 25: the under-notch pill is drawn (hover and empty lines only fade it; the size never changes).
    var lyricPillVisible: Bool { lyricWidth != nil && !lyricHidden && !lyricEmpty }
    /// Set by the controller: this top Emper draws its idle lyric under the built-in notch.
    @Published var lyricsBelow = false
    /// Physical notch height above the content (0 = none).
    @Published var clearance: CGFloat = 0
    /// Idle hover zone in view coordinates (origin top-left), drawn while a margin is being tuned.
    @Published var hitbox: CGRect?
    /// Pencil mode: placeholders on the Home row can be dragged and changed.
    @Published var editingHome = false
    /// Round 27: pencil mode on Home keeps room past both ends so the "+" buttons stay on screen.
    var addSlotReach: CGFloat {
        isExpanded && editingHome && selectedID == ModuleRegistry.homeID ? IslandGeometry.addSlotReach : 0
    }
    /// Pencil mode: the "add a tab" picker is open over the content.
    @Published var addingTab = false
    /// Bumped on every open, so Home's placeholders replay their entrance even when reopened mid-fade.
    @Published var openCount = 0
    /// Bumped on every collapse: replays the idle content's settle bounce.
    @Published var closeCount = 0
    /// Features as they were when the pencil was pressed, for Cancel.
    var editStart: IslandConfig?
    /// Bottom Emper keeps its idle length: an active timer takes the idle spot instead of joining the music.
    var compactTimer: Bool { timerLive && config.edge == .bottom }
    /// Music live activity shown idle (not while the bottom timer has the spot).
    var showsLive: Bool { isLive && !compactTimer }
    /// Music and timer side by side in the idle Emper.
    var dualIdle: Bool { isLive && timerLive && !config.edge.isVertical && !compactTimer }

    func beginEdit() { editStart = config; editingHome = true }
    func finishEdit() { editStart = nil; editingHome = false; addingTab = false }
    /// Puts the tabs and Home placeholders back as they were before the pencil.
    func cancelEdit() {
        if let s = editStart {
            onEditConfig { c in
                c.moduleIDs = s.moduleIDs
                c.homeSlots = s.homeSlots
                c.homeScales = s.homeScales
                c.homeSizes = s.homeSizes
            }
        }
        finishEdit()
    }
    /// Pointer inside the open island (for hover in views); separate object so moves only redraw those views.
    let pointer = PointerState()
    var onSelect: (String) -> Void = { _ in }
    /// Saves a new Home placeholder layout.
    var onHomeSlots: ([String], Int?) -> Void = { _, _ in }
    func onHomeSlots(_ slots: [String]) { onHomeSlots(slots, nil) }
    /// Applies any change to this island's saved config (Home menu: move a feature between tab and Home).
    var onEditConfig: ((inout IslandConfig) -> Void) -> Void = { _ in }
    /// Round 24: a change shown live (resize drag) without saving it; `onEditConfig` saves the final one.
    var onPreviewConfig: ((inout IslandConfig) -> Void) -> Void = { _ in }
    /// Round 26: Emper button in the tab bar: Settings › Empers on this Emper's screen and side.
    var onOpenEmperSettings: () -> Void = {}
    /// Every feature on this island (tabs and Home placeholders), by id.
    @Published var features: [String: ModuleEntry] = [:]
    @Published var toast: IslandToast?
    /// Files are being dragged over this island.
    @Published var dropTargeted = false
    /// Timer running/paused and this island has the timer: idle island shows the B-tide strip
    /// (beside the music live activity when both are on).
    @Published var timerLive = false
    /// Full-screen app on this display: thin idle line, no idle activity.
    @Published var isCompact = false

    /// Feature that gets typing: the selected tab, or on Home the calculator wherever it sits.
    var keyFeature: String {
        if selectedID != ModuleRegistry.homeID { return selectedID }
        let s = config.homeSlots
        if s.contains(ModuleRegistry.calculatorID) { return ModuleRegistry.calculatorID }
        return s[config.homeMainIndex]
    }

    init(config: IslandConfig) { self.config = config }
}

/// One island: one panel + its module instances. Hover is decided geometrically from the pointer
/// position, so even a fully transparent idle island responds.
@MainActor
final class IslandController {
    /// Set by the app: opens the Settings window (gear button in the open island).
    static var openSettings: () -> Void = {}
    /// Set by the app: opens Settings › About (gear button while an update is waiting).
    static var openAbout: () -> Void = {}
    /// Set by the app: opens Settings › Empers on a screen (emperID) and side.
    static var openEmperSettings: (String, IslandEdge) -> Void = { _, _ in }

    var closeDelay: TimeInterval { model.config.closeDelayMs / 1000 }
    var openDelay: TimeInterval { model.config.openDelayMs / 1000 }

    let model: IslandModel
    let panel: IslandPanel
    private var instances: [String: any IslandModule] = [:]
    private(set) var tabIDs: [String] = []
    private var area: CGRect
    private var hold: Bool
    private var collapseWork: DispatchWorkItem?
    private var openWork: DispatchWorkItem?
    private var showHitbox = false
    /// Set by the manager: applies a change to this island's saved config.
    var onEdit: ((inout IslandConfig) -> Void) -> Void = { _ in }
    private var bag = Set<AnyCancellable>()

    init(config: IslandConfig, area: CGRect, clearance: CGFloat, hold: Bool) {
        self.area = area
        self.hold = hold
        model = IslandModel(config: config)
        model.clearance = clearance
        panel = IslandPanel(frame: CGRect(x: area.midX, y: area.midY, width: 10, height: 10))
        let host = FirstClickHostingView(rootView: IslandRootView(model: model))
        panel.contentView = host
        model.onSelect = { [weak self] in self?.select($0) }
        model.onHomeSlots = { [weak self] slots, main in
            self?.model.onEditConfig { $0.setHomeSlots(slots, main: main) }
        }
        model.onEditConfig = { [weak self] change in
            guard let self else { return }
            change(&self.model.config)
            self.onEdit(change)
            self.rebuild()
        }
        model.onPreviewConfig = { [weak self] change in
            guard let self else { return }
            // No animation: the row and the Emper follow the pointer frame by frame.
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) {
                change(&self.model.config)
                self.rebuild()
            }
        }
        model.isLive = liveNow
        rebuild()
        panel.orderFrontRegardless()
        setExpanded(hold)
        host.onMouseDown = { [weak self] in
            guard let self else { return }
            // Round 28: a click elsewhere in the Emper ends typing in a text box (a box click starts it again).
            TextOverlay.shared.end(in: self.panel)
            TimeEntry.shared.end()
            if self.model.keyFeature == ModuleRegistry.calculatorID { KeyCatcher.shared.take(for: self) }
        }

        NowPlaying.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.musicChanged() }
            .store(in: &bag)
        TimerService.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.timerChanged() }
            .store(in: &bag)
    }

    /// Idle strip for an active timer, on islands that carry the timer (also beside live music).
    private func timerChanged() {
        let has = slotIDs.contains(ModuleRegistry.timerID) || tabIDs.contains(ModuleRegistry.timerID)
        let live = has && TimerService.shared.isActive && !model.config.edge.isVertical && !compact
        if live != model.timerLive {
            model.timerLive = live
            refreshSize()
        }
    }

    func update(config: IslandConfig, area: CGRect, clearance: CGFloat, hold: Bool,
                fullScreen: Bool = true, showHitbox: Bool = false, dockCovered: Bool = false) {
        let lyricPlaceChanged = config.notchLyrics != model.config.notchLyrics
        if config != model.config { model.config = config }
        if dockCovered != self.dockCovered {
            self.dockCovered = dockCovered
            // Under the Dock (drawn behind it) while the Dock covers it; above everything otherwise.
            panel.level = dockCovered
                ? NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) - 1)
                : NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
            if dockCovered, model.isExpanded, !hold { setExpanded(false) }
        }
        if clearance != model.clearance { model.clearance = clearance }
        self.area = area
        panel.showsInFullScreen = fullScreen
        self.showHitbox = showHitbox
        rebuild()
        if lyricPlaceChanged { musicChanged() }
        if hold != self.hold {
            self.hold = hold
            setExpanded(hold)
        }
    }

    // MARK: Modules & size

    /// Live while playing, and for `pauseGrace` after a pause so the idle play button can resume it.
    private var liveNow: Bool {
        let np = NowPlaying.shared
        // 0.1.3: any top/bottom Emper with Music as a tab or a Home placeholder (the separate "Show music
        // while it plays" switch is gone); never the side ones.
        let c = model.config
        guard !compact, !c.edge.isVertical, np.hasTrack, showsMusic else { return false }
        if np.isPlaying { return true }
        return pausedAt.map { Date().timeIntervalSince($0) < Self.pauseGrace } ?? false
    }
    static let pauseGrace: TimeInterval = 60
    private var pausedAt: Date?
    private var wasPlaying = false
    private var graceWork: DispatchWorkItem?

    /// Top/bottom islands open on Home (music lives in a placeholder there); side islands keep a Music tab.
    private var usesHome: Bool {
        // Round 23: every edge can use Home (left/right lay it out as a column); off by default on the sides.
        // Home off but no tab to show: keep Home, or the Emper could never open (round 15 bug).
        let tabs = model.config.moduleIDs.contains { ModuleRegistry.descriptor($0) != nil && $0 != ModuleRegistry.homeID }
        return model.config.homeEnabled || !tabs
    }
    /// Music is a tab, or a placeholder on the Home this Emper opens on.
    private var showsMusic: Bool {
        model.config.moduleIDs.contains(ModuleRegistry.musicID)
            || (usesHome && model.config.homeSlots.contains(ModuleRegistry.musicID))
    }
    /// Tab that shows the music: Home when music has a placeholder, else its own tab.
    private var musicTab: String? {
        if usesHome, model.config.homeSlots.contains(ModuleRegistry.musicID) { return ModuleRegistry.homeID }
        return tabIDs.contains(ModuleRegistry.musicID) ? ModuleRegistry.musicID : nil
    }
    private var slotIDs: [String] = []

    private func rebuild() {
        let np = NowPlaying.shared
        var seen = Set<String>()
        let slots = usesHome ? model.config.homeSlots.filter { !$0.isEmpty && ModuleRegistry.descriptor($0) != nil } : []
        var ids = model.config.moduleIDs.filter {
            ModuleRegistry.descriptor($0) != nil && $0 != ModuleRegistry.homeID && seen.insert($0).inserted
        }
        if usesHome { ids.insert(ModuleRegistry.homeID, at: 0) }
        if ids != tabIDs || slots != slotIDs {
            let needed = Set(ids + slots)
            for (id, m) in instances where !needed.contains(id) {
                m.stop()
                instances[id] = nil
            }
            var all: [String: ModuleEntry] = [:]
            for id in needed {
                guard let d = ModuleRegistry.descriptor(id) else { continue }
                let m = instances[id] ?? d.make()
                instances[id] = m
                all[id] = model.features[id] ?? ModuleEntry(id: id, name: d.name, symbol: d.symbol, view: m.makeView(), compact: m.makeCompactView())
            }
            model.features = all
            model.tabs = ids.compactMap { all[$0] }
            tabIDs = ids
            slotIDs = slots
            if !ids.contains(model.selectedID) { model.selectedID = ids.first ?? "" }
            if ids.isEmpty, model.isExpanded { setExpanded(false) }
        }
        let f = IslandGeometry.panelFrame(for: model.config, maxSize: maxSize, in: area)
        if panel.frame != f { panel.setFrame(f, display: true) }
        if model.panelFrame != f { model.panelFrame = f }
        refreshSize()
        timerChanged()
    }

    func musicChanged() {
        rebuild()
        let np = NowPlaying.shared
        if np.isPlaying != wasPlaying {
            wasPlaying = np.isPlaying
            graceWork?.cancel()
            pausedAt = np.isPlaying ? nil : Date()
            if !np.isPlaying {
                let w = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.musicChanged() } }
                graceWork = w
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.pauseGrace + 0.1, execute: w)
            }
        }
        let live = liveNow
        let line = np.currentLyric.trimmingCharacters(in: .whitespaces)
        let empty = lyricsBelow && line.isEmpty
        let lyric: CGFloat? = lyricsBelow
            // Round 25: the pill keeps its place (last width) on an empty line and only fades, so the Emper
            // never jumps when an instrumental part starts or ends.
            ? (live && np.lyricsEnabled && !np.lyrics.isEmpty
               ? (empty ? (model.lyricWidth ?? 1) : LyricMetrics.width(np.currentLyric, small: true)) : nil)
            : (live && np.showsIdleLyrics && IslandGeometry.supportsInlineLyrics(model.config) ? LyricMetrics.width(np.currentLyric) : nil)
        if model.lyricsBelow != lyricsBelow { model.lyricsBelow = lyricsBelow }
        if model.lyricEmpty != empty { withAnimation(.easeOut(duration: 0.25)) { model.lyricEmpty = empty } }
        if lyric == nil || !lyricsBelow, model.lyricHidden { model.lyricHidden = false; lyricRestore?.cancel(); lyricRestore = nil }
        if live != model.isLive || lyric != model.lyricWidth {
            if live, !model.isLive, !model.isExpanded, let t = musicTab { model.selectedID = t }
            model.isLive = live
            model.lyricWidth = lyric
            refreshSize()
            timerChanged()
        }
    }

    private var underNotch: Bool { model.clearance > 0 }
    /// Round 23: this top Emper puts the idle lyric in a small strip under the built-in notch.
    var lyricsBelow: Bool { underNotch && model.config.edge == .top && model.config.notchLyrics == .below }

    /// The tab row is always there: it also carries the Settings button, and every island keeps one open size.
    private var hasTabBar: Bool { true }

    func expandedSize(for id: String) -> CGSize {
        let content = ModuleRegistry.descriptor(id)?.contentSize(model.config) ?? .zero
        return IslandGeometry.expandedSize(content: content, config: model.config, tabBar: hasTabBar, clearance: model.clearance)
    }

    /// Largest state any tab can reach; the panel is sized once for it so it never resizes mid-animation.
    private var maxSize: CGSize {
        let c = model.config
        let widestLyric: CGFloat? = NowPlaying.shared.lyricsEnabled ? .greatestFiniteMagnitude : nil
        var live = IslandGeometry.liveSize(c, lyricWidth: widestLyric, notch: underNotch, below: lyricsBelow)
        live.width += IslandGeometry.timerChip
        var sizes = [IslandGeometry.collapsedSize(c), live,
                     IslandGeometry.toastSize(c, notch: underNotch, wide: true)]
        sizes += ModuleRegistry.all.map {
            IslandGeometry.expandedSize(content: $0.contentSize(c), config: c, tabBar: true, clearance: model.clearance)
        }
        return CGSize(width: sizes.map(\.width).max()!, height: sizes.map(\.height).max()!)
    }

    private func refreshSize() {
        let c = model.config
        let s: CGSize
        if model.isExpanded, !model.selectedID.isEmpty { s = expandedSize(for: model.selectedID) }
        else if compact { s = IslandGeometry.compactSize(c) }
        else if let t = model.toast { s = IslandGeometry.toastSize(c, notch: underNotch, wide: t.battery != nil) }
        else if model.compactTimer { s = IslandGeometry.compactTimerSize(c) }
        else if model.isLive {
            let m = IslandGeometry.liveSize(c, lyricWidth: lyricsBelow ? model.lyricWidth : model.shownLyricWidth,
                                            notch: underNotch, below: lyricsBelow,
                                            dual: model.dualIdle)
            // Timer too: its body joins on the right; the same width stays empty on the left (music keeps its place).
            // Timer joins on the right; the whole pair is centred on the idle spot.
            s = model.dualIdle ? CGSize(width: m.width + IslandGeometry.timerChip, height: m.height) : m
        }
        else if model.timerLive { s = IslandGeometry.timerIdleSize(c) }
        else { s = IslandGeometry.collapsedSize(c) }
        if s != model.size { model.size = s }
        refreshHitbox()
    }

    private func refreshHitbox() {
        guard showHitbox else {
            if model.hitbox != nil { model.hitbox = nil }
            return
        }
        let z = idleZone().zone
        let f = panel.frame
        let r = CGRect(x: z.minX - f.minX, y: f.maxY - z.maxY, width: z.width, height: z.height)
        if r != model.hitbox { model.hitbox = r }
    }

    func select(_ id: String) {
        guard tabIDs.contains(id) else { return }
        guard id != model.selectedID else { return }
        model.selectedID = id
        refreshSize()
        syncKeys()
    }

    /// Keyboard follows the calculator: taken while it is on screen in the open island, given back otherwise.
    private func syncKeys() {
        if model.isExpanded, model.keyFeature == ModuleRegistry.calculatorID { KeyCatcher.shared.take(for: self) }
        else { KeyCatcher.shared.release(from: self) }
    }

    // MARK: Toast & file drop

    func showToast(_ t: IslandToast, for seconds: TimeInterval = 3) {
        guard !compact else { return }   // full screen: nothing shows while idle
        model.toast = t
        refreshSize()
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.model.toast?.id == t.id else { return }
                self.model.toast = nil
                self.refreshSize()
            }
        }
    }

    /// The File Shelf, if this island has it (own tab or placeholder).
    var shelfPlace: String? {
        if slotIDs.contains(ModuleRegistry.shelfID) { return ModuleRegistry.homeID }
        return tabIDs.contains(ModuleRegistry.shelfID) ? ModuleRegistry.shelfID : nil
    }

    /// Files dragged over the idle island: open it on the shelf so they can be dropped.
    func fileDragHover(at p: CGPoint) -> Bool {
        guard let place = shelfPlace else { return false }
        let open = model.isExpanded && IslandGeometry.hotZone(for: openRect, edge: model.config.edge, margin: 8)
            .union(idleZone().zone).contains(p)
        guard open || inIdleZone(p) else { return false }
        if !model.isExpanded {
            setExpanded(true)
        }
        if place == ModuleRegistry.homeID { model.selectedID = place } else { select(place) }
        return true
    }

    // MARK: Hover

    /// Round 29: the open Emper plus, on left/right Empers, the floating button pill beside it.
    private var openRect: CGRect {
        var r = currentRect
        guard model.isExpanded, model.config.edge.isVertical else { return r }
        r.size.width += IslandGeometry.sidePillRoom
        if model.config.edge == .right { r.origin.x -= IslandGeometry.sidePillRoom }
        return r
    }

    var currentRect: CGRect {
        IslandGeometry.islandRect(size: model.size, config: model.config, panel: panel.frame, reach: model.addSlotReach)
    }

    /// A centred bottom island under a visible Dock: shown, never opened by hover.
    private var dockCovered = false

    func pointerMoved(to p: CGPoint) {
        guard !hidden else { return }
        if dockCovered, !model.isExpanded {
            if !panel.ignoresMouseEvents { panel.ignoresMouseEvents = true }
            return
        }
        // Idle: only the notch-length body (the lyric never widens it), shrunk on the inner sides so
        // brushing past does not open it. Open: the whole open island plus a forgiving margin, and
        // always the idle zone too, so the spot that opened it can never close it.
        let idle = idleZone()
        let inZone = model.isExpanded
            ? IslandGeometry.hotZone(for: openRect, edge: model.config.edge, outward: 2 + CGFloat(model.config.edgeGap),
                                       margin: model.editingHome ? IslandGeometry.sideButtonRoom + 4 : 8).union(idle.zone).contains(p)
            : inIdleZone(p)
        defer {
            // Hover for views inside the open island (seek bar), in view coordinates.
            let f = panel.frame
            let local: CGPoint? = model.isExpanded ? CGPoint(x: p.x - f.minX, y: f.maxY - p.y) : nil
            if model.pointer.location != local { model.pointer.location = local }
        }
        trackLyricHover(p)
        if !model.isExpanded {
            let takeClicks = idleButtonsHit(p)
            if panel.ignoresMouseEvents == takeClicks { panel.ignoresMouseEvents = !takeClicks }
        }
        if inZone {
            collapseWork?.cancel()
            collapseWork = nil
            guard !model.isExpanded, openWork == nil else { return }
            if openDelay <= 0 {
                setExpanded(true)
            } else {
                // Resting on the island opens it; passing over it does not.
                let work = DispatchWorkItem { [weak self] in
                    MainActor.assumeIsolated {
                        self?.openWork = nil
                        self?.setExpanded(true)
                    }
                }
                openWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + openDelay, execute: work)
            }
        } else {
            openWork?.cancel()
            openWork = nil
            guard model.isExpanded, !hold, collapseWork == nil else { return }
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    self?.collapseWork = nil
                    self?.setExpanded(false)
                }
            }
            collapseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + closeDelay, execute: work)
        }
    }

    private func setExpanded(_ e: Bool) {
        let e = e && !model.tabs.isEmpty
        if model.isExpanded != e {
            // Typing went to the calculator through the invisible key catcher: hand the keyboard back.
            // The island itself is never key, so nothing visible is re-ordered (no blink).
            if !e {
                KeyCatcher.shared.release(from: self)
                TextOverlay.shared.end(in: panel)
                TimeEntry.shared.end()
                model.editingHome = false
                model.addingTab = false
                model.pointer.location = nil
            }
            if e, model.isLive, let t = musicTab { model.selectedID = t }
            if e { model.openCount &+= 1 } else if model.isExpanded { model.closeCount &+= 1 }
            model.isExpanded = e
            refreshSize()
            // Calculator on Home or selected: typing goes straight to it while the island is open, no click needed.
            if e { syncKeys() }
        }
        // Idle: clicks pass through to the menu bar / apps underneath (except the idle play buttons).
        panel.ignoresMouseEvents = !e
    }

    /// Idle with music or timer: the wings beside the idle body hold play/pause buttons. They are outside
    /// the hover zone (so they never open the island) and take clicks only while the pointer is on them.
    private func idleButtonsHit(_ p: CGPoint) -> Bool {
        guard !model.isExpanded, model.toast == nil, model.isLive || model.timerLive else { return false }
        return idleBodyRect.contains(p) && !inIdleZone(p)
    }

    /// Round 24: the idle Emper without the lyric strip under a built-in notch. The strip is never part of
    /// the hover zone or the click area: margins are measured from this body.
    private var idleBodyRect: CGRect {
        var r = currentRect
        guard lyricStripShown else { return r }
        let extra = IslandGeometry.belowExtra(model.config)
        r.origin.y += extra
        r.size.height -= extra
        return r
    }
    private var lyricStripShown: Bool {
        !model.isExpanded && model.toast == nil && model.showsLive && lyricsBelow && model.lyricWidth != nil
    }

    /// Where the lyric strip sits (or would sit while it is hidden by hover), screen coordinates.
    private var lyricStripRect: CGRect? {
        guard !model.isExpanded, model.toast == nil, model.showsLive, lyricsBelow, model.lyricWidth != nil else { return nil }
        let c = model.config
        guard let lw = model.lyricWidth else { return nil }
        var s = IslandGeometry.liveSize(c, lyricWidth: lw, notch: underNotch, below: true, dual: model.dualIdle)
        if model.dualIdle { s.width += IslandGeometry.timerChip }
        let r = IslandGeometry.islandRect(size: s, config: c, panel: panel.frame)
        let l = IslandGeometry.lyricBelowRect(c, size: s, lyricWidth: lw, dual: model.dualIdle)
        return CGRect(x: r.minX + l.minX, y: r.maxY - l.maxY, width: l.width, height: l.height)
    }
    private var lyricRestore: DispatchWorkItem?

    /// Pointer on the strip: fade it out. It comes back a moment after the pointer leaves that area.
    private func trackLyricHover(_ p: CGPoint) {
        guard let strip = lyricStripRect else {
            lyricRestore?.cancel(); lyricRestore = nil
            if model.lyricHidden { model.lyricHidden = false }
            return
        }
        if strip.insetBy(dx: -6, dy: -6).contains(p) {
            lyricRestore?.cancel(); lyricRestore = nil
            if !model.lyricHidden {
                withAnimation(.easeOut(duration: 0.18)) { model.lyricHidden = true }
                refreshSize()
            }
        } else if model.lyricHidden, lyricRestore == nil {
            let w = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.lyricRestore = nil
                    withAnimation(.easeOut(duration: 0.25)) { self.model.lyricHidden = false }
                    self.refreshSize()
                }
            }
            lyricRestore = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: w)
        }
    }

    /// Idle hover zone. Follows the idle Emper as it is now (wider/deeper with lyrics, timer, live music) with
    /// the same side and far margins as the plain idle zone. `holes` are the idle buttons (music artwork,
    /// music play/pause, timer play/pause): they never open the Emper and take clicks instead.
    private func idleZone() -> (zone: CGRect, holes: [CGRect]) {
        let c = model.config
        if compact { return (IslandGeometry.edgeHotZone(c, panel: panel.frame), []) }
        let busy = !model.isExpanded && model.toast == nil && (model.isLive || model.timerLive)
        let plain = IslandGeometry.idleHotZone(c, panel: panel.frame)
        guard busy, !c.edge.isVertical else { return (plain, []) }
        let r = idleBodyRect
        let flare = c.style == .island ? 0 : CGFloat(IslandConfig.notchFlare)
        let along = max(r.width - 2 * flare - 2 * CGFloat(c.hoverInset), 8)
        let depth = max(r.height - CGFloat(c.hoverInsetFar), 4)
        let outward: CGFloat = 2 + CGFloat(c.edgeGap)
        let y = c.edge == .top ? r.maxY - depth : r.minY - outward
        let zone = CGRect(x: r.midX - along / 2, y: y, width: along, height: depth + outward)
        func hole(_ x0: CGFloat, _ x1: CGFloat) -> CGRect {
            CGRect(x: x0, y: r.minY - outward - 2, width: max(x1 - x0, 0), height: r.height + outward + 4)
        }
        var holes: [CGRect] = []
        let timerButton: CGFloat = 36   // play/pause (22) + its padding at the trailing end
        if model.showsLive {
            let pad = IslandGeometry.livePad(), art = IslandGeometry.liveArt(c)
            let m0 = r.minX
            let m1 = model.dualIdle ? r.maxX - IslandGeometry.timerChip : r.maxX
            holes.append(hole(m0, m0 + pad + art + 3))          // artwork
            holes.append(hole(m1 - pad - art - 3, m1))          // music play/pause (bars)
        }
        if model.timerLive { holes.append(hole(r.maxX - timerButton, r.maxX)) }
        return (zone, holes)
    }

    private func inIdleZone(_ p: CGPoint) -> Bool {
        let z = idleZone()
        return z.zone.contains(p) && !z.holes.contains { $0.contains(p) }
    }

    /// Keyboard input while the open island has keyboard focus (after a click in it).
    func handleKey(_ event: NSEvent) -> Bool {
        guard KeyCatcher.shared.owner === self, model.isExpanded else { return false }
        guard model.keyFeature == ModuleRegistry.calculatorID,
              let calc = instances[ModuleRegistry.calculatorID] as? CalculatorModule else { return false }
        return calc.type(event)
    }

    /// Full-screen app on this display: the idle Emper shrinks to a thin line with no activity (music, timer,
    /// lyric, toast) and opens only when the pointer is pushed against the screen edge.
    private(set) var compact = false
    func setCompact(_ on: Bool) {
        guard on != compact else { return }
        compact = on
        if on { model.toast = nil }
        if model.isCompact != on { model.isCompact = on }
        musicChanged()
        timerChanged()
        refreshSize()
    }

    /// Mission Control: fade the island out (the panel stays ordered, so nothing re-layers afterwards).
    private var hidden = false
    func setHidden(_ h: Bool) {
        guard h != hidden else { return }
        hidden = h
        let a: CGFloat = h ? 0 : 1
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = a
        }
        if h { setExpanded(false); panel.ignoresMouseEvents = true }
    }

    func close() {
        collapseWork?.cancel()
        openWork?.cancel()
        KeyCatcher.shared.release(from: self)
        bag.removeAll()
        for m in instances.values { m.stop() }
        panel.orderOut(nil)
        panel.close()
    }
}

/// Lets the first click on a button in an inactive panel act immediately. The island panel never becomes
/// key; `onMouseDown` lets the controller hand keyboard focus to the invisible `KeyCatcher` instead.
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    var onMouseDown: () -> Void = {}

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        // Before SwiftUI handles the click, so a button that wants the keyboard (search) finds its island.
        onMouseDown()
        super.mouseDown(with: event)
    }
}

/// A 1x1 transparent, non-activating panel that takes keyboard focus for the calculator. Giving the
/// keyboard back means re-ordering this panel, which nobody can see, instead of the island (that blinked).
@MainActor
final class KeyCatcher {
    static let shared = KeyCatcher()
    private(set) weak var owner: IslandController?
    private let panel: NSPanel

    private init() {
        // A plain borderless panel refuses to become key, so typing never arrived: subclass that allows it.
        panel = KeyPanel(contentRect: CGRect(x: 0, y: 0, width: 1, height: 1),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.alphaValue = 0
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.level = .floating
    }

    func take(for c: IslandController) {
        owner = c
        if !panel.isKeyWindow {
            panel.setFrameOrigin(CGPoint(x: c.panel.frame.midX, y: c.panel.frame.midY))
            panel.makeKeyAndOrderFront(nil)
        }
    }

    /// Round 30: keyboard for a Emper control that is not the calculator (reminder time boxes).
    func takeFree() {
        owner = nil
        if !panel.isKeyWindow {
            panel.setFrameOrigin(NSEvent.mouseLocation)
            panel.makeKeyAndOrderFront(nil)
        }
    }

    func releaseFree() {
        guard owner == nil else { return }
        if panel.isVisible { panel.orderOut(nil) }
    }

    /// Round 28: a Quick Note / Reminder text box takes the keyboard.
    func releaseAll() {
        owner = nil
        if panel.isVisible { panel.orderOut(nil) }
    }

    func release(from c: IslandController) {
        guard owner === c else { return }
        owner = nil
        // Ordering the key panel out returns keyboard focus to the app underneath.
        if panel.isVisible { panel.orderOut(nil) }
    }
}

/// Borderless, non-activating, and still allowed to take the keyboard.
private final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Lyric line text metrics, shared by the size maths and the view.
enum LyricMetrics {
    static let font = NSFont.systemFont(ofSize: 12, weight: .medium)
    /// Round 23: the line under a built-in notch.
    static let smallFont = NSFont.systemFont(ofSize: 11, weight: .medium)

    @MainActor
    static func width(_ text: String, small: Bool = false) -> CGFloat {
        let t = text.isEmpty ? "♪" : text
        return (NSAttributedString(string: t, attributes: [.font: small ? smallFont : font]).size().width + 4).rounded(.up)
    }
}
