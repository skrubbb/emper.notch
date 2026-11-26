import SwiftUI
import EmperCore

extension IslandEdge {
    var alignment: Alignment {
        switch self {
        case .top: .top
        case .bottom: .bottom
        case .left: .leading
        case .right: .trailing
        }
    }

    var anchor: UnitPoint {
        switch self {
        case .top: .top
        case .bottom: .bottom
        case .left: .leading
        case .right: .trailing
        }
    }
}

/// Motion tuning in one place.
enum IslandMotion {
    /// Open / tab switch / live: quick with a little overshoot.
    static let expand = Animation.spring(response: 0.3, dampingFraction: 0.74)
    /// Close: critically damped, settles in ~0.35 s (plus the 0.12 s hover-exit delay).
    static let collapse = Animation.spring(response: 0.26, dampingFraction: 1)
    static let contentIn = Animation.easeOut(duration: 0.18).delay(0.04)
    static let contentOut = Animation.easeIn(duration: 0.07)
}

struct IslandRootView: View {
    @ObservedObject var model: IslandModel

    static func gapEdges(_ e: IslandEdge) -> Edge.Set {
        switch e {
        case .top: .top
        case .bottom: .bottom
        case .left: .leading
        case .right: .trailing
        }
    }

    /// Along-edge shift of the island from the panel centre: it stays on its idle centre and slides inwards
    /// only where a screen side (or the menu bar) would cut it.
    static func shift(_ model: IslandModel) -> CGSize {
        guard !model.panelFrame.isNull, !model.config.area.isNull else { return .zero }
        return IslandGeometry.alongShift(size: model.size, config: model.config, panel: model.panelFrame, reach: model.addSlotReach)
    }

    /// Vertical offset of the side pill from the Emper's middle: level with the main slot on Home.
    static func pillY(_ model: IslandModel) -> CGFloat {
        let c = model.config
        guard model.selectedID == ModuleRegistry.homeID, c.homeSlots.count > 1 else { return 0 }
        let ins = IslandGeometry.contentInsets(c, clearance: model.clearance)
        let f = HomeLayout.frames(c)
        let mi = c.homeMainIndex
        guard f.indices.contains(mi) else { return 0 }
        return (ins.top + f[mi].x + f[mi].width / 2).rounded() - model.size.height / 2
    }

