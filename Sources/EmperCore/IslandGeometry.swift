import CoreGraphics

/// Insets in view terms (top = towards the top of the screen).
public struct Insets: Equatable, Sendable {
    public var top, leading, bottom, trailing: CGFloat
}

/// Pure frame maths in AppKit global coordinates (origin bottom-left, y up).
public enum IslandGeometry {
    /// Extra room inside the panel so the spring overshoot and shadow are not clipped.
    public static let overshootPadding: CGFloat = 16
    public static let tabBarHeight: CGFloat = 24
    public static let tabSpacing: CGFloat = 8
    /// Round 27: gap between the tab column and the content on left/right Empers: the same as the
    /// column's inset from the screen side, so the column sits evenly between them.
    public static func tabGap(_ c: IslandConfig) -> CGFloat { c.edge.isVertical ? verticalAttachedInset(c) : tabSpacing }
    public static func verticalAttachedInset(_ c: IslandConfig) -> CGFloat { c.style == .island ? 12 : 10 }
    /// Round 27: how far a "+ placeholder" button reaches past each end of the Emper (offset 30 from the Emper's end to the
    /// button's outer edge: the overlay is aligned to that end, round 28 fix; was counted as 44).
    public static let addSlotReach: CGFloat = 30
    /// Round 28: part of the reach that has to fit inside the floating gap's range: the "+" may sit in the
    /// island gap, right up to the screen side.
    public static func reach(_ r: CGFloat, _ c: IslandConfig) -> CGFloat { max(0, r - sideGap(c)) }
    /// Narrowest open island on top/bottom edges, whatever the idle length: a short notch still opens wide.
    public static let minOpenWidth: CGFloat = 440
    /// Content height shared by every module on a top/bottom island (same open size for every tab).
    public static let moduleHeight: CGFloat = 110
    /// Concave flare width of the open island (eats into the visible width along the edge).
    public static let openFlare: CGFloat = 10
    /// Visible breathing room between the island's body and its content.
    public static let margin: CGFloat = 18
    /// Widest the idle live activity may grow to fit a long lyric line.
    public static let maxLiveWidth: CGFloat = 640
    /// Gap between the lyric text and the artwork / bars.
    public static let lyricGap: CGFloat = 10
    /// Strip under a built-in notch for the small lyric line (round 23).
    public static let belowLyricHeight: CGFloat = 20
    /// Round 24: Island style puts the line in its own pill, detached under the body.
    public static let lyricPillGap: CGFloat = 4
    public static let lyricPillHeight: CGFloat = 22
    public static func lyricPillWidth(_ lw: CGFloat) -> CGFloat { min((lw + 24).rounded(.up), maxLiveWidth) }
    /// Depth the under-notch lyric adds below the body (strip, or gap + pill).
    /// Round 25: both styles use the detached pill.
    public static func belowExtra(_ c: IslandConfig) -> CGFloat { lyricPillGap + lyricPillHeight }

    /// Where the under-notch lyric sits in an idle Emper of `size` (view space, origin top-left, top edge).
    /// Notch: a strip under the music part. Island: a pill under it, centred on the music part. `dual` =
    /// a timer body joined on the right (`timerChip` wide), which keeps its own depth.
    public static func lyricBelowRect(_ c: IslandConfig, size: CGSize, lyricWidth lw: CGFloat, dual: Bool) -> CGRect {
        let depth = liveDepth(c)
        let musicW = dual ? size.width - timerChip : size.width
        let w = min(lyricPillWidth(lw), size.width)
        let x = min(max((musicW - w) / 2, 0), size.width - w)
        return CGRect(x: x.rounded(), y: depth + lyricPillGap, width: w, height: lyricPillHeight)
    }
    /// Music and timer both live: the timer body (time + play/pause) joins the music on the right, and the
    /// same width stays empty on the left so the music keeps its place. Each side adds this much.
    public static let timerChip: CGFloat = 100
    /// Pinched neck between the music body and the timer body.
    public static let timerNeck: CGFloat = 10

    public static func collapsedSize(_ c: IslandConfig) -> CGSize {
        CGSize(width: c.collapsedWidth, height: c.collapsedHeight)
    }

