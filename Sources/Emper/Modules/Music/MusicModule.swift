import SwiftUI
import EmperCore

@MainActor
final class MusicModule: IslandModule {
    func makeView() -> AnyView { AnyView(MusicView()) }
    func makeCompactView() -> AnyView? { AnyView(MusicCompactView()) }
}

struct ArtworkView: View {
    @ObservedObject var np = NowPlaying.shared
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22).fill(Color.primary.opacity(0.12))
            if let img = np.artwork {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "music.note").font(.system(size: size * 0.45)).foregroundStyle(Color.primary.opacity(0.8))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
        .animation(.easeOut(duration: 0.25), value: np.artwork != nil)
    }
}

/// Wide, shallow layout: [art | title, artist | controls] on top, the lyric under it, progress at the bottom.
struct MusicView: View {
    @ObservedObject var np = NowPlaying.shared
    @Environment(\.islandVertical) private var vertical
    var body: some View {
        if vertical { tall } else { wide }
    }

    /// Left/right Emper (tall, narrow). Round 26: everything centred: artwork, title and artist, the lyric,
    /// then the controls right above the timestamps.
    private var tall: some View {
        // Round 27: back to the left-aligned layout (round 26 tried it centred).
        VStack(alignment: .leading, spacing: 6) {
            Button { np.openPlayer() } label: {
                HStack(spacing: 10) {
                    ArtworkView(size: 38)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(np.hasTrack ? np.title : "Nothing playing")
                            .font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        MusicSubtitle()
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleStyle())
            .help("Open the player")
            Spacer(minLength: 0)
            if np.lyricsEnabled { LyricsView() }
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                control("backward.fill") { np.command("previous track") }
                control(np.isPlaying ? "pause.fill" : "play.fill", size: 18) { np.command("playpause") }
                control("forward.fill") { np.command("next track") }
                Spacer(minLength: 0)
            }
            // Round 23: which app is playing, on the left; the controls stay centred.
            .overlay(alignment: .leading) { SourceBadge() }
            ProgressRow()
        }
        .foregroundStyle(Color.primary)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var wide: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button { np.openPlayer() } label: {
                HStack(spacing: 12) {
                ArtworkView(size: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text(np.hasTrack ? np.title : "Nothing playing")
                        .font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    MusicSubtitle()
                }
                }
                .contentShape(Rectangle())
                }
                .buttonStyle(PressScaleStyle())
                .help("Open the player")
                Spacer(minLength: 8)
                HStack(spacing: 4) {
                    SourceBadge()
                    control("backward.fill") { np.command("previous track") }
                    control(np.isPlaying ? "pause.fill" : "play.fill", size: 18) { np.command("playpause") }
                    control("forward.fill") { np.command("next track") }
                }
            }
                if np.lyricsEnabled {
                    LyricsView().frame(maxHeight: .infinity)
                } else {
                    Spacer(minLength: 0)
                }
                ProgressRow()
        }
        .foregroundStyle(Color.primary)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func control(_ symbol: String, size: CGFloat = 14, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: size))
                .frame(width: 32, height: 28).contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
    }
}

/// Progress bar you can click or drag to jump; the time labels follow the drag, the player seeks on release.
/// Thin at rest; under the pointer it thickens and shows a knob that grows while dragged.
struct ProgressRow: View {
    @Environment(\.islandPointer) private var pointer

    var body: some View { ProgressRowBody(pointer: pointer) }
}

private struct ProgressRowBody: View {
    @ObservedObject var np = NowPlaying.shared
    @ObservedObject var pointer: PointerState
    @StateObject private var scrub = DragState()

    var body: some View {
        // Once a second (the times shown are whole seconds); was 2 Hz.
        TimelineView(SecondTicks()) { _ in
            let dur = max(np.duration, 1)
            let pos = scrub.fraction.map { $0 * dur } ?? min(max(np.currentPosition, 0), dur)
            HStack(spacing: 8) {
                Text(Self.time(pos))
                GeometryReader { g in
                    SeekTrack(fraction: pos / dur, dragging: scrub.dragging, hovering: pointer.seekHover)
                        .onAppear { pointer.seekFrame = g.frame(in: .global) }
                        .onChange(of: g.frame(in: .global)) { _, f in pointer.seekFrame = f }
                        .onDisappear { pointer.seekFrame = .null }
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { v in
                                scrub.dragging = true
                                scrub.fraction = min(max(v.location.x / max(g.size.width, 1), 0), 1)
                            }
                            .onEnded { v in
                                let f = min(max(v.location.x / max(g.size.width, 1), 0), 1)
                                np.seek(to: f * dur)
                                scrub.fraction = nil
                                scrub.dragging = false
                            })
                }
                .frame(height: 16)
                Text(Self.time(np.duration))
            }
            .font(.system(size: 10).monospacedDigit())
            .foregroundStyle(Color.primary.opacity(0.55))
        }
    }

    static func time(_ s: Double) -> String {
        let t = Int(max(s, 0))
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}

