import SwiftUI
import Combine
import EmperCore

/// Round 28: one plain note. No list, no Apply: what is typed is saved to
/// ~/Library/Application Support/Emper/quick-note.txt (half a second after the last key) and stays
/// across restarts until the person clears it with the trash button (two clicks).
@MainActor
final class QuickNote: ObservableObject {
    static let shared = QuickNote()
    @Published var text: String { didSet { if text != oldValue { scheduleSave() } } }
    private var save: DispatchWorkItem?

    static var url: URL {
        // Self-test / render runs never touch the person's note.
        let a = CommandLine.arguments
        if a.contains("--selftest") || a.contains("--render") || a.contains("--bench") {
            return FileManager.default.temporaryDirectory.appendingPathComponent("emper-test-quick-note.txt")
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Emper/quick-note.txt")
    }

    private init() {
        text = (try? String(contentsOf: Self.url, encoding: .utf8)) ?? ""
    }

    private func scheduleSave() {
        save?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.flush() }
        save = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: w)
    }

    /// Written at once (also on quit), atomically, so a crash never leaves half a note.
    func flush() {
        save?.cancel(); save = nil
        let u = Self.url
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        if text.isEmpty { try? FileManager.default.removeItem(at: u) }
        else {
            try? text.write(to: u, atomically: true, encoding: .utf8)
            // Owner-only (0600): a note can hold private text.
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: u.path)
        }
    }

    func clear() {
        TextOverlay.shared.end()
        text = ""
        flush()
    }
}

@MainActor
final class QuickNoteModule: IslandModule {
    func makeView() -> AnyView { AnyView(QuickNoteView(compact: false)) }
    func makeCompactView() -> AnyView? { AnyView(QuickNoteView(compact: true)) }
}

/// Two clicks to clear: the first turns the button red ("Clear?") for 3 s.
final class ArmFlag: ObservableObject {
    @Published var armed = false
    /// Every Quick Note box shows the same note; each needs its own id for the editor.
    let boxID = "note-" + UUID().uuidString
    var work: DispatchWorkItem?
}

struct QuickNoteView: View {
    let compact: Bool
    @ObservedObject private var note = QuickNote.shared
    @StateObject private var arm = ArmFlag()

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        VStack(alignment: .leading, spacing: compact ? 4 : 6) {
            HStack(spacing: 6) {
                Image(systemName: "note.text").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.55))
                Text(compact ? "Note" : "Quick Note").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.primary.opacity(0.55))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if !note.text.isEmpty { clearButton }
            }
            .frame(height: 18)
            OverlayTextBox(id: arm.boxID, text: $note.text, placeholder: "Type a note…", fontSize: compact ? 11 : 12)
        }
        // A side placeholder already draws the card and its padding.
        .padding(compact ? 0 : 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(shape.fill(Color.primary.opacity(compact ? 0 : 0.06)))
    }

    private var clearButton: some View {
        Button {
            if arm.armed {
                arm.work?.cancel(); arm.armed = false
                note.clear()
            } else {
                arm.armed = true
                let a = arm
                let w = DispatchWorkItem { [weak a] in a?.armed = false }
                arm.work = w
                DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: w)
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "trash").font(.system(size: 9, weight: .semibold))
                if arm.armed { Text("Clear?").font(.system(size: 10, weight: .semibold)) }
            }
            .foregroundStyle(arm.armed ? Color.white : Color.primary.opacity(0.6))
            .padding(.horizontal, arm.armed ? 7 : 0)
            .frame(minWidth: 18, minHeight: 18)
            .background(Capsule().fill(arm.armed ? EditPalette.danger : Color.primary.opacity(0.08)))
            .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle())
        .animation(.easeOut(duration: 0.12), value: arm.armed)
        .help(arm.armed ? "Click again to delete the note" : "Delete the note")
    }
}
