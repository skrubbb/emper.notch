import AppKit
import Combine
import QuickLookThumbnailing

/// Recent files in the folder macOS saves screenshots to. Never changes the screenshot settings: the
/// folder comes from `com.apple.screencapture location` (default: Desktop). Optionally Emper moves each
/// *new* screenshot (files macOS marks as a screen capture) into a folder of the person's choice.
@MainActor
final class ScreenshotShelf: ObservableObject {
    static let shared = ScreenshotShelf()

    struct Item: Identifiable, Equatable {
        let url: URL
        let date: Date
        var id: URL { url }
    }

    @Published private(set) var items: [Item] = []
    @Published private(set) var thumbnails: [URL: NSImage] = [:]
    @Published private(set) var folder: URL
    /// The folder is one macOS guards (Desktop, Documents, Downloads, iCloud) and the person has not
    /// pressed Allow yet: Emper does not touch it, so macOS shows no access prompt at launch (round 27).
    @Published private(set) var needsAccess = false
    /// Allowed in Emper but macOS refused the folder (the person said no in the macOS prompt).
    @Published private(set) var denied = false
    private static let grantKey = "screenshotFolderAllowed"
    private var granted: Bool {
        get { UserDefaults.standard.bool(forKey: Self.grantKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.grantKey) }
    }

    nonisolated static let maxItems = 10
    nonisolated static let extensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff", "gif", "pdf", "mov", "mp4"]

    private var source: DispatchSourceFileSystemObject?
    private var active = false
    private var reloadWork: DispatchWorkItem?
    /// Move-new-screenshots target (nil = off) and its watcher on the macOS screenshot folder.
    private(set) var destination: URL?
    private var mover: DispatchSourceFileSystemObject?
    /// Bumped whenever a watcher is replaced, so a late-opening one for an old folder is dropped.
    private var sourceGen = 0, moverGen = 0
    private var moverSince = Date()
    private var moveWork: DispatchWorkItem?

    init(folder: URL? = nil) {
        self.folder = folder ?? Self.systemFolder()
    }