/// Current lyric, plus either its translation (when the LRC file carries one at the same timestamp,
/// marked with a translate badge so it does not read as the next line) or the next line, dimmed.
struct LyricsView: View {
    @ObservedObject var np = NowPlaying.shared
    /// Round 26: left/right Empers centre the lines.
    var centered = false

    var body: some View {
        // Driven by NowPlaying's lyricIndex (published only when the line changes); a 5 Hz TimelineView
        // here re-laid out the whole open Emper (round 21 CPU fix).
        Group {
            if np.lyrics.isEmpty {
                Text(np.lyricsStatus.isEmpty ? " " : np.lyricsStatus)
                    .font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.45))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: centered ? .center : .leading)
            } else {
                let i = np.lyricIndex.flatMap { np.lyrics.indices.contains($0) ? $0 : nil }
                let line = i.map { np.lyrics[$0] }
                let current = line?.text ?? ""
                VStack(alignment: centered ? .center : .leading, spacing: 3) {
                    Text(current.isEmpty ? "♪" : current).font(.system(size: 13, weight: .semibold))
                    if let tr = line?.translation, !tr.isEmpty {
                        HStack(spacing: 5) {
                            Image(systemName: "translate").font(.system(size: 9, weight: .semibold))
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(Capsule().fill(Color.primary.opacity(0.14)))
                            Text(tr).font(.system(size: 11).italic())
                        }
                        .foregroundStyle(Color(red: 0.55, green: 0.8, blue: 1).opacity(0.85))
                    } else {
                        let next = np.lyrics[min((i ?? -1) + 1, np.lyrics.count - 1)].text
                        Text(next).font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.35))
                    }
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: centered ? .center : .leading)
                .id(i ?? -1)
                .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                        removal: .move(edge: .top).combined(with: .opacity)))
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: i)
            }
        }
        .clipped()
    }
}

/// Compact "live activity" shown in the idle island while music plays: artwork, bars, and (top/bottom
/// islands, lyrics on) the current lyric line in the same row. The row's depth never changes; the island
/// only grows sideways to fit the line. Under a physical notch the lyric sits in the right wing.
struct LiveActivityView: View {
    @ObservedObject var np = NowPlaying.shared
    let config: IslandConfig
    let lyricWidth: CGFloat?
    let notch: Bool
    var below = false
    var dual = false

    var body: some View {
        let size = IslandGeometry.liveSize(config, lyricWidth: lyricWidth, notch: notch, below: below, dual: dual)
        let art = IslandGeometry.liveArt(config)
        // Bars double as the idle play/pause button (outside the hover zone, so it never opens the island).
        let bars = LivePlayButton(art: art)
        // Visible gap between the wing's outer edge and its content (past the flare).
        let pad = IslandGeometry.livePad()
        let gap = IslandGeometry.lyricGap
        Group {
            if config.edge.isVertical {
                VStack(spacing: 0) {
                    ArtworkView(size: art)
                    Spacer(minLength: 0)
                    bars
                }
                .padding(.vertical, pad)
            } else if lyricWidth != nil, notch, below {
                // Artwork and bars beside the notch; the line itself is drawn by the surface (strip or pill).
                // Island style keeps the body its usual length even when the pill under it is wider.
                HStack(spacing: 0) {
                    ArtworkView(size: art)
                    Spacer(minLength: 0)
                    bars.frame(width: art)
                }
                .padding(.horizontal, pad)
                .frame(width: dual ? size.width : min(size.width, IslandGeometry.liveSize(config, notch: true).width),
                       height: IslandGeometry.liveDepth(config))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else if lyricWidth != nil, notch {
                let body = CGFloat(config.collapsedWidth)
                HStack(spacing: 0) {
                    ArtworkView(size: art)
                    Spacer(minLength: 0)
                    IdleLyricLine(alignment: .leading)
                        .frame(width: max((size.width - body) / 2 - gap - gap - art - pad, 0))
                        .padding(.trailing, gap)
                    bars
                }
                .padding(.horizontal, pad)
            } else {
                HStack(spacing: 0) {
                    ArtworkView(size: art)
                    if lyricWidth != nil {
                        IdleLyricLine(alignment: .center)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, gap)
                    } else {
                        Spacer(minLength: 0)
                    }
                    bars.frame(width: art)
                }
                .padding(.horizontal, pad)
            }
        }
        .frame(width: size.width, height: size.height)
    }
}

