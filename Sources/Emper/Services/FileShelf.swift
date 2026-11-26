import AppKit
import Foundation
import UniformTypeIdentifiers

/// Files parked on the island to drag somewhere else later. Holds references only (nothing is
/// copied or moved) and lives in memory: the shelf is empty after Emper quits.
@MainActor
final class FileShelf: ObservableObject {
    static let shared = FileShelf()
    static let limit = 30

    @Published private(set) var items: [URL] = []

    func add(_ urls: [URL]) {
        for u in urls where !items.contains(u) { items.append(u) }
        if items.count > Self.limit { items.removeFirst(items.count - Self.limit) }
    }

    func remove(_ u: URL) { items.removeAll { $0 == u } }
    func clear() { items.removeAll() }

    /// Drop handler: collects file URLs from the providers.
    func accept(_ providers: [NSItemProvider]) -> Bool {
        let file = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !file.isEmpty else { return false }
        for p in file {
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                guard let url, url.isFileURL else { return }
                DispatchQueue.main.async { MainActor.assumeIsolated { FileShelf.shared.add([url]) } }
            }
        }
        return true
    }

    /// True while the system drag pasteboard carries files (a Finder drag is in progress).
    static func dragCarriesFiles() -> Bool {
        let pb = NSPasteboard(name: .drag)
        return pb.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
    }
}
