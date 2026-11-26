import SwiftUI
import AppKit
import EmperCore

// Round 23: pencil-mode edit cards, resize grips, "+" and the feature picker, from Desmond's spec
// (docs/design/r23/spec.md). Crisp on 1x screens: no hairline or dashed strokes; surfaces are fills,
// any stroke is 2 pt drawn inside the frame, frames on whole points.

enum EditPalette {
    static let accent = Color(nsColor: .systemBlue)
    static let danger = Color(nsColor: .systemRed)
    static func card(_ dark: Bool) -> Color { Color.primary.opacity(dark ? 0.07 : 0.06) }
    static func cardHover(_ dark: Bool) -> Color { Color.primary.opacity(dark ? 0.11 : 0.10) }
    static let hoverStroke = Color.primary.opacity(0.3)
    static let secondary = Color.primary.opacity(0.55)
}

/// A placeholder in edit mode: filled card with the feature's icon and name. Click = feature picker
/// (inside the island), drag = swap places. A plain view, not a system menu, so the drag still works.
struct EditSlot: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var edit: HomeEditState
    let index: Int
    let isMain: Bool
    let dragging: Bool
    var dropTarget = false
    @StateObject private var hover = HoverFlag()
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        let slots = model.config.homeSlots
        let id = slots.indices.contains(index) ? slots[index] : ""
        let d = ModuleRegistry.descriptor(id)
        let previewing = edit.resizeIndex == index && d != nil
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        let v = model.config.edge.isVertical
        let ink = d == nil ? EditPalette.secondary : Color.primary
        // Round 26: side slots in a column are as tall as the main one, so they stack like the rest.
        let layout = AnyLayout(VStackLayout(spacing: 4))
        let fill: Color = dropTarget ? EditPalette.accent.opacity(0.28)
            : (dragging || hover.on) ? EditPalette.cardHover(dark) : EditPalette.card(dark)
        let stroke: Color? = (dragging || dropTarget) ? EditPalette.accent : hover.on ? EditPalette.hoverStroke : nil
        layout {
            Image(systemName: d?.symbol ?? "circle.slash").font(.system(size: 20, weight: .medium))
                .foregroundStyle(ink)
                .frame(height: 24)
            Text(d?.name ?? "Empty").font(.system(size: 12, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                .foregroundStyle(ink)
            if isMain {
                Text("Main").font(.system(size: 10, weight: .medium)).foregroundStyle(EditPalette.secondary)
            }
            Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(EditPalette.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(previewing ? 0 : 1)
        .background(shape.fill(fill))
        .overlay {
            // Round 25: while resizing, the real feature layout fades in at the new size.
            if previewing {
                SideCard(model: model, id: id).allowsHitTesting(false).transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: previewing)
        .overlay { if let stroke { shape.strokeBorder(stroke, lineWidth: 2) } }
        .contentShape(shape)
        .onHover { hover.on = $0 }
        .onTapGesture { edit.picking = index }
        .overlay {
            // Side placeholders: grips on both ends show they can be widened (1x, 1.5x, 2x).
            if !isMain {
                if v {
                    VStack(spacing: 0) {
                        ResizeHandle(model: model, edit: edit, index: index, growsLeft: true)
                        Spacer(minLength: 0)
                        ResizeHandle(model: model, edit: edit, index: index, growsLeft: false)
                    }
                } else {
                    HStack(spacing: 0) {
                        ResizeHandle(model: model, edit: edit, index: index, growsLeft: true)
                        Spacer(minLength: 0)
                        ResizeHandle(model: model, edit: edit, index: index, growsLeft: false)
                    }
                }
            }
        }
        .overlay(alignment: .top) {
            // Round 24: pinned step while resizing.
            if edit.resizeIndex == index, let p = edit.pinned {
                Text(ScaleLabel.text(p))
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 8)
                    .frame(height: 20)
                    .background(Capsule().fill(EditPalette.accent))
                    .padding(.top, 6)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .overlay {
            if edit.resizeIndex == index { shape.strokeBorder(EditPalette.accent.opacity(edit.pinned == nil ? 0.5 : 1), lineWidth: 2) }
        }
        .animation(.easeOut(duration: 0.1), value: edit.pinned)
        .overlay(alignment: .topTrailing) {
            // Round 28: every side placeholder can be removed right here (sides are free, so any one can go).
            if !isMain, slots.count > 1, edit.resizeIndex != index {
                SlotRemoveButton {
                    let a = HomeLayout.removing(slots, main: model.config.homeMainIndex, at: index)
                    if edit.picking == index { edit.picking = nil }
                    model.onHomeSlots(a.slots, a.main)
                }
                .padding(5)
            }
        }
        .scaleEffect(dragging ? 1.03 : 1)
        .animation(.easeOut(duration: 0.12), value: hover.on)
        .help("Click to choose a feature · drag to move")
    }
}

/// Round 28: small "×" in a side placeholder's corner (pencil mode): removes that placeholder.
struct SlotRemoveButton: View {
    let action: () -> Void
    @StateObject private var hover = HoverFlag()

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark").resizable().scaledToFit().fontWeight(.bold)
                .frame(width: 8, height: 8)
                .foregroundStyle(Color.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(hover.on ? EditPalette.danger : Color.primary.opacity(0.45)))
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle())
        .onHover { hover.on = $0 }
        .animation(.easeOut(duration: 0.12), value: hover.on)
        .help("Remove this placeholder")
    }
}

enum ScaleLabel {
    static func text(_ s: CGFloat) -> String {
        let t = String(format: "%.2f", Double(s))
        var r = t
        while r.hasSuffix("0") { r.removeLast() }
        if r.hasSuffix(".") { r.removeLast() }
        return r + "×"
    }
}

final class ResizeDrag: ObservableObject {
    var start: CGFloat?
    var origin: CGPoint = .zero
    var last: CGFloat = 1
}

/// Grip on a side placeholder's end: drag along the row to resize it freely between 1× and 2×; it pins
/// to 1.25×, 1.5×, 1.75× and 2× when close. Round 24: measured from the pointer on the screen. The
/// gesture's own translation is relative to the Emper's window, which moves as the Emper grows (that loop
/// was the vibrating). The Emper stays centred, so its grip moves half as far as the width changes: the
/// width follows twice the pointer's travel to keep the grip under the pointer. Shown live, saved on release.
struct ResizeHandle: View {
    @ObservedObject var model: IslandModel
    let edit: HomeEditState
    let index: Int
    let growsLeft: Bool
    @StateObject private var drag = ResizeDrag()
    @StateObject private var hover = HoverFlag()

    var body: some View {
        let v = model.config.edge.isVertical
        // 4 x 24 pill, 5 pt in from the card edge, 20 x 44 hit area (spec 03).
        Capsule().fill(Color.primary.opacity(hover.on ? 0.6 : 0.32))
            .frame(width: v ? 24 : 4, height: v ? 4 : 24)
            .padding(growsLeft ? (v ? .top : .leading) : (v ? .bottom : .trailing), 5)
            .frame(width: v ? 44 : 20, height: v ? 20 : 44, alignment: growsLeft ? (v ? .top : .leading) : (v ? .bottom : .trailing))
            .contentShape(Rectangle())
            .onHover { hover.on = $0 }
            .highPriorityGesture(DragGesture(minimumDistance: 2)
                .onChanged { _ in
                    let c = model.config
                    let mouse = NSEvent.mouseLocation
                    let cur = c.homeSlotScales.indices.contains(index) ? c.homeSlotScales[index] : 1
                    if drag.start == nil {
                        drag.start = cur; drag.origin = mouse; drag.last = cur
                        edit.resizing = true; edit.resizeIndex = index
                    }
                    let base = HomeLayout.sideBase(c)
                    // Screen y grows upward; a column grows downward from its bottom grip.
                    let t = c.edge.isVertical ? drag.origin.y - mouse.y : mouse.x - drag.origin.x
                    let d = growsLeft ? -t : t
                    var (want, pin) = HomeLayout.snapped((drag.start ?? cur) + 2 * d / (base + HomeLayout.gap(c)), max: c.homeMaxScale)
                    // Round 27: stop where a "+" button would leave the screen (or reach the menu bar).
                    let room = IslandGeometry.homeRoom(c, clearance: model.clearance)
                    if room.isFinite {
                        let top = max(cur + room / (base + HomeLayout.gap(c)), 1)
                        if want > top { want = (top * 100).rounded(.down) / 100; pin = nil }
                    }
                    if pin != edit.pinned {
                        if pin != nil { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
                        edit.pinned = pin
                    }
                    if want != drag.last {
                        drag.last = want
                        model.onPreviewConfig { $0.setHomeSize(index, Double(want)) }
                    }
                }
                .onEnded { _ in
                    let final = drag.last
                    drag.start = nil
                    edit.resizing = false; edit.resizeIndex = nil; edit.pinned = nil
                    model.onEditConfig { $0.setHomeSize(index, Double(final)) }
                })
            .help(model.config.edge.isVertical ? "Drag to resize · pins at 1.25× and 1.5×" : "Drag to resize · pins at 1.25×, 1.5×, 1.75× and 2×")
    }
}

/// Round "+" floating just outside the Emper: adds a placeholder on that end. Solid 28-pt disc.
struct AddSlotButton: View {
    @ObservedObject var model: IslandModel
    let left: Bool
    @StateObject private var hover = HoverFlag()
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let slots = model.config.homeSlots
        // Round 27: also no room when one more 1× placeholder would push a "+" past the screen side.
        let c = model.config
        let room = slots.count < HomeLayout.maxSlots
            && IslandGeometry.homeRoom(c, clearance: model.clearance) >= HomeLayout.sideBase(c) + HomeLayout.gap(c)
        let dark = scheme == .dark
        Button {
            let a = HomeLayout.adding(slots, main: c.homeMainIndex, left: left)
            model.onHomeSlots(a.slots, a.main)
        } label: {
            CrossGlyph(size: 14, line: 2.25)
                .foregroundStyle(dark ? Color.black : Color.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(dark ? Color.white : Color(white: 0.11)))
                .scaleEffect(hover.on && room ? 30.0 / 28.0 : 1)
                .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle())
        .onHover { hover.on = $0 }
        .animation(.easeOut(duration: 0.12), value: hover.on)
        .disabled(!room)
        .opacity(room ? 1 : 0.3)
        .help(room ? "Add a placeholder \(c.edge.isVertical ? (left ? "on top" : "at the bottom") : (left ? "on the left" : "on the right"))"
              : slots.count < HomeLayout.maxSlots ? "No more room on this screen" : "Up to \(HomeLayout.maxSlots) placeholders")
    }
}

/// Feature picker: a tray the size of the placeholder row, tied to the clicked slot by a mini-map
/// (round 24: the accent marker on the tray edge is gone, the mini-map says it). Tiles: one row of 8 (wide), 4 x 2 (narrow) or
/// one column of full-width rows (left/right Emper, round 28).
struct FeaturePicker: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var edit: HomeEditState
    let index: Int
    @Environment(\.colorScheme) private var scheme

    enum Kind { case wide, narrow, vertical }

    var body: some View {
        let c = model.config
        let slots = c.homeSlots
        let current = slots.indices.contains(index) ? slots[index] : ""
        let m = c.homeMainIndex
        let frames = HomeLayout.frames(c)
        let total = frames.last.map { $0.x + $0.width } ?? 0
        let kind: Kind = c.edge.isVertical ? .vertical : (total >= 620 ? .wide : .narrow)
        let options = IslandConfig.features.filter { ModuleRegistry.descriptor($0) != nil } + [""]
        let shape = RoundedRectangle(cornerRadius: kind == .narrow ? 14 : 16, style: .continuous)
        let dark = scheme == .dark
        let pad: CGFloat = 8
        VStack(alignment: .leading, spacing: kind == .narrow ? 6 : 10) {
            header(slots: slots, main: m, current: current, kind: kind)
            tiles(options, current: current, kind: kind)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, pad)
        .padding(.top, kind == .narrow ? 6 : 10)
        .padding(.bottom, kind == .narrow ? 8 : 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(shape.fill(Color.islandFill))
        .background(shape.fill(Color.primary.opacity(dark ? 0.055 : 0.05)))
        .clipShape(shape)
        // Round 24: where the tray is in its window, so a click anywhere else closes it.
        .background(GeometryReader { g in
            Color.clear
                .onAppear { edit.trayFrame = g.frame(in: .global) }
                .onChange(of: g.frame(in: .global)) { _, f in edit.trayFrame = f }
        })
    }

    private func slotName(_ slots: [String], main m: Int) -> String {
        if index == m { return "Main" }
        let v = model.config.edge.isVertical
        let before = index < m
        let far = abs(index - m) > 1
        let side = v ? (before ? "Above" : "Below") : (before ? "Left side" : "Right side")
        return far ? (v ? (before ? "Top" : "Bottom") : (before ? "Far left" : "Far right")) : side
    }

    private func header(slots: [String], main m: Int, current: String, kind: Kind) -> some View {
        let small = kind == .narrow
        let feature = ModuleRegistry.descriptor(current)?.name ?? "Empty"
        let h: CGFloat = small ? 18 : 24
        return HStack(spacing: 8) {
            miniMap(count: slots.count, main: m, small: small)
            (Text(slotName(slots, main: m)).font(.system(size: small ? 11 : 12, weight: .semibold))
             + Text(" · \(feature)").font(.system(size: small ? 11 : 12)).foregroundColor(EditPalette.secondary))
                .lineLimit(1)
            Spacer(minLength: 4)
            if index != m, slots.count > 1 {
                RemovePill(iconOnly: kind == .vertical, height: h) {
                    let a = HomeLayout.removing(slots, main: m, at: index)
                    model.onHomeSlots(a.slots, a.main); edit.picking = nil
                }
            }
            CloseDisc(size: h) { edit.picking = nil }
        }
        .frame(height: h)
        .padding(.leading, 6)
        .padding(.trailing, 2)
    }

    private func miniMap(count: Int, main m: Int, small: Bool) -> some View {
        let unit: CGFloat = small ? 8 : 14
        return HStack(spacing: 3) {
            ForEach(0..<count, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(i == index ? EditPalette.accent : Color.primary.opacity(0.22))
                    .frame(width: i == m ? unit * 2 : unit, height: 10)
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder private func tiles(_ options: [String], current: String, kind: Kind) -> some View {
        switch kind {
        case .wide:
            HStack(spacing: 6) {
                ForEach(options, id: \.self) { f in tile(f, current: current, kind: kind).frame(height: 56) }
            }
        case .narrow:
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 5), spacing: 4) {
                ForEach(options, id: \.self) { f in tile(f, current: current, kind: kind).frame(height: 34) }
            }
        case .vertical:
            // Round 28: left/right Emper: one full-width row per feature, same height; scrolls on a short column.
            HintedScroll {
                VStack(spacing: 4) {
                    ForEach(options, id: \.self) { f in tile(f, current: current, kind: kind).frame(height: 36) }
                }
                .padding(.bottom, 6)
            }
        }
    }

    private func tile(_ f: String, current: String, kind: Kind) -> some View {
        let d = ModuleRegistry.descriptor(f)
        let name = d?.name ?? "Empty"
        let short = kind == .narrow ? (["System Stats": "Stats", "Screenshots": "Shots", "Calculator": "Calc", "File Shelf": "Shelf", "Quick Note": "Note", "Reminder": "Remind"][name] ?? name) : name
        return PickerTile(symbol: d?.symbol ?? "circle.slash", title: short, selected: f == current, stacked: kind == .wide,
                          leading: kind == .vertical) {
            pick(f)
        }
        .help(name)
    }

    private func pick(_ f: String) {
        let i = index
        model.onEditConfig { c in c.assignHome(i, f) }
        edit.picking = nil
    }
}

/// Tile in the picker. Rest / hover / pressed are fills; selected adds a 2-pt inside accent stroke and a
/// check badge (not colour only).
struct PickerTile: View {
    let symbol: String
    let title: String
    let selected: Bool
    let stacked: Bool
    var leading = false
    let action: () -> Void
    @StateObject private var hover = HoverFlag()

    var body: some View {
        Button(action: action) {
            let layout = stacked ? AnyLayout(VStackLayout(spacing: 6)) : AnyLayout(HStackLayout(spacing: 6))
            layout {
                Image(systemName: symbol).font(.system(size: stacked ? 17 : 13, weight: .medium))
                    .foregroundStyle(selected ? EditPalette.accent : Color.primary)
                    .frame(height: stacked ? 20 : 16)
                Text(title).font(.system(size: 11, weight: selected ? .semibold : .medium))
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .padding(.horizontal, leading ? 12 : 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: leading ? .leading : .center)
        }
        .buttonStyle(TileStyle(selected: selected, hover: hover.on, radius: stacked ? 10 : 8))
        .overlay(alignment: .topTrailing) {
            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: stacked ? 14 : 10, weight: .semibold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color.white, EditPalette.accent)
                    .padding(stacked ? 3 : 2)
                    .allowsHitTesting(false)
            }
        }
        .onHover { hover.on = $0 }
        .foregroundStyle(Color.primary)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct TileStyle: ButtonStyle {
    let selected: Bool
    let hover: Bool
    let radius: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let fill: Color = selected ? EditPalette.accent.opacity(0.28)
            : Color.primary.opacity(configuration.isPressed ? 0.18 : hover ? 0.15 : 0.10)
        return configuration.label
            .background(shape.fill(fill))
            .overlay { if selected { shape.strokeBorder(EditPalette.accent, lineWidth: 2) } }
            .contentShape(shape)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.1), value: hover)
    }
}

private struct RemovePill: View {
    let iconOnly: Bool
    let height: CGFloat
    let action: () -> Void
    @StateObject private var hover = HoverFlag()

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "trash").font(.system(size: height > 20 ? 11 : 10, weight: .semibold))
                if !iconOnly { Text("Remove").font(.system(size: height > 20 ? 12 : 11, weight: .semibold)) }
            }
            .foregroundStyle(EditPalette.danger)
            .padding(.horizontal, iconOnly ? 0 : 10)
            .frame(width: iconOnly ? 30 : nil, height: height)
            .background(Capsule().fill(EditPalette.danger.opacity(hover.on ? 0.28 : 0.18)))
            .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle())
        .onHover { hover.on = $0 }
        .help("Remove this placeholder")
    }
}

