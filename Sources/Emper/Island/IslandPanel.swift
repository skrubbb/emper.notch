import AppKit

/// Borderless, non-activating floating panel that sits above the menu bar and on every Space.
final class IslandPanel: NSPanel {
    init(frame: CGRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false            // shadow is drawn in SwiftUI so it follows the shape
        isFloatingPanel = true
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        // Above the menu bar (mainMenu = 24). +3 also clears status-bar items.
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        // .stationary: stays during Show Desktop (drag files from the desktop onto the shelf). Mission
        // Control is handled by `SpaceWatcher` (it would keep the island over the Spaces bar).
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        ignoresMouseEvents = true
        acceptsMouseMovedEvents = true
    }

    /// Keyboard focus goes to `KeyCatcher`, never to the island (re-ordering a key island blinked).
    override var canBecomeKey: Bool { false }

    /// Off: the island stays out of full-screen Spaces.
    var showsInFullScreen = true {
        didSet {
            guard showsInFullScreen != oldValue else { return }
            if showsInFullScreen { collectionBehavior.insert(.fullScreenAuxiliary) } else { collectionBehavior.remove(.fullScreenAuxiliary) }
        }
    }
    override var canBecomeMain: Bool { false }

    // Do not let AppKit push the panel below the menu bar.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}
