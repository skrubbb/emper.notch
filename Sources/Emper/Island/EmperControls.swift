import SwiftUI

// MARK: Dropdown (round 29)

/// One choice in a `EmperDropdown`.
struct DropdownOption: Identifiable, Equatable {
    let id: String
    let label: String
}

/// Round 29: Emper's own dropdown. A macOS menu opens as its own window and can run past the Emper (moving
/// down to its last item then leaves the Emper, which closes). This list is drawn inside the view that hosts
/// it (`.dropdownHost()`, e.g. a side card), below its button when it fits, above otherwise, and scrolls
/// when the host is shorter than the list. A greyer surface than the card tells it apart.
@MainActor
final class DropdownCenter: ObservableObject {
    static let space = "emperDropdownHost"
    @Published private(set) var openID: String?
    @Published var hover: String?
    private(set) var anchor: CGRect = .zero
    private(set) var options: [DropdownOption] = []
    private(set) var selected: String?
    private var pick: (String) -> Void = { _ in }
    /// Round 30: a custom panel (the date calendar) instead of a list, and its size.
    private(set) var custom: AnyView?
    private(set) var customSize: CGSize = .zero
    /// Button frames in the host, kept up to date while they lay out.
    var frames: [String: CGRect] = [:]
    /// Render hook: open the dropdown whose id ends with this as soon as its button appears.
    static var renderOpen: String?

    func toggle(_ id: String, options: [DropdownOption], selected: String?, pick: @escaping (String) -> Void) {
        if openID == id { close(); return }
        anchor = frames[id] ?? .zero
        self.options = options
        self.selected = selected
        self.pick = pick
        custom = nil
        hover = nil
        openID = id
    }

    func toggle(_ id: String, size: CGSize, content: AnyView) {
        if openID == id { close(); return }
        anchor = frames[id] ?? .zero
        options = []
        selected = nil
        custom = content
        customSize = size
        hover = nil
        openID = id
    }

    func choose(_ id: String) {
        let p = pick
        close()
        p(id)
    }

    func close() { if openID != nil { openID = nil } }
}

/// Button that opens a dropdown in the nearest `.dropdownHost()`.
struct EmperDropdown<Label: View>: View {
    let id: String
    let options: [DropdownOption]
    let selected: String?
    let pick: (String) -> Void
    /// Round 30: a custom panel instead of the option list; it gets a closure that closes it.
    var popSize: CGSize = .zero
    var popover: ((@escaping () -> Void) -> AnyView)? = nil
    @ViewBuilder var label: Label
    @EnvironmentObject private var center: DropdownCenter

    private func open() {
        if let p = popover {
            let c = center
            center.toggle(id, size: popSize, content: p { c.close() })
        } else {
            center.toggle(id, options: options, selected: selected, pick: pick)
        }
    }

    var body: some View {
        Button {
            TextOverlay.shared.end()
            TimeEntry.shared.end()
            open()
        } label: {
            HStack(spacing: 3) {
                label
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 7, weight: .bold))
                    .foregroundStyle(Color.primary.opacity(0.45))
            }
            .padding(.horizontal, 7).frame(height: 18)
            .background(Capsule().fill(Color.primary.opacity(center.openID == id ? 0.2 : 0.1)))
            .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle())
        .background(GeometryReader { g in
            let f = g.frame(in: .named(DropdownCenter.space))
            Color.clear
                .onAppear {
                    center.frames[id] = f
                    if let r = DropdownCenter.renderOpen, id.hasSuffix(r) {
                        DispatchQueue.main.async { open() }
                    }
                }
                .onChange(of: f) { _, n in center.frames[id] = n }
        })
    }
}

extension View {
    /// The area dropdowns inside this view are drawn in (and kept within).
    func dropdownHost() -> some View { modifier(DropdownHost()) }
}

private struct DropdownHost: ViewModifier {
    @StateObject private var center = DropdownCenter()
    @Environment(\.colorScheme) private var scheme

    static let row: CGFloat = 22

    func body(content: Content) -> some View {
        content
            .environmentObject(center)
            .coordinateSpace(name: DropdownCenter.space)
            .overlay {
                GeometryReader { g in
                    if center.openID != nil { list(in: g.size) }
                }
            }
            .animation(.easeOut(duration: 0.12), value: center.openID)
            .onDisappear { center.close() }
    }

