import CoreGraphics
import Foundation

/// Notch: attached to the edge with concave flares. Island: floats a little off the edge, fully rounded (iPhone-like).
public enum IslandStyle: String, Codable, Sendable, CaseIterable {
    case notch, island
}

/// One Emper's styling: the General setting, or its own.
public enum StyleChoice: String, Codable, Sendable, CaseIterable {
    case general, notch, island

    public func resolve(_ global: IslandStyle) -> IslandStyle {
        switch self {
        case .general: global
        case .notch: .notch
        case .island: .island
        }
    }
}

/// Island colours. System follows macOS light/dark.
public enum IslandTheme: String, Codable, Sendable, CaseIterable {
    case system, dark, light
}

/// Bottom edge: one island in the middle, or islands flush in the corners beside the Dock.
public enum BottomLayout: String, Codable, Sendable, CaseIterable {
    case center, oneSide, twoSides
}

/// Where an island sits along its edge. Leading/trailing = flush in the left/right corner.
public enum IslandAnchor: String, Codable, Sendable, CaseIterable {
    case center, leading, trailing
}

/// One island = edge + size + position + modules. Sizes are in screen points.
/// The expanded size is not stored: it follows the selected module, so the island morphs between tabs.
public struct IslandConfig: Codable, Equatable, Sendable {
    public var edge: IslandEdge
    public var enabled: Bool
    /// Modules shown as tabs, in registry order.
    public var moduleIDs: [String]
    /// Show what's playing here automatically (live activity + Music tab).
    public var musicDetection: Bool
    public var collapsedWidth: Double
    public var collapsedHeight: Double
    /// Shift from the centre of the edge, in points (x for top/bottom, y for left/right).
    public var offset: Double
    /// Opacity while idle. 0 = invisible (hover still works, it is geometric).
    public var idleOpacity: Double
    public var cornerRadius: Double
    /// Idle hover zone is shrunk by this much on the sides not touching the screen edge,
    /// so brushing past the island does not open it.
    /// Left + right margin (top/bottom islands) or top + bottom margin (side islands).
    public var hoverInset: Double
    /// Margin on the side facing into the screen (bottom of a top island). The edge side has none.
    public var hoverInsetFar: Double
    /// Milliseconds the pointer must rest on the idle island before it opens.
    public var openDelayMs: Double
    /// Milliseconds after the pointer leaves before the open island closes.
    public var closeDelayMs: Double
    /// Home tab placeholders, left to right (top/bottom islands). "" = empty. See `HomeLayout`.
    public var homeSlots: [String]
    /// Set at runtime from `EmperConfig.style` (one look for every island). Kept in the file only for old configs.
    public var style: IslandStyle
    /// Bottom edge only.
    public var bottomLayout: BottomLayout
    /// Bottom, one side: which corner.
    public var bottomSide: IslandAnchor
    /// Bottom, two sides: the right island's tabs and Home placeholders (the left uses `moduleIDs` / `homeSlots`).
    /// Size, position and look are shared and mirrored.
    public var rightModuleIDs: [String]
    public var rightHomeSlots: [String]
    /// Side placeholder width per feature on Home: 1, 1.5 or 2 (pencil handles). Missing = 1.
    public var homeScales: [String: Double] = [:]
    /// Round 23: width per placeholder position (same order as `homeSlots`), so empty placeholders can be
    /// widened too. Empty or wrong length = fall back to `homeScales` by feature.
    public var homeSizes: [Double] = []
    /// Same for the bottom right island (two sides).
    public var rightHomeSizes: [Double] = []
    /// Round 28: index of the main slot in `homeSlots` (sides are free). nil / out of range = the old
    /// centred default (`HomeLayout.mainIndex(count:)`).
    public var homeMain: Int?
    public var rightHomeMain: Int?
    /// Opens on Home (placeholders) instead of the first tab. Top/bottom only; on by default on the top.
    public var homeEnabled: Bool = true
    /// Styling of this Emper: follows General unless set. A notched screen's top Emper starts on Notch.
    public var styleChoice: StyleChoice = .general
    /// Island styling only: distance from the screen edge (and from the sides in a corner).
    public var islandGap: Double = 6
    /// Round 23: top Emper on a screen with a built-in notch: the idle lyric follows General (in the wing
    /// beside the notch) or sits as a small line right under the notch. Round 24: under the notch by default
    /// (saved under a new key, so Empers saved with the round-23 default pick it up too).
    public var notchLyrics: NotchLyrics = .below
    /// Shrink button (beside the pencil): the idle Emper stays a thin line, as in full screen, and opens
    /// only when the pointer is pushed against the screen edge. Off by default.
    public var shrunk: Bool = false

