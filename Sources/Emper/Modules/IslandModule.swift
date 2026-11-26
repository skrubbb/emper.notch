import SwiftUI
import EmperCore

/// A module is one tab of an island. Each island gets its own instance (shared state lives in services).
/// To add a module: implement this protocol and add one `ModuleDescriptor` to `ModuleRegistry.all`.
@MainActor
protocol IslandModule: AnyObject {
    /// Full view: own tab, or the main Home placeholder.
    func makeView() -> AnyView
    /// Small view for a side placeholder (30 % of the main width). nil = an icon tile.
    func makeCompactView() -> AnyView?
    /// Release observers/timers when the island closes or drops the module.
    func stop()
}

extension IslandModule {
    func makeCompactView() -> AnyView? { nil }
    func stop() {}
}

struct ModuleDescriptor: Identifiable {
    let id: String
    let name: String
    let symbol: String
    /// Content size without island insets. Depends on the island (e.g. calculator follows the notch
    /// length) and on settings (e.g. lyrics).
    let contentSize: @MainActor (IslandConfig) -> CGSize
    let make: @MainActor () -> any IslandModule
}

@MainActor
enum ModuleRegistry {
    static let homeID = "home"
    static let musicID = "music"
    static let screenshotsID = "screenshots"
    static let calculatorID = "calculator"
    static let statsID = "stats"
    static let timerID = "timer"
    static let shelfID = "shelf"
    static let noteID = "note"
    static let reminderID = "reminder"

    /// v0.1.0 release scope: only these features are shown. The other features stay fully in the code and are
    /// switched on again with `defaults write com.skrubbb.emper showExperimental -bool true` (or the
    /// `--experimental` launch argument; self-test and render runs always show everything).
    static let releaseIDs: Set<String> = [homeID, musicID, screenshotsID, noteID]
    static let showExperimental: Bool = {
        let a = CommandLine.arguments
        return UserDefaults.standard.bool(forKey: "showExperimental")
            || a.contains("--experimental") || a.contains("--selftest") || a.contains("--render") || a.contains("--bench") || a.contains("--zones")
    }()

    /// Every module that exists in the code.
    static let everything: [ModuleDescriptor] = [
        ModuleDescriptor(id: homeID, name: "Home", symbol: "house.fill",
                         contentSize: { homeRow($0) },
                         make: { HomeModule() }),
        ModuleDescriptor(id: musicID, name: "Music", symbol: "music.note",
                         contentSize: { single($0) },
                         make: { MusicModule() }),
        ModuleDescriptor(id: statsID, name: "System Stats", symbol: "cpu",
                         contentSize: { single($0) },
                         make: { StatsModule() }),
        ModuleDescriptor(id: timerID, name: "Timer", symbol: "timer",
                         contentSize: { single($0) },
                         make: { TimerModule() }),
        ModuleDescriptor(id: calculatorID, name: "Calculator", symbol: "plus.forwardslash.minus",
                         contentSize: { single($0) },
                         make: { CalculatorModule() }),
        ModuleDescriptor(id: "clipboard", name: "Clipboard", symbol: "doc.on.clipboard",
                         contentSize: { single($0) },
                         make: { ClipboardModule() }),
        ModuleDescriptor(id: screenshotsID, name: "Screenshots", symbol: "camera.viewfinder",
                         contentSize: { single($0) },
                         make: { ScreenshotsModule() }),
        ModuleDescriptor(id: shelfID, name: "File Shelf", symbol: "tray.full",
                         contentSize: { single($0) },
                         make: { ShelfModule() }),
        // Round 28.
        ModuleDescriptor(id: noteID, name: "Quick Note", symbol: "note.text",
                         contentSize: { single($0) },
                         make: { QuickNoteModule() }),
        ModuleDescriptor(id: reminderID, name: "Reminder", symbol: "checklist",
                         contentSize: { single($0) },
                         make: { ReminderModule() }),
    ]

    /// What the app offers right now (release scope unless experimental features are on).
    static let all: [ModuleDescriptor] = showExperimental ? everything : everything.filter { releaseIDs.contains($0.id) }

    /// Home tab of a top/bottom island: the placeholder row (main slot + side slots). Side slots exist
    /// only on Home, so this is the widest tab.
    static func homeRow(_ c: IslandConfig) -> CGSize {
        let along = HomeLayout.length(c)
        // Left/right Empers: the row is a column (round 23).
        return c.edge.isVertical ? CGSize(width: HomeLayout.verticalWidth, height: along)
            : CGSize(width: along, height: IslandGeometry.moduleHeight)
    }

    /// Any other tab: just the main size (the open island shrinks to it when you leave Home).
    static func single(_ c: IslandConfig) -> CGSize {
        c.edge.isVertical ? CGSize(width: 260, height: 170)
            : CGSize(width: IslandGeometry.openContentWidth(c), height: IslandGeometry.moduleHeight)
    }

    /// Features offered in Settings (Home itself is automatic on top/bottom islands). Each one goes on
    /// Home or in its own tab.
    static func tabModules(for edge: IslandEdge) -> [ModuleDescriptor] {
        all.filter { $0.id != homeID }
    }

    static func descriptor(_ id: String) -> ModuleDescriptor? { all.first { $0.id == id } }
}

/// Small squash on press, for a tactile feel.
struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .brightness(configuration.isPressed ? 0.12 : 0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