    private func list(in host: CGSize) -> some View {
        let a = center.anchor
        let opts = center.options
        let custom = center.custom
        let inner = custom != nil ? center.customSize.height : CGFloat(opts.count) * Self.row + 8
        let h = min(inner, max(host.height - 8, Self.row + 8))
        let w = min(custom != nil ? center.customSize.width : max(a.width + 24, 120), host.width - 8)
        // Right edges line up (the values sit on the right of their rows), kept inside the host.
        let x = min(max(a.maxX - w, 4), host.width - 4 - w)
        let below = a.maxY + 4, above = a.minY - 4 - h
        let y = below + h <= host.height - 4 ? below : (above >= 4 ? above : max(4, host.height - 4 - h))
        let dark = scheme == .dark
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        return ZStack(alignment: .topLeading) {
            // A click anywhere else in the host closes it.
            Color.black.opacity(0.001).onTapGesture { center.close() }
            ScrollView(.vertical, showsIndicators: inner > h) {
                if let custom {
                    custom.frame(width: w, height: center.customSize.height)
                } else {
                    VStack(spacing: 0) {
                        ForEach(opts) { o in row(o, dark: dark) }
                    }
                    .padding(4)
                }
            }
            .frame(width: w, height: h)
            .background(shape.fill(Color(white: dark ? 0.27 : 0.86)))
            .overlay(shape.strokeBorder(Color.primary.opacity(dark ? 0.14 : 0.12), lineWidth: 1))
            .clipShape(shape)
            .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
            .offset(x: x, y: y)
            .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: y < a.minY ? .bottom : .top)))
        }
        .frame(width: host.width, height: host.height, alignment: .topLeading)
    }

    private func row(_ o: DropdownOption, dark: Bool) -> some View {
        let on = o.id == center.selected
        let hot = center.hover == o.id
        return Button { center.choose(o.id) } label: {
            HStack(spacing: 6) {
                Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)).opacity(on ? 1 : 0).frame(width: 9)
                Text(o.label).font(.system(size: 10.5, weight: on ? .semibold : .regular)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(hot ? Color.white : Color.primary)
            .padding(.horizontal, 6)
            .frame(height: Self.row)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(hot ? EditPalette.accent : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside { center.hover = o.id } else if center.hover == o.id { center.hover = nil }
        }
    }
}

// MARK: Calendar (round 30)

final class CalendarPageState: ObservableObject {
    /// First day of the month on screen.
    @Published var month: Date
    init(month: Date) { self.month = month }
}

/// Month grid for picking a day: ‹ › change the month, the year has its own ‹ ›, Today / Tomorrow are
/// one click. Weeks start on the system's first weekday. Drawn inside a `EmperDropdown` popover.
struct EmperCalendar: View {
    static let size = CGSize(width: 168, height: 194)
    let selected: Date
    let pick: (Date) -> Void
    @StateObject private var page: CalendarPageState

    init(selected: Date, pick: @escaping (Date) -> Void) {
        self.selected = selected
        self.pick = pick
        let cal = Calendar.current
        _page = StateObject(wrappedValue: CalendarPageState(
            month: cal.date(from: cal.dateComponents([.year, .month], from: selected)) ?? selected))
    }