    /// Insets around module content, measured from the island's bounding box. Sides along the edge
    /// add the flare so the *visible* margin is `margin`. `clearance` is the physical notch height
    /// (0 on screens without one: the open island covers the menu bar, so content can go up high).
    public static func contentInsets(_ c: IslandConfig, clearance: CGFloat = 0) -> Insets {
        if c.style == .island {
            // Floating island: no flares; even margins all round, below a physical notch when it sits behind one.
            let m: CGFloat = 16
            // Round 27: left/right: the tab column hugs the screen side as closely as it sits to the content.
            if c.edge == .left { return Insets(top: m, leading: verticalAttachedInset(c), bottom: m, trailing: m + 4) }
            if c.edge == .right { return Insets(top: m, leading: m + 4, bottom: m, trailing: verticalAttachedInset(c)) }
            return Insets(top: clearance > 0 ? clearance + 6 : m, leading: m + 4, bottom: m, trailing: m + 4)
        }
        let side = openFlare + margin
        let attached = clearance > 0 ? clearance + 6 : 10
        let far: CGFloat = 14
        switch c.edge {
        case .top: return Insets(top: attached, leading: side, bottom: far, trailing: side)
        case .bottom: return Insets(top: far, leading: side, bottom: 10, trailing: side)
        case .left: return Insets(top: side, leading: verticalAttachedInset(c), bottom: side, trailing: far)
        case .right: return Insets(top: side, leading: far, bottom: side, trailing: verticalAttachedInset(c))
        }
    }

    public static func expandedSize(content: CGSize, config c: IslandConfig, tabBar: Bool, clearance: CGFloat = 0) -> CGSize {
        let i = contentInsets(c, clearance: clearance)
        let tabs = tabBar ? tabBarHeight + tabGap(c) : 0
        // Round 26: left/right Empers carry the tab bar as a column on the screen side (adds width).
        var w = content.width + i.leading + i.trailing + (c.edge.isVertical ? tabs : 0)
        var h = content.height + i.top + i.bottom + (c.edge.isVertical ? 0 : tabs)
        // Never narrower (along the edge) than the idle island: the pointer that opened it must stay
        // inside the open island, otherwise it closes and reopens in a loop.
        if c.edge.isVertical { h = max(h, CGFloat(c.collapsedHeight)) } else { w = max(w, CGFloat(c.collapsedWidth), minOpenWidth) }
        return CGSize(width: w, height: h)
    }

    /// Width modules get on a top/bottom island before any module asks for more: the open island's
    /// minimum (idle length or `minOpenWidth`) minus the side insets. Modules fill it, so there is no gap.
    public static func openContentWidth(_ c: IslandConfig, clearance: CGFloat = 0) -> CGFloat {
        let i = contentInsets(c, clearance: clearance)
        return max(CGFloat(c.collapsedWidth), minOpenWidth) - i.leading - i.trailing
    }

    /// Depth of the live-activity island (music playing), without the lyric strip.
    public static func liveDepth(_ c: IslandConfig) -> CGFloat {
        max(CGFloat(c.edge.isVertical ? c.collapsedWidth : c.collapsedHeight), 24)
    }

    /// Artwork size inside the live activity: 6 pt clear above and below.
    public static func liveArt(_ c: IslandConfig) -> CGFloat { max(liveDepth(c) - 12, 12) }

    /// Clear space between the live activity's outer edge (past the flare) and the artwork / bars.
    public static func livePad() -> CGFloat { CGFloat(IslandConfig.notchFlare) + 14 }

    /// Width of each "wing" beside the idle shape: pad + artwork + 8.
    public static func liveWing(_ c: IslandConfig) -> CGFloat {
        livePad() + 8 + liveArt(c)
    }

    /// Lyrics sit in the live activity's row on top/bottom islands only (vertical text is unreadable).
    public static func supportsInlineLyrics(_ c: IslandConfig) -> Bool { !c.edge.isVertical }

    /// Live activity. With `lyricWidth` (measured text width) the island grows sideways so the line fits
    /// between the artwork and the bars; its depth never changes. Under a physical notch the centre is
    /// hidden, so the lyric goes in the right wing next to the bars and both wings grow to stay centred.
    public static func liveSize(_ c: IslandConfig, lyricWidth: CGFloat? = nil, notch: Bool = false, below: Bool = false,
                                dual: Bool = false) -> CGSize {
        let depth = liveDepth(c), wing = liveWing(c)
        if c.edge.isVertical {
            return CGSize(width: depth, height: CGFloat(c.collapsedHeight) + 2 * wing)
        }
        let base = CGFloat(c.collapsedWidth) + 2 * wing
        guard let lw = lyricWidth, lw > 0 else { return CGSize(width: base, height: depth) }
        let pad = livePad()
        // Round 23: small line under the notch: the Emper gets a strip deeper and only as wide as the line needs.
        if notch && below {
            // Round 24, Island style: the line has its own pill, so the body keeps its length; the pill
            // may be wider than a lone body. With a timer beside it the pair's width stays put.
            // Round 25: the notch style uses the same pill.
            return CGSize(width: dual ? base : max(base, lyricPillWidth(lw)), height: depth + belowExtra(c))
        }
        let art = liveArt(c)
        let need: CGFloat
        if notch {
            let rightWing = lyricGap + lw + lyricGap + art + pad
            need = CGFloat(c.collapsedWidth) + 2 * rightWing
        } else {
            need = 2 * (pad + art + lyricGap) + lw
        }
        return CGSize(width: min(max(base, need), max(base, maxLiveWidth)), height: depth)
    }