    var body: some View {
        let c = model.config
        let addSlots = model.isExpanded && model.editingHome && model.selectedID == ModuleRegistry.homeID
        let v = c.edge.isVertical
        // "+" sits level with the placeholder row, not the middle of the whole Emper (tab bar and notch shift it).
        let ins = IslandGeometry.contentInsets(c, clearance: model.clearance)
        let bar = IslandGeometry.tabBarHeight + IslandGeometry.tabSpacing
        let rowH = max(model.size.height - ins.top - ins.bottom - bar, 0)
        let rowMid = (c.edge == .bottom ? ins.top : ins.top + bar) + rowH / 2
        // Whole-point centre so the 22-pt circle and its glyph land on whole pixels (crisp on 1x screens).
        let addSlotY = rowMid.rounded() - model.size.height / 2
        // Round 27: left/right Emper: "+" sits over the side-slot column (beside the tab column), not the whole Emper.
        let sideMid = ins.leading + IslandGeometry.tabBarHeight + IslandGeometry.tabGap(c) + HomeLayout.verticalSideWidth / 2
        let addSlotX = v ? ((c.edge == .left ? sideMid : model.size.width - (ins.trailing + IslandGeometry.tabBarHeight
            + IslandGeometry.tabGap(c) + HomeLayout.verticalSideWidth / 2)).rounded() - model.size.width / 2) : 0
        IslandSurface(model: model)
            .frame(width: model.size.width, height: model.size.height)
            // Pencil on Home: "+ placeholder" floats on its own just outside each end of the Emper.
            .overlay(alignment: .leading) {
                if addSlots, !v { AddSlotButton(model: model, left: true).offset(x: -30, y: addSlotY).transition(.opacity.combined(with: .scale(scale: 0.6))) }
            }
            .overlay(alignment: .trailing) {
                if addSlots, !v { AddSlotButton(model: model, left: false).offset(x: 30, y: addSlotY).transition(.opacity.combined(with: .scale(scale: 0.6))) }
            }
            // Left/right Emper: the column grows up and down, so "+" floats above and below it.
            .overlay(alignment: .top) {
                if addSlots, v { AddSlotButton(model: model, left: true).offset(x: addSlotX, y: -30).transition(.opacity.combined(with: .scale(scale: 0.6))) }
            }
            .overlay(alignment: .bottom) {
                if addSlots, v { AddSlotButton(model: model, left: false).offset(x: addSlotX, y: 30).transition(.opacity.combined(with: .scale(scale: 0.6))) }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: addSlots)
            // Round 29: left/right Emper: pencil and settings float in a pill beside the Emper, level with the main slot.
            .overlay(alignment: c.edge == .left ? .trailing : .leading) {
                if v, model.isExpanded {
                    SideControlsPill(model: model)
                        .offset(x: c.edge == .left ? IslandGeometry.sidePillRoom : -IslandGeometry.sidePillRoom,
                                y: Self.pillY(model))
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }
            .animation(.easeOut(duration: 0.16), value: model.isExpanded)
            // Floating style: lifted off the edge by the gap (the corner inset is in the panel's position).
            .padding(Self.gapEdges(c.edge), CGFloat(c.edgeGap))
            .offset(Self.shift(model))
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: model.addSlotReach)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: c.edge.alignment)
            .animation(model.isExpanded || model.isLive ? IslandMotion.expand : IslandMotion.collapse, value: model.size)
            .environment(\.islandPointer, model.pointer)
            .environment(\.islandVertical, c.edge.isVertical)
            .overlay(alignment: .topLeading) {
                // Live preview of the idle hover zone while a margin is tuned in Settings.
                if let r = model.hitbox {
                    Rectangle()
                        .fill(Color.green.opacity(0.18))
                        .overlay(Rectangle().strokeBorder(Color.green, style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                        .frame(width: r.width, height: r.height)
                        .offset(x: r.minX, y: r.minY)
                        .allowsHitTesting(false)
                }
            }
    }
}

struct IslandSurface: View {
    @ObservedObject var model: IslandModel

    static func homeColumn(_ c: IslandConfig, size: CGSize, clearance: CGFloat, floating: Bool) -> AnyShape {
        let ins = IslandGeometry.contentInsets(c, clearance: clearance)
        let f = HomeLayout.frames(c)
        let mi = c.homeMainIndex
        let m = f[mi]
        let g = HomeLayout.gap(c)
        // Round 28: the wide part reaches the nearest side slot's edge (was the middle of the gap). With no
        // side slot before/after the main one, that end stays wide.
        let len = c.edge.isVertical ? size.height : size.width
        let lo = mi == 0 ? 0 : ins.top + m.x - g, hi = mi == f.count - 1 ? len : ins.top + m.x + m.width + g
        return AnyShape(HomeColumnShape(edge: c.edge, style: c.style,
                                        cornerRadius: max(c.cornerRadius * 2, floating ? 28 : 22),
                                        flare: IslandGeometry.openFlare, band: lo...hi, full: size,
                                        dip: HomeLayout.verticalWidth - HomeLayout.verticalSideWidth))
    }