    /// Runtime only (not saved): set per panel by the manager.
    public var anchor: IslandAnchor = .center
    /// Runtime only: distance between the screen edge and the island body (island style, notch height).
    public var edgeGap: Double = 0
    /// Runtime only: the screen this island lives on. Set, it keeps every island state (idle, live, open)
    /// centred on the idle position and slides it inwards only as far as needed to stay on screen.
    public var area: CGRect = .null
    /// Runtime only: room kept free at the top of the screen (menu bar) for left/right islands.
    public var topReserve: Double = 0

    public init(edge: IslandEdge, enabled: Bool, moduleIDs: [String], musicDetection: Bool,
                collapsedWidth: Double, collapsedHeight: Double,
                offset: Double = 0, idleOpacity: Double = 1, cornerRadius: Double = 15, hoverInset: Double = 5,
                hoverInsetFar: Double? = nil, openDelayMs: Double = 0, closeDelayMs: Double = 120,
                homeSlots: [String] = ["", "music", ""], style: IslandStyle = .notch,
                bottomLayout: BottomLayout = .center, bottomSide: IslandAnchor = .leading,
                rightModuleIDs: [String] = [], rightHomeSlots: [String] = ["music"]) {
        self.edge = edge
        self.enabled = enabled
        self.moduleIDs = moduleIDs
        self.musicDetection = musicDetection
        self.collapsedWidth = collapsedWidth
        self.collapsedHeight = collapsedHeight
        self.offset = offset
        self.idleOpacity = idleOpacity
        self.cornerRadius = cornerRadius
        self.hoverInset = hoverInset
        self.hoverInsetFar = hoverInsetFar ?? hoverInset
        self.openDelayMs = openDelayMs
        self.closeDelayMs = closeDelayMs
        self.homeSlots = homeSlots
        self.style = style
        self.bottomLayout = bottomLayout
        self.bottomSide = bottomSide
        self.rightModuleIDs = rightModuleIDs
        self.rightHomeSlots = rightHomeSlots
        self.homeEnabled = edge == .top
    }

    /// Feature ids that can be placed (Home placeholder or own tab). Home itself is automatic.
    public static let features = ["music", "stats", "timer", "calculator", "clipboard", "screenshots", "shelf", "note", "reminder"]
    /// Round 28: size a side placeholder takes when this feature is put in it at 1× (Reminder has many fields).
    public static let preferredScale: [String: Double] = ["reminder": 1.5]

    /// Home and own tab are independent: a feature can sit in a Home placeholder and also have its own tab.
    public func onHome(_ id: String) -> Bool { homeSlots.contains(id) }

    /// Width scale of each Home slot (main is always 1).
    public var homeMainIndex: Int { HomeLayout.mainIndex(count: homeSlots.count, main: homeMain) }
    /// Widest a side slot may be: 2× on top/bottom, 1.5× on left/right (round 28).
    public var homeMaxScale: CGFloat { HomeLayout.maxScale(vertical: edge.isVertical) }

