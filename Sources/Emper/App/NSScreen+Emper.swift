import AppKit

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    /// Stable per-monitor key (survives reboots and port changes better than the display ID).
    var emperID: String {
        if let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue(),
           let s = CFUUIDCreateString(nil, uuid) {
            return s as String
        }
        return "display-\(displayID)"
    }

    /// Notch size, or nil on screens without one.
    var notchSize: CGSize? {
        guard safeAreaInsets.top > 0, let l = auxiliaryTopLeftArea, let r = auxiliaryTopRightArea else { return nil }
        return CGSize(width: frame.width - l.width - r.width, height: safeAreaInsets.top)
    }
}

extension NSScreen {
    /// Menu bar height on this screen (falls back to the system thickness if the menu bar is hidden).
    var menuBarHeight: Double {
        let h = frame.maxY - visibleFrame.maxY
        return Double(h > 0 ? h : NSStatusBar.system.thickness)
    }
}
