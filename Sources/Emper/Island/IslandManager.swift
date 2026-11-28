import AppKit
import Combine
import EmperCore

/// Owns every island on every display. Reconciles panels with config, Dock and screen changes,
/// feeds pointer position to all islands and switches shared services on only when used.
@MainActor
final class IslandManager {
    private let store: ConfigStore
    private let dock: DockMonitor
    private let selfTest: Bool
    private var controllers: [String: IslandController] = [:]
    private var bag = Set<AnyCancellable>()
    private var monitors: [Any] = []
    private var pollTimer: Timer?
    private var pollInterval: TimeInterval = 0
    private var musicPrimed = false
    /// Self-test turns this off so the real cursor does not interfere with simulated hover.
    var followsRealPointer = true

    init(store: ConfigStore, dock: DockMonitor, selfTest: Bool) {
        self.store = store
        self.dock = dock
        self.selfTest = selfTest
    }

    var dockEdge: IslandEdge { dock.info.edge }

    func start() {
        // @Published fires in willSet, so hop to the next main-loop turn before reading the store.
        store.$config.map { _ in () }
            .merge(with: store.$holdExpanded.map { _ in () }, dock.$info.map { _ in () }, store.$hitboxKey.map { _ in () },
                   SpaceWatcher.shared.$missionControl.map { _ in () }, SpaceWatcher.shared.$fullScreen.map { _ in () })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.reconcile() }
            .store(in: &bag)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reconcile() }
            .store(in: &bag)

        // Hover: mouse-moved event monitors fire instantly (no Accessibility permission needed for
        // mouse events). A poll backs them up: 60 Hz while an island is open (fast exit detection),
        // 10 Hz when idle.
        let types: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let g = NSEvent.addGlobalMonitorForEvents(matching: types, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.pointerMoved() }
        }) { monitors.append(g) }
        if let l = NSEvent.addLocalMonitorForEvents(matching: types, handler: { [weak self] e in
            MainActor.assumeIsolated { self?.pointerMoved() }
            return e
        }) { monitors.append(l) }
        schedulePoll(0.1)

        // Keys only reach Emper after a click made an island key; nothing global, no permission.
        if let k = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] e in
            nonisolated(unsafe) let ev = e
            let used = MainActor.assumeIsolated { self?.handleKey(ev) ?? false }
            return used ? nil : e
        }) { monitors.append(k) }

        reconcile()
    }

    var allControllers: [String: IslandController] { controllers }

    func controller(for screen: NSScreen, edge: IslandEdge) -> IslandController? {
        controllers[key(screen, edge)]
    }

    private func key(_ s: NSScreen, _ e: IslandEdge) -> String { "\(s.emperID)|\(e.rawValue)" }

    func reconcile() {
        NowPlaying.shared.lyricsEnabled = store.config.lyricsEnabled
        NowPlaying.shared.scriptingAllowed = store.config.musicAppControl
        if NowPlaying.shared.idleLyrics != store.config.idleLyrics { NowPlaying.shared.idleLyrics = store.config.idleLyrics }
        var alive = Set<String>()
        var usesClipboard = false, usesMusic = false, usesShelf = false
        for screen in NSScreen.screens {
            let display = store.display(for: screen)
            for edge in IslandEdge.allCases {
                let saved = display[edge]
                // Left/right: no island on the Dock's edge. Bottom: always allowed; a centred one the Dock
                // covers stays on but cannot be opened (Pang, round 14: "ketutup dock ya wasalam").
                guard saved.enabled else { continue }
                guard edge != dock.info.edge || edge == .bottom else { continue }
                let dockCovers = edge == .bottom && dock.info.edge == .bottom && !dock.info.autohide
                    && saved.bottomLayout == .center && screen.visibleFrame.minY > screen.frame.minY
                for (k, cfg, right) in variants(screen, edge, saved) {
                    let all = (cfg.moduleIDs + cfg.homeSlots).filter { ModuleRegistry.descriptor($0) != nil }
                    usesClipboard = usesClipboard || all.contains("clipboard")
                    usesShelf = usesShelf || all.contains(ModuleRegistry.screenshotsID)
                    usesMusic = usesMusic || all.contains(ModuleRegistry.musicID)
                    alive.insert(k)
                    let notch = edge == .top ? (screen.notchSize?.height ?? 0) : 0
                    var c2 = cfg
                    // Look: this Emper's own choice, or General › Appearance.
                    c2.style = cfg.styleChoice.resolve(store.config.style)
                    // Floating style: its own gap from the edge, notched screens included (round 16). The content
                    // only clears the part of the notch the gap doesn't already leave behind.
                    if c2.style == .island { c2.edgeGap = cfg.islandGap }
                    let clearance = max(0, notch - CGFloat(c2.edgeGap))
                    // Placement along the edge: centred on the idle spot, kept on screen and below the menu bar.
                    c2.area = screen.frame
                    c2.topReserve = Double(max(0, screen.frame.maxY - screen.visibleFrame.maxY))
                    let c = controllers[k] ?? IslandController(config: c2, area: screen.frame, clearance: clearance, hold: store.holdExpanded)
                    controllers[k] = c
                    let sid = screen.emperID
                    c.model.onOpenEmperSettings = { IslandController.openEmperSettings(sid, edge) }
                    c.onEdit = { [weak store] change in
                        guard let store else { return }
                        store.update(screen, edge) { saved in
                            guard right else { return change(&saved) }
                            // Right corner island: its features live in the right* fields.
                            var t = saved
                            t.moduleIDs = saved.rightModuleIDs
                            t.homeSlots = saved.rightHomeSlots
                            t.homeSizes = saved.rightHomeSizes
                            t.homeMain = saved.rightHomeMain
                            change(&t)
                            saved.rightModuleIDs = t.moduleIDs
                            saved.rightHomeSlots = t.homeSlots
                            saved.rightHomeSizes = t.homeSizes
                            saved.rightHomeMain = t.homeMain
                        }
                    }
                    c.update(config: c2, area: screen.frame, clearance: clearance, hold: store.holdExpanded,
                             fullScreen: store.config.showInFullScreen, showHitbox: store.hitboxKey == key(screen, edge),
                             dockCovered: dockCovers)
                    c.panel.appearance = store.config.theme.appearance
                    c.setHidden(store.config.hideInMissionControl && SpaceWatcher.shared.missionControl)
                    c.setCompact(c2.shrunk || (store.config.showInFullScreen && SpaceWatcher.shared.fullScreen.contains(screen.emperID)))
                }
            }
        }
        for (k, c) in controllers where !alive.contains(k) {
            c.close()
            controllers[k] = nil
        }
        if !selfTest {
            // Music › Players: with direct control off, any app is always on (0.1.3: both off reads as "Any app").
            let anyApp = store.config.systemAudio || !store.config.musicAppControl
            ClipboardHistory.shared.setActive(usesClipboard)
            ScreenshotShelf.shared.setDestination(store.config.screenshotFolder.map { URL(fileURLWithPath: $0, isDirectory: true) })
            ScreenshotShelf.shared.setActive(usesShelf)
            NowPlaying.shared.systemAudioOn = usesMusic && anyApp
            // Primed once per opt-in, so turning control on picks up what is already playing.
            if usesMusic, store.config.musicAppControl, !musicPrimed {
                musicPrimed = true
                NowPlaying.shared.refreshIfRunning()
            }
            if !store.config.musicAppControl { musicPrimed = false }
            NowPlaying.enableAppControl = { [weak self] in self?.store.setGlobal { $0.musicAppControl = true } }
            SystemMedia.shared.onInfo = { NowPlaying.shared.applySystem($0) }
            SystemMedia.shared.setActive(usesMusic && anyApp)
            BluetoothMonitor.shared.onConnect = { [weak self] e in self?.showBluetooth(e) }
            BluetoothMonitor.shared.setActive(store.config.bluetoothToast)
            SpaceWatcher.shared.setActive(store.config.hideInMissionControl || store.config.showInFullScreen)
        }
    }

    /// One island per edge, except the bottom with corner layouts: one corner, or both (two islands).
    private func variants(_ screen: NSScreen, _ edge: IslandEdge, _ c: IslandConfig) -> [(String, IslandConfig, Bool)] {
        let k = key(screen, edge)
        guard edge == .bottom else { return [(k, c, false)] }
        switch c.bottomLayout {
        case .center:
            return [(k, c, false)]
        case .oneSide:
            var l = c
            l.anchor = c.bottomSide == .trailing ? .trailing : .leading
            return [(k, l, false)]
        case .twoSides:
            var l = c, r = c
            l.anchor = .leading
            r.anchor = .trailing
            r.moduleIDs = c.rightModuleIDs
            r.homeSlots = c.rightHomeSlots
            r.homeSizes = c.rightHomeSizes
            r.homeMain = c.rightHomeMain
            return [(k, l, false), (k + "-right", r, true)]
        }
    }

    /// Bluetooth toast on the main display's top island (or any island there if the top is off).
    private func showBluetooth(_ e: BluetoothMonitor.Event) {
        guard store.config.bluetoothToast, let main = NSScreen.main ?? NSScreen.screens.first else { return }
        let toast = IslandToast(symbol: e.symbol, title: e.name, battery: e.battery)
        let c = controllers[key(main, .top)] ?? controllers.first { $0.key.hasPrefix(main.emperID + "|") }?.value
        c?.showToast(toast)
    }

    func handleKey(_ e: NSEvent) -> Bool {
        if TimeEntry.shared.handle(e) { return true }
        return controllers.values.contains { $0.handleKey(e) }
    }

    private var dragBaseline = NSPasteboard(name: .drag).changeCount
    private var fileDragHandled = false
    private var buttonWasDown = false

    /// Bench only: a fake cursor fed through the same path as real mouse events.
    var pointerOverride: CGPoint?

    func pointerMoved() {
        guard followsRealPointer || pointerOverride != nil else { return }
        let p = pointerOverride ?? NSEvent.mouseLocation
        if fileDrag(at: p) { return }
        for c in controllers.values { c.pointerMoved(to: p) }
        schedulePoll(controllers.values.contains { $0.model.isExpanded } ? 1.0 / 60 : 0.1)
    }

    /// A file drag from Finder (button held, drag pasteboard changed since the press and holds files):
    /// an island with the File Shelf under the pointer opens on the shelf. Checked only while the button is down.
    private func fileDrag(at p: CGPoint) -> Bool {
        guard NSEvent.pressedMouseButtons & 1 != 0 else {
            if fileDragHandled { fileDragHandled = false }
            // Baseline read once per release, not on every move (it asks the pasteboard server).
            if buttonWasDown { dragBaseline = NSPasteboard(name: .drag).changeCount; buttonWasDown = false }
            return false
        }
        buttonWasDown = true
        let pb = NSPasteboard(name: .drag)
        guard pb.changeCount != dragBaseline, FileShelf.dragCarriesFiles() else { return false }
        var hit = false
        for c in controllers.values where c.fileDragHover(at: p) { hit = true }
        if hit { fileDragHandled = true; schedulePoll(1.0 / 30) }
        // Keep islands opened by the drag open until the drop: skip the normal hover exit meanwhile.
        return fileDragHandled
    }

    private func schedulePoll(_ interval: TimeInterval) {
        guard interval != pollInterval else { return }
        pollInterval = interval
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pointerMoved() }
        }
    }
}