    public var homeSlotScales: [CGFloat] {
        let m = homeMainIndex, top = homeMaxScale
        let bySlot = homeSizes.count == homeSlots.count
        return homeSlots.enumerated().map { i, id in
            if i == m { return 1 }
            if bySlot { return HomeLayout.clampScale(CGFloat(homeSizes[i]), max: top) }
            return id.isEmpty ? 1 : HomeLayout.clampScale(CGFloat(homeScales[id] ?? 1), max: top)
        }
    }

    /// New placeholder layout; each placeholder keeps its width: a feature by its id, an empty one by
    /// its place relative to the main slot (add/remove), else the nearest old empty one (swap).
    /// `main`: the new main index (add/remove from pencil mode). nil: same count keeps it, else the default.
    public mutating func setHomeSlots(_ new: [String], main: Int? = nil) {
        let old = homeSlots, oldS = homeSlotScales
        let om = homeMainIndex
        let nm = HomeLayout.mainIndex(count: new.count, main: main ?? (new.count == old.count ? homeMain : nil))
        var used = Set<Int>()
        var sizes = [Double](repeating: 1, count: new.count)
        var open: [Int] = []
        for (j, id) in new.enumerated() {
            if !id.isEmpty, let k = old.firstIndex(of: id), !used.contains(k) { sizes[j] = Double(oldS[k]); used.insert(k) }
            else { open.append(j) }
        }
        // Round 24: a feature new to Home takes over the place it lands in (a widened empty placeholder
        // keeps its width when a feature is put in it), like an empty one does.
        let vacated: (Int) -> Bool = { k in old[k].isEmpty || !new.contains(old[k]) }
        var rest: [Int] = []
        for j in open {
            let k = om + (j - nm)
            if old.indices.contains(k), vacated(k), !used.contains(k) { sizes[j] = Double(oldS[k]); used.insert(k) }
            else { rest.append(j) }
        }
        for j in rest {
            let free = old.indices.filter { vacated($0) && !used.contains($0) }
            if let k = free.min(by: { abs($0 - j) < abs($1 - j) }) { sizes[j] = Double(oldS[k]); used.insert(k) }
        }
        if new.indices.contains(nm) { sizes[nm] = 1 }
        homeSlots = new
        homeSizes = sizes
        homeMain = nm
    }

    /// Picker: put `id` in placeholder `i`. Widths belong to the places, not the features, so the slot
    /// keeps the size it was given (round 24 bug: it went back to 1× after a feature was picked).
    public mutating func assignHome(_ i: Int, _ id: String) {
        var sizes = homeSlotScales.map(Double.init)
        homeSlots = HomeLayout.assigned(homeSlots, at: i, id)
        if sizes.indices.contains(i), i != homeMainIndex, sizes[i] == 1, let p = Self.preferredScale[id] {
            sizes[i] = Double(HomeLayout.clampScale(CGFloat(p), max: homeMaxScale))
        }
        homeSizes = sizes
    }

    /// Width of placeholder `i` (pencil grips): free between 1× and 2×. The main slot stays 1.
    public mutating func setHomeSize(_ i: Int, _ scale: Double) {
        guard homeSlots.indices.contains(i), i != homeMainIndex else { return }
        var sizes = homeSlotScales.map(Double.init)
        sizes[i] = Double(HomeLayout.clampScale(CGFloat(scale), max: homeMaxScale))
        homeSizes = sizes
    }
    public func hasTab(_ id: String) -> Bool { moduleIDs.contains(id) }

    /// Add to Home (first empty placeholder, adding one if needed) or take it out of Home.
    public mutating func setHome(_ id: String, _ on: Bool) {
        var s = homeSlots.map { $0 == id ? "" : $0 }
        if on {
            if let i = HomeLayout.preferredEmpty(s, main: homeMainIndex) { s[i] = id }
            else if s.count < HomeLayout.maxSlots {
                // Round 28: the new placeholder goes on the side with fewer slots (right on a tie).
                let left = homeMainIndex < s.count - 1 - homeMainIndex
                let a = HomeLayout.adding(s, main: homeMainIndex, left: left)
                var t = a.slots
                t[left ? 0 : t.count - 1] = id
                setHomeSlots(t, main: a.main)
                return
            }
        }
        setHomeSlots(s)
        if on, let i = homeSlots.firstIndex(of: id), i != homeMainIndex, homeSlotScales[i] == 1, let p = Self.preferredScale[id] {
            setHomeSize(i, p)
        }
    }

