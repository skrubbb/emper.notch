import AppKit
import SwiftUI
import EmperCore

extension Color {
    /// Island body: black in dark, white in light. Also the ink on "primary" filled buttons.
    static let islandFill = Color(nsColor: NSColor(name: "EmperIslandFill") { a in
        a.bestMatch(from: [.darkAqua, .aqua]) == .aqua ? .white : .black
    })
}

extension IslandTheme {
    /// Panel appearance: views inside follow it (Color.primary, colorScheme). nil = follow macOS.
    var appearance: NSAppearance? {
        switch self {
        case .system: nil
        case .dark: NSAppearance(named: .darkAqua)
        case .light: NSAppearance(named: .aqua)
        }
    }

    var name: String {
        switch self {
        case .system: "System"
        case .dark: "Dark"
        case .light: "Light"
        }
    }
}