    /// Short notice in the idle island (e.g. Bluetooth connected): wings beside the idle shape like the
    /// live activity; `wide` leaves room for a battery readout. Under a notch both wings stay equal.
    /// Idle timer on the bottom Emper: keeps the idle length (time centred, play/pause at the end).
    public static func compactTimerSize(_ c: IslandConfig) -> CGSize {
        CGSize(width: max(CGFloat(c.collapsedWidth), 110), height: liveDepth(c))
    }

    /// Timer-only idle (top/side): just enough wing for "TIMER" on one side and time + play/pause on the
    /// other (round 22: the 260-pt toast width was far too long for a timer).
    public static let timerWing: CGFloat = CGFloat(IslandConfig.notchFlare) + 64
    public static func timerIdleSize(_ c: IslandConfig) -> CGSize {
        let depth = liveDepth(c)
        if c.edge.isVertical { return CGSize(width: depth, height: CGFloat(c.collapsedHeight) + 2 * 40) }
        return CGSize(width: CGFloat(c.collapsedWidth) + 2 * timerWing, height: depth)
    }

    public static func toastSize(_ c: IslandConfig, notch: Bool = false, wide: Bool = false) -> CGSize {
        let depth = liveDepth(c)
        let wing: CGFloat = wide ? 96 : 72
        if c.edge.isVertical { return CGSize(width: depth, height: CGFloat(c.collapsedHeight) + 2 * 40) }
        return CGSize(width: max(CGFloat(c.collapsedWidth) + 2 * wing, 260), height: depth)
    }

    /// Gap kept between a floating island and the screen's sides.
    public static func sideGap(_ c: IslandConfig) -> CGFloat { c.style == .island ? CGFloat(c.islandGap) : 0 }

    /// Where an island may sit along its edge: the screen, minus the floating gap at the sides and, for
    /// left/right islands, minus the menu bar at the top.
    public static func alongRange(_ c: IslandConfig, area: CGRect) -> (lo: CGFloat, hi: CGFloat) {
        let g = sideGap(c)
        if c.edge.isVertical { return (area.minY + g, area.maxY - CGFloat(c.topReserve) - g) }
        return (area.minX + g, area.maxX - g)
    }

    /// Round 27: room left along the edge for the open Home after its "+" buttons: negative when a side
    /// slot already pushes a button past the screen side (or under the menu bar). Infinite without a screen.
    public static func homeRoom(_ c: IslandConfig, clearance: CGFloat = 0) -> CGFloat {
        guard !c.area.isNull else { return .infinity }
        let r = alongRange(c, area: c.area)
        let len = HomeLayout.length(c)
        let content = c.edge.isVertical ? CGSize(width: HomeLayout.verticalWidth, height: len) : CGSize(width: len, height: moduleHeight)
        let s = expandedSize(content: content, config: c, tabBar: true, clearance: clearance)
        return (r.hi - r.lo) - (c.edge.isVertical ? s.height : s.width) - 2 * reach(addSlotReach, c)
    }

    /// Centre of the idle island along its edge. Corner islands (bottom, 1 or 2 sides) start flush in their
    /// corner and `offset` moves them inwards; everything else is the screen centre plus `offset`.
    public static func idleCenter(_ c: IslandConfig, area: CGRect) -> CGFloat {
        let r = alongRange(c, area: area)
        let idle = CGFloat(c.edge.isVertical ? c.collapsedHeight : c.collapsedWidth)
        switch (c.edge.isVertical, c.anchor) {
        case (false, .leading): return r.lo + max(CGFloat(c.offset), 0) + idle / 2
        case (false, .trailing): return r.hi - max(CGFloat(c.offset), 0) - idle / 2
        case (true, _): return area.midY + CGFloat(c.offset)
        default: return area.midX + CGFloat(c.offset)
        }
    }

