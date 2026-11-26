import SwiftUI
import AppKit
import EmperCore

/// Round 23: who is playing, left of the backward button. Drawn as vectors (crisp on 1x and 2x screens);
/// any other app shows its own icon. Click = bring that app to the front.
struct SourceBadge: View {
    @ObservedObject var np = NowPlaying.shared
    var size: CGFloat = 16

    var body: some View {
        if np.hasTrack, np.source != .none {
            Button { np.openPlayer() } label: {
                glyph
                    .frame(width: size, height: size)
                    // 28 pt tall hit area like the controls next to it.
                    .frame(width: size + 10, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleStyle())
            .help("Playing in \(name)")
            .accessibilityLabel("Playing in \(name)")
            .transition(.opacity)
        }
    }

    private var name: String {
        switch np.source {
        case .spotify: "Spotify"
        case .appleMusic: "Apple Music"
        default: np.sourceName
        }
    }

    @ViewBuilder private var glyph: some View {
        switch np.source {
        case .spotify: SpotifyMark()
        case .appleMusic: AppleMusicMark()
        case .app(let b): AppIconMark(bundle: b)
        case .none: EmptyView()
        }
    }
}

/// Spotify: green disc with three arcs, thickest on top.
struct SpotifyMark: View {
    var body: some View {
        GeometryReader { g in
            let s = min(g.size.width, g.size.height)
            ZStack {
                Circle().fill(Color(red: 0x1E / 255, green: 0xD7 / 255, blue: 0x60 / 255))
                ForEach(0..<3, id: \.self) { i in
                    SpotifyArc(row: i)
                        .stroke(Color.black, style: StrokeStyle(lineWidth: s * [0.115, 0.095, 0.08][i], lineCap: .round))
                }
            }
            .frame(width: s, height: s)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

private struct SpotifyArc: Shape {
    let row: Int
    func path(in r: CGRect) -> Path {
        let w = r.width
        let y = r.minY + w * [0.36, 0.53, 0.69][row]
        let half = w * [0.29, 0.255, 0.215][row]
        let lift = w * [0.075, 0.06, 0.05][row]
        let shift = w * [0, 0.005, 0.015][row]
        var p = Path()
        p.move(to: CGPoint(x: r.midX - half - shift, y: y + lift * 0.3))
        p.addQuadCurve(to: CGPoint(x: r.midX + half - shift, y: y + lift),
                       control: CGPoint(x: r.midX - shift * 2, y: y - lift))
        return p
    }
}

/// Apple Music: red-pink rounded square with a white note.
struct AppleMusicMark: View {
    var body: some View {
        GeometryReader { g in
            let s = min(g.size.width, g.size.height)
            RoundedRectangle(cornerRadius: s * 0.24, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.98, green: 0.36, blue: 0.45), Color(red: 0.98, green: 0.14, blue: 0.23)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(Image(systemName: "music.note").font(.system(size: s * 0.58, weight: .bold)).foregroundStyle(.white))
                .frame(width: s, height: s)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}


/// Any other app: its real icon (looked up once per bundle).
struct AppIconMark: View {
    let bundle: String
    private static var cache: [String: NSImage] = [:]

    var body: some View {
        if let img = Self.icon(bundle) {
            Image(nsImage: img).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "waveform").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.primary.opacity(0.7))
        }
    }

    @MainActor static func icon(_ b: String) -> NSImage? {
        if let i = cache[b] { return i }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: b) else { return nil }
        let i = NSWorkspace.shared.icon(forFile: url.path)
        cache[b] = i
        return i
    }
}