    var body: some View {
        let c = model.config
        let open = model.isExpanded
        let floating = c.style == .island
        let dual = !open && model.toast == nil && model.dualIdle
        // Round 24: idle lyric under a built-in notch (strip under the music part, or a detached pill).
        let size = model.size
        let lyricRect: CGRect? = !open && model.toast == nil && model.showsLive && model.lyricsBelow
            ? model.lyricWidth.map { IslandGeometry.lyricBelowRect(c, size: size, lyricWidth: $0, dual: dual) } : nil
        let depth = IslandGeometry.liveDepth(c)
        // Round 26: open left/right Emper on Home: the outline narrows around the 4/5-wide side slots.
        let column: AnyShape? = open && c.edge.isVertical && model.selectedID == ModuleRegistry.homeID
            && c.homeSlots.count > 1 ? Self.homeColumn(c, size: size, clearance: model.clearance, floating: floating) : nil
        let body: AnyShape = column ?? (dual
            ? AnyShape(DualIdleShape(edge: c.edge, style: c.style, cornerRadius: c.cornerRadius, flare: IslandConfig.notchFlare,
                                     pad: IslandGeometry.timerChip, neck: IslandGeometry.timerNeck))
            : AnyShape(IslandShape(edge: c.edge,
                                cornerRadius: open ? max(c.cornerRadius * 2, floating ? 28 : 22) : (floating ? 100 : c.cornerRadius),
                                flare: open ? IslandGeometry.openFlare : IslandConfig.notchFlare,
                                style: c.style, anchor: c.anchor)))
        // Round 25: with the pill reserved, the body keeps its plain size on top; the pill is its own layer.
        let shape: AnyShape = lyricRect != nil
            ? AnyShape(BodyOnTopShape(body: body, bodyWidth: dual ? size.width : IslandGeometry.liveSize(c, notch: true).width,
                                      bodyHeight: depth))
            : body
        // The shape alone decides the island's size; content sits in an overlay so it can never
        // inflate the idle island.
        ZStack(alignment: .topLeading) {
        shape
            .fill(Color.islandFill)
            .opacity(open || model.isLive || model.timerLive || model.toast != nil ? 1 : c.idleOpacity)
            .overlay(alignment: c.edge.alignment) {
                ZStack(alignment: c.edge.alignment) {
                    if open {
                        ExpandedContent(model: model)
                            .transition(.asymmetric(
                                insertion: .opacity.animation(IslandMotion.contentIn),
                                removal: .opacity.animation(IslandMotion.contentOut)))
                    } else if let t = model.toast {
                        ToastView(toast: t, config: c)
                            .id(t.id)
                            .transition(.opacity.animation(.easeOut(duration: 0.18)))
                    } else if model.showsLive {
                        ZStack(alignment: .topLeading) {
                            HStack(alignment: .top, spacing: 0) {
                                // Timer active too: its own body joined on the right (time + play/pause together).
                                LiveActivityView(config: c, lyricWidth: model.lyricsBelow ? model.lyricWidth : model.shownLyricWidth,
                                                 notch: model.clearance > 0,
                                                 below: model.lyricsBelow, dual: dual)
                                if dual {
                                    Color.clear.frame(width: IslandGeometry.timerNeck)
                                    // Keeps its own depth when the lyric strip makes the music part deeper.
                                    TimerChip().frame(width: IslandGeometry.timerChip - IslandGeometry.timerNeck,
                                                      height: lyricRect != nil ? depth : nil)
                                }
                            }
                        }
                        .frame(width: size.width, height: size.height, alignment: .topLeading)
                        .transition(.opacity.animation(.easeOut(duration: 0.18)))
                    } else if model.timerLive {
                        TideIdleStrip(config: c, compact: model.compactTimer)
                            .transition(.opacity.animation(.easeOut(duration: 0.18)))
                    }
                }
                // The idle content takes its final place at once instead of riding the shrinking frame
                // (that ride was the sideways slide); SettleIn then gives it its own small rise.
                .animation(open ? IslandMotion.expand : nil, value: model.size)
                .modifier(SettleIn(gen: model.closeCount, edge: c.edge))
            }
            .clipShape(shape)
            // Shadow only for the floating style (a notch is flush to the edge, its shadow was invisible but
            // still re-blurred every frame of the open animation, the GPU spike on hover).
            .shadow(color: .black.opacity(floating ? 0.3 : 0), radius: floating ? (open ? 8 : 4) : 0, y: 3)
            // Round 25: the lyric's own pill. Its place is fixed while the song has lyrics; hover and
            // instrumental parts only fade it, so the Emper never changes size for them.
            if let r = lyricRect {
                IdleLyricLine(alignment: .center, small: true)
                    .padding(.horizontal, 12)
                    .frame(width: r.width, height: r.height)
                    .background(Capsule(style: .continuous).fill(Color.islandFill))
                    .shadow(color: .black.opacity(floating ? 0.3 : 0), radius: floating ? 4 : 0, y: 3)
                    .offset(x: r.minX, y: r.minY)
                    .opacity(model.lyricPillVisible ? 1 : 0)
                    .animation(.easeOut(duration: 0.2), value: model.lyricPillVisible)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }
}

/// Tabs + selected module, laid out at the target size and revealed by the growing shape.
/// The tab bar sits on the Emper's own edge: top for top/side Empers, bottom for the bottom Emper.
struct ExpandedContent: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        let i = IslandGeometry.contentInsets(model.config, clearance: model.clearance)
        let bottom = model.config.edge == .bottom
        let edge = model.config.edge
        // Round 26: left/right Empers carry the tab bar as a column on the screen side.
        let gap = IslandGeometry.tabGap(model.config)
        let layout = edge.isVertical ? AnyLayout(HStackLayout(spacing: gap)) : AnyLayout(VStackLayout(spacing: gap))
        layout {
            // zIndex: the hover tips of the bar draw over the content next to it.
            if edge == .top { TabBar(model: model).frame(height: IslandGeometry.tabBarHeight).zIndex(1) }
            if edge == .left { TabBar(model: model, part: .tabs).frame(width: IslandGeometry.tabBarHeight).zIndex(1) }
            Group {
                if model.selectedID == ModuleRegistry.homeID {
                    // Side placeholders live on Home only; other tabs show just their feature at the main size.
                    HomeRow(model: model)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .transition(.opacity.animation(.easeOut(duration: 0.16)))
                } else if let entry = model.tabs.first(where: { $0.id == model.selectedID }) {
                    // Modules fill the island's full inner width, so a long notch leaves no empty gap.
                    entry.view
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .id(entry.id)
                        .transition(.opacity.animation(.easeOut(duration: 0.16)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                if model.editingHome, model.addingTab {
                    // Round 29: on a left/right Home the outline narrows beside the side slots; stay inside it.
                    let dip = edge.isVertical && model.selectedID == ModuleRegistry.homeID && model.config.homeSlots.count > 1
                        ? HomeLayout.verticalWidth - HomeLayout.verticalSideWidth : 0
                    AddTabPicker(model: model)
                        .padding(edge == .right ? .leading : .trailing, dip)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .animation(.easeOut(duration: 0.16), value: model.addingTab)
            if bottom { TabBar(model: model).frame(height: IslandGeometry.tabBarHeight).zIndex(1) }
            if edge == .right { TabBar(model: model, part: .tabs).frame(width: IslandGeometry.tabBarHeight).zIndex(1) }
        }
        .padding(EdgeInsets(top: i.top, leading: i.leading, bottom: i.bottom, trailing: i.trailing))
        .frame(width: model.size.width, height: model.size.height)
        // Round 22: the content jumps to its final size; only the shape animates. Riding the animated
        // size re-laid out the old and new module every frame of a tab switch (~150 ms CPU per switch).
        .animation(nil, value: model.size)
    }
}

/// Pencil mode "+" tab: every feature that isn't a tab yet, as chips drawn inside the island.
struct AddTabPicker: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        let left = IslandConfig.features.filter { ModuleRegistry.descriptor($0) != nil && !model.config.moduleIDs.contains($0) }
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        VStack(alignment: .leading, spacing: 6) {
            Text("Add a tab").font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.primary.opacity(0.55))
            // Round 28: left/right Emper: one column of full-width rows.
            let v = model.config.edge.isVertical
            // Round 29: scrolls (with a "more below" hint) when the features don't fit.
            HintedScroll {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: v ? 1 : 4), spacing: 6) {
                ForEach(left, id: \.self) { id in
                    if let d = ModuleRegistry.descriptor(id) {
                        Button {
                            model.onEditConfig { $0.setTab(id, true) }
                            model.addingTab = false
                            model.onSelect(id)
                        } label: {
                            HStack(spacing: v ? 8 : 5) {
                                Image(systemName: d.symbol).font(.system(size: 11, weight: .semibold))
                                Text(v ? d.name : TabBar.label(d.name)).font(.system(size: 10, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
                            }
                            .padding(.horizontal, v ? 12 : 0)
                            .frame(maxWidth: .infinity, minHeight: 28, alignment: v ? .leading : .center)
                            .background(Capsule().fill(Color.primary.opacity(0.08)))
                            .contentShape(Capsule())
                        }
                        .buttonStyle(PressScaleStyle())
                        .foregroundStyle(Color.primary)
                    }
                }
            }
            .padding(.bottom, 6)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(shape.fill(Color.islandFill))
        .overlay(shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
    }
}

/// Live drag of one tab while arranging (pencil mode).
final class TabDrag: ObservableObject {
    @Published var hover: String?
    @Published var id: String?
    @Published var dx: CGFloat = 0
}

/// Icon-only tabs. The open tab is a solid accent pill; the name shows as a tooltip.
/// Pencil mode: drag tabs to reorder them (Home stays first) and, when Home is on, add placeholders.
struct TabBar: View {
    @ObservedObject var model: IslandModel
    /// Round 29: left/right Empers split the bar: `.tabs` in the column, `.controls` in the floating pill.
    enum Part { case all, tabs, controls }
    var part: Part = .all
    @StateObject private var drag = TabDrag()
    @StateObject private var tip = HoverTip()
    @ObservedObject private var updates = UpdateChecker.shared
    private var vertical: Bool { model.config.edge.isVertical }

    static let accent = Color(red: 10 / 255, green: 132 / 255, blue: 1)
    private static let tabWidth: CGFloat = 30
    private static let gap: CGFloat = 4
    private var pitch: CGFloat { Self.tabWidth + Self.gap }

    var body: some View {
        let editing = model.editingHome
        let hasHome = model.tabs.first?.id == ModuleRegistry.homeID
        // Only tabs the user configured can move; Home and the auto music tab stay put.
        let movable = model.tabs.map(\.id).filter { $0 != ModuleRegistry.homeID && model.config.moduleIDs.contains($0) }
        let v = vertical
        // Round 26: a column on left/right Empers (pencil on top, Home first, Emper and Settings at the bottom).
        let stack = v ? AnyLayout(VStackLayout(spacing: 6)) : AnyLayout(HStackLayout(spacing: 6))
        let inner = v ? AnyLayout(VStackLayout(spacing: Self.gap)) : AnyLayout(HStackLayout(spacing: Self.gap))
        // Round 27: the tabs sit in the true middle of the bar (pushed aside only if they would hit an end).
        let pencil = circleButton(editing ? "checkmark" : "pencil", active: editing, tip: editing ? "Done" : "Edit", lead: true) {
            if editing { model.finishEdit(); return }
            if hasHome { model.onSelect(ModuleRegistry.homeID) }
            model.beginEdit()
        }
        let tabs = stack {
            inner {
                ForEach(model.tabs) { tab in
                    tabView(tab, editing: editing, movable: movable)
                }
            }
            if editing { addTabButton }
        }
        let ends = stack {
            if editing {
                circleButton("xmark", active: false, tip: "Cancel", lead: false) { model.cancelEdit() }
            } else {
                // Round 26: this Emper's own page in Settings, next to the general Settings button.
                emperButton
                gearButton
            }
        }
        Group {
            switch part {
            case .all:
                EndsCenterLayout(vertical: v, spacing: 6) { pencil; tabs; ends }
            case .tabs:
                // The tabs alone, centred on the column.
                EndsCenterLayout(vertical: v, spacing: 6) { Color.clear.frame(width: 0, height: 0); tabs; Color.clear.frame(width: 0, height: 0) }
            case .controls:
                VStack(spacing: 6) { pencil; ends }
            }
        }
        // Round 22: short fade, not a ~0.6 s spring; every frame of it redrew the whole open Emper.
        .animation(.easeOut(duration: 0.12), value: model.selectedID)
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: editing)
        .onChange(of: editing) { _, on in drag.id = nil; drag.dx = 0; if !on { model.addingTab = false } }
    }

    @ViewBuilder
    private func tabView(_ tab: ModuleEntry, editing: Bool, movable: [String]) -> some View {
        let selected = tab.id == model.selectedID
        let canMove = editing && movable.contains(tab.id)
        let removing = canMove && drag.hover == tab.id && drag.id == nil
        // Pencil + hover: the icon turns into a round ✕ in the middle; a click removes the tab.
        let pill = Group {
            if removing {
                CrossGlyph(size: 8, line: 1.6, rotated: true)
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(Color.white.opacity(0.22)))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.5), lineWidth: 1))
            } else {
                // Round 27: a sized symbol box, so every glyph sits in the optical middle of its pill.
                Image(systemName: tab.symbol).resizable().scaledToFit().fontWeight(.semibold).frame(width: 14, height: 14)
            }
        }
            .frame(width: vertical ? IslandGeometry.tabBarHeight : Self.tabWidth,
                   height: vertical ? Self.tabWidth : IslandGeometry.tabBarHeight)
            // Round 23: movable tabs in pencil mode get a lighter fill, no dashed hairline (jaggy on 1x screens).
            .background(Capsule().fill(selected ? Self.accent : Color.primary.opacity(canMove ? 0.14 : 0.07)))
            .foregroundStyle(selected ? Color.white : Color.primary.opacity(0.55))
            .contentShape(Capsule())
            .help(Self.label(tab.name) + (canMove ? " · click to remove, drag to reorder" : ""))
        if canMove {
            pill
                .offset(x: vertical ? 0 : offset(tab.id, movable: movable), y: vertical ? offset(tab.id, movable: movable) : 0)
                .zIndex(drag.id == tab.id ? 1 : 0)
                .scaleEffect(drag.id == tab.id ? 1.08 : 1)
                .gesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged { v in
                            if drag.id == nil { drag.id = tab.id }
                            drag.dx = vertical ? v.translation.height : v.translation.width
                        }
                        .onEnded { _ in commit(movable: movable) }
                )
                .simultaneousGesture(TapGesture().onEnded { remove(tab.id) })
                .onHover { inside in
                    if inside { drag.hover = tab.id } else if drag.hover == tab.id { drag.hover = nil }
                }
                .animation(.easeOut(duration: 0.12), value: drag.hover)
        } else {
            Button { model.onSelect(tab.id) } label: { pill }
                .buttonStyle(PressScaleStyle())
        }
    }

