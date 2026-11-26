import Foundation

/// Where the Dock lives. Read-only: Emper never writes Dock preferences.
public struct DockInfo: Equatable, Sendable {
    public var edge: IslandEdge
    public var autohide: Bool

    public init(edge: IslandEdge, autohide: Bool) {
        self.edge = edge
        self.autohide = autohide
    }

    /// `orientation` comes from the com.apple.dock "orientation" key. A missing key means bottom (macOS default).
    public static func parse(orientation: String?, autohide: Bool?) -> DockInfo {
        let edge: IslandEdge
        switch orientation?.lowercased() {
        case "left": edge = .left
        case "right": edge = .right
        default: edge = .bottom
        }
        return DockInfo(edge: edge, autohide: autohide ?? false)
    }
}