    /// Give the feature its own tab, or remove the tab.
    public mutating func setTab(_ id: String, _ on: Bool) {
        moduleIDs.removeAll { $0 == id }
        if on { moduleIDs.append(id) }
    }

    /// Corner radius shared by the defaults (Pang's tuned top island); side islands follow it.
    public static let defaultCornerRadius: Double = 15
    /// Idle width of the top island on screens without a notch (Pang's tuned value).
    public static let defaultTopWidth: Double = 200

    /// Notch flare width used by the shape; the top island adds it on both sides so it covers the notch.
    public static let notchFlare: Double = 6

    /// `menuBarHeight` is used for the top island on screens without a notch.
    public static func defaults(for edge: IslandEdge, notch: CGSize? = nil, menuBarHeight: Double = 24) -> IslandConfig {
        switch edge {
        case .top:
            let w = notch.map { Double($0.width) + 2 * notchFlare } ?? defaultTopWidth
            let h = notch.map { Double($0.height) } ?? menuBarHeight
            var t = IslandConfig(edge: .top, enabled: true, moduleIDs: ["note", "screenshots"], musicDetection: true,
                                 collapsedWidth: w, collapsedHeight: h, cornerRadius: defaultCornerRadius,
                                 homeSlots: ["note", "music", "screenshots"])
            // Behind a built-in notch the notch look matches the hardware.
            if notch != nil { t.styleChoice = .notch; t.islandGap = 0 }   // sits like the built-in notch
            return t
        case .left:
            return IslandConfig(edge: .left, enabled: false, moduleIDs: ["note"], musicDetection: false,
                                collapsedWidth: 5, collapsedHeight: 140, cornerRadius: defaultCornerRadius, hoverInset: 5)
        case .right:
            return IslandConfig(edge: .right, enabled: false, moduleIDs: ["music"], musicDetection: false,
                                collapsedWidth: 5, collapsedHeight: 140, cornerRadius: defaultCornerRadius, hoverInset: 5)
        case .bottom:
            return IslandConfig(edge: .bottom, enabled: false, moduleIDs: ["note"], musicDetection: false,
                                collapsedWidth: 200, collapsedHeight: 5, cornerRadius: defaultCornerRadius, hoverInset: 5,
                                homeSlots: ["music"])
        }
    }

