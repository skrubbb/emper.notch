import Foundation

/// The screen edge an island is attached to. One island per edge per display.
public enum IslandEdge: String, Codable, CaseIterable, Identifiable, Sendable, CodingKeyRepresentable {
    case top, left, right, bottom

    public var id: String { rawValue }

    public var settingsName: String {
        switch self {
        case .top: "Top Emper"
        case .left: "Left Emper"
        case .right: "Right Emper"
        case .bottom: "Bottom Emper"
        }
    }

    /// Left/right islands run along a vertical edge.
    public var isVertical: Bool { self == .left || self == .right }
}
