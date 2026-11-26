import CoreGraphics

/// Home tab of a top/bottom island: 1...5 placeholders in a row. One is the main slot (the size the
/// music module always had); the others are side slots 30 % of its width. Round 28: the main slot's
/// index is stored (`IslandConfig.homeMain`), so any number of side slots can sit on either side.
public enum HomeLayout {
    public static let maxSlots = 5
    /// Round 23: +50 % (was 8).
    public static let spacing: CGFloat = 12
    /// Widgets a slot can hold. "" = empty placeholder.
    public static var widgets: [String] { IslandConfig.features }

    /// Round 23: left/right Empers get Home too, as a column. The main slot keeps the side Emper's usual
    /// module size (260 × 170); side slots are 30 % of its height. First-pass layout.
    public static let verticalMain: CGFloat = 170
    public static let verticalWidth: CGFloat = 260
    /// Length of the main slot along the row (width on top/bottom, height on left/right).
    public static func mainLength(_ c: IslandConfig) -> CGFloat {
        c.edge.isVertical ? verticalMain : IslandGeometry.openContentWidth(c)
    }

    /// Index of the main slot for `count` slots: 1→0, 2→1, 3→1, 4→2, 5→2.
    public static func mainIndex(count: Int) -> Int { min(max(count, 1), maxSlots) / 2 }
    /// Round 28: sides no longer alternate, so the main slot is stored. `main` if it fits, else the default.
    public static func mainIndex(count: Int, main: Int?) -> Int {
        let n = min(max(count, 1), maxSlots)
        if let m = main, m >= 0, m < n { return m }
        return mainIndex(count: n)
    }

    /// A quarter of the main slot plus 20 %, so a side card can show its feature, not just an icon.
    public static func sideWidth(main: CGFloat) -> CGFloat { (main * 0.3).rounded() }

    /// Round 24: side slots resize freely between 1× and 2× (2× = two placeholders plus the gap between
    /// them) and pin to these steps when the drag comes close.
    public static let snaps: [CGFloat] = [1, 1.25, 1.5, 1.75, 2]
    /// How close (in scale) a drag has to come to a step to pin to it (~8 pt on a 115-pt side card).
    public static let snapRange: CGFloat = 0.06
    public static func clampScale(_ s: CGFloat, max top: CGFloat = 2) -> CGFloat { s.isFinite ? min(max(s, 1), top) : 1 }
    /// Round 28: side slots on left/right Empers go up to 1.5× only.
    public static let verticalMaxScale: CGFloat = 1.5
    public static func maxScale(vertical: Bool) -> CGFloat { vertical ? verticalMaxScale : 2 }
    /// Scale for a free drag: pinned to a step when close (`pinned` = that step), else to 0.01.
    public static func snapped(_ s: CGFloat, max top: CGFloat = 2) -> (scale: CGFloat, pinned: CGFloat?) {
        let c = clampScale(s, max: top)
        if let p = snaps.first(where: { $0 <= top && abs($0 - c) <= snapRange }) { return (p, p) }
        return ((c * 100).rounded() / 100, nil)
    }
    public static func sideWidth(main: CGFloat, scale: CGFloat) -> CGFloat {
        sideLength(base: sideWidth(main: main), scale: scale)
    }
    /// Length of a side slot of `base` length at `scale` (2× = two slots plus the gap).
    public static func sideLength(base: CGFloat, scale: CGFloat, gap: CGFloat = spacing) -> CGFloat {
        let s = clampScale(scale)
        return (base * s + gap * (s - 1)).rounded()
    }

    /// Round 27: gap between slots on left/right Empers (+50 %: the step in the outline needs room).
    public static let verticalSpacing: CGFloat = 18
    public static func gap(_ c: IslandConfig) -> CGFloat { c.edge.isVertical ? verticalSpacing : spacing }
    /// Slot frames of `c`'s Home with its own main, side and gap sizes (`slots`/`scales` override).
    public static func frames(_ c: IslandConfig, slots: Int? = nil, scales: [CGFloat]? = nil) -> [(x: CGFloat, width: CGFloat)] {
        slotFrames(main: mainLength(c), count: slots ?? c.homeSlots.count, scales: scales ?? c.homeSlotScales,
                   side: sideBase(c), gap: gap(c), mainAt: slots == nil ? c.homeMainIndex : nil)
    }
    /// Length of `c`'s Home row/column.
    public static func length(_ c: IslandConfig, slots: Int? = nil, scales: [CGFloat]? = nil) -> CGFloat {
        frames(c, slots: slots, scales: scales).last.map { $0.x + $0.width } ?? mainLength(c)
    }

    /// Round 26 (experimental): on left/right Empers a side slot is as tall as the main slot and 4/5 as wide;
    /// the Emper's outline narrows around it with a smooth curve.
    /// Round 27: 0.9 (was 0.8) so the main slot's overhang is half as deep.
    public static let verticalSideRatio: CGFloat = 0.9
    public static var verticalSideWidth: CGFloat { (verticalWidth * verticalSideRatio).rounded() }
    /// Length of a 1× side slot along the row/column.
    public static func sideBase(_ c: IslandConfig) -> CGFloat {
        c.edge.isVertical ? verticalMain : sideWidth(main: mainLength(c))
    }

