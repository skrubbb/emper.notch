import SwiftUI
import EmperCore

/// Notch-style shape attached to an edge: concave flares where it meets the edge, rounded outer corners.
/// Drawn once in a canonical "attached at top" space, then mapped to the real edge.
struct IslandShape: Shape {
    var edge: IslandEdge
    var cornerRadius: CGFloat
    var flare: CGFloat
    var style: IslandStyle = .notch
    /// Corner island (bottom left/right): the side against the screen edge is straight, no flare.
    var anchor: IslandAnchor = .center

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(cornerRadius, flare) }
        set { cornerRadius = newValue.first; flare = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let length = edge.isVertical ? rect.height : rect.width // along the edge
        let depth = edge.isVertical ? rect.width : rect.height  // away from the edge
        guard length > 0, depth > 0 else { return Path() }
        if style == .island {
            // Floating: every corner rounded (a capsule while small).
            let r = max(0, min(cornerRadius, rect.width / 2, rect.height / 2))
            return Path(roundedRect: rect, cornerRadius: r, style: .continuous)
        }
        // Always symmetric, also in a screen corner (Pang, round 14: a flush side looked broken).
        let f = max(0, min(flare, length / 4, depth / 2))
        let r = max(0, min(cornerRadius, (length - 2 * f) / 2, depth - f))

        var p = Path()
        p.move(to: .init(x: 0, y: 0))
        p.addQuadCurve(to: .init(x: f, y: f), control: .init(x: f, y: 0))
        p.addLine(to: .init(x: f, y: depth - r))
        p.addQuadCurve(to: .init(x: f + r, y: depth), control: .init(x: f, y: depth))
        p.addLine(to: .init(x: length - f - r, y: depth))
        p.addQuadCurve(to: .init(x: length - f, y: depth - r), control: .init(x: length - f, y: depth))
        p.addLine(to: .init(x: length - f, y: f))
        p.addQuadCurve(to: .init(x: length, y: 0), control: .init(x: length - f, y: 0))
        p.closeSubpath()

        // Canonical (u along, v depth) -> view space (y down).
        let t: CGAffineTransform
        switch edge {
        case .top: t = .identity
        case .bottom: t = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: rect.height)
        case .left: t = CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: 0, ty: 0)
        case .right: t = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: rect.width, ty: 0)
        }
        return p.applying(t).offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

/// Idle island with music and timer both live (top/bottom edges): the music body, then the timer body on
/// the right, joined by a pinched neck like two drops of one liquid. Notch style stays flush to the edge, so
/// only the outer side pinches; Island style pinches on both sides. The left `pad` stays empty so the music
/// body keeps its place (centred on a physical notch).
struct DualIdleShape: Shape {
    var edge: IslandEdge
    var style: IslandStyle
    var cornerRadius: CGFloat
    var flare: CGFloat
    var pad: CGFloat
    var neck: CGFloat
    /// Round 24 (notch style, lyric strip): the timer body keeps this depth while the music part is deeper.
    var timerDepth: CGFloat? = nil

    func path(in rect: CGRect) -> Path {
        if style == .notch, let td = timerDepth, td < rect.height {
            // Pinched pair at the timer's depth, then the music part on its own down to the full depth.
            var top = DualIdleShape(edge: .top, style: style, cornerRadius: cornerRadius, flare: flare, pad: pad, neck: neck)
                .path(in: CGRect(x: 0, y: 0, width: rect.width, height: td))
            let music = IslandShape(edge: .top, cornerRadius: cornerRadius, flare: flare, style: .notch)
                .path(in: CGRect(x: 0, y: 0, width: rect.width - pad, height: rect.height))
            top = top.union(music)
            if edge == .bottom { top = top.applying(CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: rect.height)) }
            return top.offsetBy(dx: rect.minX, dy: rect.minY)
        }
        let w = rect.width, h = rect.height
        guard w > pad, h > 0 else { return Path() }
        let body = CGRect(x: 0, y: 0, width: w, height: h)   // music + timer, no empty lead: centred as one
        let mid = w - pad + neck / 2          // centre of the neck
        let hw = neck / 2 + 16                 // half-width of the pinch
        var p: Path
        if style == .island {
            p = Path(roundedRect: body, cornerRadius: h / 2, style: .continuous)
            let d = h * 0.3
            p = p.subtracting(Self.bite(mid: mid, hw: hw, depth: d, base: h))
            p = p.subtracting(Self.bite(mid: mid, hw: hw, depth: d, base: h)
                .applying(CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: h)))
        } else {
            p = IslandShape(edge: .top, cornerRadius: cornerRadius, flare: flare, style: .notch).path(in: body)
            p = p.subtracting(Self.bite(mid: mid, hw: hw, depth: h * 0.5, base: h))
        }
        // Canonical space is "attached at the top"; the bottom edge flips it.
        if edge == .bottom { p = p.applying(CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: h)) }
        return p.offsetBy(dx: rect.minX, dy: rect.minY)
    }

    /// Smooth bump cut up from the line y = base, `depth` tall at `mid`.
    private static func bite(mid: CGFloat, hw: CGFloat, depth: CGFloat, base: CGFloat) -> Path {
        var b = Path()
        b.move(to: CGPoint(x: mid - hw, y: base))
        b.addCurve(to: CGPoint(x: mid, y: base - depth),
                   control1: CGPoint(x: mid - hw * 0.45, y: base), control2: CGPoint(x: mid - hw * 0.55, y: base - depth))
        b.addCurve(to: CGPoint(x: mid + hw, y: base),
                   control1: CGPoint(x: mid + hw * 0.55, y: base - depth), control2: CGPoint(x: mid + hw * 0.45, y: base))
        b.addLine(to: CGPoint(x: mid + hw, y: base + 2))
        b.addLine(to: CGPoint(x: mid - hw, y: base + 2))
        b.closeSubpath()
        return b
    }
}

