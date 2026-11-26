import SwiftUI
import UniformTypeIdentifiers
import EmperCore

/// File Shelf: drop files on the island, drag them out later. Dragging files over the idle island
/// opens it here (when this island has the shelf).
@MainActor
final class ShelfModule: IslandModule {
    func makeView() -> AnyView { AnyView(ShelfView(compact: false)) }
    func makeCompactView() -> AnyView? { AnyView(ShelfView(compact: true)) }
}

struct ShelfView: View {
    @ObservedObject var shelf = FileShelf.shared
    let compact: Bool
    @StateObject private var drop = ShelfDropState()

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12)
        Group {
            if shelf.items.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "tray.and.arrow.down").font(.system(size: compact ? 18 : 22, weight: .medium))
                    Text(compact ? "Drop files" : "Drop files here to keep them for later")
                        .font(.system(size: 10, weight: .medium)).multilineTextAlignment(.center)
                }
                .foregroundStyle(Color.primary.opacity(0.5))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if compact {
                VStack(spacing: 4) {
                    ZStack {
                        ForEach(Array(shelf.items.suffix(3).enumerated()), id: \.element) { i, u in
                            FileIcon(url: u, size: 40).rotationEffect(.degrees(Double(i - 1) * 8))
                        }
                    }
                    .frame(height: 50)
                    .onDrag { provider(for: shelf.items) }
                    Text("\(shelf.items.count) file\(shelf.items.count == 1 ? "" : "s")")
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(Color.primary.opacity(0.7))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .help("Drag out the newest file")
            } else {
                HStack(spacing: 0) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(shelf.items, id: \.self) { u in tile(u) }
                        }
                        .padding(.horizontal, 4)
                    }
                    Button { shelf.clear() } label: {
                        Image(systemName: "trash").font(.system(size: 11, weight: .semibold))
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(Color.primary.opacity(0.1)))
                            .contentShape(Circle())
                    }
                    .buttonStyle(PressScaleStyle())
                    .help("Clear the shelf")
                }
            }
        }
        .background(shape.fill(Color.primary.opacity(drop.targeted ? 0.12 : 0)))
        .overlay(shape.strokeBorder(Color.primary.opacity(drop.targeted ? 0.5 : 0), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        .onDrop(of: [UTType.fileURL], isTargeted: Binding(get: { drop.targeted }, set: { drop.targeted = $0 })) {
            FileShelf.shared.accept($0)
        }
        .foregroundStyle(Color.primary)
    }

    private func tile(_ u: URL) -> some View {
        VStack(spacing: 4) {
            FileIcon(url: u, size: 44)
            Text(u.lastPathComponent).font(.system(size: 9, weight: .medium)).lineLimit(1).truncationMode(.middle)
                .frame(width: 64)
        }
        // Room for the remove badge inside the tile: the scroll view clips anything outside it.
        .padding(.top, 6).padding(.horizontal, 4)
        .overlay(alignment: .topTrailing) {
            Button { shelf.remove(u) } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 13))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color.islandFill, Color.primary.opacity(0.75))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .offset(x: -6)
            .help("Remove from shelf")
        }
        .onDrag { NSItemProvider(contentsOf: u) ?? NSItemProvider() }
        .help(u.path)
    }

    private func provider(for items: [URL]) -> NSItemProvider {
        items.last.flatMap { NSItemProvider(contentsOf: $0) } ?? NSItemProvider()
    }
}

final class ShelfDropState: ObservableObject {
    @Published var targeted = false
}

struct FileIcon: View {
    let url: URL
    let size: CGFloat

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
            .resizable().interpolation(.high)
            .frame(width: size, height: size)
    }
}