    /// Width of the whole row for a main slot of width `main`.
    public static func contentWidth(main: CGFloat, count: Int, scales: [CGFloat] = [], side: CGFloat? = nil,
                                    gap: CGFloat = spacing, mainAt: Int? = nil) -> CGFloat {
        guard let last = slotFrames(main: main, count: count, scales: scales, side: side, gap: gap, mainAt: mainAt).last else { return main }
        return last.x + last.width
    }

    /// Slot frames (x, width) from the row's leading edge. `scales[i]` widens side slot i.
    public static func slotFrames(main: CGFloat, count: Int, scales: [CGFloat] = [], side: CGFloat? = nil,
                                  gap: CGFloat = spacing, mainAt: Int? = nil) -> [(x: CGFloat, width: CGFloat)] {
        let n = min(max(count, 1), maxSlots), m = mainIndex(count: n, main: mainAt)
        let base = side ?? sideWidth(main: main)
        var x: CGFloat = 0
        return (0..<n).map { i in
            let w = i == m ? main : sideLength(base: base, scale: scales.indices.contains(i) ? scales[i] : 1, gap: gap)
            defer { x += w + gap }
            return (x, w)
        }
    }

    /// Slot under `x` (row coordinates); the nearest slot when `x` falls in a gap or outside.
    public static func slot(at x: CGFloat, main: CGFloat, count: Int, scales: [CGFloat] = [], side: CGFloat? = nil,
                            gap: CGFloat = spacing, mainAt: Int? = nil) -> Int {
        let f = slotFrames(main: main, count: count, scales: scales, side: side, gap: gap, mainAt: mainAt)
        if let i = f.firstIndex(where: { x >= $0.x && x < $0.x + $0.width }) { return i }
        return f.indices.min { abs(f[$0].x + f[$0].width / 2 - x) < abs(f[$1].x + f[$1].width / 2 - x) } ?? 0
    }

    /// Change the slot count, keeping every widget where it is relative to the main slot. New slots are
    /// empty and appear on the outside (left first); removing drops the outermost ones.
    public static func resized(_ slots: [String], to count: Int, main: Int? = nil) -> [String] {
        let old = slots.isEmpty ? [""] : Array(slots.prefix(maxSlots))
        let om = mainIndex(count: old.count, main: main)
        var left = Array(old[..<om]), right = Array(old[(om + 1)...])
        let main = old[om]
        let n = min(max(count, 1), maxSlots), nm = mainIndex(count: n)
        let nl = nm, nr = n - 1 - nm
        while left.count < nl { left.insert("", at: 0) }
        while left.count > nl { left.removeFirst() }
        while right.count < nr { right.append("") }
        while right.count > nr { right.removeLast() }
        return left + [main] + right
    }

    /// First empty placeholder, main slot first, then nearest to it.
    public static func preferredEmpty(_ slots: [String], main: Int? = nil) -> Int? {
        let m = mainIndex(count: slots.count, main: main)
        return slots.indices.filter { slots[$0].isEmpty }.min { abs($0 - m) < abs($1 - m) }
    }

    /// Put `id` in slot `i` (picked from the menu). If it was already in another slot, the two swap.
    public static func assigned(_ slots: [String], at i: Int, _ id: String) -> [String] {
        guard slots.indices.contains(i) else { return slots }
        var s = slots
        if !id.isEmpty, let j = s.firstIndex(of: id), j != i { s[j] = s[i] }
        s[i] = id
        return s
    }

    /// Round 28: add one empty side placeholder on the left/top or right/bottom end. Sides are free (left 2,
    /// right 0 is fine): the main slot stays where it is and its index moves with a placeholder put before it.
    public static func adding(_ slots: [String], main: Int? = nil, left: Bool) -> (slots: [String], main: Int) {
        let m = mainIndex(count: slots.count, main: main)
        guard slots.count < maxSlots else { return (slots, m) }
        var s = slots
        if left { s.insert("", at: 0) } else { s.append("") }
        return (s, left ? m + 1 : m)
    }

    /// Remove side slot `i` (never the main one, never the last one). Slots after it close up.
    public static func removing(_ slots: [String], main: Int? = nil, at i: Int) -> (slots: [String], main: Int) {
        let m = mainIndex(count: slots.count, main: main)
        guard slots.count > 1, slots.indices.contains(i), i != m else { return (slots, m) }
        var s = slots
        s.remove(at: i)
        return (s, i < m ? m - 1 : m)
    }

    /// Swap two slots' widgets.
    public static func swapped(_ slots: [String], _ a: Int, _ b: Int) -> [String] {
        guard slots.indices.contains(a), slots.indices.contains(b) else { return slots }
        var s = slots
        s.swapAt(a, b)
        return s
    }

    /// Next widget for slot `i` when tapped in edit mode: cycles through the widgets not used elsewhere, then empty.
    public static func cycled(_ slots: [String], at i: Int) -> [String] {
        guard slots.indices.contains(i) else { return slots }
        let used = Set(slots.enumerated().filter { $0.offset != i }.map(\.element))
        let options = widgets.filter { !used.contains($0) } + [""]
        let cur = options.firstIndex(of: slots[i]) ?? -1
        var s = slots
        s[i] = options[(cur + 1) % options.count]
        return s
    }
}