    /// Where the drag would drop the tab, as an index into `movable`.
    private func target(movable: [String]) -> (from: Int, to: Int)? {
        guard let id = drag.id, let from = movable.firstIndex(of: id) else { return nil }
        let to = min(max(0, from + Int((drag.dx / pitch).rounded())), movable.count - 1)
        return (from, to)
    }

    private func offset(_ id: String, movable: [String]) -> CGFloat {
        guard let t = target(movable: movable), let i = movable.firstIndex(of: id) else { return 0 }
        if id == drag.id { return drag.dx }
        if t.from < t.to, i > t.from, i <= t.to { return -pitch }
        if t.from > t.to, i >= t.to, i < t.from { return pitch }
        return 0
    }

    private func remove(_ id: String) {
        drag.hover = nil
        model.onEditConfig { $0.setTab(id, false) }
    }

    private func commit(movable: [String]) {
        defer { drag.id = nil; drag.dx = 0 }
        guard let t = target(movable: movable), t.from != t.to else { return }
        let order = TabOrder.moving(movable, from: t.from, to: t.to)
        model.onEditConfig { c in c.moduleIDs = TabOrder.apply(order, to: c.moduleIDs) }
    }

    /// The pill floats outside the Emper, so its tips open towards the Emper (the other way).
    private var tipEdge: IslandEdge {
        guard part == .controls else { return model.config.edge }
        return model.config.edge == .left ? .right : .left
    }

