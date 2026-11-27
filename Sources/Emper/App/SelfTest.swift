import Combine
import AppKit
import SwiftUI
import EmperCore

/// `Emper --selftest`: drives the real panels without moving the user's cursor, without touching the real
/// clipboard, Spotify or network. Prints PASS/FAIL and exits.
@MainActor
enum SelfTest {
    static func run(manager: IslandManager, store: ConfigStore) {
        manager.followsRealPointer = false
        NowPlaying.shared.offline = true
        var results: [(String, Bool)] = []
        func check(_ name: String, _ ok: Bool) { results.append((name, ok)) }

        guard let screen = NSScreen.screens.first,
              let c = manager.controller(for: screen, edge: .top) else {
            print("FAIL: no top island on the menu-bar screen")
            exit(1)
        }
        let cfg = c.model.config

        // Space signals (made-up window lists, two displays; the second has a 38 pt notch).
        typealias W = SpaceWatcher.Win
        let d1 = CGRect(x: 0, y: 0, width: 2560, height: 1440), d2 = CGRect(x: 410, y: 1440, width: 1800, height: 1169)
        let ds: [(id: String, frame: CGRect, top: CGFloat)] = [("A", d1, 0), ("B", d2, 38)]
        let bars = [W(number: 1, owner: "Window Server", pid: 9, layer: 24, bounds: CGRect(x: 0, y: 0, width: 2560, height: 30)),
                    W(number: 2, owner: "Window Server", pid: 9, layer: 24, bounds: CGRect(x: 410, y: 1440, width: 1800, height: 39))]
        let big = W(number: 50, owner: "Overlay", pid: 77, layer: 0, bounds: d1)
        var r = SpaceWatcher.evaluate(bars + [big], displays: ds, me: 1, previous: [:])
        check("spaces: desktop with menu bars is not full screen (full-size overlay ignored)", !r.missionControl && r.fsWindow.isEmpty)
        let app = W(number: 60, owner: "Safari", pid: 88, layer: 0, bounds: CGRect(x: 410, y: 1478, width: 1800, height: 1131))
        r = SpaceWatcher.evaluate([bars[0], app], displays: ds, me: 1, previous: [:])
        check("spaces: app below the notch, menu bar gone = full screen on that display only", r.fsWindow == ["B": 60])
        r = SpaceWatcher.evaluate(bars + [app], displays: ds, me: 1, previous: ["B": 60], pointerTop: ["B"])
        check("spaces: menu bar sliding in under the pointer keeps full screen while the same window stays", r.fsWindow == ["B": 60])
        r = SpaceWatcher.evaluate(bars + [app], displays: ds, me: 1, previous: ["B": 60], pointerTop: [])
        check("spaces: menu bar back with the pointer elsewhere = left full screen (maximised window)", r.fsWindow.isEmpty)
        do {
            let fresh = EmperConfig()
            check("permissions: fresh install has the Bluetooth toast off (no Bluetooth prompt at launch)", !fresh.bluetoothToast)
            check("permissions: fresh install has direct Spotify/Music control off (no Automation prompt at launch)", !fresh.musicAppControl)
            let old = try? JSONDecoder().decode(EmperConfig.self, from: Data("{}".utf8))
            check("permissions: config without the keys decodes with both off", old?.bluetoothToast == false && old?.musicAppControl == false)
            check("permissions: no AppleScript while direct control is off", !NowPlaying.shared.scriptingAllowed)
            check("music: another app taking Now Playing (QuickTime) keeps the Spotify track, off Now Playing",
                  NowPlaying.shared.selfTestNowPlayingTakeover())
        }
        let mcw = [W(number: 70, owner: "WindowManager", pid: 5, layer: 19, bounds: d1)]
        r = SpaceWatcher.evaluate(bars + mcw, displays: ds, me: 1, previous: ["B": 60])
        check("spaces: Mission Control seen (WindowManager layer 19 full display)", r.missionControl && r.fsWindow == ["B": 60])

        after(0.6) {
            c.setCompact(true)
            check("full screen: idle Emper is a thin line, no activity",
                  c.model.size.height == IslandGeometry.compactDepth && !c.model.isLive && !c.model.timerLive && c.model.toast == nil)
            c.showToast(IslandToast(symbol: "airpods", title: "Test", battery: nil))
            check("full screen: toasts are not shown", c.model.toast == nil)
            c.setCompact(false)
            check("leaving full screen restores the idle size", c.model.size == IslandGeometry.collapsedSize(c.model.config))
            check("panel on screen", c.panel.isVisible)
            check("panel level above menu bar (\(c.panel.level.rawValue) > \(NSWindow.Level.mainMenu.rawValue))",
                  c.panel.level.rawValue > NSWindow.Level.mainMenu.rawValue)
            check("panel flush with physical top edge", abs(c.panel.frame.maxY - screen.frame.maxY) < 0.5)
            check("idle panel lets clicks through", c.panel.ignoresMouseEvents)
            for other in NSScreen.screens {
                let oc = manager.controller(for: other, edge: .top)
                let info = other.notchSize.map { "notch \(Int($0.width))x\(Int($0.height))" } ?? "menu bar \(Int(other.menuBarHeight)) pt"
                if other == screen {
                    let s = oc?.model.size ?? .zero
                    check("main display \(other.localizedName) (\(info)): top island idle \(Int(s.width))x\(Int(s.height)), flush & centred",
                          oc.map { abs($0.panel.frame.maxY - other.frame.maxY) < 0.5 && abs($0.panel.frame.midX - other.frame.midX) < 0.5 } ?? false)
                } else {
                    check("other display \(other.localizedName): no top island by default", oc == nil)
                }
            }

            // The bug Pang saw: idle island drawn as tall as the open one. Measure real pixels.
            let drawn = drawnDepth(c)
            check("idle island draws \(fmt(drawn)) pt tall (config \(Int(cfg.collapsedHeight)))",
                  abs(drawn - cfg.collapsedHeight) <= 2)

            // Idle hover zone = notch length minus the hover margin; the flare and the margin don't trigger.
            let collapsed = c.currentRect
            let zone = IslandGeometry.idleHotZone(cfg, panel: c.panel.frame)
            let notchLen = cfg.collapsedWidth - 2 * IslandConfig.notchFlare
            check("idle hover zone \(Int(zone.width)) pt = idle length \(Int(notchLen)) - 2 x margin \(Int(cfg.hoverInset))",
                  abs(zone.width - (notchLen - 2 * cfg.hoverInset)) < 0.5)
            c.pointerMoved(to: CGPoint(x: collapsed.minX + 3, y: screen.frame.maxY - 1))
            c.pointerMoved(to: CGPoint(x: collapsed.midX, y: collapsed.minY + 2))
            check("brushing the flare / lower edge does not open it", !c.model.isExpanded)
            c.pointerMoved(to: CGPoint(x: collapsed.midX, y: screen.frame.maxY - 1))
            check("expands on the same event the pointer enters (no delay)", c.model.isExpanded)
            check("expanded panel accepts clicks", !c.panel.ignoresMouseEvents)
            check("tabs: \(c.model.tabs.map(\.id).joined(separator: ", "))",
                  c.model.tabs.map(\.id) == [ModuleRegistry.homeID, "note", ModuleRegistry.screenshotsID])
            check("pointer position reaches the open island's views (seek-bar hover)", c.model.pointer.location != nil)
            let calcModule = CalculatorModule()
            for ch in ["1", "2", "+", "3", "="] {
                if let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                            context: nil, characters: ch, charactersIgnoringModifiers: ch, isARepeat: false,
                                            keyCode: ch == "=" ? 24 : 0) { _ = calcModule.type(e) }
            }
            check("calculator keyboard: 12+3= -> \(calcModule.engine.display)", calcModule.engine.display == "15")
            let calc = ModuleRegistry.homeRow(cfg)
            let mainW = IslandGeometry.openContentWidth(cfg)
            let rowW = HomeLayout.contentWidth(main: mainW, count: cfg.homeSlots.count, scales: cfg.homeSlotScales)
            check("home row \(fmt(calc)) = main \(Int(mainW)) + \(cfg.homeSlots.count - 1) side slots of \(Int(HomeLayout.sideWidth(main: mainW)))",
                  abs(calc.width - rowW) < 0.5 && cfg.homeSlots == ["note", "music", "screenshots"])
            check("open island \(Int(c.model.size.width)) >= minimum \(Int(IslandGeometry.minOpenWidth)) even with idle \(Int(cfg.collapsedWidth))",
                  c.model.size.width >= IslandGeometry.minOpenWidth)
            c.select(ModuleRegistry.homeID)
            let homeSize = c.model.size
            c.select("note")
            check("other tabs drop the side placeholders: Home \(fmt(homeSize)) -> note \(fmt(c.model.size))",
                  c.model.size.width < homeSize.width && c.model.size.height == homeSize.height)
            check("side placeholder 30% of main: \(Int(HomeLayout.sideWidth(main: 384))) == 115", HomeLayout.sideWidth(main: 384) == 115)
            let ins = IslandGeometry.contentInsets(cfg, clearance: c.model.clearance)
            if let notch = screen.notchSize {
                check("tabs clear the notch (top inset \(Int(ins.top)) >= notch \(Int(notch.height)) + 8)", ins.top >= notch.height + 8)
            } else {
                check("no notch: tabs sit high (top inset \(Int(ins.top)) pt)", ins.top <= 14)
            }
            check("visible side margin \(Int(ins.leading - IslandGeometry.openFlare)) pt past the flare",
                  ins.leading - IslandGeometry.openFlare >= 18 && ins.bottom >= 14)

            after(0.6) {
                let open = drawnDepth(c)
                check("expanded island draws \(fmt(open)) pt tall (target \(Int(c.model.size.height)))",
                      abs(open - c.model.size.height) <= 3)
                c.pointerMoved(to: CGPoint(x: screen.frame.midX, y: screen.frame.midY - 300))
                after(c.closeDelay + 0.05) {
                    check("collapse starts \(c.closeDelay) s after pointer leaves", !c.model.isExpanded)

                    NowPlaying.shared.simulate(title: "Test Song", playing: true)
                    after(0.3) {
                        let live = IslandGeometry.liveSize(cfg)
                        check("music playing -> live activity \(fmt(c.model.size))", c.model.isLive && c.model.size == live)
                        let idleZone = IslandGeometry.idleHotZone(cfg, panel: c.panel.frame)
                        NowPlaying.shared.lyricsEnabled = true   // before the store, so the reconcile is a no-op
                        store.setLyricsEnabled(true)
                        NowPlaying.shared.simulateLyrics([LyricLine(time: 0, text: "A much longer lyric line that should stretch the island"),
                                                          LyricLine(time: 60, text: "Second")])
                        after(0.4) {
                        let s = c.model.size
                        check("lyric in the idle row: \(fmt(live)) -> \(fmt(s)), same depth, wider",
                              c.model.lyricWidth != nil && s.height == live.height && s.width > live.width)
                        check("lyric does not change the hover zone",
                              IslandGeometry.idleHotZone(c.model.config, panel: c.panel.frame) == idleZone)
                        // Round 23: built-in notch, lyric "Under the notch": same width rules, a 20-pt strip deeper.
                        let keep = c.model.config, keepClear = c.model.clearance
                        var nc = keep; nc.notchLyrics = .below
                        c.update(config: nc, area: screen.frame, clearance: 32, hold: false)
                        let nb = c.model.size
                        check("under-notch lyric: \(fmt(nb)) has its pill under the body",
                              c.lyricsBelow && c.model.lyricWidth != nil && nb.height == IslandGeometry.liveDepth(nc) + IslandGeometry.belowExtra(nc))
                        // Round 24: the strip is not part of the hitbox: hovering it fades it out and never opens.
                        let body = c.currentRect
                        c.pointerMoved(to: CGPoint(x: body.midX, y: body.minY + 6))
                        check("hover on the under-notch lyric fades it, Emper stays closed and keeps its size (\(fmt(c.model.size)))",
                              c.model.lyricHidden && !c.model.isExpanded && c.model.size == nb)
                        check("the lyric strip lets clicks through", c.panel.ignoresMouseEvents)
                        c.pointerMoved(to: CGPoint(x: body.midX, y: body.maxY - 1))
                        check("the notch body above the strip still opens it", c.model.isExpanded)
                        c.pointerMoved(to: CGPoint(x: screen.frame.midX, y: screen.frame.midY - 300))
                        c.update(config: nc, area: screen.frame, clearance: 32, hold: true)
                        c.update(config: nc, area: screen.frame, clearance: 32, hold: false)
                        nc.notchLyrics = .general
                        c.update(config: nc, area: screen.frame, clearance: 32, hold: false)
                        check("General on the notch: lyric beside the notch, no strip (\(fmt(c.model.size)))",
                              !c.lyricsBelow && c.model.size.height == IslandGeometry.liveDepth(nc))
                        // Round 25: an empty (instrumental) line keeps the pill's place: no size change, only a fade.
                        nc.notchLyrics = .below
                        c.update(config: nc, area: screen.frame, clearance: 32, hold: false)
                        let before = c.model.size
                        NowPlaying.shared.simulateLyrics([LyricLine(time: 0, text: "")])
                        c.musicChanged()
                        check("instrumental line: pill fades, Emper keeps its size (\(fmt(before)) -> \(fmt(c.model.size)))",
                              c.model.lyricEmpty && !c.model.lyricPillVisible && c.model.size == before)
                        NowPlaying.shared.simulateLyrics([LyricLine(time: 0, text: "A much longer lyric line that should stretch the island"),
                                                          LyricLine(time: 60, text: "Second")])
                        c.musicChanged()
                        // Round 25: Island style gets its own pill under the body; same hover/no-hitbox rules.
                        nc.notchLyrics = .below; nc.style = .island
                        c.update(config: nc, area: screen.frame, clearance: 32, hold: false)
                        check("island style: detached lyric pill \(fmt(c.model.size))",
                              c.lyricsBelow && c.model.size.height == IslandGeometry.liveDepth(nc) + IslandGeometry.belowExtra(nc))
                        let ib = c.currentRect
                        c.pointerMoved(to: CGPoint(x: ib.midX, y: ib.minY + 6))
                        check("hover on the island lyric pill hides it, Emper stays closed",
                              c.model.lyricHidden && !c.model.isExpanded && c.panel.ignoresMouseEvents)
                        c.pointerMoved(to: CGPoint(x: screen.frame.midX, y: screen.frame.midY - 300))
                        c.update(config: keep, area: screen.frame, clearance: keepClear, hold: false)
                        check("no separate Music tab on the top island (music is a Home placeholder)",
                              c.model.tabs.first?.id == ModuleRegistry.homeID && !c.model.tabs.contains { $0.id == ModuleRegistry.musicID })
                        c.select("calculator")
                        c.pointerMoved(to: CGPoint(x: c.currentRect.midX, y: screen.frame.maxY - 1))
                        check("hover while playing opens Home", c.model.isExpanded && c.model.selectedID == ModuleRegistry.homeID)
                        c.pointerMoved(to: CGPoint(x: screen.frame.midX, y: screen.frame.midY - 300))
                        store.update(screen, .top) { $0.musicDetection = false }
                        after(0.3) {
                            check("pointer cleared after closing", c.model.pointer.location == nil)
                            // Round 18: music shows on any top/bottom Emper with Home on, detection or not.
                            check("music detection off, Home on -> still live, no music tab",
                                  c.model.isLive && !c.model.tabs.contains { $0.id == ModuleRegistry.musicID })
                            homeChecks(c, store: store, screen: screen, check: check)
                            NowPlaying.shared.simulate(title: "", playing: false)
                            store.setLyricsEnabled(false)

                            store.update(screen, .top) {
                                $0.collapsedWidth = 260
                                $0.offset = 200
                            }
                            after(0.4) {
                                check("idle width setting applied (\(Int(c.model.size.width)) == 260)", abs(c.model.size.width - 260) < 0.5)
                                check("position setting applied (shift \(Int(c.panel.frame.midX - screen.frame.midX)) == 200)",
                                      abs(c.panel.frame.midX - screen.frame.midX - 200) < 0.5)
                                wideIdleChecks(c, store: store, screen: screen, check: check)
                                clipboardChecks(check)
                                shelfChecks(check)
                                check("island panel never takes keyboard focus (no blink on close)", !c.panel.canBecomeKey)
                                store.update(screen, .top) { $0.openDelayMs = 200; $0.hoverInsetFar = 3 }
                                c.update(config: store.display(for: screen)[.top], area: screen.frame, clearance: c.model.clearance,
                                         hold: false, showHitbox: true)
                                let z = IslandGeometry.idleHotZone(c.model.config, panel: c.panel.frame)
                                check("hover-zone preview drawn \(fmt(c.model.hitbox?.size ?? .zero)) == zone \(fmt(z.size))",
                                      c.model.hitbox.map { abs($0.width - z.width) < 0.5 && abs($0.height - z.height) < 0.5 } ?? false)
                                after(0.3) {   // let the wide-idle test's island close first
                                c.pointerMoved(to: CGPoint(x: z.midX, y: screen.frame.maxY - 1))
                                check("open delay 200 ms: not open right away", !c.model.isExpanded)
                                after(0.3) {
                                check("open delay 200 ms: opens after resting", c.model.isExpanded)
                                c.pointerMoved(to: CGPoint(x: screen.frame.midX, y: screen.frame.midY - 300))
                                store.update(screen, .top) { $0.musicDetection = true }
                                NowPlaying.shared.simulate(title: "Test Song", playing: true)
                                TimerService.shared.toggle()
                                after(0.5) {
                                let cfgNow = c.model.config
                                let want = IslandGeometry.liveSize(cfgNow).width + IslandGeometry.timerChip
                                check("music + timer: idle shows both, \(Int(c.model.size.width)) == \(Int(want))",
                                      c.model.isLive && c.model.timerLive && !c.model.isExpanded && abs(c.model.size.width - want) < 0.5)
                                let zone = IslandGeometry.idleHotZone(cfgNow, panel: c.panel.frame)
                                let wing = CGPoint(x: c.currentRect.maxX - 12, y: screen.frame.maxY - 6)
                                c.pointerMoved(to: wing)
                                check("idle play/pause wing takes clicks without opening",
                                      !zone.contains(wing) && !c.panel.ignoresMouseEvents && !c.model.isExpanded)
                                c.pointerMoved(to: CGPoint(x: screen.frame.midX, y: screen.frame.midY - 300))
                                check("pointer away: idle lets clicks through again", c.panel.ignoresMouseEvents)
                                TimerService.shared.reset()
                                NowPlaying.shared.simulate(title: "", playing: false)
                                store.update(screen, .top) { $0.shrunk = true }
                                after(0.3) {
                                check("shrink: idle Emper becomes the thin line (saved per Emper)",
                                      c.model.isCompact && c.model.size.height == IslandGeometry.compactDepth
                                      && store.display(for: screen)[.top].shrunk)
                                store.update(screen, .top) { $0.shrunk = false }
                                after(0.3) {
                                check("shrink off: back to the normal idle", !c.model.isCompact
                                      && c.model.size == IslandGeometry.collapsedSize(c.model.config))
                                check("music: ✕ hides a paused app until it plays again", NowPlaying.shared.selfTestDismiss())
                                store.update(screen, .top) { $0.enabled = false }
                                after(0.3) {
                                    check("toggle off removes the island", manager.controller(for: screen, edge: .top) == nil)
                                    var allOK = true
                                    for (n, ok) in results {
                                        print("\(ok ? "PASS" : "FAIL"): \(n)")
                                        allOK = allOK && ok
                                    }
                                    print("dock=\(manager.dockEdge.rawValue)")
                                    exit(allOK ? 0 : 1)
                                }
                                }
                                }
                                }
                                }
                                }
                            }
                        }
                        }
                    }
                }
            }
        }
    }

    /// Pang's setup: idle stretched to 600 pt, wider than any module. Hovering the far end of the idle
    /// zone must open it and keep it open (no open/close loop), also while moving down into it.
    private static func wideIdleChecks(_ c: IslandController, store: ConfigStore, screen: NSScreen, check: (String, Bool) -> Void) {
        store.update(screen, .top) { $0.collapsedWidth = 600; $0.offset = 0 }
        c.update(config: store.display(for: screen)[.top], area: screen.frame, clearance: c.model.clearance, hold: false)
        let zone = IslandGeometry.idleHotZone(c.model.config, panel: c.panel.frame)
        let edgeSpot = CGPoint(x: zone.maxX - 1, y: screen.frame.maxY - 1)
        c.pointerMoved(to: edgeSpot)
        let opened = c.model.isExpanded
        c.pointerMoved(to: edgeSpot)
        c.pointerMoved(to: CGPoint(x: edgeSpot.x, y: screen.frame.maxY - c.model.size.height + 10))
        check("idle 600 pt: open island \(Int(c.model.size.width)) pt wide, far end stays open (no flicker)",
              opened && c.model.isExpanded && c.model.size.width >= 600)
        c.pointerMoved(to: CGPoint(x: screen.frame.midX, y: screen.frame.midY - 300))
    }

    /// `Emper --bench timer|music|both`: idle island with a running timer and/or playing music, cursor
    /// ignored, until killed. Measure with `top -pid`.
    nonisolated(unsafe) static var benchBag: [AnyCancellable] = []

    static func bench(manager: IslandManager, mode: String) {
        manager.followsRealPointer = false
        NowPlaying.shared.offline = true
        if mode != "music" { TimerService.shared.toggle() }
        if mode != "timer" { NowPlaying.shared.simulate(title: "Test Song", playing: true) }
        if CommandLine.arguments.contains("--lyrics") {
            NowPlaying.shared.lyricsEnabled = true
            NowPlaying.shared.simulateLyrics((0..<60).map { LyricLine(time: Double($0) * 3, text: "Bench lyric line number \($0) here") })
        }
        // `--open`: the top Emper is opened by a resting pointer; `--move` also wiggles it at 60 Hz (hovering hand).
        if CommandLine.arguments.contains("--open") {
            let moving = CommandLine.arguments.contains("--move")
            func tryOpen(_ n: Int) {
                guard let screen = NSScreen.screens.first, let c = manager.controller(for: screen, edge: .top) else {
                    if n < 20 { after(0.5) { tryOpen(n + 1) } }; return
                }
                let r0 = c.currentRect
                c.pointerMoved(to: CGPoint(x: r0.midX, y: r0.maxY - 4))
                guard c.model.isExpanded else {
                    if n < 20 { after(0.5) { tryOpen(n + 1) } } else { FileHandle.standardError.write("never opened\n".data(using: .utf8)!) }
                    return
                }
                opened(c)
            }
            after(1.0) { tryOpen(0) }
            func opened(_ c: IslandController) {
                let r = c.currentRect
                FileHandle.standardError.write("opened=\(c.model.isExpanded)\n".data(using: .utf8)!)
                // Change counters: who keeps re-rendering the open Emper.
                var counts = [String: Int]()
                benchBag.append(c.model.objectWillChange.sink { counts["model", default: 0] += 1 })
                benchBag.append(NowPlaying.shared.objectWillChange.sink { counts["nowPlaying", default: 0] += 1 })
                benchBag.append(TimerService.shared.objectWillChange.sink { counts["timer", default: 0] += 1 })
                benchBag.append(c.model.pointer.objectWillChange.sink { counts["pointer", default: 0] += 1 })
                Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
                    MainActor.assumeIsolated {
                        FileHandle.standardError.write("counts/3s \(counts.sorted { $0.key < $1.key }) size=\(c.model.size) sel=\(c.model.selectedID)\n".data(using: .utf8)!)
                        counts = [:]
                    }
                }
                // `--tab <id>`: stay on one tab; `--cycle`: switch to the next tab every 0.7 s (tab hopping).
                let args = CommandLine.arguments
                if let i = args.firstIndex(of: "--tab"), i + 1 < args.count {
                    c.select(args[i + 1])
                    FileHandle.standardError.write("tab=\(c.model.selectedID)\n".data(using: .utf8)!)
                }
                if args.contains("--cycle") {
                    var k = 0
                    Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { _ in
                        MainActor.assumeIsolated {
                            // `--cycle a,b`: only those tabs.
                            var ids = c.tabIDs
                            if let j = args.firstIndex(of: "--cycle"), j + 1 < args.count, !args[j + 1].hasPrefix("--") {
                                ids = args[j + 1].split(separator: ",").map(String.init)
                            }
                            guard !ids.isEmpty else { return }
                            k = (k + 1) % ids.count
                            c.select(ids[k])
                        }
                    }
                }
                guard moving else { return }
                // Like a real mouse: ~250 move events a second through the manager (all Empers, drag check, poll).
                var t = 0.0
                Timer.scheduledTimer(withTimeInterval: 1.0 / 250, repeats: true) { _ in
                    MainActor.assumeIsolated {
                        t += 1.0 / 250
                        manager.pointerOverride = CGPoint(x: r.midX + 60 * sin(t * 2), y: r.maxY - 12 - 4 * cos(t * 3))
                        manager.pointerMoved()
                        if Int(t * 250) % 750 == 0 { FileHandle.standardError.write("open=\(c.model.isExpanded)\n".data(using: .utf8)!) }
                    }
                }
            }
        }
    }

    /// `Emper --render <dir>`: writes PNGs of the open top island (Home, edit mode, calculator) for a
    /// visual check without screen capture. Temp config, simulated track, real cursor ignored.
    static func render(manager: IslandManager, store: ConfigStore, dock: DockMonitor, to dir: URL) {
        manager.followsRealPointer = false
        NowPlaying.shared.offline = true
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let screen = NSScreen.screens.first, let c = manager.controller(for: screen, edge: .top) else { exit(1) }
        func shot(_ name: String) {
            guard let v = c.panel.contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return }
            v.cacheDisplay(in: v.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent(name + ".png"))
        }
        NowPlaying.shared.simulate(title: "Test Song", playing: true)
        store.holdExpanded = true
        after(1.0) {
            let r = c.currentRect
            c.pointerMoved(to: CGPoint(x: r.midX + 60, y: r.minY + 20))   // over the seek bar area
            after(0.5) {
                shot("home")
                // Seek-bar hover now comes from the frame the seek bar registers (round 21).
                let sf = c.model.pointer.seekFrame
                if !sf.isNull {
                    c.model.pointer.location = CGPoint(x: sf.midX, y: sf.midY)
                    let on = c.model.pointer.seekHover
                    c.model.pointer.location = CGPoint(x: sf.midX, y: sf.maxY + 40)
                    FileHandle.standardError.write("seek hover check: on=\(on) off=\(!c.model.pointer.seekHover) frame=\(sf)\n".data(using: .utf8)!)
                } else { FileHandle.standardError.write("seek hover check: no seek bar frame\n".data(using: .utf8)!) }
                // Big render of the floating "+" to check the glyph sits in the middle of its circle.
                let big = ImageRenderer(content: AddSlotButton(model: c.model, left: true).padding(6))
                big.scale = 8
                if let img = big.nsImage, let t = img.tiffRepresentation, let r = NSBitmapImageRep(data: t) {
                    try? r.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("plus-big.png"))
                }
                // Same check for the idle stopwatch glyph (round 22), drawn alone in a 22-pt box.
                let sw = ImageRenderer(content: StopwatchGlyph(size: 11).frame(width: 22, height: 22).background(Color.white).foregroundStyle(Color.black))
                sw.scale = 8
                if let img = sw.nsImage, let t = img.tiffRepresentation, let r = NSBitmapImageRep(data: t) {
                    try? r.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("stopwatch-big.png"))
                }
                // Round 23: the three source marks, big, on the Emper's black.
                let marks = ImageRenderer(content: HStack(spacing: 8) {
                    SpotifyMark().frame(width: 16, height: 16)
                    AppleMusicMark().frame(width: 16, height: 16)
                }.padding(6).background(Color.black))
                marks.scale = 8
                if let img = marks.nsImage, let t = img.tiffRepresentation, let r = NSBitmapImageRep(data: t) {
                    try? r.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("sources-big.png"))
                }
                c.model.editingHome = true
                after(0.6) {
                    shot("home-edit")
                    c.model.editingHome = false
                    // Round 23: Desmond's picker, opened from the left side slot.
                    HomeEditState.renderPick = 0
                    after(0.3) { c.model.editingHome = true }
                    after(0.9) {
                    shot("home-picker")
                    HomeEditState.renderPick = nil
                    c.model.editingHome = false
                    c.select("calculator")
                    after(0.6) {
                        shot("calculator")
                        c.select(ModuleRegistry.homeID)
                        after(0.5) {
                            shot("home-calc")
                            store.update(screen, .top) { $0.homeSlots = ["music", "timer", "stats"] }
                            after(0.5) {
                                shot("timer-main")
                                for _ in 0..<12 { SystemStats.shared.sample(); usleep(60_000) }
                                store.update(screen, .top) { $0.homeSlots = ["music", "stats", "timer"] }
                                after(0.5) {
                                    shot("stats-main")
                                    NowPlaying.shared.simulate(title: "", playing: false)
                                    store.holdExpanded = false
                                    TimerService.shared.toggle()
                                    after(0.8) {
                                        shot("timer-idle")
                                        NowPlaying.shared.simulate(title: "Test Song", playing: true)
                                        after(0.6) {
                                        shot("dual-idle")
                                        TimerService.shared.reset()
                                        NowPlaying.shared.simulate(title: "", playing: false)
                                        c.showToast(IslandToast(symbol: "headphones", title: "AirPods Pro", battery: 0.8), for: 5)
                                        after(0.6) {
                                            shot("toast")
                                            // Round 23: lyric under a (pretend) built-in notch.
                                            c.model.toast = nil
                                            let keep = c.model.config
                                            var nc = keep; nc.notchLyrics = .below
                                            NowPlaying.shared.lyricsEnabled = true
                                            NowPlaying.shared.simulate(title: "Test Song", playing: true)
                                            NowPlaying.shared.simulateLyrics([LyricLine(time: 0, text: "Small lyric line under the notch"), LyricLine(time: 90, text: "Next")])
                                            c.update(config: nc, area: screen.frame, clearance: 32, hold: false)
                                            after(0.8) {
                                            shot("notch-lyric-below")
                                            c.update(config: keep, area: screen.frame, clearance: 0, hold: false)
                                            NowPlaying.shared.simulate(title: "", playing: false)
                                            store.setGlobal { $0.style = .island }
                                            after(0.8) {
                                                let fc = manager.controller(for: screen, edge: .top) ?? c
                                                if let v = fc.panel.contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
                                                    v.cacheDisplay(in: v.bounds, to: rep)
                                                    try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("island-style.png"))
                                                }
                                                renderSides(manager: manager, store: store, screen: screen, to: dir) {
                                                    renderSettings(store: store, dock: dock, to: dir)
                                                    print("rendered to \(dir.path)")
                                                    exit(0)
                                                }
                                                }
                                            }
                                        }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// Right Emper open on Music, pushed into the top corner (must stop below the menu bar), and the bottom
    /// left corner Emper open (must stay flush with the side). Drawn with the panel's screen frame noted.
    private static func renderSides(manager: IslandManager, store: ConfigStore, screen: NSScreen, to dir: URL,
                                    done: @escaping () -> Void) {
        func shot(_ c: IslandController?, _ name: String) {
            guard let c, let v = c.panel.contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return }
            v.cacheDisplay(in: v.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent(name + ".png"))
            print("\(name): panel \(c.panel.frame) island \(c.currentRect) screen \(screen.frame) visible \(screen.visibleFrame)")
        }
        store.setGlobal { $0.style = .notch; $0.lyricsEnabled = true }
        store.update(screen, .right) { $0.enabled = true; $0.moduleIDs = ["music"]; $0.offset = Double(screen.frame.height) }
        store.update(screen, .bottom) { $0.enabled = true; $0.bottomLayout = .oneSide; $0.bottomSide = .leading; $0.offset = 0 }
        NowPlaying.shared.simulate(title: "A Rather Long Song Title For Testing", playing: true)
        store.holdExpanded = true
        after(1.0) {
            shot(manager.controller(for: screen, edge: .right), "right-music-corner")
            shot(manager.controller(for: screen, edge: .bottom), "bottom-left-open")
            store.update(screen, .right) { $0.offset = 0 }
            after(0.8) {
                shot(manager.controller(for: screen, edge: .right), "right-music-centre")
                // Round 23: Home on a side Emper (column), then pencil mode.
                store.update(screen, .right) { $0.homeEnabled = true; $0.homeSlots = ["", "music", ""]; $0.homeSizes = [1, 1, 1.5] }
                after(0.3) { manager.controller(for: screen, edge: .right)?.select(ModuleRegistry.homeID) }
                after(0.8) {
                shot(manager.controller(for: screen, edge: .right), "right-home")
                manager.controller(for: screen, edge: .right)?.model.beginEdit()
                after(0.6) {
                shot(manager.controller(for: screen, edge: .right), "right-home-edit")
                manager.controller(for: screen, edge: .right)?.model.cancelEdit()
                store.update(screen, .right) { $0.homeEnabled = false }
                store.holdExpanded = false
                NowPlaying.shared.simulate(title: "", playing: false)
                after(0.8) {
                    shot(manager.controller(for: screen, edge: .bottom), "bottom-left-idle")
                    store.update(screen, .bottom) { $0.homeEnabled = true; $0.setTab("timer", true); if !$0.homeSlots.contains("timer") { $0.homeSlots.append("timer") } }
                    TimerService.shared.toggle()
                    after(0.8) {
                        shot(manager.controller(for: screen, edge: .bottom), "bottom-timer-idle")
                        TimerService.shared.reset()
store.holdExpanded = true
                // Round 28: tall left Emper in pencil mode (the "+" must stay 30 pt off its ends).
                store.update(screen, .left) { $0.enabled = true; $0.homeEnabled = true; $0.styleChoice = .island
                    $0.homeSlots = ["", "", "music", ""]; $0.homeSizes = [1.5, 1, 1, 1.5]; $0.homeMain = 2 }
                after(0.3) { manager.controller(for: screen, edge: .left)?.select(ModuleRegistry.homeID); manager.controller(for: screen, edge: .left)?.model.beginEdit() }
                after(1.0) {
                    shot(manager.controller(for: screen, edge: .left), "left-home-edit-tall")
                    manager.controller(for: screen, edge: .left)?.model.cancelEdit()
                    // Round 28: two sides above, none below; Reminder at its 1.5x default; Quick Note.
                    QuickNote.shared.text = "Call the printer about the A3 proofs\nBuy oat milk"
                    store.update(screen, .left) { $0.homeSlots = ["note", "reminder", "music"]; $0.homeSizes = [1, 1.5, 1]; $0.homeMain = 2 }
                    after(1.0) {
                        shot(manager.controller(for: screen, edge: .left), "left-home-note-reminder")
                        // Round 29: Emper's own dropdown (Repeat) open inside the side card.
                        DropdownCenter.renderOpen = "-repeat"
                        store.update(screen, .left) { $0.homeSlots = ["reminder", "note", "music"]; $0.homeSizes = [1.5, 1, 1] }
                        after(1.0) {
                        shot(manager.controller(for: screen, edge: .left), "left-reminder-dropdown")
                        // Round 30: date calendar in the side card, minutes box taking typing.
                        DropdownCenter.renderOpen = "-day"
                        TimeEntry.shared.begin(.minute)
                        store.update(screen, .left) { $0.homeSlots = ["note", "reminder", "music"]; $0.homeSizes = [1, 1.5, 1] }
                        after(1.0) {
                        shot(manager.controller(for: screen, edge: .left), "left-reminder-calendar")
                        TimeEntry.shared.end()
                        DropdownCenter.renderOpen = nil
                        manager.controller(for: screen, edge: .left)?.model.beginEdit()
                        manager.controller(for: screen, edge: .left)?.model.addingTab = true
                        after(0.8) {
                        shot(manager.controller(for: screen, edge: .left), "left-add-tab")
                        manager.controller(for: screen, edge: .left)?.model.cancelEdit()
                        store.update(screen, .left) { $0.homeEnabled = false }
                        store.update(screen, .top) { $0.homeEnabled = true; $0.homeSlots = ["note", "music", "reminder"]; $0.homeSizes = [1, 1, 1.5]; $0.homeMain = 1 }
                        after(1.0) {
                            shot(manager.controller(for: screen, edge: .top), "top-home-note-reminder")
                            store.update(screen, .top) { $0.setTab("reminder", true) }
                            after(0.3) { manager.controller(for: screen, edge: .top)?.select("reminder") }
                            after(1.0) {
                                shot(manager.controller(for: screen, edge: .top), "top-reminder-tab")
                                // Round 30: date calendar open, minutes box taking typing.
                                DropdownCenter.renderOpen = "-day"
                                TimeEntry.shared.begin(.minute)
                                store.update(screen, .top) { $0.homeEnabled = false }
                                after(0.3) { manager.controller(for: screen, edge: .top)?.select("reminder") }
                                after(1.2) {
                                shot(manager.controller(for: screen, edge: .top), "top-reminder-calendar")
                                DropdownCenter.renderOpen = nil
                                TimeEntry.shared.end()
                                store.holdExpanded = false
                                done()
                                }
                        }
                            }
                        }
                        }
                        }
                    }
                }

                    }
                }
            }
                }
                }
        }
    }

    /// Prints every island's screen, panel, idle rect and idle hover zone (copy of the real settings).
    static func dumpZones(manager: IslandManager) {
        manager.followsRealPointer = false
        after(1.0) {
            for s in NSScreen.screens { print("screen \(s.emperID) frame \(s.frame) visible \(s.visibleFrame) notch \(String(describing: s.notchSize))") }
            for (k, c) in manager.allControllers.sorted(by: { $0.key < $1.key }) {
                let z = IslandGeometry.idleHotZone(c.model.config, panel: c.panel.frame)
                print("\(k) style \(c.model.config.style) anchor \(c.model.config.anchor) gap \(c.model.config.edgeGap)\n  panel \(c.panel.frame)\n  idle \(c.currentRect)\n  zone \(z) level \(c.panel.level.rawValue)")
            }
            exit(0)
        }
    }

    /// Every Settings page, drawn off screen at the default window size.
    private static func renderSettings(store: ConfigStore, dock: DockMonitor, to dir: URL) {
        for page in SettingsPage.allCases {
            let v = NSHostingView(rootView: SettingsView(store: store, dock: dock, page: page))
            v.appearance = NSAppearance(named: .darkAqua)
            let w = NSWindow(contentRect: NSRect(x: -4000, y: 0, width: 880, height: 720), styleMask: [.borderless], backing: .buffered, defer: false)
            w.contentView = v
            w.orderFrontRegardless()
            v.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            if let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
                v.cacheDisplay(in: v.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("settings-\(page.rawValue).png"))
            }
            w.orderOut(nil)
        }
    }

    /// Pencil edits: +/- placeholders (left first), swap, sizes follow; stats sample; music search keys.
    private static func homeChecks(_ c: IslandController, store: ConfigStore, screen: NSScreen, check: (String, Bool) -> Void) {
        // v0.1.0: new top Empers start with Quick Note and Screenshots beside music (main).
        check("default Home: note | music (main) | screenshots \(IslandConfig.defaults(for: .top).homeSlots)",
              IslandConfig.defaults(for: .top).homeSlots == ["note", "music", "screenshots"])
        c.model.onHomeSlots(["timer", "music", "stats"])
        // Round 23: left/right Empers lay Home out as a column.
        var lc = IslandConfig.defaults(for: .left)
        lc.homeEnabled = true
        lc.homeSlots = ["", "music", ""]
        let col = ModuleRegistry.homeRow(lc)
        // Round 26: side slots as tall as the main one (4/5 as wide); the tab column adds width, not height.
        let side = HomeLayout.verticalMain
        check("side Emper Home is a column \(fmt(col)) = 260 x (3 x 170 + 2 gaps of 18)",
              col.width == HomeLayout.verticalWidth && col.height == HomeLayout.verticalMain + 2 * side + 2 * HomeLayout.verticalSpacing)
        let lopen = IslandGeometry.expandedSize(content: col, config: lc, tabBar: true)
        let lins = IslandGeometry.contentInsets(lc)
        check("side Emper tab column adds width \(fmt(lopen))",
              lopen.width == col.width + lins.leading + lins.trailing + IslandGeometry.tabBarHeight + IslandGeometry.tabGap(lc)
              && lins.leading == IslandGeometry.tabGap(lc)
              && lopen.height == col.height + lins.top + lins.bottom)
        // Round 27: room for the "+" buttons along the screen; one more 1x slot costs side + gap.
        var rc = lc
        rc.area = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let room3 = IslandGeometry.homeRoom(rc)
        rc.homeSlots = HomeLayout.adding(rc.homeSlots, left: true).slots
        let room4 = IslandGeometry.homeRoom(rc)
        check("side Emper room shrinks by one slot + gap per placeholder (\(Int(room3)) -> \(Int(room4)))",
              abs(room3 - room4 - (HomeLayout.verticalMain + HomeLayout.verticalSpacing)) < 1 && room3.isFinite)
        rc.homeSlots = HomeLayout.resized(rc.homeSlots, to: 5)
        check("5 side-Emper placeholders do not fit a 900-pt-tall screen with their + buttons (room \(Int(IslandGeometry.homeRoom(rc))))",
              IslandGeometry.homeRoom(rc) < 0)
        lc.setHomeSize(0, 2)
        check("side Emper placeholder stops at 1.5x \(lc.homeSlotScales)", lc.homeSlotScales[0] == 1.5)
        check("side Emper placeholder grows in height at 1.5x \(fmt(ModuleRegistry.homeRow(lc)))",
              ModuleRegistry.homeRow(lc).height > col.height && ModuleRegistry.homeRow(lc).width == col.width)
        let lp = IslandGeometry.panelFrame(for: lc, maxSize: col, in: screen.frame)
        check("side Emper panel has room for + above and below (\(Int(lp.height)) >= \(Int(col.height + 2 * IslandGeometry.sideButtonRoom)))",
              lp.height >= col.height + 2 * IslandGeometry.sideButtonRoom)
        let before = c.model.size.width
        c.model.onHomeSlots(HomeLayout.resized(c.model.config.homeSlots, to: 4))
        check("4 placeholders: new one on the left \(c.model.config.homeSlots)", c.model.config.homeSlots == ["", "timer", "music", "stats"])
        check("placeholder change saved to the config", store.display(for: screen)[.top].homeSlots.count == 4)
        c.update(config: store.display(for: screen)[.top], area: screen.frame, clearance: c.model.clearance, hold: false)
        c.pointerMoved(to: CGPoint(x: c.currentRect.midX, y: screen.frame.maxY - 1))
        let wide = c.model.size.width
        check("open width \(Int(before)) -> \(Int(wide)) with 4 placeholders", wide > before || !c.model.isExpanded)
        c.pointerMoved(to: CGPoint(x: screen.frame.midX, y: screen.frame.midY - 300))
        c.model.onHomeSlots(HomeLayout.swapped(c.model.config.homeSlots, 1, 2))
        check("drag swap timer <-> music", c.model.config.homeSlots == ["", "music", "timer", "stats"])
        // Round 23: picker fill, remove, resize and cancel (pencil mode end to end on the model).
        c.model.onHomeSlots(HomeLayout.assigned(c.model.config.homeSlots, at: 0, "clipboard"))
        check("picker puts clipboard in the empty placeholder \(c.model.config.homeSlots)", c.model.config.homeSlots == ["clipboard", "music", "timer", "stats"])
        c.model.onHomeSlots(HomeLayout.assigned(c.model.config.homeSlots, at: 0, "stats"))
        check("picking a feature already on Home swaps it \(c.model.config.homeSlots)", c.model.config.homeSlots == ["stats", "music", "timer", "clipboard"])
        let rm = HomeLayout.removing(c.model.config.homeSlots, main: c.model.config.homeMainIndex, at: 0)
        c.model.onHomeSlots(rm.slots, rm.main)
        check("remove left placeholder keeps the main widget main \(c.model.config.homeSlots)",
              c.model.config.homeSlots.count == 3 && c.model.config.homeSlots[c.model.config.homeMainIndex] == "timer")
        // Round 28: sides are free: two on the left, none on the right.
        let rr = HomeLayout.removing(c.model.config.homeSlots, main: c.model.config.homeMainIndex, at: 2)
        c.model.onHomeSlots(rr.slots, rr.main)
        let al = HomeLayout.adding(c.model.config.homeSlots, main: c.model.config.homeMainIndex, left: true)
        c.model.onHomeSlots(al.slots, al.main)
        // Round 29: typed reminder time.
        let rd = ReminderDraft.shared
        rd.reset()
        check("reminder time defaults to 09:00", rd.time == 9 * 60)
        check("time box keeps two digits", ReminderDraft.digits("1a2:3") == "12")
        let h1 = rd.typeHour("1"), h2 = rd.typeHour("14")
        check("hour 1 waits, 14 moves on", !h1 && h2)
        check("typed hour 14 → \(rd.time / 60)", rd.time / 60 == (ReminderDraft.uses12h ? 0 : 14))
        check("minute 7 completes", rd.typeMinute("7"))
        rd.nudge(hour: false, by: -8)
        check("↓ wraps minutes \(rd.time % 60)", rd.time % 60 == 59)
        rd.typeMinute("7")
        check("typed minute 7 → \(rd.time % 60)", rd.time % 60 == 7)
        rd.reset()
        check("free sides: 2 left, 0 right, main last \(c.model.config.homeSlots) main \(c.model.config.homeMainIndex)",
              c.model.config.homeSlots == ["", "music", "timer"] && c.model.config.homeMainIndex == 2
              && store.display(for: screen)[.top].homeMain == 2)
        c.model.onHomeSlots(["timer", "music", "stats"], 1)
        c.model.beginEdit()
        let w1 = HomeLayout.contentWidth(main: 384, count: 3, scales: c.model.config.homeSlotScales)
        c.model.onEditConfig { $0.setHomeSize(0, 1.5) }
        let w15 = HomeLayout.contentWidth(main: 384, count: 3, scales: c.model.config.homeSlotScales)
        c.model.onEditConfig { $0.setHomeSize(0, 2) }
        let w2 = HomeLayout.contentWidth(main: 384, count: 3, scales: c.model.config.homeSlotScales)
        check("resize side 1x/1.5x/2x widens the row \(Int(w1)) < \(Int(w15)) < \(Int(w2))", w1 < w15 && w15 < w2)
        check("resize saved to the config", store.display(for: screen)[.top].homeSizes.first == 2)
        c.model.onEditConfig { $0.setHomeSize(1, 2) }
        check("main slot never scales", c.model.config.homeSlotScales[1] == 1)
        c.model.onHomeSlots(["", "music", "stats"])
        c.model.onEditConfig { $0.setHomeSize(0, 1.5) }
        check("empty placeholder can be widened too \(c.model.config.homeSlotScales)", c.model.config.homeSlotScales[0] == 1.5)
        // Round 24: picking a feature for a widened empty placeholder keeps its width.
        c.model.onEditConfig { $0.assignHome(0, "clipboard") }
        check("picked feature keeps the widened placeholder's size \(c.model.config.homeSlotScales)",
              c.model.config.homeSlots[0] == "clipboard" && c.model.config.homeSlotScales[0] == 1.5)
        c.model.onEditConfig { $0.setHomeSlots(["clipboard", "music", "timer"]) }
        check("feature dropped in from Settings takes the slot's size \(c.model.config.homeSlotScales)",
              c.model.config.homeSlotScales == [1.5, 1, 1])
        c.model.onEditConfig { $0.assignHome(0, "") }
        // Round 24: free resize, shown live without saving; pins near 1.25 / 1.5 / 1.75 / 2.
        c.model.onPreviewConfig { $0.setHomeSize(0, 1.37) }
        check("live resize shows 1.37x \(c.model.config.homeSlotScales[0]) without saving",
              abs(c.model.config.homeSlotScales[0] - 1.37) < 0.001 && store.display(for: screen)[.top].homeSizes.first == 1.5)
        check("snaps: 1.27 -> 1.25 pinned, 1.37 free, 1.97 -> 2", HomeLayout.snapped(1.27).pinned == 1.25
              && HomeLayout.snapped(1.37).pinned == nil && HomeLayout.snapped(1.97).scale == 2)
        c.model.onEditConfig { $0.setHomeSize(0, 1.5) }
        let ad = HomeLayout.adding(c.model.config.homeSlots, main: c.model.config.homeMainIndex, left: true)
        c.model.onHomeSlots(ad.slots, ad.main)
        check("adding a placeholder keeps the widened one \(c.model.config.homeSlots) \(c.model.config.homeSlotScales)",
              c.model.config.homeSlotScales == [1, 1.5, 1, 1])
        c.model.onHomeSlots(HomeLayout.swapped(c.model.config.homeSlots, 1, 3))
        check("swap: width moves with its card \(c.model.config.homeSlots) \(c.model.config.homeSlotScales)",
              c.model.config.homeSlotScales[3] == 1.5)
        c.model.onHomeSlots(HomeLayout.swapped(c.model.config.homeSlots, 0, 2))
        c.model.cancelEdit()
        check("cancel puts placeholders and sizes back \(c.model.config.homeSlots) \(c.model.config.homeScales)",
              c.model.config.homeSlots == ["timer", "music", "stats"] && c.model.config.homeSlotScales == [1, 1, 1] && !c.model.editingHome)
        c.model.onHomeSlots(["timer", "music", "stats"])

        let stats = SystemStats.shared
        stats.sample()
        Thread.sleep(forTimeInterval: 0.2)
        stats.sample()
        check("stats: cpu \(Int(stats.cpu * 100))% mem \(Int(stats.memory * 100))% gpu \(stats.gpu.map { "\(Int($0 * 100))%" } ?? "n/a")",
              (0...1).contains(stats.cpu) && stats.memory > 0 && stats.memory <= 1)

        let t = TimerService.shared
        t.reset(); t.setMode(.timer)
        check("timer shows 5:00 before start", TimerService.format(t.display()) == "5:00")
        t.adjust(minutes: 2)
        check("timer +2 min -> 7:00", TimerService.format(t.display()) == "7:00")
        t.adjust(minutes: -2)

    }

    /// Uses a private pasteboard, never the user's clipboard.
    private static func clipboardChecks(_ check: (String, Bool) -> Void) {
        let pb = NSPasteboard(name: NSPasteboard.Name("emper-selftest-\(UUID().uuidString)"))
        let h = ClipboardHistory(pasteboard: pb)
        pb.clearContents(); pb.setString("hello", forType: .string); h.poll()
        pb.clearContents(); pb.setString("world", forType: .string); h.poll()
        pb.clearContents()
        pb.declareTypes([.string, NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")], owner: nil)
        pb.setString("secret", forType: .string); h.poll()
        check("clipboard history newest first, concealed skipped (\(h.items.map(\.text)))", h.items.map(\.text) == ["world", "hello"])
        pb.releaseGlobally()
    }

    /// Uses a temp folder, never the real screenshot folder.
    private static func shelfChecks(_ check: (String, Bool) -> Void) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("emper-shelf-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        for (i, name) in ["old.png", "notes.txt", "new.jpg"].enumerated() {
            let u = dir.appendingPathComponent(name)
            FileManager.default.createFile(atPath: u.path, contents: Data([0]))
            try? FileManager.default.setAttributes([.creationDate: Date(timeIntervalSinceNow: Double(i) * 60)], ofItemAtPath: u.path)
        }
        let names = (ScreenshotShelf.scan(dir) ?? []).map(\.url.lastPathComponent)
        check("screenshot shelf: images only, newest first (\(names))", names == ["new.jpg", "old.png"])
    }

    /// Height of opaque island pixels in the panel's centre column, in points.
    private static func drawnDepth(_ c: IslandController) -> Double {
        guard let view = c.panel.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return -1 }
        view.cacheDisplay(in: view.bounds, to: rep)
        let scale = Double(rep.pixelsHigh) / Double(view.bounds.height)
        let x = rep.pixelsWide / 2
        var count = 0
        for y in 0..<rep.pixelsHigh where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 { count += 1 }
        return Double(count) / scale
    }

    private static func fmt(_ d: Double) -> String { String(format: "%.1f", d) }
    private static func fmt(_ s: CGSize) -> String { "\(Int(s.width))x\(Int(s.height))" }

    private static func after(_ s: Double, _ f: @escaping @MainActor () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + s) { MainActor.assumeIsolated { f() } }
    }
}