    // Tolerant decoding: missing fields fall back to defaults instead of failing.
    enum CodingKeys: String, CodingKey {
        case edge, enabled, moduleIDs, moduleID, musicDetection, collapsedWidth, collapsedHeight,
             offset, idleOpacity, cornerRadius, hoverInset, hoverInsetFar, openDelayMs, closeDelayMs, homeSlots,
             style, bottomLayout, bottomSide, rightModuleIDs, rightHomeSlots, homeScales, homeSizes, rightHomeSizes, homeEnabled, styleChoice, islandGap,
             homeMain, rightHomeMain, shrunk
        case notchLyrics = "notchLyrics2"
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(edge, forKey: .edge)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(moduleIDs, forKey: .moduleIDs)
        try c.encode(musicDetection, forKey: .musicDetection)
        try c.encode(collapsedWidth, forKey: .collapsedWidth)
        try c.encode(collapsedHeight, forKey: .collapsedHeight)
        try c.encode(offset, forKey: .offset)
        try c.encode(idleOpacity, forKey: .idleOpacity)
        try c.encode(cornerRadius, forKey: .cornerRadius)
        try c.encode(hoverInset, forKey: .hoverInset)
        try c.encode(hoverInsetFar, forKey: .hoverInsetFar)
        try c.encode(openDelayMs, forKey: .openDelayMs)
        try c.encode(closeDelayMs, forKey: .closeDelayMs)
        try c.encode(homeSlots, forKey: .homeSlots)
        try c.encode(style, forKey: .style)
        try c.encode(bottomLayout, forKey: .bottomLayout)
        try c.encode(bottomSide, forKey: .bottomSide)
        try c.encode(rightModuleIDs, forKey: .rightModuleIDs)
        try c.encode(rightHomeSlots, forKey: .rightHomeSlots)
        try c.encode(homeScales, forKey: .homeScales)
        try c.encode(homeSizes, forKey: .homeSizes)
        try c.encode(rightHomeSizes, forKey: .rightHomeSizes)
        try c.encodeIfPresent(homeMain, forKey: .homeMain)
        try c.encodeIfPresent(rightHomeMain, forKey: .rightHomeMain)
        try c.encode(homeEnabled, forKey: .homeEnabled)
        try c.encode(styleChoice, forKey: .styleChoice)
        try c.encode(islandGap, forKey: .islandGap)
        try c.encode(notchLyrics, forKey: .notchLyrics)
        try c.encode(shrunk, forKey: .shrunk)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let edge = try c.decode(IslandEdge.self, forKey: .edge)
        let d = IslandConfig.defaults(for: edge)
        self.edge = edge
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        if let ids = try c.decodeIfPresent([String].self, forKey: .moduleIDs) {
            moduleIDs = ids
        } else if let old = try c.decodeIfPresent(String.self, forKey: .moduleID) {
            moduleIDs = [old == "spotify" ? "music" : old]
        } else {
            moduleIDs = d.moduleIDs
        }
        musicDetection = try c.decodeIfPresent(Bool.self, forKey: .musicDetection) ?? d.musicDetection
        collapsedWidth = try c.decodeIfPresent(Double.self, forKey: .collapsedWidth) ?? d.collapsedWidth
        collapsedHeight = try c.decodeIfPresent(Double.self, forKey: .collapsedHeight) ?? d.collapsedHeight
        offset = try c.decodeIfPresent(Double.self, forKey: .offset) ?? d.offset
        idleOpacity = try c.decodeIfPresent(Double.self, forKey: .idleOpacity) ?? d.idleOpacity
        cornerRadius = try c.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? d.cornerRadius
        hoverInset = try c.decodeIfPresent(Double.self, forKey: .hoverInset) ?? d.hoverInset
        hoverInsetFar = try c.decodeIfPresent(Double.self, forKey: .hoverInsetFar) ?? hoverInset
        openDelayMs = try c.decodeIfPresent(Double.self, forKey: .openDelayMs) ?? d.openDelayMs
        closeDelayMs = try c.decodeIfPresent(Double.self, forKey: .closeDelayMs) ?? d.closeDelayMs
        let slots = try c.decodeIfPresent([String].self, forKey: .homeSlots) ?? d.homeSlots
        homeSlots = slots.isEmpty ? [""] : Array(slots.prefix(HomeLayout.maxSlots))
        style = (try? c.decodeIfPresent(IslandStyle.self, forKey: .style)) ?? d.style
        bottomLayout = (try? c.decodeIfPresent(BottomLayout.self, forKey: .bottomLayout)) ?? d.bottomLayout
        let side = (try? c.decodeIfPresent(IslandAnchor.self, forKey: .bottomSide)) ?? d.bottomSide
        bottomSide = side == .center ? .leading : side
        rightModuleIDs = try c.decodeIfPresent([String].self, forKey: .rightModuleIDs) ?? d.rightModuleIDs
        let right = try c.decodeIfPresent([String].self, forKey: .rightHomeSlots) ?? d.rightHomeSlots
        rightHomeSlots = right.isEmpty ? [""] : Array(right.prefix(HomeLayout.maxSlots))
        homeScales = (try? c.decodeIfPresent([String: Double].self, forKey: .homeScales)) ?? [:]
        homeSizes = (try? c.decodeIfPresent([Double].self, forKey: .homeSizes)) ?? []
        rightHomeSizes = (try? c.decodeIfPresent([Double].self, forKey: .rightHomeSizes)) ?? []
        homeMain = (try? c.decodeIfPresent(Int.self, forKey: .homeMain)) ?? nil
        rightHomeMain = (try? c.decodeIfPresent(Int.self, forKey: .rightHomeMain)) ?? nil
        homeEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .homeEnabled)) ?? (edge == .top)
        styleChoice = (try? c.decodeIfPresent(StyleChoice.self, forKey: .styleChoice)) ?? .general
        islandGap = (try? c.decodeIfPresent(Double.self, forKey: .islandGap)) ?? 6
        notchLyrics = (try? c.decodeIfPresent(NotchLyrics.self, forKey: .notchLyrics)) ?? .below
        shrunk = (try? c.decodeIfPresent(Bool.self, forKey: .shrunk)) ?? false
    }
}