    static func label(_ name: String) -> String { name.components(separatedBy: " (").first ?? name }

    private func circleButton(_ symbol: String, active: Bool, tip text: String, lead: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if symbol == "xmark" { CrossGlyph(size: 10, line: 2, rotated: true) }
                else { Image(systemName: symbol).resizable().scaledToFit().fontWeight(.semibold).frame(width: 12, height: 12) }
            }
                .frame(width: IslandGeometry.tabBarHeight, height: IslandGeometry.tabBarHeight)
                .background(Circle().fill(active ? Self.accent : Color.primary.opacity(0.06)))
                .foregroundStyle(active ? Color.white : Color.primary.opacity(0.6))
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle())
        .modifier(TipModifier(tip: tip, key: symbol, text: text, edge: tipEdge, lead: lead))
    }

    /// Round 26: opens Settings › Empers on this Emper's screen and side. Round 28: the Empers page's own
    /// symbol, in the gear button's grey (not the page's colour).
    private var emperButton: some View {
        circleButton("capsule.fill", active: false, tip: "This Emper's settings", lead: false) { model.onOpenEmperSettings() }
    }

    /// Gear: opens Settings. With an update waiting it carries a red dot and opens About instead.
    private var gearButton: some View {
        let update = updates.available != nil
        return circleButton("gearshape.fill", active: false, tip: update ? "Update available" : "Settings", lead: false) {
            if update { IslandController.openAbout() } else { IslandController.openSettings() }
        }
        .overlay(alignment: .topTrailing) {
            if update {
                Circle().fill(Color.red).frame(width: 7, height: 7)
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.6), lineWidth: 1))
                    .offset(x: 1, y: -1)
                    .allowsHitTesting(false)
            }
        }
    }

    /// "+" right of the tabs: picks a feature that isn't a tab yet.
    private var addTabButton: some View {
        let left = IslandConfig.features.filter { ModuleRegistry.descriptor($0) != nil && !model.config.moduleIDs.contains($0) }
        return Button { model.addingTab.toggle() } label: {
            CrossGlyph(size: 10, line: 2, rotated: model.addingTab)
                .frame(width: vertical ? IslandGeometry.tabBarHeight : Self.tabWidth,
                       height: vertical ? Self.tabWidth : IslandGeometry.tabBarHeight)
                .background(Capsule().fill(model.addingTab ? Self.accent : Color.primary.opacity(0.14)))
                .foregroundStyle(model.addingTab ? Color.white : Color.primary)
                .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle())
        .disabled(left.isEmpty && !model.addingTab)
        .opacity(left.isEmpty && !model.addingTab ? 0.3 : 1)
        .help(left.isEmpty ? "Every feature is already a tab" : "Add a tab")
    }
}

