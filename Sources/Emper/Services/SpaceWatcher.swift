import AppKit
import CoreGraphics

/// Tells when Mission Control is open and which displays show a full-screen app, from the on-screen window
/// list. It reads only each window's owner, layer and size (no titles, no contents), which needs no
/// permission. Checked once a second, plus right after a Space or app switch.
///
/// Signals found by experiment on macOS 27 (not documented by Apple, may change in a later macOS):
/// - Mission Control: windows owned by "WindowManager" at layer 19 covering a whole display.
/// - Full screen: the display's menu bar window (layer 24) is gone and another app's normal window
///   (layer 0) spans the display's width down to its bottom edge. While the same window stays, the display
///   stays full screen when the menu bar slides in, but only while the pointer is (or just was) at the top
///   of that display. A menu bar that shows with the pointer elsewhere means the app left full screen
///   (a maximised window looks the same on a notched display, so the pointer is what tells them apart).
/// If a signal is not found, Emper simply behaves as on a normal desktop.
@MainActor
final class SpaceWatcher: ObservableObject {
    static let shared = SpaceWatcher()
    @Published private(set) var missionControl = false
    /// `emperID`s of displays showing a full-screen app.
    @Published private(set) var fullScreen: Set<String> = []
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    /// Display → window number of the full-screen window found there.
    private var fsWindow: [String: Int] = [:]
    /// Display → last time the pointer was in its top band (where it reveals a full-screen menu bar).
    private var pointerTopAt: [String: Date] = [:]

    func setActive(_ on: Bool) {
        if on, timer == nil {
            let t = Timer(timeInterval: 1, repeats: true) { _ in MainActor.assumeIsolated { SpaceWatcher.shared.check() } }
            t.tolerance = 0.2
            RunLoop.main.add(t, forMode: .common)
            timer = t
            let nc = NSWorkspace.shared.notificationCenter
            for n in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
                observers.append(nc.addObserver(forName: n, object: nil, queue: .main) { _ in
                    // The Space slide takes a moment: look right away and once more after it.
                    for d in [0.1, 0.6] {
                        DispatchQueue.main.asyncAfter(deadline: .now() + d) { MainActor.assumeIsolated { SpaceWatcher.shared.check() } }
                    }
                })
            }
            check()
        } else if !on, let t = timer {
            t.invalidate()
            timer = nil
            observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
            observers = []
            fsWindow = [:]
            if missionControl { missionControl = false }
            if !fullScreen.isEmpty { fullScreen = [] }
        }
    }

    struct Win { let number: Int; let owner: String; let pid: pid_t; let layer: Int; let bounds: CGRect }

    func check() {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return }
        let wins: [Win] = list.compactMap { w in
            guard let layer = w[kCGWindowLayer as String] as? Int,
                  let bd = w[kCGWindowBounds as String] as? NSDictionary,
                  let b = CGRect(dictionaryRepresentation: bd) else { return nil }
            return Win(number: w[kCGWindowNumber as String] as? Int ?? 0, owner: w[kCGWindowOwnerName as String] as? String ?? "",
                       pid: w[kCGWindowOwnerPID as String] as? pid_t ?? 0, layer: layer, bounds: b)
        }
        let ds = Self.displays()
        let r = Self.evaluate(wins, displays: ds, me: ProcessInfo.processInfo.processIdentifier, previous: fsWindow,
                              pointerTop: pointerNearTop(ds))
        fsWindow = r.fsWindow
        if r.missionControl != missionControl { missionControl = r.missionControl }
        let fs = Set(r.fsWindow.keys)
        if fs != fullScreen { fullScreen = fs }
    }

    /// Displays whose top band (menu bar height + margin) holds the pointer now or did in the last 1.5 s.
    private func pointerNearTop(_ ds: [(id: String, frame: CGRect, top: CGFloat)]) -> Set<String> {
        let h = NSScreen.screens.first?.frame.height ?? 0
        let m = NSEvent.mouseLocation
        let p = CGPoint(x: m.x, y: h - m.y)   // window-list coordinates
        let now = Date()
        for d in ds where p.x >= d.frame.minX && p.x <= d.frame.maxX && p.y >= d.frame.minY - 1
            && p.y <= d.frame.minY + max(d.top, 24) + 40 {
            pointerTopAt[d.id] = now
        }
        return Set(pointerTopAt.filter { now.timeIntervalSince($0.value) < 1.5 }.keys)
    }

    /// Displays in window-list coordinates (origin top-left of the primary display), with the notch height.
    static func displays() -> [(id: String, frame: CGRect, top: CGFloat)] {
        let h = NSScreen.screens.first?.frame.height ?? 0
        return NSScreen.screens.map { s in
            let f = s.frame
            return (s.emperID, CGRect(x: f.minX, y: h - f.maxY, width: f.width, height: f.height), s.safeAreaInsets.top)
        }
    }

    /// Pure decision, so the self-test can feed it made-up window lists.
    nonisolated static func evaluate(_ wins: [Win], displays: [(id: String, frame: CGRect, top: CGFloat)], me: pid_t,
                                     previous: [String: Int], pointerTop: Set<String> = [])
        -> (missionControl: Bool, fsWindow: [String: Int]) {
        func same(_ a: CGRect, _ b: CGRect) -> Bool {
            abs(a.minX - b.minX) < 1 && abs(a.minY - b.minY) < 1 && abs(a.width - b.width) < 1 && abs(a.height - b.height) < 1
        }
        let mc = wins.contains { w in w.owner == "WindowManager" && w.layer == 19 && displays.contains { same($0.frame, w.bounds) } }
        var fs: [String: Int] = [:]
        guard !mc else { return (true, previous) }   // keep the full-screen state as it was while Mission Control is open
        for d in displays {
            // A normal window of another app covering the display (below the notch at most).
            let covers = wins.filter { w in
                w.layer == 0 && w.pid != me && w.owner != "WindowManager"
                    && abs(w.bounds.width - d.frame.width) < 1 && abs(w.bounds.minX - d.frame.minX) < 1
                    && abs(w.bounds.maxY - d.frame.maxY) < 1 && w.bounds.minY <= d.frame.minY + d.top + 1
            }
            let menuBar = wins.contains { w in
                w.layer == 24 && w.owner == "Window Server" && abs(w.bounds.minY - d.frame.minY) < 1
                    && abs(w.bounds.minX - d.frame.minX) < 1 && abs(w.bounds.width - d.frame.width) < 1
            }
            if let p = previous[d.id], covers.contains(where: { $0.number == p }), !menuBar || pointerTop.contains(d.id) {
                fs[d.id] = p
                continue
            }
            if !menuBar, let w = covers.first { fs[d.id] = w.number }
        }
        return (false, fs)
    }
}
