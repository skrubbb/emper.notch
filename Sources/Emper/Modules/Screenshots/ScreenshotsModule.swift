import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class ScreenshotsModule: IslandModule {
    func makeView() -> AnyView { AnyView(ScreenshotsView()) }
    func makeCompactView() -> AnyView? { AnyView(ScreenshotsCompactView()) }
}

/// Recent screenshots: click opens, drag out to any app, right-click for more.
struct ScreenshotsView: View {
    @ObservedObject var shelf = ScreenshotShelf.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Screenshots").font(.system(size: 13, weight: .semibold))
                Text(shelf.folder.lastPathComponent).font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.45))
                Spacer()
                Button { shelf.openFolder() } label: {
                    Image(systemName: "folder").font(.system(size: 11))
                }
                .buttonStyle(PressScaleStyle()).foregroundStyle(Color.primary.opacity(0.6))
                .help("Open folder")
            }
            if shelf.needsAccess || shelf.denied {
                ScreenshotAccessPrompt(shelf: shelf, compact: false)
            } else if shelf.items.isEmpty {
                Text("Take a screenshot and it shows up here.")
                    .font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.45))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(shelf.items) { item in tile(item) }
                    }
                }
            }
        }
        .foregroundStyle(Color.primary)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: shelf.items)
    }

    private func tile(_ item: ScreenshotShelf.Item) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.08))
                .overlay {
                    if let img = shelf.thumbnails[item.url] {
                        Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: "photo").foregroundStyle(Color.primary.opacity(0.4))
                    }
                }
            .frame(width: 104, height: 66)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            Text(item.date, format: .dateTime.hour().minute())
                .font(.system(size: 10).monospacedDigit()).foregroundStyle(Color.primary.opacity(0.5))
        }
        .contentShape(Rectangle())
        .onTapGesture { shelf.open(item) }
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
        .contextMenu {
            Button("Open") { shelf.open(item) }
            Button("Copy") { shelf.copy(item) }
            Button("Show in Finder") { shelf.reveal(item) }
        }
    }
}

/// Side placeholder: a grid of the newest screenshots. 1× shows 2×2, 1.5× 3×2, 2× 4×2 (the card's
/// width decides). Click opens, drag out, right-click for more.
struct ScreenshotsCompactView: View {
    @ObservedObject var shelf = ScreenshotShelf.shared

    var body: some View {
        GeometryReader { g in
            let cols = g.size.width < 150 ? 2 : g.size.width < 230 ? 3 : 4
            let gap: CGFloat = 4
            let w = (g.size.width - gap * CGFloat(cols - 1)) / CGFloat(cols)
            let h = (g.size.height - gap) / 2
            if shelf.needsAccess || shelf.denied {
                ScreenshotAccessPrompt(shelf: shelf, compact: true)
            } else if shelf.items.isEmpty {
                VStack(spacing: 4) {
                    Image(systemName: "camera.viewfinder").font(.system(size: 18, weight: .medium))
                    Text("No screenshots yet").font(.system(size: 9)).multilineTextAlignment(.center)
                }
                .foregroundStyle(Color.primary.opacity(0.8))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let items = Array(shelf.items.prefix(cols * 2))
                VStack(spacing: gap) {
                    ForEach(0..<2, id: \.self) { r in
                        HStack(spacing: gap) {
                            ForEach(0..<cols, id: \.self) { k in
                                let i = r * cols + k
                                if i < items.count { thumb(items[i]).frame(width: w, height: h) }
                                else { Color.clear.frame(width: w, height: h) }
                            }
                        }
                    }
                }
            }
        }
    }

    private func thumb(_ item: ScreenshotShelf.Item) -> some View {
        // A fixed frame with the image as overlay: aspect-fill can never widen the card.
        RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.08))
            .overlay {
                if let img = shelf.thumbnails[item.url] {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "photo").font(.system(size: 10)).foregroundStyle(Color.primary.opacity(0.4))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            .onTapGesture { shelf.open(item) }
            .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
            .contextMenu {
                Button("Open") { shelf.open(item) }
                Button("Copy") { shelf.copy(item) }
                Button("Show in Finder") { shelf.reveal(item) }
            }
            .help("Click to open · drag out")
    }
}

/// Shown instead of the shelf until the person allows the screenshot folder (Desktop by default), so
/// macOS asks only when they choose to, never at launch.
struct ScreenshotAccessPrompt: View {
    @ObservedObject var shelf: ScreenshotShelf
    let compact: Bool

    var body: some View {
        let name = shelf.folder.lastPathComponent
        VStack(spacing: compact ? 4 : 8) {
            Image(systemName: "lock.shield").font(.system(size: compact ? 16 : 20, weight: .medium))
            Text(shelf.denied ? "macOS blocked the \(name) folder" : "Needs access to the \(name) folder")
                .font(.system(size: compact ? 9 : 12)).multilineTextAlignment(.center)
            Button(shelf.denied ? "Open Privacy Settings" : "Allow Access") {
                if shelf.denied { shelf.openPrivacySettings() } else { shelf.allowAccess() }
            }
            .buttonStyle(.plain)
            .font(.system(size: compact ? 9 : 11, weight: .semibold))
            .padding(.horizontal, compact ? 8 : 12).padding(.vertical, compact ? 3 : 5)
            .background(Capsule().fill(Color.primary.opacity(0.14)))
        }
        .foregroundStyle(Color.primary.opacity(0.85))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