/// Idle-island notice (Bluetooth device connected): icon on the left wing, name and battery on the right.
struct ToastView: View {
    let toast: IslandToast
    let config: IslandConfig

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: toast.symbol).font(.system(size: 13, weight: .semibold))
            Text(toast.title).font(.system(size: 11, weight: .semibold)).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: CGFloat(config.collapsedWidth) * 0.6)
            Text("Connected").font(.system(size: 10, weight: .medium)).foregroundStyle(Color.primary.opacity(0.55))
            if let b = toast.battery {
                HStack(spacing: 3) {
                    Image(systemName: Self.batterySymbol(b)).font(.system(size: 12))
                        .foregroundStyle(b < 0.2 ? Color(red: 1, green: 0.42, blue: 0.38) : Color.primary)
                    Text("\(Int((b * 100).rounded()))%").font(.system(size: 10, weight: .semibold).monospacedDigit())
                }
            }
        }
        .foregroundStyle(Color.primary)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    static func batterySymbol(_ b: Double) -> String {
        switch b {
        case ..<0.13: "battery.0percent"
        case ..<0.38: "battery.25percent"
        case ..<0.63: "battery.50percent"
        case ..<0.88: "battery.75percent"
        default: "battery.100percent"
        }
    }
}

/// Round 27: bar with a first and last item at its ends and the middle item centred on the bar itself,
/// not on the gap between the ends (they differ in size). Expects exactly three subviews.
struct EndsCenterLayout: Layout {
    var vertical: Bool
    var spacing: CGFloat

