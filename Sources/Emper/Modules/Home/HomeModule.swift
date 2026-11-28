import SwiftUI
import EmperCore

/// Home tab. Its content is the row of placeholders drawn by `HomeRow`; this module only gives it a tab.
@MainActor
final class HomeModule: IslandModule {
    func makeView() -> AnyView { AnyView(EmptyView()) }
}

/// Drag state while rearranging placeholders (kept apart from the island model so a drag only redraws the row).
final class HomeEditState: ObservableObject {
    @Published var dragIndex: Int?
    @Published var dragX: CGFloat = 0
    /// Placeholder whose feature picker is open (drawn inside the island, so hovering it keeps it open).
    @Published var picking: Int?
    /// A resize handle is being dragged: the card's own swap drag stays still.
    var resizing = false
    /// Round 24: slot being resized and the step it is pinned to (shown as "1.5×" on the card).
    @Published var resizeIndex: Int?
    @Published var pinned: CGFloat?
    /// Picker tray in its window (SwiftUI global space) and the click-outside monitor.
    var trayFrame: CGRect = .zero
    @MainActor lazy var dismiss = PickerDismissMonitor()
    /// Render hook: open the picker on this slot when pencil mode starts.
    @MainActor static var renderPick: Int?
}

/// The placeholder row of a top/bottom island (Home tab only). Every slot shows its feature directly:
/// the main slot the full view, side slots a compact one.
struct HomeRow: View {
    @ObservedObject var model: IslandModel
    @StateObject private var edit = HomeEditState()

    var body: some View {
        let c = model.config
        let slots = c.homeSlots
        let mainW = HomeLayout.mainLength(c)
        // Left/right Empers: the same row turned into a column (x ↔ y).
        let v = c.edge.isVertical
        let scales = c.homeSlotScales
        let sideBase = HomeLayout.sideBase(c)
        let gap = HomeLayout.gap(c)
        let frames = HomeLayout.frames(c)
        let m = c.homeMainIndex
        // Slot the dragged card would swap with (drawn as the drop target).
        let dropTarget: Int? = edit.dragIndex.flatMap { d in
            guard frames.indices.contains(d) else { return nil }
            let t = HomeLayout.slot(at: frames[d].x + frames[d].width / 2 + edit.dragX, main: mainW, count: slots.count, scales: scales,
                                    side: sideBase, gap: gap, mainAt: m)
            return t == d ? nil : t
        }
        ZStack(alignment: .topLeading) {
            ForEach(Array(frames.enumerated()), id: \.offset) { i, f in
                Group {
                    if model.editingHome {
                        EditSlot(model: model, edit: edit, index: i, isMain: i == m, dragging: edit.dragIndex == i,
                                 dropTarget: dropTarget == i)
                            .offset(x: !v && edit.dragIndex == i ? edit.dragX : 0, y: v && edit.dragIndex == i ? edit.dragX : 0)
                            .zIndex(edit.dragIndex == i ? 1 : 0)
                            .simultaneousGesture(DragGesture(minimumDistance: 6)
                                .onChanged { g in
                                    guard !edit.resizing else { return }
                                    edit.dragIndex = i
                                    edit.dragX = v ? g.translation.height : g.translation.width
                                }
                                .onEnded { g in
                                    guard !edit.resizing, edit.dragIndex == i else { edit.dragIndex = nil; edit.dragX = 0; return }
                                    let d = v ? g.translation.height : g.translation.width
                                    let target = HomeLayout.slot(at: f.x + f.width / 2 + d, main: mainW, count: slots.count, scales: scales,
                                                                 side: sideBase, gap: gap, mainAt: m)
                                    edit.dragIndex = nil
                                    edit.dragX = 0
                                    if target != i { model.onHomeSlots(HomeLayout.swapped(slots, i, target)) }
                                })
                    } else if i == m {
                        mainView(slot: slots[i]).modifier(StaggerIn(order: 0, edge: c.edge, gen: model.openCount))
                    } else {
                        SideCard(model: model, id: slots[i]).modifier(StaggerIn(order: abs(i - m), edge: c.edge, gen: model.openCount))
                    }
                }
                // Round 26: side slots on a left/right Emper are 4/5 wide, kept against the screen side.
                .frame(width: v ? (i == m ? nil : HomeLayout.verticalSideWidth) : f.width, height: v ? f.width : nil)
                .frame(maxWidth: v ? .infinity : nil, maxHeight: v ? nil : .infinity,
                       alignment: c.edge == .right ? .trailing : .leading)
                .offset(x: v ? 0 : f.x, y: v ? f.x : 0)
            }
        }
        .frame(width: v ? nil : HomeLayout.length(c), height: v ? HomeLayout.length(c) : nil,
               alignment: .topLeading)
        .frame(maxWidth: v ? .infinity : nil, alignment: .topLeading)
        .overlay {
            if model.editingHome, let p = edit.picking, slots.indices.contains(p) {
                FeaturePicker(model: model, edit: edit, index: p)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .onChange(of: model.editingHome) { _, on in if !on { edit.picking = nil } else if let p = HomeEditState.renderPick { edit.picking = p } }
        .onChange(of: edit.picking) { _, p in
            if p == nil { edit.dismiss.stop(); return }
            let e = edit
            e.dismiss.start(tray: { e.trayFrame }, close: { e.picking = nil })
        }
        .onDisappear { edit.dismiss.stop() }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: slots)
        .animation(.easeOut(duration: 0.16), value: edit.picking)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: model.editingHome)
    }

