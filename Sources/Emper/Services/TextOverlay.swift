import AppKit
import SwiftUI

/// Round 28: typing into Quick Note and Reminder. The Emper itself never becomes key (re-ordering a key
/// Emper blinked), so a click on a text box lays a transparent, key-capable editor exactly over that box.
/// The editor takes the keyboard (IME, selection, copy/paste and undo all work) and is ordered out when
/// the Emper closes, another part of the Emper is clicked, Escape is pressed or another app is clicked.
/// The calculator keeps the keyboard by default: a text box needs a click first.
@MainActor
final class TextOverlay: NSObject, ObservableObject, NSWindowDelegate, NSTextViewDelegate {
    static let shared = TextOverlay()

    /// Box being edited (its `OverlayTextBox.id`); the box hides its own text meanwhile.
    @Published private(set) var activeID: String?

    private let panel: OverlayPanel
    private let scroll = NSScrollView()
    private let text = OverlayTextView()
    private var onChange: (String) -> Void = { _ in }
    private var onReturn: (() -> Void)?
    private var multiline = true
    /// Round 29: cleans what is typed (time boxes keep at most two digits).
    private var filter: ((String) -> String)?
    /// Round 29: a box asked to take over (time: hour → minute). Its `OverlayTextBox` starts editing.
    @Published private(set) var request: String?
    /// Island panel the box lives in (closing that Emper ends editing).
    private(set) weak var host: NSWindow?

    private override init() {
        panel = OverlayPanel(contentRect: CGRect(x: 0, y: 0, width: 10, height: 10),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        super.init()
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 4)   // just above the Emper
        panel.delegate = self

        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.borderType = .noBorder
        text.drawsBackground = false
        text.isRichText = false
        text.importsGraphics = false
        text.allowsUndo = true
        text.isAutomaticQuoteSubstitutionEnabled = false
        text.isAutomaticDashSubstitutionEnabled = false
        text.textContainerInset = .zero
        text.textContainer?.lineFragmentPadding = 0
        text.textContainer?.widthTracksTextView = true
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.delegate = self
        text.onEscape = { [weak self] in self?.end() }
        scroll.documentView = text
        panel.contentView = scroll
    }

    /// Start editing in `rect` (screen coordinates, AppKit origin bottom-left).
    func begin(id: String, rect: CGRect, host: NSWindow?, value: String, font: NSFont, multiline: Bool,
               appearance: NSAppearance?, onChange: @escaping (String) -> Void, onReturn: (() -> Void)? = nil,
               filter: ((String) -> String)? = nil, selectAll: Bool = false, alignment: NSTextAlignment = .natural) {
        if activeID != nil, activeID != id { finish() }
        self.host = host
        self.onChange = onChange
        self.onReturn = onReturn
        self.multiline = multiline
        self.filter = filter
        if request == id { request = nil }
        text.alignment = alignment
        panel.appearance = appearance
        text.font = font
        text.textColor = .labelColor
        text.insertionPointColor = .controlAccentColor
        text.typingAttributes = [.font: font, .foregroundColor: NSColor.labelColor]
        if text.string != value { text.string = value }
        move(to: rect)
        // The calculator's invisible key catcher gives the keyboard up while a box is edited.
        TimeEntry.shared.end()
        KeyCatcher.shared.releaseAll()
        panel.orderFrontRegardless()
        panel.makeKey()
        panel.makeFirstResponder(text)
        let len = (text.string as NSString).length
        text.setSelectedRange(selectAll ? NSRange(location: 0, length: len) : NSRange(location: len, length: 0))
        text.scrollRangeToVisible(text.selectedRange())
        if activeID != id { activeID = id }
    }

    /// Follow the box when the Emper lays it out again.
    func move(to rect: CGRect) {
        guard rect.width > 4, rect.height > 4 else { return }
        if panel.frame != rect { panel.setFrame(rect.integral, display: true) }
        text.frame.size.width = rect.width
        text.minSize = CGSize(width: rect.width, height: rect.height)
        text.maxSize = CGSize(width: rect.width, height: .greatestFiniteMagnitude)
    }

    /// Stop editing (keeps what was typed). `host`: only if editing in that window.
    func end(in host: NSWindow? = nil) {
        guard activeID != nil else { return }
        if let host, self.host !== host { return }
        finish()
    }