/// All islands of one display.
public struct DisplayConfig: Codable, Equatable, Sendable {
    public var islands: [IslandEdge: IslandConfig]

    public init(islands: [IslandEdge: IslandConfig]) { self.islands = islands }

    /// `isMain`: the display with the menu bar. Only it gets the top island by default; others start empty.
    public static func defaults(notch: CGSize?, menuBarHeight: Double = 24, isMain: Bool = true) -> DisplayConfig {
        var all: [IslandEdge: IslandConfig] = [:]
        for e in IslandEdge.allCases { all[e] = IslandConfig.defaults(for: e, notch: notch, menuBarHeight: menuBarHeight) }
        if !isMain { all[.top]?.enabled = false }
        return DisplayConfig(islands: all)
    }

    public subscript(edge: IslandEdge) -> IslandConfig {
        get { islands[edge] ?? IslandConfig.defaults(for: edge) }
        set { islands[edge] = newValue }
    }
}

/// Whole settings file. Displays are keyed by display UUID so each monitor keeps its own setup.
public struct EmperConfig: Codable, Equatable, Sendable {
    /// Files older than this are replaced with defaults (prototype stage, no migration promised).
    public static let currentVersion = 7
    /// Oldest file version that can be migrated instead of reset.
    public static let oldestMigratable = 2

    public var version: Int
    public var displays: [String: DisplayConfig]
    /// Global: fetch synced lyrics from lrclib.net (sends track title/artist). Off by default.
    public var lyricsEnabled: Bool
    /// Show the current lyric line under the idle live activity (needs `lyricsEnabled`).
    public var idleLyrics: Bool
    /// Islands also appear over full-screen apps.
    public var showInFullScreen: Bool
    /// When set, Emper moves new screenshots from the macOS screenshot folder into this folder.
    /// The macOS setting itself is never changed. nil = off.
    public var screenshotFolder: String?
    /// Follow anything playing on the Mac (browsers, other players) through macOS's Now Playing,
    /// besides the Spotify / Apple Music path.
    public var systemAudio: Bool
    /// Show a short toast when a Bluetooth device connects (with its battery when macOS reports it).
    public var bluetoothToast: Bool
    /// Talk to Spotify / Apple Music directly with AppleScript (macOS asks for Automation once per app).
    /// Off: they are followed through macOS's Now Playing like any other app, with no permission.
    public var musicAppControl: Bool
    /// Look of every island: notch (attached) or island (floating).
    public var style: IslandStyle
    public var theme: IslandTheme
    /// Hide the islands while Mission Control is open (no permission needed). Show Desktop keeps them.
    public var hideInMissionControl: Bool

