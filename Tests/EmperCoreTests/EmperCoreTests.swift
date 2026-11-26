import CoreGraphics
import Foundation
import Testing
@testable import EmperCore

func near(_ a: CGFloat, _ b: Double) -> Bool { abs(Double(a) - b) < 0.001 }

struct GeometryTests {
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)

    let maxS = CGSize(width: 300, height: 260)

    @Test func topPanelIsCentredAndFlush() {
        let c = IslandConfig.defaults(for: .top)
        let f = IslandGeometry.panelFrame(for: c, maxSize: maxS, in: screen)
        #expect(f.maxY == screen.maxY)
        #expect(f.midX == screen.midX)
        #expect(near(f.width, 300 + 2 * Double(IslandGeometry.overshootPadding + IslandGeometry.sideButtonRoom)))
    }

    @Test func offsetMovesAndClamps() {
        var c = IslandConfig.defaults(for: .top)
        c.offset = 100
        #expect(IslandGeometry.panelFrame(for: c, maxSize: maxS, in: screen).midX == screen.midX + 100)
        c.offset = 10_000
        let f = IslandGeometry.panelFrame(for: c, maxSize: maxS, in: screen)
        // Round 27: the panel also keeps the "+ placeholder" reach on screen.
        #expect(near(f.midX, Double(screen.maxX) - 150 - Double(IslandGeometry.addSlotReach)))
    }

    @Test func expandedSizeAddsInsetsAndTabBar() {
        let c = IslandConfig.defaults(for: .top, notch: CGSize(width: 185, height: 32))
        let s = IslandGeometry.expandedSize(content: CGSize(width: 200, height: 100), config: c, tabBar: true, clearance: 32)
        // Sides: flare 10 + margin 18 each, but never under the minimum open width. Top clears the notch + 6. Bottom 14.
        #expect(near(s.width, Double(IslandGeometry.minOpenWidth)))
        #expect(near(s.height, 100 + (32 + 6) + 14 + IslandGeometry.tabBarHeight + IslandGeometry.tabSpacing))
        let wide = IslandGeometry.expandedSize(content: CGSize(width: 500, height: 100), config: c, tabBar: true, clearance: 32)
        #expect(near(wide.width, 556))
        // No notch: tabs go up to 10 pt from the top.
        #expect(IslandGeometry.contentInsets(c, clearance: 0).top == 10)
    }

    @Test func idleHotZoneIsNotchLengthMinusMargin() {
        let c = IslandConfig.defaults(for: .top, notch: CGSize(width: 220, height: 38)) // idle 232 x 38, inset 6
        let panel = IslandGeometry.panelFrame(for: c, maxSize: CGSize(width: 400, height: 300), in: screen)
        let z = IslandGeometry.idleHotZone(c, panel: panel, sides: 6, far: 6)
        #expect(near(z.width, 220 - 12))
        #expect(near(z.maxY, screen.maxY + 2))       // reaches past the top edge
        #expect(near(z.minY, screen.maxY - 32))      // 38 deep minus 6
        #expect(near(z.midX, screen.midX))
    }

    @Test func sideAndFarMarginsAreSeparate() {
        var c = IslandConfig.defaults(for: .top) // no notch: 200 x 24
        c.hoverInset = 10; c.hoverInsetFar = 4
        let panel = IslandGeometry.panelFrame(for: c, maxSize: CGSize(width: 400, height: 300), in: screen)
        let z = IslandGeometry.idleHotZone(c, panel: panel)
        #expect(near(z.width, 200 - 12 - 20))
        #expect(near(z.minY, screen.maxY - 20))       // 24 deep minus 4
        #expect(near(z.maxY, screen.maxY + 2))        // the edge side has no margin
    }

    @Test func newDefaultsAndOldFilesDecode() throws {
        let top = IslandConfig.defaults(for: .top)
        #expect(top.collapsedWidth == 200 && top.cornerRadius == 15 && top.closeDelayMs == 120 && top.openDelayMs == 0)
        #expect(IslandConfig.defaults(for: .left).cornerRadius == 15 && IslandConfig.defaults(for: .right).cornerRadius == 15)
        let old = #"{"edge":"top","hoverInset":9}"#
        let c = try JSONDecoder().decode(IslandConfig.self, from: Data(old.utf8))
        #expect(c.hoverInset == 9 && c.hoverInsetFar == 9)
        let g = try JSONDecoder().decode(EmperConfig.self, from: Data(#"{"version":3}"#.utf8))
        #expect(g.showInFullScreen && g.screenshotFolder == nil)
    }

    @Test func inlineLyricWidensButNeverDeepens() {
        let c = IslandConfig.defaults(for: .top) // no notch: 200 x 24
        let base = IslandGeometry.liveSize(c)
        let short = IslandGeometry.liveSize(c, lyricWidth: 10)
        let long = IslandGeometry.liveSize(c, lyricWidth: 300)
        let huge = IslandGeometry.liveSize(c, lyricWidth: 5000)
        #expect(short == base)
        #expect(long.width > base.width && long.height == base.height)
        #expect(near(huge.width, Double(IslandGeometry.maxLiveWidth)))
        let notched = IslandConfig.defaults(for: .top, notch: CGSize(width: 185, height: 32))
        let n = IslandGeometry.liveSize(notched, lyricWidth: 200, notch: true)
        #expect(n.height == 32 && n.width > IslandGeometry.liveSize(notched).width)
        let side = IslandGeometry.liveSize(.defaults(for: .left), lyricWidth: 300)
        #expect(side == IslandGeometry.liveSize(.defaults(for: .left)))
    }

    @Test func openIslandNeverNarrowerThanIdle() {
        var c = IslandConfig.defaults(for: .top)
        c.collapsedWidth = 600
        let s = IslandGeometry.expandedSize(content: CGSize(width: 200, height: 100), config: c, tabBar: true)
        #expect(s.width == 600)
    }

    @Test func onlyMainDisplayGetsTopIslandByDefault() {
        #expect(DisplayConfig.defaults(notch: nil, isMain: true)[.top].enabled)
        #expect(!DisplayConfig.defaults(notch: nil, isMain: false)[.top].enabled)
    }

    @Test func liveSizeAddsWings() {
        let c = IslandConfig.defaults(for: .top, notch: CGSize(width: 185, height: 32))
        let l = IslandGeometry.liveSize(c)
        #expect(l.height == 32)
        #expect(near(l.width, c.collapsedWidth + 96))
    }

    @Test func sideIslandsAttachToTheirEdge() {
        let l = IslandGeometry.panelFrame(for: .defaults(for: .left), maxSize: maxS, in: screen)
        let r = IslandGeometry.panelFrame(for: .defaults(for: .right), maxSize: maxS, in: screen)
        let b = IslandGeometry.panelFrame(for: .defaults(for: .bottom), maxSize: maxS, in: screen)
        #expect(l.minX == screen.minX)
        #expect(r.maxX == screen.maxX)
        #expect(b.minY == screen.minY)
    }

    @Test func secondDisplayUsesItsOwnOrigin() {
        let ext = CGRect(x: 1512, y: -200, width: 2560, height: 1440)
        let f = IslandGeometry.panelFrame(for: .defaults(for: .top), maxSize: maxS, in: ext)
        #expect(f.maxY == ext.maxY)
        #expect(f.midX == ext.midX)
    }

    @Test func hotZoneHasMinimumDepthForThinIslands() {
        let thin = CGRect(x: 0, y: 400, width: 3, height: 140)
        let z = IslandGeometry.hotZone(for: thin, edge: .left)
        #expect(z.contains(CGPoint(x: 0, y: 450)))
        #expect(z.contains(CGPoint(x: 7, y: 450)))
        #expect(!z.contains(CGPoint(x: 20, y: 450)))
    }
}

struct DockTests {
    @Test func parse() {
        #expect(DockInfo.parse(orientation: nil, autohide: nil).edge == .bottom)
        #expect(DockInfo.parse(orientation: "left", autohide: true) == DockInfo(edge: .left, autohide: true))
        #expect(DockInfo.parse(orientation: "right", autohide: nil).edge == .right)
    }
}

struct ConfigTests {
    @Test func notchSizedTopDefault() {
        let c = IslandConfig.defaults(for: .top, notch: CGSize(width: 185, height: 32))
        #expect(c.collapsedWidth == 185 + 2 * IslandConfig.notchFlare)
        #expect(c.collapsedHeight == 32)
    }

    @Test func roundTripAndTolerantDecode() throws {
        var cfg = EmperConfig()
        cfg.displays["A"] = DisplayConfig.defaults(notch: nil)
        let data = try JSONEncoder().encode(cfg)
        #expect(try JSONDecoder().decode(EmperConfig.self, from: data) == cfg)

        let partial = #"{"edge":"right","enabled":true}"#.data(using: .utf8)!
        let i = try JSONDecoder().decode(IslandConfig.self, from: partial)
        #expect(i.enabled && i.moduleIDs == ["music"])

        let old = #"{"edge":"top","moduleID":"spotify"}"#.data(using: .utf8)!
        #expect(try JSONDecoder().decode(IslandConfig.self, from: old).moduleIDs == ["music"])
    }

    @Test func v2FilesMigrateAndGainScreenshots() throws {
        let json = #"{"version":2,"lyricsEnabled":true,"displays":{"A":{"islands":{"top":{"edge":"top","moduleIDs":["clipboard"],"collapsedWidth":300}}}}}"#
        let old = try JSONDecoder().decode(EmperConfig.self, from: json.data(using: .utf8)!)
        let m = old.migrated()
        #expect(m.version == EmperConfig.currentVersion)
        #expect(m.displays["A"]?[.top].moduleIDs == ["clipboard", "screenshots"])
        #expect(m.displays["A"]?[.top].collapsedWidth == 300)   // tuning kept
        #expect(m.displays["A"]?[.top].hoverInset == 5 && m.displays["A"]?[.top].hoverInsetFar == 5 && m.lyricsEnabled && m.idleLyrics)
    }

    @Test func noNotchTopUsesMenuBarHeight() {
        #expect(IslandConfig.defaults(for: .top, notch: nil, menuBarHeight: 25).collapsedHeight == 25)
    }
}

struct CalculatorTests {
    @Test func keyboardTyping() {
        var e = CalculatorEngine()
        for k in ["1", "2", ",", "5", "*", "2", "enter"] { _ = e.type(k) }
        #expect(e.display == "25")
        for k in ["7", "8", "delete"] { _ = e.type(k) }
        #expect(e.display == "7")
        let cleared = e.type("escape")
        #expect(cleared && e.display == "0")
        let unknown = e.type("q")
        #expect(!unknown)
    }

    func run(_ keys: String) -> String {
        var e = CalculatorEngine()
        for ch in keys {
            switch ch {
            case "0"..."9": e.digit(Int(String(ch))!)
            case ".": e.decimal()
            case "+": e.operation(.add)
            case "-": e.operation(.subtract)
            case "*": e.operation(.multiply)
            case "/": e.operation(.divide)
            case "=": e.equals()
            case "%": e.percent()
            case "c": e.clear()
            default: break
            }
        }
        return e.display
    }

    @Test func basics() {
        #expect(run("12+7=") == "19")
        #expect(run("2*3+4=") == "10")
        #expect(run("0.1+0.2=") == "0.3")
        #expect(run("1/0=") == "Error")
        #expect(run("9-12=") == "-3")
        #expect(run("50+10%=") == "50.1")
        #expect(run("5+*2=") == "10")
        #expect(run("7c") == "0")
    }
}

struct LyricsTests {
    @Test func parseAndIndex() {
        let lines = LRC.parse("[ar:Someone]\n[00:01.50]Hello\n[00:05.00][00:10.00]Again\n[00:03.00] World ")
        #expect(lines.map(\.text) == ["Hello", "World", "Again", "Again"])
        #expect(lines[1].time == 3)
        #expect(LRC.index(at: 0.5, in: lines) == nil)
        #expect(LRC.index(at: 4, in: lines) == 1)
        #expect(LRC.index(at: 99, in: lines) == 3)
    }

    @Test func sameTimestampLineIsTranslation() {
        let lines = LRC.parse("[00:01.00]君のための歌\n[00:01.00]A song for you\n[00:04.00]Next")
        #expect(lines.count == 2)
        #expect(lines[0].text == "君のための歌" && lines[0].translation == "A song for you")
        #expect(lines[1].translation == nil)
        let caret = LRC.parse("[00:27.85]全ての声を掲げる音がした^I heard the sound of raising all voices")
        #expect(caret[0].text == "全ての声を掲げる音がした" && caret[0].translation == "I heard the sound of raising all voices")
    }
}

@Test func homeMainSlotLeftFirst() {
    #expect((1...5).map { HomeLayout.mainIndex(count: $0) } == [0, 1, 1, 2, 2])
    #expect(HomeLayout.resized(["music"], to: 2) == ["", "music"])
    #expect(HomeLayout.resized(["", "music"], to: 3) == ["", "music", ""])
    #expect(HomeLayout.resized(["timer", "music", "stats"], to: 5) == ["", "timer", "music", "stats", ""])
    #expect(HomeLayout.resized(["", "timer", "music", "stats", ""], to: 1) == ["music"])
    #expect(HomeLayout.resized(["timer", "music", "stats"], to: 9).count == 5)
}

@Test func homeSlotSizesAndHitTest() {
    let f = HomeLayout.slotFrames(main: 400, count: 3)
    #expect(f.map(\.width) == [120, 400, 120])
    #expect(f.map(\.x) == [0, 132, 544])
    #expect(HomeLayout.contentWidth(main: 400, count: 3) == 664)
    // 2× side = two side slots plus the gap between them.
    #expect(HomeLayout.sideWidth(main: 400, scale: 2) == 252)
    #expect(HomeLayout.contentWidth(main: 400, count: 3, scales: [2, 1, 1.5]) == CGFloat(862)) // 252 + 12 + 400 + 12 + 186 (round 23 gap 12)
    #expect(HomeLayout.slot(at: 50, main: 400, count: 3) == 0)
    #expect(HomeLayout.slot(at: 300, main: 400, count: 3) == 1)
    #expect(HomeLayout.slot(at: 900, main: 400, count: 3) == 2)
}

@Test func homeCycleSkipsUsedWidgets() {
    #expect(HomeLayout.cycled(["timer", "music", ""], at: 2) == ["timer", "music", "stats"])
    #expect(HomeLayout.cycled(["timer", "music", "reminder"], at: 2) == ["timer", "music", ""])   // last feature (round 28)
    #expect(HomeLayout.swapped(["a", "b"], 0, 1) == ["b", "a"])
}

@Test func homeMenuAssignAddRemove() {
    // Picking a feature already in another slot swaps the two.
    #expect(HomeLayout.assigned(["timer", "music", "stats"], at: 0, "stats") == ["stats", "music", "timer"])
    #expect(HomeLayout.assigned(["timer", "music", "stats"], at: 2, "") == ["timer", "music", ""])
    // Round 28: + on either side keeps the main slot where it is (its index moves with a left add).
    let left = HomeLayout.adding(["timer", "music", "stats"], main: 1, left: true)
    #expect(left.slots == ["", "timer", "music", "stats"] && left.main == 2)
    let added = HomeLayout.adding(["timer", "music", "stats"], main: 1, left: false)
    #expect(added.slots == ["timer", "music", "stats", ""] && added.main == 1)
    let removed = HomeLayout.removing(["a", "timer", "music", "stats", "b"], main: 2, at: 0)
    #expect(removed.slots == ["timer", "music", "stats", "b"] && removed.main == 1)
    #expect(HomeLayout.removing(["music"], at: 0).slots == ["music"])
    #expect(HomeLayout.removing(["a", "music"], main: 1, at: 1).slots == ["a", "music"])   // main stays
    // Free sides: 2 on the left, none on the right.
    var two = HomeLayout.adding(["music"], main: 0, left: true)
    two = HomeLayout.adding(two.slots, main: two.main, left: true)
    #expect(two.slots == ["", "", "music"] && two.main == 2)
    var c = IslandConfig.defaults(for: .top)
    c.setHomeSlots(two.slots, main: two.main)
    #expect(c.homeMainIndex == 2 && HomeLayout.frames(c)[2].width == HomeLayout.mainLength(c))
    let data = try! JSONEncoder().encode(c)
    #expect(try! JSONDecoder().decode(IslandConfig.self, from: data).homeMainIndex == 2)
    // Left/right Empers: side slots stop at 1.5x.
    var l = IslandConfig.defaults(for: .left)
    l.setHomeSlots(["", "music", ""], main: 1)
    l.setHomeSize(0, 2)
    #expect(l.homeSlotScales[0] == 1.5 && HomeLayout.snapped(1.9, max: 1.5).scale == 1.5)
}

@Test func homeAndTabAreIndependent() {
    var c = IslandConfig.defaults(for: .top)
    c.setHome("note", true)
    #expect(c.onHome("note") && c.hasTab("note"))
    c.setTab("note", false)
    #expect(c.onHome("note") && !c.hasTab("note"))
    c.setTab("note", true)
    c.setHome("note", false)
    #expect(!c.onHome("note") && c.hasTab("note"))
}

@Test func sideSlotsAre30Percent() {
    #expect(HomeLayout.sideWidth(main: 384) == 115)
    let w = HomeLayout.contentWidth(main: 384, count: 3)
    #expect(w == 638, "got \(w)")
}

@Test func globalStyleMigratesFromTopIsland() throws {
    let json = #"{"version":3,"displays":{"A":{"islands":{"top":{"edge":"top","enabled":true,"style":"island"}}}}}"#.data(using: .utf8)!
    let c = try JSONDecoder().decode(EmperConfig.self, from: json)
    #expect(c.style == .island && c.theme == .dark && c.hideInMissionControl)
    let back = try JSONDecoder().decode(EmperConfig.self, from: JSONEncoder().encode(c))
    #expect(back == c)
}

@Test func cornerAnchorsAndFloatingGap() {
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    var c = IslandConfig.defaults(for: .bottom)
    c.area = screen
    let open = CGSize(width: 300, height: 120)
    let idle = IslandGeometry.collapsedSize(c)
    c.anchor = .leading
    let l = IslandGeometry.panelFrame(for: c, maxSize: open, in: screen)
    #expect(l.minY == 0)
    // In the corner: idle and open both stop flush at the screen side.
    #expect(IslandGeometry.islandRect(size: idle, config: c, panel: l).minX == 0)
    #expect(IslandGeometry.islandRect(size: open, config: c, panel: l).minX == 0)
    c.anchor = .trailing
    let r = IslandGeometry.panelFrame(for: c, maxSize: open, in: screen)
    #expect(IslandGeometry.islandRect(size: open, config: c, panel: r).maxX == screen.maxX)
    // Moved inwards: every state grows from the idle centre.
    c.anchor = .leading
    c.offset = 500
    let m = IslandGeometry.panelFrame(for: c, maxSize: open, in: screen)
    let mid = IslandGeometry.islandRect(size: idle, config: c, panel: m).midX
    #expect(mid == 500 + idle.width / 2)
    #expect(IslandGeometry.islandRect(size: open, config: c, panel: m).midX == mid)
    #expect(m.contains(IslandGeometry.islandRect(size: open, config: c, panel: m)))
    // Floating: lifted off the edge and kept 6 pt from the side.
    c.offset = 0
    c.style = .island
    c.edgeGap = 6
    let f = IslandGeometry.panelFrame(for: c, maxSize: open, in: screen)
    #expect(IslandGeometry.islandRect(size: open, config: c, panel: f).minX == 6)
    #expect(IslandGeometry.islandRect(size: idle, config: c, panel: f).minY == 6)
    #expect(IslandGeometry.contentInsets(c).top == 16)
    #expect(IslandGeometry.contentInsets(c, clearance: 32).top == 38)
}

@Test func sideIslandStaysBelowMenuBar() {
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    var c = IslandConfig.defaults(for: .right)
    c.area = screen
    c.topReserve = 33
    c.offset = 480 // idle pushed into the top corner
    let open = CGSize(width: 300, height: 260)
    let p = IslandGeometry.panelFrame(for: c, maxSize: open, in: screen)
    let r = IslandGeometry.islandRect(size: open, config: c, panel: p)
    #expect(r.maxY == screen.maxY - 33)
    #expect(r.maxX == screen.maxX)
    #expect(p.contains(r))
    // Away from the corner it opens centred on the idle spot.
    c.offset = 0
    let p2 = IslandGeometry.panelFrame(for: c, maxSize: open, in: screen)
    #expect(IslandGeometry.islandRect(size: open, config: c, panel: p2).midY == screen.midY)
}

@Test func homeDefaultsTopOnlyAndV4Migration() throws {
    #expect(IslandConfig.defaults(for: .top).homeEnabled)
    #expect(!IslandConfig.defaults(for: .bottom).homeEnabled)
    for e in IslandEdge.allCases {
        #expect(IslandConfig.defaults(for: e).cornerRadius == 15 && IslandConfig.defaults(for: e).idleOpacity == 1)
    }
    let json = #"{"version":3,"displays":{"A":{"islands":{"bottom":{"edge":"bottom","enabled":true,"cornerRadius":3,"idleOpacity":0.15}}}}}"#.data(using: .utf8)!
    let c = try JSONDecoder().decode(EmperConfig.self, from: json).migrated()
    let b = c.displays["A"]?.islands[.bottom]
    #expect(b?.cornerRadius == 15 && b?.idleOpacity == 1 && b?.homeEnabled == false)
}

@Test func styleAndBottomLayoutDecode() throws {
    let json = #"{"edge":"bottom","enabled":true,"style":"island","bottomLayout":"twoSides","bottomSide":"center"}"#.data(using: .utf8)!
    let c = try JSONDecoder().decode(IslandConfig.self, from: json)
    #expect(c.style == .island && c.bottomLayout == .twoSides)
    #expect(c.bottomSide == .leading)
    #expect(c.rightHomeSlots == ["music"])
    let old = try JSONDecoder().decode(IslandConfig.self, from: #"{"edge":"top","enabled":true}"#.data(using: .utf8)!)
    #expect(old.style == .notch && old.bottomLayout == .center)
    let back = try JSONDecoder().decode(IslandConfig.self, from: JSONEncoder().encode(c))
    #expect(back == c)
}

@Test func toastFitsBesideTheNotch() {
    let c = IslandConfig.defaults(for: .top)
    let t = IslandGeometry.toastSize(c, wide: true)
    #expect(t.width >= CGFloat(c.collapsedWidth) + 192)
    #expect(t.height == IslandGeometry.liveDepth(c))
}

@Test func timerIdleIsCompact() {
    let c = IslandConfig.defaults(for: .top)
    let t = IslandGeometry.timerIdleSize(c)
    #expect(t.width < IslandGeometry.toastSize(c, wide: true).width)
    #expect(t.width - CGFloat(c.collapsedWidth) >= 2 * 60)
}

@Test func homeSlotsDecodeDefault() throws {
    let json = #"{"edge":"top","enabled":true}"#.data(using: .utf8)!
    let c = try JSONDecoder().decode(IslandConfig.self, from: json)
    #expect(c.homeSlots == ["note", "music", "screenshots"])   // v0.1.0 default: both sides filled
}

@Test func perEmperStyleChoiceAndGap() throws {
    // Notched top defaults to Notch; everything else follows General.
    #expect(IslandConfig.defaults(for: .top, notch: CGSize(width: 220, height: 38)).styleChoice == .notch)
    #expect(IslandConfig.defaults(for: .top).styleChoice == .general)
    #expect(IslandConfig.defaults(for: .bottom, notch: CGSize(width: 220, height: 38)).styleChoice == .general)
    #expect(StyleChoice.general.resolve(.island) == .island && StyleChoice.notch.resolve(.island) == .notch)
    let old = try JSONDecoder().decode(IslandConfig.self, from: #"{"edge":"bottom","enabled":true}"#.data(using: .utf8)!)
    #expect(old.styleChoice == .general && old.islandGap == 6)
    var c = IslandConfig.defaults(for: .bottom)
    c.styleChoice = .island
    c.islandGap = 14
    let back = try JSONDecoder().decode(IslandConfig.self, from: JSONEncoder().encode(c))
    #expect(back.styleChoice == .island && back.islandGap == 14)
    c.style = .island
    #expect(IslandGeometry.sideGap(c) == 14)
    c.style = .notch
    #expect(IslandGeometry.sideGap(c) == 0)
}

@Test func tabReorderKeepsOtherIDs() {
    #expect(TabOrder.moving(["a", "b", "c"], from: 0, to: 2) == ["b", "c", "a"])
    #expect(TabOrder.moving(["a", "b", "c"], from: 2, to: 0) == ["c", "a", "b"])
    #expect(TabOrder.moving(["a"], from: 0, to: 3) == ["a"])
    // "x" is saved but not shown (unknown feature): it keeps its slot.
    #expect(TabOrder.apply(["c", "a"], to: ["a", "x", "c"]) == ["c", "x", "a"])
}

@Test func notchedTopStartsFlush() {
    let c = IslandConfig.defaults(for: .top, notch: CGSize(width: 220, height: 38))
    #expect(c.islandGap == 0)
    #expect(IslandConfig.defaults(for: .top).islandGap == 6)
}

// Round 23
@Test func perSlotSizesFollowTheirCards() {
    var c = IslandConfig.defaults(for: .top)
    c.homeSlots = ["timer", "music", "stats"]
    c.setHomeSize(0, 1.5)
    c.setHomeSize(1, 2)              // main never scales
    #expect(c.homeSlotScales == [1.5, 1, 1])
    c.setHomeSlots(["stats", "music", "timer"])   // widths move with the features
    #expect(c.homeSlotScales == [1, 1, 1.5])
    c.setHomeSlots(["", "stats", "music", "timer"])
    #expect(c.homeSlotScales.count == 4 && c.homeSlotScales[2] == 1 && c.homeSlotScales[3] == 1.5)
}

@Test func emptyPlaceholderCanGrow() {
    var c = IslandConfig.defaults(for: .top)
    #expect(c.homeSlots == ["note", "music", "screenshots"])
    c.homeSlots = ["", "music", ""]
    c.setHomeSize(2, 2)
    #expect(c.homeSlotScales == [1, 1, 2])
}

@Test func verticalHomeColumn() {
    var c = IslandConfig.defaults(for: .left)
    #expect(!c.homeEnabled)
    #expect(HomeLayout.mainLength(c) == HomeLayout.verticalMain)
    c.homeSlots = ["", "music", ""]
    let len = HomeLayout.contentWidth(main: HomeLayout.mainLength(c), count: 3, scales: c.homeSlotScales)
    #expect(len == 170 + 2 * 51 + 2 * HomeLayout.spacing)
}

@Test func lyricUnderNotch() {
    let c = IslandConfig.defaults(for: .top)
    #expect(c.notchLyrics == .below)
    let plainN = IslandGeometry.liveSize(c, notch: true)
    let below = IslandGeometry.liveSize(c, lyricWidth: 100, notch: true, below: true)
    // Round 25: the notch style uses the same pill; a timer pair keeps its width.
    #expect(below.height == plainN.height + IslandGeometry.belowExtra(c) && below.width == plainN.width)
    #expect(IslandGeometry.liveSize(c, lyricWidth: 100, notch: false, below: true).height == plainN.height)
    #expect(IslandGeometry.liveSize(c, lyricWidth: 500, notch: true, below: true, dual: true).width == plainN.width)
    let pr = IslandGeometry.lyricBelowRect(c, size: CGSize(width: 500, height: 56), lyricWidth: 100, dual: true)
    #expect(pr.midX == ((500 - IslandGeometry.timerChip) / 2).rounded() + 0 || abs(pr.midX - (500 - IslandGeometry.timerChip) / 2) <= 1)
    // Island style: a detached pill; the body keeps its length.
    var i = c; i.style = .island
    let plain = IslandGeometry.liveSize(i, notch: true)
    let pill = IslandGeometry.liveSize(i, lyricWidth: 100, notch: true, below: true)
    #expect(pill.width == plain.width && pill.height == plain.height + IslandGeometry.lyricPillGap + IslandGeometry.lyricPillHeight)
    let wide = IslandGeometry.liveSize(i, lyricWidth: 500, notch: true, below: true)
    #expect(wide.width == IslandGeometry.lyricPillWidth(500))
    #expect(IslandGeometry.liveSize(i, lyricWidth: 500, notch: true, below: true, dual: true).width == plain.width)
    let r = IslandGeometry.lyricBelowRect(i, size: wide, lyricWidth: 500, dual: false)
    #expect(r.minY == IslandGeometry.liveDepth(i) + IslandGeometry.lyricPillGap && r.width == wide.width)
}

@Test func notchLyricsDecodeDefault() throws {
    let d = try JSONDecoder().decode(IslandConfig.self, from: Data(#"{"edge":"top"}"#.utf8))
    #expect(d.notchLyrics == .below)
    // Round 24: the round-23 key (saved as "general" by default) no longer counts.
    let old = try JSONDecoder().decode(IslandConfig.self, from: Data(#"{"edge":"top","notchLyrics":"general"}"#.utf8))
    #expect(old.notchLyrics == .below)
}

@Test func mediaSourceDetection() {
    #expect(MediaSource.detect(bundle: nil, nativeSpotify: true, title: "x") == .spotify)
    #expect(MediaSource.detect(bundle: nil, nativeSpotify: false, title: "x") == .appleMusic)
    #expect(MediaSource.detect(bundle: nil, nativeSpotify: true, title: "") == .none)
    #expect(MediaSource.detect(bundle: "com.google.Chrome", nativeSpotify: true, title: "Lofi Mix") == .app("com.google.Chrome"))
    #expect(MediaSource.detect(bundle: "com.colliderli.iina", nativeSpotify: true, title: "a") == .app("com.colliderli.iina"))
}

@Test func pickedFeatureKeepsSlotSize() {
    var c = IslandConfig.defaults(for: .top)
    c.homeSlots = ["", "music", ""]
    c.setHomeSize(0, 1.75)
    c.assignHome(0, "timer")
    #expect(c.homeSlots == ["timer", "music", ""] && c.homeSlotScales == [1.75, 1, 1])
    c.setHomeSize(2, 1.25)
    c.setHomeSlots(["timer", "music", "stats"])
    #expect(c.homeSlotScales == [1.75, 1, 1.25])
}

@Test func freeResizePinsToSteps() {
    #expect(HomeLayout.snapped(1.52) == (1.5, 1.5))
    #expect(HomeLayout.snapped(1.4).pinned == nil && HomeLayout.snapped(1.4).scale == 1.4)
    #expect(HomeLayout.snapped(3).scale == 2 && HomeLayout.snapped(0.2).scale == 1)
    #expect(HomeLayout.sideWidth(main: 384, scale: 1.37) == HomeLayout.sideWidth(main: 384, scale: 1.37).rounded())
}

@Test func sideEmperColumnSlots() {
    var c = IslandConfig.defaults(for: .left)
    c.homeSlots = ["", "music", ""]
    #expect(HomeLayout.sideBase(c) == HomeLayout.verticalMain)
    #expect(HomeLayout.verticalSideWidth == 234)
    #expect(HomeLayout.length(c) == 3 * 170 + 2 * HomeLayout.verticalSpacing)
    let f = HomeLayout.slotFrames(main: HomeLayout.mainLength(c), count: 3, scales: [2, 1, 1], side: HomeLayout.sideBase(c))
    #expect(f[0].width == 2 * HomeLayout.verticalMain + HomeLayout.spacing && f[1].width == HomeLayout.verticalMain)
    let top = IslandConfig.defaults(for: .top)
    #expect(HomeLayout.sideBase(top) == HomeLayout.sideWidth(main: HomeLayout.mainLength(top)))
}

@Test func fullScreenLineAndEdgeZone() {
    var c = IslandConfig.defaults(for: .top)
    let s = IslandGeometry.compactSize(c)
    #expect(s.width == CGFloat(c.collapsedWidth) && s.height == IslandGeometry.compactDepth)
    let panel = CGRect(x: 0, y: 900, width: 400, height: 100)   // flush with a screen top at y 1000
    let z = IslandGeometry.edgeHotZone(c, panel: panel)
    #expect(z.maxY == 1002 && z.minY == 998)                     // only the last 2 pt (+2 past the edge)
    #expect(!z.contains(CGPoint(x: 200, y: 995)))                // a little below the edge does not open it
    #expect(z.contains(CGPoint(x: 200, y: 999.5)))
    c = IslandConfig.defaults(for: .left)
    let l = IslandGeometry.edgeHotZone(c, panel: CGRect(x: 0, y: 0, width: 100, height: 400))
    #expect(l.minX == -2 && l.maxX == 2)
}