    private func finish() {
        // Cleared first: a box reacting to its final value (time: hour → minute) sees editing has ended.
        activeID = nil
        onChange(text.string)
        if panel.isVisible { panel.orderOut(nil) }   // gives the keyboard back to the app underneath
    }

    func textDidChange(_ notification: Notification) {
        if let filter {
            let f = filter(text.string)
            if f != text.string { text.string = f }
        }
        onChange(text.string)
    }

    /// Ends the current box and starts editing box `id` (on the next pass, after this key is handled).
    func focus(_ id: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.finish()
            self.request = id
        }
    }

    func textView(_ textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        if sel == #selector(NSResponder.insertNewline(_:)), !multiline {
            onReturn?()
            end()
            return true
        }
        if sel == #selector(NSResponder.cancelOperation(_:)) { end(); return true }
        return false
    }

    /// A click in another app (or anywhere outside the box) ends editing.
    func windowDidResignKey(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.panel.isKeyWindow else { return }
            self.end()
        }
    }
}

private final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

private final class OverlayTextView: NSTextView {
    var onEscape: () -> Void = {}
    override func cancelOperation(_ sender: Any?) { onEscape() }
}

/// Text box drawn in the Emper. Click = edit it through `TextOverlay`; meanwhile the box hides its own text
/// so only the live editor shows (same font and origin, so nothing jumps).
struct OverlayTextBox: View {
    let id: String
    @Binding var text: String
    var placeholder = ""
    var fontSize: CGFloat = 12
    var multiline = true
    var onReturn: (() -> Void)?
    /// Round 29: time boxes: digits only, whole value selected on click, centred.
    var filter: ((String) -> String)?
    var selectAll = false
    var centered = false
    @ObservedObject private var overlay = TextOverlay.shared
    @StateObject private var anchor = ScreenAnchor()
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let editing = overlay.activeID == id
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder).foregroundStyle(Color.primary.opacity(0.35))
            }
            Text(text).foregroundStyle(Color.primary).opacity(editing ? 0 : 1)
        }
        .font(.system(size: fontSize))
        .lineLimit(multiline ? nil : 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: centered ? .top : .topLeading)
        .clipped()
        .background(ScreenAnchorView(anchor: anchor) { rect in
            if overlay.activeID == id { TextOverlay.shared.move(to: rect) }
        })
        .contentShape(Rectangle())
        .onTapGesture { begin() }
        .onChange(of: overlay.request) { _, r in if r == id { begin() } }
        .onDisappear { if TextOverlay.shared.activeID == id { TextOverlay.shared.end() } }
        .help(editing ? "" : "Click to type")
    }

    private func begin() {
        guard let v = anchor.view, let w = v.window else { return }
        let rect = w.convertToScreen(v.convert(v.bounds, to: nil))
        let binding = $text
        TextOverlay.shared.begin(id: id, rect: rect, host: w, value: text,
                                 font: .systemFont(ofSize: fontSize), multiline: multiline,
                                 appearance: w.effectiveAppearance,
                                 onChange: { s in if binding.wrappedValue != s { binding.wrappedValue = s } },
                                 onReturn: onReturn, filter: filter, selectAll: selectAll,
                                 alignment: centered ? .center : .natural)
    }
}

final class ScreenAnchor: ObservableObject {
    weak var view: NSView?
}

/// Reports the box's screen rect whenever it is laid out or its window moves.
private struct ScreenAnchorView: NSViewRepresentable {
    let anchor: ScreenAnchor
    let moved: (CGRect) -> Void

    func makeNSView(context: Context) -> AnchorNSView {
        let v = AnchorNSView()
        anchor.view = v
        v.moved = moved
        return v
    }

    func updateNSView(_ v: AnchorNSView, context: Context) {
        anchor.view = v
        v.moved = moved
        v.report()
    }
}

final class AnchorNSView: NSView {
    var moved: (CGRect) -> Void = { _ in }
    private var observer: NSObjectProtocol?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        guard let w = window else { return }
        observer = NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: w, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.report() }
        }
    }

    override func layout() {
        super.layout()
        report()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        report()
    }

    func report() {
        guard let w = window else { return }
        moved(w.convertToScreen(convert(bounds, to: nil)))
    }

    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
}