/// Round 25: the idle body in its plain size, centred on top; the lyric pill below is drawn on its own.
struct BodyOnTopShape: Shape {
    var body: AnyShape
    var bodyWidth: CGFloat
    var bodyHeight: CGFloat

    func path(in rect: CGRect) -> Path {
        let bw = min(bodyWidth, rect.width)
        return body.path(in: CGRect(x: rect.minX + ((rect.width - bw) / 2).rounded(), y: rect.minY, width: bw, height: bodyHeight))
    }
}

/// Round 26: the Emper logo mark (two bodies joined by a pinched neck, and the dot above it), from
/// Resources/logo/emper-symbol.svg (viewBox crop 254...2246 × 900...1604).
struct EmperGlyph: Shape {
    static let box = CGRect(x: 254.223, y: 900.185, width: 1991.557, height: 703.625)
    static var aspect: CGFloat { box.height / box.width }

    func path(in rect: CGRect) -> Path {
        let b = Self.box
        let k = min(rect.width / b.width, rect.height / b.height)
        let ox = rect.minX + (rect.width - b.width * k) / 2, oy = rect.minY + (rect.height - b.height * k) / 2
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + (x - b.minX) * k, y: oy + (y - b.minY) * k) }
        var s = Path()
        s.move(to: p(254.223, 1027.21))
        s.addCurve(to: p(381.245, 900.185), control1: p(254.223, 957.052), control2: p(311.09, 900.185))
        s.addLine(to: p(674.373, 900.185))
        s.addCurve(to: p(842.433, 1057.5), control1: p(774.037, 900.185), control2: p(818.983, 964.673))
        s.addCurve(to: p(1055.44, 1212.85), control1: p(864.906, 1148.37), control2: p(941.12, 1212.85))
        s.addLine(to: p(1444.56, 1212.98))
        s.addCurve(to: p(1657.57, 1057.62), control1: p(1558.88, 1212.98), control2: p(1635.09, 1148.49))
        s.addCurve(to: p(1825.63, 900.307), control1: p(1681.02, 964.795), control2: p(1725.96, 900.307))
        s.addLine(to: p(2118.75, 900.307))
        s.addCurve(to: p(2245.78, 1027.33), control1: p(2188.91, 900.307), control2: p(2245.78, 957.174))
        s.addLine(to: p(2245.78, 1476.79))
        s.addCurve(to: p(2118.75, 1603.81), control1: p(2245.78, 1546.95), control2: p(2188.91, 1603.81))
        s.addLine(to: p(1825.63, 1603.81))
        s.addCurve(to: p(1657.57, 1446.5), control1: p(1725.96, 1603.81), control2: p(1681.02, 1539.33))
        s.addCurve(to: p(1444.56, 1291.14), control1: p(1635.09, 1355.63), control2: p(1558.88, 1291.14))
        s.addLine(to: p(1055.44, 1291.02))
        s.addCurve(to: p(842.433, 1446.38), control1: p(941.12, 1291.02), control2: p(864.906, 1355.51))
        s.addCurve(to: p(674.373, 1603.69), control1: p(818.983, 1539.2), control2: p(774.037, 1603.69))
        s.addLine(to: p(381.245, 1603.69))
        s.addCurve(to: p(254.223, 1476.67), control1: p(311.09, 1603.69), control2: p(254.223, 1546.83))
        s.closeSubpath()
        let d0 = p(1184.38, 990.006), d1 = p(1315.61, 1121.236)
        s.addEllipse(in: CGRect(x: d0.x, y: d0.y, width: d1.x - d0.x, height: d1.y - d0.y))
        return s
    }
}