    @ViewBuilder
    private func mainView(slot: String) -> some View {
        if let e = model.features[slot] {
            e.view.id(slot)
        } else {
            VStack(spacing: 4) {
                Image(systemName: "square.dashed").font(.system(size: 18))
                Text("Empty placeholder · use ✎ to pick a feature").font(.system(size: 10))
            }
            .foregroundStyle(Color.primary.opacity(0.35))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Side placeholder: a card that fills the full slot height (no gap at the bottom).
struct SideCard: View {
    @ObservedObject var model: IslandModel
    let id: String
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        Group {
            if let e = model.features[id] {
                if let compact = e.compact {
                    compact
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: e.symbol).font(.system(size: 18, weight: .semibold))
                        Text(e.name).font(.system(size: 10, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(Color.primary.opacity(0.8))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                Color.clear
            }
        }
        // The timer's liquid fills the card edge to edge.
        .padding(id == ModuleRegistry.timerID ? 0 : 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Round 23: a step darker on the dark Emper (was 7 % / 8 %); light theme keeps its contrast.
        .background(shape.fill(Color.primary.opacity(dark ? 0.045 : 0.07)))
        .overlay(shape.strokeBorder(Color.primary.opacity(dark ? 0.06 : 0.08), lineWidth: 1))
        .clipShape(shape)
    }
}

// MARK: Music (compact)

/// Music in a side placeholder (0.1.3). The layout follows the card's own size:
/// - small (1× on a top/bottom Emper): artwork, title, artist, controls with ✕
/// - medium (1.5×): artwork + title/artist, the lyric line, controls with ✕, progress with times
/// - large (1.75×–2×): ✕ beside the title, two lyric lines, controls beside the progress with times
/// - stack (1× on a left/right Emper, ~218 × 154): title row, lyrics, controls, progress
/// - portrait (1.5× on a left/right Emper, ~218 × 248): big centred artwork, then the same column
struct MusicCompactView: View {
    @ObservedObject var np = NowPlaying.shared

    enum Kind { case small, medium, mediumLyric, large, stack, portrait }

    static func kind(_ s: CGSize) -> Kind {
        if s.height >= 200 { return .portrait }
        if s.height >= 130 { return .stack }
        // Default top Emper: 1× ≈ 99, 1.25× ≈ 131, 1.5× ≈ 163, 1.75× ≈ 194, 2× ≈ 226 pt inside the card.
        if s.width < 115 { return .small }
        if s.width < 147 { return .medium }       // 1.25×: no lyric (Pang, 0.1.3 check)
        if s.width < 180 { return .mediumLyric }
        return .large
    }

    var body: some View {
        GeometryReader { g in
            Group {
                switch Self.kind(g.size) {
                case .small: small
                case .medium: medium(lyric: false)
                case .mediumLyric: medium(lyric: true)
                case .large: large
                case .stack: stack
                case .portrait: portrait(g.size)
                }
            }
            .frame(width: g.size.width, height: g.size.height, alignment: .top)
        }
        .foregroundStyle(Color.primary)
    }

    // MARK: layouts

    private var small: some View {
        VStack(spacing: 3) {
            artButton(30)
            titles(center: true, titleSize: 10, artistSize: 9)
            Spacer(minLength: 0)
            controls(play: 12, side: 9, w: 17, h: 20, badge: 11, gap: 4)
        }
    }

    /// 1.25×: header, controls, progress. 1.5×: one lyric line between header and controls.
    private func medium(lyric: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            header(art: 30)
            if lyric { lyricLine.frame(height: 13).offset(y: 2) } else { Spacer(minLength: 0) }
            controls(play: 13, side: 10, w: lyric ? 24 : 21, h: 18, badge: 12)
            ProgressRow().frame(height: 16)
        }
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 4) {
            header(art: 32)
            if np.lyricsEnabled { LyricsView(scale: 0.78).frame(height: 24).padding(.top, 3) } else { Spacer(minLength: 0) }
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                controls(play: 13, side: 10, w: 19, h: 18, badge: 12, gap: 5, centred: false)
                ProgressRow().frame(height: 16)
            }
        }
    }

    private var stack: some View {
        VStack(alignment: .leading, spacing: 6) {
            header(art: 38)
            if np.lyricsEnabled { LyricsView(scale: 0.8).padding(.top, 4).frame(maxHeight: .infinity) } else { Spacer(minLength: 0) }
            controls(play: 16, side: 12, w: 30, h: 24, badge: 14, gap: 10)
            ProgressRow().frame(height: 16)
        }
    }

    private func portrait(_ s: CGSize) -> some View {
        // Artwork takes what the column leaves over (title 30, lyric 28, controls 26, progress 16, gaps).
        let art = min(s.width * 0.5, max(s.height - 30 - 28 - 26 - 16 - 6 * 5, 44)).rounded()
        return VStack(spacing: 6) {
            artButton(art)
            titles(center: true, titleSize: 12, artistSize: 10)
            if np.lyricsEnabled { LyricsView(centered: true, scale: 0.8).frame(height: 28).padding(.top, 4) } else { Spacer(minLength: 0) }
            Spacer(minLength: 0)
            controls(play: 16, side: 12, w: 30, h: 26, badge: 14, gap: 10)
            ProgressRow().frame(height: 16)
        }
    }

    // MARK: parts

    private func artButton(_ size: CGFloat) -> some View {
        Button { np.openPlayer() } label: { ArtworkView(size: size) }
            .buttonStyle(PressScaleStyle())
            .help("Open the player")
    }

    /// Artwork with title and artist beside it; the whole row opens the player.
    private func header(art: CGFloat) -> some View {
        Button { np.openPlayer() } label: {
            HStack(spacing: 8) {
                ArtworkView(size: art)
                titles(center: false, titleSize: 11, artistSize: 10)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .help("Open the player")
    }

    private func titles(center: Bool, titleSize: CGFloat, artistSize: CGFloat) -> some View {
        VStack(alignment: center ? .center : .leading, spacing: 1) {
            Text(np.hasTrack ? np.title : "Nothing playing")
                .font(.system(size: titleSize, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(np.hasTrack ? 0.9 : 0.5))
            if np.hasTrack, !np.artist.isEmpty {
                Text(np.artist).font(.system(size: artistSize)).foregroundStyle(Color.primary.opacity(0.6))
            }
        }
        .lineLimit(1)
        .frame(maxWidth: center ? .infinity : nil, alignment: center ? .center : .leading)
    }

    /// Current lyric only (one row), or nothing when lyrics are off.
    @ViewBuilder private var lyricLine: some View {
        if np.lyricsEnabled {
            IdleLyricLine(alignment: .leading, size: 10)
        } else {
            Color.clear
        }
    }

    /// Source logo · previous · play/pause · next · ✕, the same order on every size. ✕ is always there
    /// (dim until paused) so the buttons never move.
    private func controls(play: CGFloat, side: CGFloat, w: CGFloat, h: CGFloat, badge: CGFloat, gap: CGFloat = 6, centred: Bool = true) -> some View {
        HStack(spacing: 0) {
            if centred { Spacer(minLength: 0) }
            SourceBadge(size: badge, hitWidth: badge + 4, hitHeight: h)
            Spacer().frame(width: gap)
            button("backward.fill", size: side, w: w, h: h) { np.command("previous track") }
            button(np.isPlaying ? "pause.fill" : "play.fill", size: play, w: w, h: h) { np.command("playpause") }
            button("forward.fill", size: side, w: w, h: h) { np.command("next track") }
            Spacer().frame(width: gap)
            MusicDismissButton(size: max(side - 1, 8), width: w * 0.85, height: h)
            if centred { Spacer(minLength: 0) }
        }
    }

    private func button(_ s: String, size: CGFloat, w: CGFloat, h: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: s).font(.system(size: size)).frame(width: w, height: h).contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
    }
}

/// "+" (or "✕" when rotated) drawn from two bars, so it is exactly centred in its frame (SF glyphs sit on a baseline).
struct CrossGlyph: View {
    var size: CGFloat
    var line: CGFloat
    var rotated = false

    var body: some View {
        ZStack {
            Capsule().frame(width: size, height: line)
            Capsule().frame(width: line, height: size)
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(rotated ? 45 : 0))
    }
}

final class SettleFlag: ObservableObject {
    @Published var big = false
}

/// Collapse arrival (round 22): the idle content appears a little inward of its spot (below on a top
/// Emper) and rises to it with a soft overshoot. Only `gen` changes trigger it, never a first appearance.
/// Bottom and side Empers mirror it (start inward from their screen edge) - assumption, same feel per edge.
struct SettleIn: ViewModifier {
    let gen: Int
    let edge: IslandEdge
    @StateObject private var flag = SettleFlag()

    func body(content: Content) -> some View {
        let d: CGFloat = flag.big ? 7 : 0
        let o: CGSize = switch edge {
        case .top: CGSize(width: 0, height: d)
        case .bottom: CGSize(width: 0, height: -d)
        case .left: CGSize(width: d, height: 0)
        case .right: CGSize(width: -d, height: 0)
        }
        content
            .offset(o)
            .onChange(of: gen) { _, _ in
                var t = Transaction(); t.disablesAnimations = true
                withTransaction(t) { flag.big = true }
                DispatchQueue.main.async {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.62)) { flag.big = false }
                }
            }
    }
}

final class StaggerFlag: ObservableObject {
    @Published var shown = false
}

/// Home placeholders pop in one after another (main first, then outward) with a springy overshoot.
/// `gen` changes on every open, so a quick close-and-reopen replays it even if the view was never removed.
struct StaggerIn: ViewModifier {
    let order: Int
    let edge: IslandEdge
    let gen: Int
    @StateObject private var f = StaggerFlag()

    func body(content: Content) -> some View {
        content
            .scaleEffect(f.shown ? 1 : 0.84)
            .opacity(f.shown ? 1 : 0)
            .offset(y: f.shown ? 0 : (edge == .bottom ? 8 : -8))
            .onAppear { play() }
            .onChange(of: gen) { _, _ in
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) { f.shown = false }
                DispatchQueue.main.async { play() }
            }
            .onDisappear { f.shown = false }
    }

    private func play() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.58).delay(0.05 + Double(order) * 0.06)) { f.shown = true }
    }
}