    /// Centre along the edge of an island state `length` long: on the idle centre, slid inwards only as
    /// far as needed to stay inside `alongRange` (so it grows from the middle and stops neatly at a side).
    public static func center(length: CGFloat, config c: IslandConfig, area: CGRect) -> CGFloat {
        let r = alongRange(c, area: area)
        return clampedCenter(idleCenter(c, area: area), half: length / 2, lo: r.lo, hi: r.hi)
    }

    /// Frame of the panel window: big enough for the largest island state plus padding, flush with the edge.
    /// `area` is the rectangle the island attaches to (today: the full screen frame).
    /// Extra panel room on both ends of a Emper (along its edge) for the floating "+ placeholder" buttons.
    public static let sideButtonRoom: CGFloat = 30
    /// Round 29: open left/right Emper: pencil, this Emper's settings and Settings float in a pill beside the
    /// Emper (level with the main slot), so the tab column only holds tabs.
    public static let sidePillWidth: CGFloat = tabBarHeight + 8
    public static let sidePillGap: CGFloat = 8
    public static let sidePillRoom: CGFloat = sidePillWidth + sidePillGap

    public static func panelFrame(for c: IslandConfig, maxSize s: CGSize, in area: CGRect) -> CGRect {
        let p = overshootPadding
        let gap = CGFloat(c.edgeGap)
        switch c.edge {
        case .top, .bottom:
            let y = c.edge == .top ? area.maxY - (s.height + p + gap) : area.minY
            let h = s.height + p + gap
            let w = s.width + 2 * (p + sideButtonRoom)
            let cx = center(length: s.width + 2 * reach(addSlotReach, c), config: c, area: area)
            return CGRect(x: cx - w / 2, y: y, width: w, height: h)
        case .left, .right:
            // Round 23: left/right Empers have Home too, so they get the same room for "+" above and below.
            let w = s.width + p + gap + sidePillRoom, h = s.height + 2 * (p + sideButtonRoom)
            let cy = center(length: s.height + 2 * reach(addSlotReach, c), config: c, area: area)
            let x = c.edge == .left ? area.minX : area.maxX - w
            return CGRect(x: x, y: cy - h / 2, width: w, height: h)
        }
    }

    /// Rect of an island of `size` anchored to its edge inside `panel` (centred, no gap).
    public static func islandRect(size: CGSize, edge: IslandEdge, panel: CGRect) -> CGRect {
        islandRect(size: size, config: IslandConfig.defaults(for: edge), panel: panel)
    }

    /// Rect of an island of `size` inside `panel`, honouring the floating gap. With `config.area` set, the
    /// position along the edge follows `center(length:)`; without it, the island is centred in the panel.
    /// `reach`: room kept past both ends (pencil mode on Home: the "+" buttons stay on screen).
    public static func islandRect(size: CGSize, config c: IslandConfig, panel: CGRect, reach: CGFloat = 0) -> CGRect {
        let g = CGFloat(c.edgeGap)
        let known = !c.area.isNull
        switch c.edge {
        case .top, .bottom:
            let cx = known ? center(length: size.width + 2 * Self.reach(reach, c), config: c, area: c.area) : panel.midX
            let x = cx - size.width / 2
            let y = c.edge == .top ? panel.maxY - g - size.height : panel.minY + g
            return CGRect(x: x, y: y, width: size.width, height: size.height)
        case .left, .right:
            let cy = known ? center(length: size.height + 2 * Self.reach(reach, c), config: c, area: c.area) : panel.midY
            let x = c.edge == .left ? panel.minX + g : panel.maxX - g - size.width
            return CGRect(x: x, y: cy - size.height / 2, width: size.width, height: size.height)
        }
    }

    /// Shift of an island of `size` from the panel's centre along the edge, in view terms (x right, y down).
    public static func alongShift(size: CGSize, config c: IslandConfig, panel: CGRect, reach: CGFloat = 0) -> CGSize {
        let r = islandRect(size: size, config: c, panel: panel, reach: reach)
        return c.edge.isVertical ? CGSize(width: 0, height: panel.midY - r.midY) : CGSize(width: r.midX - panel.midX, height: 0)
    }