    private var cal: Calendar { Calendar.current }

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 0) {
                arrow("chevron.left") { shift(.month, -1) }
                Text(Self.monthName(page.month)).font(.system(size: 10.5, weight: .semibold))
                    .frame(maxWidth: .infinity)
                arrow("chevron.right") { shift(.month, 1) }
                Rectangle().fill(Color.primary.opacity(0.15)).frame(width: 1, height: 12).padding(.horizontal, 3)
                arrow("chevron.left") { shift(.year, -1) }
                Text(String(cal.component(.year, from: page.month))).font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                    .frame(width: 32)
                arrow("chevron.right") { shift(.year, 1) }
            }
            .frame(height: 18)
            HStack(spacing: 0) {
                ForEach(Array(weekdays.enumerated()), id: \.offset) { _, w in
                    Text(w).font(.system(size: 8.5, weight: .medium)).foregroundStyle(Color.primary.opacity(0.5))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 11)
            VStack(spacing: 1) {
                ForEach(0..<6, id: \.self) { w in
                    HStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { i in cell(days[w * 7 + i]) }
                    }
                }
            }
            HStack(spacing: 4) {
                quick("Today", 0)
                quick("Tomorrow", 1)
                quick("Next week", 7)
            }
            .frame(height: 18)
        }
        .padding(6)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .top)
    }

    static func monthName(_ d: Date) -> String {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMM")
        return f.string(from: d)
    }

    private var weekdays: [String] {
        let s = cal.veryShortStandaloneWeekdaySymbols
        let first = cal.firstWeekday - 1
        return (0..<7).map { s[(first + $0) % 7] }
    }

    /// 42 days from the start of the week containing the 1st.
    private var days: [Date] {
        let lead = (cal.component(.weekday, from: page.month) - cal.firstWeekday + 7) % 7
        let start = cal.date(byAdding: .day, value: -lead, to: page.month) ?? page.month
        return (0..<42).map { cal.date(byAdding: .day, value: $0, to: start) ?? start }
    }

    private func shift(_ c: Calendar.Component, _ n: Int) {
        page.month = cal.date(byAdding: c, value: n, to: page.month) ?? page.month
    }

    private func cell(_ day: Date) -> some View {
        let inMonth = cal.isDate(day, equalTo: page.month, toGranularity: .month)
        let on = cal.isDate(day, inSameDayAs: selected)
        let today = cal.isDateInToday(day)
        return Button { pick(cal.startOfDay(for: day)) } label: {
            Text(String(cal.component(.day, from: day)))
                .font(.system(size: 9.5, weight: on || today ? .bold : .regular).monospacedDigit())
                .foregroundStyle(on ? Color.white : today ? EditPalette.accent : Color.primary.opacity(inMonth ? 0.9 : 0.3))
                .frame(maxWidth: .infinity).frame(height: 19)
                .background(Circle().fill(on ? EditPalette.accent : Color.clear).frame(width: 19, height: 19))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func quick(_ label: String, _ n: Int) -> some View {
        Button {
            let s = cal.startOfDay(for: Date())
            pick(cal.date(byAdding: .day, value: n, to: s) ?? s)
        } label: {
            Text(label).font(.system(size: 9, weight: .medium)).lineLimit(1)
                .frame(maxWidth: .infinity).frame(height: 16)
                .background(Capsule().fill(Color.primary.opacity(0.1)))
                .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle())
    }

    private func arrow(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 8, weight: .bold))
                .frame(width: 14, height: 16).contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .foregroundStyle(Color.primary.opacity(0.65))
    }
}

// MARK: Scroll with a "more below" hint (round 29)

final class ScrollHintState: ObservableObject {
    @Published var more = false
}

private struct ScrollBottomKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Vertical scroll view that fades its bottom edge and shows a small chevron while there is more content
/// below (clicking the chevron scrolls to the end). Nothing extra shows when everything fits.
struct HintedScroll<Content: View>: View {
    @ViewBuilder var content: Content
    @StateObject private var s = ScrollHintState()
    private static var space: String { "hintedScroll" }

    var body: some View {
        GeometryReader { outer in
            let height = outer.size.height
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        content
                        Color.clear.frame(height: 1).id("hint-end")
                    }
                    .background(GeometryReader { g in
                        Color.clear.preference(key: ScrollBottomKey.self, value: g.frame(in: .named(Self.space)).maxY)
                    })
                }
                .coordinateSpace(name: Self.space)
                .onPreferenceChange(ScrollBottomKey.self) { bottom in
                    let m = bottom > height + 4
                    if m != s.more { s.more = m }
                }
                .mask(
                    LinearGradient(stops: [.init(color: .black, location: 0),
                                           .init(color: .black, location: s.more ? max(0, 1 - 22 / max(height, 1)) : 1),
                                           .init(color: .black.opacity(s.more ? 0.15 : 1), location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                )
                .overlay(alignment: .bottom) {
                    if s.more {
                        Button { withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("hint-end", anchor: .bottom) } } label: {
                            Image(systemName: "chevron.compact.down").font(.system(size: 12, weight: .bold))
                                .frame(width: 30, height: 12)
                                .foregroundStyle(Color.primary.opacity(0.7))
                                .background(Capsule().fill(Color.primary.opacity(0.12)))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(PressScaleStyle())
                        .help("More below")
                        .transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: 0.15), value: s.more)
            }
        }
    }
}