/// Round 26 (experimental): open left/right Emper on Home. The far side follows the slots: full depth at the
/// main slot, `dip` shallower at the side slots, with rounded steps between (round 27). Canonical space is
/// "attached at the top" (u along, v depth) like `IslandShape`, then mapped to the real edge.
/// `band` = the main slot's span along the edge and `full` the open size the band was measured in,
/// so the outline scales with the animated frame and the dip only appears as the Emper reaches full size.
struct HomeColumnShape: Shape {
    var edge: IslandEdge
    var style: IslandStyle
    var cornerRadius: CGFloat
    var flare: CGFloat
    var band: ClosedRange<CGFloat>
    var full: CGSize
    var dip: CGFloat

    func path(in rect: CGRect) -> Path {
        let length = edge.isVertical ? rect.height : rect.width
        let depth = edge.isVertical ? rect.width : rect.height
        let fullLen = edge.isVertical ? full.height : full.width
        let fullDepth = edge.isVertical ? full.width : full.height
        guard length > 0, depth > 0, fullLen > 0 else { return Path() }
        let k = length / fullLen
        let d = max(0, min(dip, dip - (fullDepth - depth)))         // grows in over the last `dip` points
        let lo = band.lowerBound * k, hi = band.upperBound * k
        let island = style == .island
        let f = island ? 0 : max(0, min(flare, length / 4, depth / 2))
        let r = max(0, min(cornerRadius, (length - 2 * f) / 2, (depth - d) - f))
        let side = depth - d
        // Round 27: the main slot's overhang steps out with rounded corners of the Emper's own radius
        // (halved when the step is shallower than two radii), not an S-curve.
        let rc = max(0, min(r, d / 2))
        // Far-edge depth at the two ends.
        let startD = lo > f + r + 1 ? side : depth
        let endD = hi < length - f - r - 1 ? side : depth

        var p = Path()
        if island {
            p.move(to: .init(x: 0, y: r))
        } else {
            p.move(to: .init(x: 0, y: 0))
            p.addQuadCurve(to: .init(x: f, y: f), control: .init(x: f, y: 0))
        }
        p.addLine(to: .init(x: f, y: startD - r))
        p.addQuadCurve(to: .init(x: f + r, y: startD), control: .init(x: f, y: startD))
        if startD < depth {
            p.addLine(to: .init(x: max(f + r, lo - rc), y: side))
            p.addQuadCurve(to: .init(x: lo, y: side + rc), control: .init(x: lo, y: side))
            p.addLine(to: .init(x: lo, y: depth - rc))
            p.addQuadCurve(to: .init(x: lo + rc, y: depth), control: .init(x: lo, y: depth))
        }
        if endD < depth {
            p.addLine(to: .init(x: hi - rc, y: depth))
            p.addQuadCurve(to: .init(x: hi, y: depth - rc), control: .init(x: hi, y: depth))
            p.addLine(to: .init(x: hi, y: side + rc))
            p.addQuadCurve(to: .init(x: min(length - f - r, hi + rc), y: side), control: .init(x: hi, y: side))
        }
        p.addLine(to: .init(x: length - f - r, y: endD))
        p.addQuadCurve(to: .init(x: length - f, y: endD - r), control: .init(x: length - f, y: endD))
        if island {
            p.addLine(to: .init(x: length, y: r))
            p.addQuadCurve(to: .init(x: length - r, y: 0), control: .init(x: length, y: 0))
            p.addLine(to: .init(x: r, y: 0))
            p.addQuadCurve(to: .init(x: 0, y: r), control: .init(x: 0, y: 0))
            p.closeSubpath()
        } else {
            p.addLine(to: .init(x: length - f, y: f))
            p.addQuadCurve(to: .init(x: length, y: 0), control: .init(x: length - f, y: 0))
            p.closeSubpath()
        }
        let t: CGAffineTransform
        switch edge {
        case .top: t = .identity
        case .bottom: t = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: rect.height)
        case .left: t = CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: 0, ty: 0)
        case .right: t = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: rect.width, ty: 0)
        }
        return p.applying(t).offsetBy(dx: rect.minX, dy: rect.minY)
    }
}