    /// Where macOS saves screenshots (Screenshot app › Options › Save to).
    nonisolated static func systemFolder() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        if let raw = CFPreferencesCopyAppValue("location" as CFString, "com.apple.screencapture" as CFString) as? String,
           !raw.isEmpty {
            let path = (raw as NSString).expandingTildeInPath
            var dir: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &dir), dir.boolValue {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
        }
        return home.appendingPathComponent("Desktop", isDirectory: true)
    }

    /// Folder the shelf lists: the chosen destination, or the macOS screenshot folder.
    private var listedFolder: URL { destination ?? Self.systemFolder() }

    /// Folders macOS asks about before an app may read them.
    nonisolated static func isProtected(_ url: URL) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        return ["Desktop", "Documents", "Downloads", "Library/Mobile Documents"].contains { d in
            let root = home + "/" + d
            return path == root || path.hasPrefix(root + "/")
        }
    }

    /// True while a folder Emper would read still waits for the person's Allow.
    private var blocked: Bool {
        guard !granted else { return false }
        return Self.isProtected(listedFolder) || (destination != nil && Self.isProtected(Self.systemFolder()))
    }

    /// Called from the Screenshots tab or Settings: now macOS may show its prompt, once.
    func allowAccess() {
        granted = true
        denied = false
        needsAccess = false
        startMover()
        if active {
            folder = listedFolder
            startWatching()
            reload()
        }
    }

    func openPrivacySettings() {
        if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders") {
            NSWorkspace.shared.open(u)
        }
    }

    func setDestination(_ url: URL?) {
        guard url?.standardizedFileURL != destination?.standardizedFileURL else { return }
        destination = url
        moverSince = Date()
        startMover()
        if active {
            folder = listedFolder
            if blocked { stopWatching(); items = []; needsAccess = true; return }
            needsAccess = false
            startWatching()
            reload()
        }
    }

    private func startMover() {
        mover?.cancel()
        mover = nil
        moverGen += 1
        if blocked, destination != nil { needsAccess = true; return }
        guard !blocked, let url = destination, url.standardizedFileURL != Self.systemFolder().standardizedFileURL else { return }
        let g = moverGen
        Self.watch(Self.systemFolder(), create: url) { [weak self] in self?.scheduleMove() } ready: { [weak self] src in
            guard let self, g == self.moverGen else { src?.cancel(); return }
            self.mover = src
        }
    }

    private func scheduleMove() {
        moveWork?.cancel()
        let w = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.moveNewScreenshots() } }
        moveWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: w)
    }

    /// Moves screenshots taken since the option was turned on. Older files are never touched.
    private func moveNewScreenshots() {
        guard let dest = destination else { return }
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.creationDateKey, .isRegularFileKey]
        guard let urls = try? fm.contentsOfDirectory(at: Self.systemFolder(), includingPropertiesForKeys: Array(keys),
                                                     options: [.skipsHiddenFiles]) else { return }
        for url in urls {
            guard let v = try? url.resourceValues(forKeys: keys), v.isRegularFile == true,
                  (v.creationDate ?? .distantPast) >= moverSince, Self.isScreenCapture(url) else { continue }
            var target = dest.appendingPathComponent(url.lastPathComponent)
            var n = 2
            while fm.fileExists(atPath: target.path) {
                let base = url.deletingPathExtension().lastPathComponent
                target = dest.appendingPathComponent("\(base) \(n)").appendingPathExtension(url.pathExtension)
                n += 1
            }
            do { try fm.moveItem(at: url, to: target) } catch { NSLog("Emper: could not move screenshot: \(error)") }
        }
    }

    /// macOS tags screenshots and screen recordings with kMDItemIsScreenCapture.
    nonisolated static func isScreenCapture(_ url: URL) -> Bool {
        let name = "com.apple.metadata:kMDItemIsScreenCapture"
        return getxattr(url.path, name, nil, 0, 0, 0) > 0
    }

    /// Watch the folder only while an island uses this module.
    func setActive(_ on: Bool) {
        guard on != active else { return }
        active = on
        if on {
            let current = listedFolder
            if current != folder { folder = current }
            if blocked { needsAccess = true; return }
            needsAccess = false
            startWatching()
            reload()
        } else {
            stopWatching()
            items = []
            thumbnails = [:]
        }
    }

    func reload() {
        let dir = folder
        Task.detached(priority: .utility) {
            let found = Self.scan(dir)
            await MainActor.run {
                self.denied = found == nil && Self.isProtected(dir)
                self.apply(found ?? [])
            }
        }
    }

    /// nil when the folder cannot be read (missing, or macOS refused access).
    nonisolated static func scan(_ dir: URL) -> [Item]? {
        let keys: [URLResourceKey] = [.creationDateKey, .isRegularFileKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys,
                                                                      options: [.skipsHiddenFiles]) else { return nil }
        let items = urls.compactMap { url -> Item? in
            guard extensions.contains(url.pathExtension.lowercased()),
                  let v = try? url.resourceValues(forKeys: Set(keys)), v.isRegularFile == true else { return nil }
            return Item(url: url, date: v.creationDate ?? .distantPast)
        }
        return Array(items.sorted { $0.date > $1.date }.prefix(maxItems))
    }

    private func apply(_ found: [Item]) {
        guard found != items else { return }
        items = found
        let keep = Set(found.map(\.url))
        thumbnails = thumbnails.filter { keep.contains($0.key) }
        for item in found where thumbnails[item.url] == nil { loadThumbnail(item.url) }
    }

    private func loadThumbnail(_ url: URL) {
        let req = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 160, height: 100),
                                               scale: 2, representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { rep, _ in
            guard let img = rep?.nsImage else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.thumbnails[url] = img }
            }
        }
    }

    func open(_ item: Item) { NSWorkspace.shared.open(item.url) }
    func reveal(_ item: Item) { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
    func openFolder() { NSWorkspace.shared.open(folder) }

    func copy(_ item: Item) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([item.url as NSURL])
    }

    private func startWatching() {
        stopWatching()
        let g = sourceGen
        Self.watch(folder) { [weak self] in self?.scheduleReload() } ready: { [weak self] src in
            guard let self, g == self.sourceGen else { src?.cancel(); return }
            self.source = src
        }
    }

    /// Opens `dir` for change events off the main thread: on a fresh build macOS may hold `open` until the
    /// person answers the Desktop/Documents access prompt, and the islands must not wait for that (round 14).
    /// `create` is made first (same reason). `ready` runs on the main thread with the watcher (nil on failure).
    private static func watch(_ dir: URL, create: URL? = nil, _ changed: @escaping @MainActor @Sendable () -> Void,
                              ready: @escaping @MainActor @Sendable (DispatchSourceFileSystemObject?) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            if let create { try? FileManager.default.createDirectory(at: create, withIntermediateDirectories: true) }
            let fd = Darwin.open(dir.path, O_EVTONLY)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard fd >= 0 else { return ready(nil) }
                    let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete],
                                                                        queue: .main)
                    src.setEventHandler { MainActor.assumeIsolated { changed() } }
                    src.setCancelHandler { close(fd) }
                    src.resume()
                    ready(src)
                }
            }
        }
    }

    private func stopWatching() {
        sourceGen += 1
        source?.cancel()
        source = nil
    }

    /// Screenshots are written in steps (temp file, rename); wait for the dust to settle.
    private func scheduleReload() {
        reloadWork?.cancel()
        let w = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.reload() } }
        reloadWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: w)
    }
}