    private func along(_ s: CGSize) -> CGFloat { vertical ? s.height : s.width }
    private func across(_ s: CGSize) -> CGFloat { vertical ? s.width : s.height }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let need = sizes.map(along).reduce(0, +) + spacing * CGFloat(max(sizes.count - 1, 0))
        let len = max((vertical ? proposal.height : proposal.width) ?? need, need)
        let cross = sizes.map(across).max() ?? 0
        return vertical ? CGSize(width: cross, height: len) : CGSize(width: len, height: cross)
    }

    func placeSubviews(in b: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 3 else { return }
        let s = subviews.map { $0.sizeThatFits(.unspecified) }
        let start = vertical ? b.minY : b.minX, end = vertical ? b.maxY : b.maxX
        let mid = (start + end) / 2
        let lo = start + along(s[0]) + spacing, hi = end - along(s[2]) - spacing
        let m0 = min(max(mid - along(s[1]) / 2, lo), max(hi - along(s[1]), lo))
        let starts = [start, m0, end - along(s[2])]
        for i in 0..<3 {
            let c = vertical ? CGPoint(x: b.midX, y: starts[i] + s[i].height / 2) : CGPoint(x: starts[i] + s[i].width / 2, y: b.midY)
            subviews[i].place(at: c, anchor: .center, proposal: ProposedViewSize(s[i]))
        }
    }
}

