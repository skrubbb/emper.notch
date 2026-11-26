import SwiftUI

@MainActor
final class ClipboardModule: ObservableObject, IslandModule {
    @Published var copiedID: UUID?
    private var resetWork: DispatchWorkItem?

    func makeView() -> AnyView { AnyView(ClipboardView(module: self)) }
    func makeCompactView() -> AnyView? { AnyView(ClipboardCompactView(module: self)) }

    func flash(_ id: UUID) {
        copiedID = id
        resetWork?.cancel()
        let w = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.copiedID = nil } }
        resetWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: w)
    }
}

struct ClipboardView: View {
    @ObservedObject var module: ClipboardModule
    @ObservedObject var history = ClipboardHistory.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Clipboard").font(.system(size: 13, weight: .semibold))
                Spacer()
                if !history.items.isEmpty {
                    Button("Clear") { history.clear() }
                        .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.55))
                }
            }
            if history.items.isEmpty {
                Text("Copy some text and it shows up here.")
                    .font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.45))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 5) {
                        ForEach(history.items) { item in row(item) }
                    }
                }
            }
        }
        .foregroundStyle(Color.primary)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: history.items)
    }

    private func row(_ item: ClipboardHistory.Item) -> some View {
        Button {
            history.copy(item)
            module.flash(item.id)
        } label: {
            HStack(spacing: 8) {
                Text(item.text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces))
                    .font(.system(size: 12)).lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: module.copiedID == item.id ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 10)).foregroundStyle(Color.primary.opacity(0.5))
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.08)))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
    }
}

/// Side placeholder: the three newest items; click copies.
struct ClipboardCompactView: View {
    @ObservedObject var module: ClipboardModule
    @ObservedObject var history = ClipboardHistory.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Clipboard", systemImage: "doc.on.clipboard").font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.55))
            if history.items.isEmpty {
                Text("Copy text to see it here").font(.system(size: 9)).foregroundStyle(Color.primary.opacity(0.45))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ForEach(history.items.prefix(3)) { item in
                    Button {
                        history.copy(item)
                        module.flash(item.id)
                    } label: {
                        HStack(spacing: 3) {
                            Text(item.text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces))
                                .font(.system(size: 10)).lineLimit(1)
                            Spacer(minLength: 0)
                            if module.copiedID == item.id { Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)) }
                        }
                        .padding(.horizontal, 6).frame(height: 22)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.08)))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressScaleStyle())
                    .help(item.text)
                }
                Spacer(minLength: 0)
            }
        }
        .foregroundStyle(Color.primary)
    }
}