/// The current lyric line; rolls up when the line changes.
/// Equalizer bars while playing, play icon while paused, pause icon under the pointer. Click = play/pause.
struct LivePlayButton: View {
    @ObservedObject var np = NowPlaying.shared
    @StateObject private var hover = HoverFlag()
    let art: CGFloat

    var body: some View {
        Button { np.command("playpause") } label: {
            ZStack {
                if hover.on || !np.isPlaying {
                    Image(systemName: np.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: max(art * 0.55, 9), weight: .bold))
                } else {
                    EqualizerBars(playing: true).frame(width: art * 0.8, height: art * 0.6)
                }
            }
            .frame(width: art, height: art)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .onHover { hover.on = $0 }
        .help(np.isPlaying ? "Pause" : "Play")
    }
}

final class HoverFlag: ObservableObject {
    @Published var on = false
}

struct IdleLyricLine: View {
    @ObservedObject var np = NowPlaying.shared
    var alignment: Alignment = .center
    var small = false

    var body: some View {
        let text = np.currentLyric
        Text(text.isEmpty ? "♪" : text)
            .font(Font(small ? LyricMetrics.smallFont : LyricMetrics.font))
            .foregroundStyle(Color.primary.opacity(small ? 0.75 : 0.9))
            .lineLimit(1)
            .truncationMode(.tail)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: alignment)
            .id(np.lyricIndex ?? -1)
            .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                    removal: .move(edge: .top).combined(with: .opacity)))
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: np.lyricIndex)
            .clipped()
    }
}

struct EqualizerBars: View {
    let playing: Bool

    /// Core Animation bars: the bounce runs in the window server, so Emper's main thread does no work per
    /// frame (the SwiftUI/TimelineView version re-laid out every Emper showing music 15-30 times a second).
    var body: some View { EqualizerLayerView(playing: playing) }
}

private struct EqualizerLayerView: NSViewRepresentable {
    let playing: Bool

    func makeNSView(context: Context) -> EqualizerNSView { EqualizerNSView() }
    func updateNSView(_ v: EqualizerNSView, context: Context) { v.playing = playing }
}

final class EqualizerNSView: NSView {
    private let bars = (0..<4).map { _ in CALayer() }
    private static let periods: [CFTimeInterval] = [0.62, 0.43, 0.51, 0.37]
    var playing = false { didSet { if playing != oldValue { restart() } } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        bars.forEach { layer?.addSublayer($0) }
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let n = CGFloat(bars.count), gap = bounds.width * 0.12
        let w = max((bounds.width - gap * (n - 1)) / n, 1)
        for (i, b) in bars.enumerated() {
            b.bounds = CGRect(x: 0, y: 0, width: w, height: bounds.height)
            b.position = CGPoint(x: CGFloat(i) * (w + gap) + w / 2, y: bounds.midY)
            b.cornerRadius = w / 2
        }
        CATransaction.commit()
        restart()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        recolor()
    }

    private func recolor() {
        var c = NSColor.labelColor.withAlphaComponent(0.9).cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance { c = NSColor.labelColor.withAlphaComponent(0.9).cgColor }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        bars.forEach { $0.backgroundColor = c }
        CATransaction.commit()
    }

    private func restart() {
        recolor()
        for (i, b) in bars.enumerated() {
            b.removeAllAnimations()
            CATransaction.begin(); CATransaction.setDisableActions(true)
            b.transform = CATransform3DMakeScale(1, playing ? 0.5 : 0.2, 1)
            CATransaction.commit()
            guard playing else { continue }
            let a = CABasicAnimation(keyPath: "transform.scale.y")
            a.fromValue = 0.3
            a.toValue = 1.0
            a.duration = Self.periods[i]
            a.autoreverses = true
            a.repeatCount = .infinity
            a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            a.timeOffset = Double(i) * 0.17
            b.add(a, forKey: "eq")
        }
    }
}

/// Artist line, or the Allow button when Spotify / Apple Music only works with direct control.
/// macOS asks for Automation access only after this tap, never at launch.
struct MusicSubtitle: View {
    @ObservedObject var np = NowPlaying.shared

    var body: some View {
        if np.needsAppControl {
            Button { NowPlaying.enableAppControl() } label: {
                Label("Allow Spotify & Apple Music control", systemImage: "lock.shield")
                    .font(.system(size: 10, weight: .semibold)).lineLimit(1)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.14)))
            }
            .buttonStyle(.plain)
            .help("macOS will ask once whether Emper may control the app")
        } else {
            Text(np.hasTrack ? np.artist : (np.status.isEmpty ? "Play something in Spotify or Apple Music" : np.status))
                .font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.6)).lineLimit(1)
        }
    }
}