/// Round 27: short hover tips for the bar buttons. `.help` tooltips never show on the Emper's
/// non-activating panel, so the tip is drawn inside the Emper after a short hover.
@MainActor
final class HoverTip: ObservableObject {
    @Published var shown: String?
    private var work: DispatchWorkItem?

    func hover(_ key: String, _ inside: Bool) {
        work?.cancel()
        if inside {
            let w = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.shown = key } }
            work = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: w)
        } else if shown == key {
            shown = nil
        }
    }
}

struct TipModifier: ViewModifier {
    @ObservedObject var tip: HoverTip
    let key: String
    let text: String
    let edge: IslandEdge
    /// Button at the start of the bar (left / top): the tip grows away from the Emper's nearer end.
    let lead: Bool

    func body(content: Content) -> some View {
        // Into the Emper: beside the column on left/right Empers, above or below the bar on top/bottom ones.
        let (align, dx, dy): (Alignment, CGFloat, CGFloat) = switch edge {
        case .left: (.leading, IslandGeometry.tabBarHeight + 6, 0)
        case .right: (.trailing, -(IslandGeometry.tabBarHeight + 6), 0)
        case .top: (lead ? .topLeading : .topTrailing, 0, IslandGeometry.tabBarHeight + 6)
        case .bottom: (lead ? .bottomLeading : .bottomTrailing, 0, -(IslandGeometry.tabBarHeight + 6))
        }
        content
            .onHover { tip.hover(key, $0) }
            .simultaneousGesture(TapGesture().onEnded { tip.hover(key, false) })
            .overlay(alignment: align) {
                if tip.shown == key {
                    Text(text)
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(Color.primary.opacity(0.92)))
                        .foregroundStyle(Color.islandFill)
                        .offset(x: dx, y: dy)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.12), value: tip.shown == key)
    }
}

/// Round 29: the floating pill of a left/right Emper (pencil, this Emper's settings, Settings).
struct SideControlsPill: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        TabBar(model: model, part: .controls)
            .padding(4)
            .frame(width: IslandGeometry.sidePillWidth)
            .background(Capsule(style: .continuous).fill(Color.islandFill))
            .overlay(Capsule(style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
            .shadow(color: .black.opacity(model.config.style == .island ? 0.3 : 0.15), radius: 4, y: 2)
    }
}