private struct CloseDisc: View {
    let size: CGFloat
    let action: () -> Void
    @StateObject private var hover = HoverFlag()

    var body: some View {
        Button(action: action) {
            CrossGlyph(size: size * 0.42, line: 1.75, rotated: true)
                .foregroundStyle(Color.primary.opacity(hover.on ? 1 : 0.6))
                .frame(width: size, height: size)
                .background(Circle().fill(Color.primary.opacity(hover.on ? 0.17 : 0.12)))
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle())
        .onHover { hover.on = $0 }
        .help("Close")
        .keyboardShortcut(.cancelAction)
    }
}

/// Round 24: closes the picker on a click outside its tray: inside the Emper (local events) or in any other
/// app (global events; mouse clicks need no permission). Installed only while the picker is open.
@MainActor
final class PickerDismissMonitor {
    private var local: Any?
    private var global: Any?

    func start(tray: @escaping () -> CGRect, close: @escaping () -> Void) {
        stop()
        local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { e in
            // SwiftUI's global space is the window's content, top-left origin.
            if let h = e.window?.contentView?.bounds.height {
                let p = CGPoint(x: e.locationInWindow.x, y: h - e.locationInWindow.y)
                if !tray().contains(p) { DispatchQueue.main.async { close() } }
            }
            return e
        }
        global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
            DispatchQueue.main.async { close() }
        }
    }

    func stop() {
        if let l = local { NSEvent.removeMonitor(l) }
        if let g = global { NSEvent.removeMonitor(g) }
        local = nil; global = nil
    }
}