    /// Hover zone: at least `minimumDepth` deep, extended `outward` past the screen edge (pointer pinned
    /// against the edge still counts) and grown by `margin` on the other sides (forgiving exits).
    public static func hotZone(for rect: CGRect, edge: IslandEdge, minimumDepth: CGFloat = 8,
                               outward: CGFloat = 2, margin: CGFloat = 0) -> CGRect {
        var r: CGRect
        switch edge {
        case .top:
            let d = max(rect.height, minimumDepth) + margin
            r = CGRect(x: rect.minX - margin, y: rect.maxY - d, width: rect.width + 2 * margin, height: d + outward)
        case .bottom:
            let d = max(rect.height, minimumDepth) + margin
            r = CGRect(x: rect.minX - margin, y: rect.minY - outward, width: rect.width + 2 * margin, height: d + outward)
        case .left:
            let d = max(rect.width, minimumDepth) + margin
            r = CGRect(x: rect.minX - outward, y: rect.minY - margin, width: d + outward, height: rect.height + 2 * margin)
        case .right:
            let d = max(rect.width, minimumDepth) + margin
            r = CGRect(x: rect.maxX - d, y: rect.minY - margin, width: d + outward, height: rect.height + 2 * margin)
        }
        return r
    }

    /// Idle hover zone: only the idle body (flares excluded, so it matches the notch length), shrunk by
    /// `sides` along the edge and `far` on the side facing into the screen (never on the edge side), and
    /// extended `outward` past the edge so a pointer pinned against the edge still counts.
    public static func idleHotZone(_ c: IslandConfig, panel: CGRect, sides: CGFloat, far: CGFloat, outward: CGFloat = 2,
                                   depth: CGFloat? = nil) -> CGRect {
        let flare = c.style == .island ? 0 : CGFloat(IslandConfig.notchFlare)
        // An idle activity deeper than the idle body (live music, timer) deepens the zone with it; the
        // length along the edge stays the idle length.
        var size = collapsedSize(c)
        if let d = depth {
            if c.edge.isVertical { size.width = max(size.width, d) } else { size.height = max(size.height, d) }
        }
        let body = islandRect(size: size, config: c, panel: panel)
        // A floating island's zone reaches the screen edge across the gap.
        let outward = outward + CGFloat(c.edgeGap)
        let depth = max((c.edge.isVertical ? body.width : body.height) - far, 4)
        switch c.edge {
        case .top, .bottom:
            let along = max(body.width - 2 * flare - 2 * sides, 8)
            let y = c.edge == .top ? body.maxY - depth : body.minY - outward
            return CGRect(x: body.midX - along / 2, y: y, width: along, height: depth + outward)
        case .left, .right:
            let along = max(body.height - 2 * flare - 2 * sides, 8)
            let x = c.edge == .left ? body.minX - outward : body.maxX - depth
            return CGRect(x: x, y: body.midY - along / 2, width: depth + outward, height: along)
        }
    }

    /// Thickness of the idle line while a full-screen app is shown.
    public static let compactDepth: CGFloat = 4

    /// Full screen: the idle Emper keeps its length along the edge and shrinks to a thin line.
    public static func compactSize(_ c: IslandConfig) -> CGSize {
        let s = collapsedSize(c)
        return c.edge.isVertical ? CGSize(width: compactDepth, height: s.height) : CGSize(width: s.width, height: compactDepth)
    }

    /// Full screen: only the outermost points against the screen edge open the Emper (the pointer has to be
    /// pushed to the edge), along the idle length minus the side margins.
    public static func edgeHotZone(_ c: IslandConfig, panel: CGRect, depth: CGFloat = 2) -> CGRect {
        let flare = c.style == .island ? 0 : CGFloat(IslandConfig.notchFlare)
        let body = islandRect(size: compactSize(c), config: c, panel: panel)
        // The panel sits flush with the screen edge; 2 pt past it still counts (pointer pinned to the edge).
        switch c.edge {
        case .top, .bottom:
            let along = max(body.width - 2 * flare - 2 * CGFloat(c.hoverInset), 8)
            let y = c.edge == .top ? panel.maxY - depth : panel.minY - 2
            return CGRect(x: body.midX - along / 2, y: y, width: along, height: depth + 2)
        case .left, .right:
            let along = max(body.height - 2 * flare - 2 * CGFloat(c.hoverInset), 8)
            let x = c.edge == .left ? panel.minX - 2 : panel.maxX - depth
            return CGRect(x: x, y: body.midY - along / 2, width: depth + 2, height: along)
        }
    }

    /// Idle hover zone using the island's own margins.
    public static func idleHotZone(_ c: IslandConfig, panel: CGRect, depth: CGFloat? = nil) -> CGRect {
        idleHotZone(c, panel: panel, sides: CGFloat(c.hoverInset), far: CGFloat(c.hoverInsetFar), depth: depth)
    }

    static func clampedCenter(_ v: CGFloat, half: CGFloat, lo: CGFloat, hi: CGFloat) -> CGFloat {
        if hi - lo <= 2 * half { return (lo + hi) / 2 }
        return min(max(v, lo + half), hi - half)
    }
}