    public init(version: Int = EmperConfig.currentVersion, displays: [String: DisplayConfig] = [:],
                lyricsEnabled: Bool = false, idleLyrics: Bool = true, showInFullScreen: Bool = true,
                screenshotFolder: String? = nil, systemAudio: Bool = true, bluetoothToast: Bool = false,
                musicAppControl: Bool = false,
                style: IslandStyle = .notch, theme: IslandTheme = .dark, hideInMissionControl: Bool = true) {
        self.version = version
        self.displays = displays
        self.lyricsEnabled = lyricsEnabled
        self.idleLyrics = idleLyrics
        self.showInFullScreen = showInFullScreen
        self.screenshotFolder = screenshotFolder
        self.systemAudio = systemAudio
        self.bluetoothToast = bluetoothToast
        self.musicAppControl = musicAppControl
        self.style = style
        self.theme = theme
        self.hideInMissionControl = hideInMissionControl
    }

    enum CodingKeys: String, CodingKey {
        case version, displays, lyricsEnabled, idleLyrics, showInFullScreen, screenshotFolder, systemAudio, bluetoothToast, musicAppControl,
             style, theme, hideInMissionControl
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        displays = try c.decodeIfPresent([String: DisplayConfig].self, forKey: .displays) ?? [:]
        lyricsEnabled = try c.decodeIfPresent(Bool.self, forKey: .lyricsEnabled) ?? false
        idleLyrics = try c.decodeIfPresent(Bool.self, forKey: .idleLyrics) ?? true
        showInFullScreen = try c.decodeIfPresent(Bool.self, forKey: .showInFullScreen) ?? true
        screenshotFolder = try c.decodeIfPresent(String.self, forKey: .screenshotFolder)
        systemAudio = try c.decodeIfPresent(Bool.self, forKey: .systemAudio) ?? true
        bluetoothToast = try c.decodeIfPresent(Bool.self, forKey: .bluetoothToast) ?? false
        musicAppControl = try c.decodeIfPresent(Bool.self, forKey: .musicAppControl) ?? false
        theme = (try? c.decodeIfPresent(IslandTheme.self, forKey: .theme)) ?? .dark
        hideInMissionControl = try c.decodeIfPresent(Bool.self, forKey: .hideInMissionControl) ?? true
        // Older files had the style per island: the top island's look becomes the global one.
        if let st = try? c.decodeIfPresent(IslandStyle.self, forKey: .style) { style = st }
        else { style = displays.values.first(where: { $0.islands[.top]?.enabled == true })?.islands[.top]?.style ?? .notch }
    }

    /// Bring an older file up to `currentVersion`, keeping the person's tuning.
    /// v2 -> v3: top islands get the new Screenshots module (hover inset decodes to its default).
    public func migrated() -> EmperConfig {
        var c = self
        if c.version < 3 {
            for (id, var d) in c.displays {
                var top = d[.top]
                if !top.moduleIDs.contains("screenshots") { top.moduleIDs.append("screenshots") }
                d[.top] = top
                c.displays[id] = d
            }
        }
        if c.version < 4 {
            // v4: every island starts round (15) and fully visible when idle (Pang, round 14).
            for (id, var d) in c.displays {
                for e in IslandEdge.allCases where d.islands[e] != nil {
                    d.islands[e]?.cornerRadius = IslandConfig.defaultCornerRadius
                    d.islands[e]?.idleOpacity = 1
                }
                c.displays[id] = d
            }
        }
        if c.version < 7 {
            // v7: every Emper's hover margin (left & right, inner edge) is 5 pt (Pang, round 20).
            for (id, var d) in c.displays {
                for e in IslandEdge.allCases where d.islands[e] != nil {
                    d.islands[e]?.hoverInset = 5
                    d.islands[e]?.hoverInsetFar = 5
                }
                c.displays[id] = d
            }
        }
        c.version = EmperConfig.currentVersion
        return c
    }
}

/// Where the idle lyric goes on a top Emper under a built-in notch (round 23).
public enum NotchLyrics: String, Codable, CaseIterable, Sendable {
    /// Same as every Emper: General's "Lyric line in the idle Emper", beside the notch.
    case general
    /// A small line right under the notch (shown whenever lyrics are on).
    case below
}
