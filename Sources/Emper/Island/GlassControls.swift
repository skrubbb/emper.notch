import AppKit
import SwiftUI

/// Drag state for the seek bar (an ObservableObject: the CLT toolchain has no @State macro).
final class DragState: ObservableObject {
    @Published var dragging = false
    /// 0...1 while dragging (the player only seeks on release).
    @Published var fraction: Double?
}

/// Pointer position inside one island, in its view's coordinates (origin top-left); nil while idle.
/// Fed by the island controller from the pointer it already tracks, because hover events do not reach
/// a panel that is never key. Only views that need hover observe it.
/// Only `seekHover` is published: re-rendering on every mouse move re-laid out the whole open Emper
/// (round 21: ~20% CPU while hovering). Views register the frame they care about instead.
final class PointerState: ObservableObject {
    var location: CGPoint? { didSet { refresh() } }
    /// Seek bar frame in the island view's coordinates, written by the seek bar itself.
    var seekFrame: CGRect = .null { didSet { refresh() } }
    @Published private(set) var seekHover = false

    private func refresh() {
        let h = location.map { !seekFrame.isNull && seekFrame.insetBy(dx: -4, dy: -6).contains($0) } ?? false
        if h != seekHover { seekHover = h }
    }
}

private struct IslandPointerKey: EnvironmentKey {
    static let defaultValue = PointerState()
}

private struct IslandVerticalKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// The view sits in a left/right Emper (tall and narrow).
    var islandVertical: Bool {
        get { self[IslandVerticalKey.self] }
        set { self[IslandVerticalKey.self] = newValue }
    }
    var islandPointer: PointerState {
        get { self[IslandPointerKey.self] }
        set { self[IslandPointerKey.self] = newValue }
    }
}

/// Seek bar in the island: thin at rest; under the pointer it thickens and shows a round knob so it
/// reads as draggable; the knob grows while dragged.
struct SeekTrack: View {
    let fraction: Double
    let dragging: Bool
    let hovering: Bool

    var body: some View {
        let active = dragging || hovering
        let trackH: CGFloat = active ? 5 : 3
        let knob: CGFloat = dragging ? 14 : 11
        GeometryReader { g in
            let w = g.size.width
            let x = w * min(max(fraction, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.2)).frame(height: trackH)
                Capsule().fill(Color.primary.opacity(active ? 1 : 0.8)).frame(width: max(x, trackH), height: trackH)
                Circle().fill(Color.primary)
                    .frame(width: knob, height: knob)
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                    .offset(x: min(max(x - knob / 2, 0), max(w - knob, 0)))
                    .opacity(active ? 1 : 0)
                    .scaleEffect(active ? 1 : 0.3)
            }
            .frame(width: w, height: g.size.height)
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: dragging)
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}
