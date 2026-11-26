import SwiftUI
import AppKit
import EventKit
import EmperCore

/// Round 28: add a reminder to Apple Reminders (EventKit) from the Emper. Fields follow the Reminders
/// detail panel's defaults: title, notes, URL, date (today), time, repeat. Anything else (early reminder: removed in round 30, no public API),
/// (list, tags, location, people) is in Reminders itself ("Open Reminders").
/// Apply is checked: after saving, the reminder is read back from a fresh connection to the Reminders
/// database, and only then shows "Added". Any failure says so in red and keeps what was typed.
@MainActor
final class ReminderDraft: ObservableObject {
    static let shared = ReminderDraft()

    enum Repeat: String, CaseIterable, Identifiable {
        case never = "Never", daily = "Daily", weekdays = "Weekdays", weekly = "Weekly", monthly = "Monthly", yearly = "Yearly"
        var id: String { rawValue }
    }
    /// Round 29: every reminder has a time, 09:00 unless changed (a date-only reminder may never alert).
    static let defaultTime = 9 * 60
    enum Status: Equatable {
        case idle, saving
        case added(String)
        case failed(String)
        case denied
    }

    @Published var title = "" { didSet { touched() } }
    @Published var notes = "" { didSet { touched() } }
    @Published var url = "" { didSet { touched() } }
    /// Start of the due day. Default today.
    @Published var day = Calendar.current.startOfDay(for: Date()) { didSet { touched() } }
    /// Minutes after midnight.
    @Published var time = ReminderDraft.defaultTime { didSet { touched() } }
    @Published var repeats: Repeat = .never { didSet { touched() } }
    @Published var status: Status = .idle

    private var quiet = false
    private func touched() {
        guard !quiet else { return }
        if case .added = status { status = .idle }
        if case .failed = status { status = .idle }
    }

    func reset() {
        quiet = true
        TextOverlay.shared.end()
        title = ""; notes = ""; url = ""
        day = Calendar.current.startOfDay(for: Date())
        time = Self.defaultTime; repeats = .never
        quiet = false
    }

    var dayLabel: String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Today" }
        if cal.isDateInTomorrow(day) { return "Tomorrow" }
        if cal.isDateInYesterday(day) { return "Yesterday" }
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate(cal.isDate(day, equalTo: Date(), toGranularity: .year) ? "EEE d MMM" : "d MMM yyyy")
        return f.string(from: day)
    }

    static func timeLabel(_ m: Int) -> String {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("jmm")
        let d = Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
        return f.string(from: d)
    }

    func shiftDay(_ n: Int) { day = Calendar.current.date(byAdding: .day, value: n, to: day) ?? day }

    // MARK: Time typed on the keyboard (round 29)

    /// The system's clock style (System Settings › General › Date & Time › 24-hour time).
    static var uses12h: Bool {
        (DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? "").contains("a")
    }
    var isPM: Bool { time >= 720 }
    var hourText: String {
        let h = time / 60
        return String(format: "%02d", Self.uses12h ? (h % 12 == 0 ? 12 : h % 12) : h)
    }
    var minuteText: String { String(format: "%02d", time % 60) }
    static func digits(_ s: String) -> String { String(s.filter(\.isNumber).prefix(2)) }

    /// An hour being typed. Complete at two digits, or at one that can't start a two-digit hour (3–9 in
    /// 24-hour time, 2–9 in 12-hour time); true means the minutes take over.
    @discardableResult func typeHour(_ s: String) -> Bool {
        guard let v = Int(s) else { return false }
        let twelve = Self.uses12h
        let h: Int
        if twelve {
            let h12 = min(max(v, 0), 12) == 0 ? 12 : min(v, 12)
            h = h12 % 12 + (isPM ? 12 : 0)
        } else {
            h = min(v, 23)
        }
        time = h * 60 + time % 60
        return s.count >= 2 || (twelve ? v >= 2 : v >= 3)
    }

    /// Minutes being typed: complete at two digits or at 6–9.
    @discardableResult func typeMinute(_ s: String) -> Bool {
        guard let v = Int(s) else { return false }
        time = time / 60 * 60 + min(v, 59)
        return s.count >= 2 || v >= 6
    }

    /// Arrow keys: one hour or one minute up or down (wraps around midnight).
    func nudge(hour: Bool, by n: Int) { time = ((time + (hour ? 60 : 1) * n) % 1440 + 1440) % 1440 }

    func togglePM() { time = (time + 720) % 1440 }

    // MARK: Saving

    func apply() {
        guard status != .saving else { return }
        TextOverlay.shared.end()
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { status = .failed("Type a title first."); return }
        status = .saving
        Task { @MainActor in
            let r = await ReminderService.add(title: t, notes: notes, url: url, day: day, time: time,
                                              repeats: repeats)
            switch r {
            case .success(let list):
                let when = dayLabel + ", " + Self.timeLabel(time)
                reset()
                let shown = "Added to \(list) · \(when)"
                status = .added(shown)
                // Round 29: the confirmation shows for about 2 seconds.
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    guard self.status == .added(shown) else { return }
                    withAnimation(.easeOut(duration: 0.25)) { self.status = .idle }
                }
            case .failure(.denied):
                status = .denied
            case .failure(.other(let msg)):
                status = .failed(msg)
            }
        }
    }
}

enum ReminderError: Error { case denied, other(String) }

@MainActor
enum ReminderService {
    private static let store = EKEventStore()

    static func authorized() async -> Bool {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess: return true
        case .notDetermined:
            return (try? await store.requestFullAccessToReminders()) ?? false
        default: return false
        }
    }

    /// Saves, then reads it back from a new store (the database, not this store's cache). Returns the list name.
    static func add(title: String, notes: String, url: String, day: Date, time t: Int,
                    repeats: ReminderDraft.Repeat) async -> Result<String, ReminderError> {
        guard await authorized() else { return .failure(.denied) }
        guard let list = store.defaultCalendarForNewReminders() else {
            return .failure(.other("No default Reminders list. Open Reminders and make one."))
        }
        let r = EKReminder(eventStore: store)
        r.calendar = list
        r.title = title
        let n = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !n.isEmpty { r.notes = n }
        let u = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if !u.isEmpty { r.url = URL(string: u.contains("://") ? u : "https://" + u) }
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: day)
        comps.hour = t / 60; comps.minute = t % 60
        if let due = cal.date(from: comps) {
            r.addAlarm(EKAlarm(absoluteDate: due))
        }
        r.dueDateComponents = comps
        if let rule = rule(repeats) { r.addRecurrenceRule(rule) }
        do {
            try store.save(r, commit: true)
        } catch {
            return .failure(.other("Reminders refused it: \(error.localizedDescription)"))
        }
        // Read it back through a fresh connection.
        let id = r.calendarItemIdentifier
        for attempt in 0..<4 {
            let check = EKEventStore()
            if let back = check.calendarItem(withIdentifier: id) as? EKReminder, back.title == title {
                return .success("“\(back.calendar?.title ?? list.title)”")
            }
            try? await Task.sleep(nanoseconds: UInt64(150_000_000 * (attempt + 1)))
        }
        return .failure(.other("Saved, but Reminders doesn't show it. Check Reminders before relying on it."))
    }

    private static func rule(_ r: ReminderDraft.Repeat) -> EKRecurrenceRule? {
        switch r {
        case .never: return nil
        case .daily: return EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: nil)
        case .weekly: return EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: nil)
        case .monthly: return EKRecurrenceRule(recurrenceWith: .monthly, interval: 1, end: nil)
        case .yearly: return EKRecurrenceRule(recurrenceWith: .yearly, interval: 1, end: nil)
        case .weekdays:
            let days: [EKRecurrenceDayOfWeek] = [.monday, .tuesday, .wednesday, .thursday, .friday].map { EKRecurrenceDayOfWeek($0) }
            return EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, daysOfTheWeek: days, daysOfTheMonth: nil,
                                    monthsOfTheYear: nil, weeksOfTheYear: nil, daysOfTheYear: nil, setPositions: nil, end: nil)
        }
    }

    static func openReminders() {
        if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.reminders") {
            NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    static func openPrivacySettings() {
        if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") {
            NSWorkspace.shared.open(u)
        }
    }
}

/// Round 30: the time boxes take typing straight from the keyboard (through the invisible `KeyCatcher`),
/// not through a floating text panel: the panel had to be placed over the box and settle, which made the
/// hour and minute boxes shake when they were clicked or the minutes took over. Click a box, type digits;
/// Tab, ":" or → go to the minutes, ← back to the hour, ↑/↓ step, Return or Esc finish.
@MainActor
final class TimeEntry: ObservableObject {
    static let shared = TimeEntry()
    enum Part { case hour, minute }
    @Published private(set) var part: Part?
    @Published private(set) var typed = ""

    func begin(_ p: Part) {
        TextOverlay.shared.end()
        if part != p { part = p }
        typed = ""
        KeyCatcher.shared.takeFree()
    }

    func end() {
        guard part != nil else { return }
        part = nil
        typed = ""
        KeyCatcher.shared.releaseFree()
    }

    /// A key while a time box is active. Command shortcuts end the entry and pass on.
    func handle(_ e: NSEvent) -> Bool {
        guard let p = part else { return false }
        if e.modifierFlags.contains(.command) { end(); return false }
        let d = ReminderDraft.shared
        switch e.keyCode {
        case 36, 76, 53: end(); return true                                   // Return, Enter, Esc
        case 48: if p == .hour { begin(.minute) } else { end() }; return true  // Tab
        case 123: if p == .minute { begin(.hour) }; return true                // ←
        case 124: if p == .hour { begin(.minute) }; return true                // →
        case 126: d.nudge(hour: p == .hour, by: 1); typed = ""; return true    // ↑
        case 125: d.nudge(hour: p == .hour, by: -1); typed = ""; return true   // ↓
        case 51, 117: typed = String(typed.dropLast()); return true            // Delete
        default: break
        }
        let ch = e.charactersIgnoringModifiers ?? ""
        if ch == ":" || ch == "." { if p == .hour { begin(.minute) }; return true }
        guard ch.count == 1, let c = ch.first, c.isASCII, c.isNumber else { return true }
        typed += String(c)
        if p == .hour {
            if d.typeHour(typed) { part = .minute; typed = "" }
        } else if d.typeMinute(typed) {
            end()
        }
        return true
    }
}

@MainActor
final class ReminderModule: IslandModule {
    func makeView() -> AnyView { AnyView(ReminderView(compact: false)) }
    func makeCompactView() -> AnyView? { AnyView(ReminderView(compact: true)) }
}

final class ReminderBoxIDs: ObservableObject {
    let base = "reminder-" + UUID().uuidString
}

/// One time box: fixed size, digits drawn in place (no animation), accent ring while it takes typing.
private struct TimeBox: View {
    let part: TimeEntry.Part
    let text: String
    @ObservedObject private var entry = TimeEntry.shared

    var body: some View {
        let on = entry.part == part
        let shown = on && !entry.typed.isEmpty ? entry.typed : text
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        Text(shown)
            .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
            .frame(width: 24, height: 18)
            .background(shape.fill(on ? EditPalette.accent.opacity(0.28) : Color.primary.opacity(0.1)))
            .overlay(shape.strokeBorder(EditPalette.accent.opacity(on ? 0.9 : 0), lineWidth: 1))
            .contentShape(shape)
            .onTapGesture { entry.begin(part) }
            .transaction { $0.animation = nil }
    }
}

/// Main slot / own tab (wide): text fields left, date and options right. Side slot (narrow): one column
/// that scrolls, with a "more below" hint. Status, Reset and Apply stay at the bottom.
/// Round 29: dropdowns are Emper's own (drawn inside this view), the time is typed.
struct ReminderView: View {
    let compact: Bool
    @ObservedObject private var d = ReminderDraft.shared
    @StateObject private var ids = ReminderBoxIDs()

    var body: some View {
        GeometryReader { g in
            let wide = g.size.width >= 300
            VStack(alignment: .leading, spacing: 6) {
                if wide {
                    HStack(alignment: .top, spacing: 10) {
                        VStack(spacing: 4) { textFields }
                        VStack(spacing: 4) { options }
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                } else {
                    HintedScroll {
                        VStack(spacing: 4) { textFields; options }
                            .padding(.bottom, 4)
                    }
                }
                footer(narrow: !wide)
            }
            .padding(compact ? 0 : 6)   // a side placeholder already pads its card
            .frame(width: g.size.width, height: g.size.height, alignment: .topLeading)
            .dropdownHost()
        }
        .foregroundStyle(Color.primary)
    }

    @ViewBuilder private var textFields: some View {
        field(ids.base + "-title", $d.title, "Title", bold: true)
        field(ids.base + "-notes", $d.notes, "Notes")
        field(ids.base + "-url", $d.url, "URL")
    }

    private func field(_ id: String, _ text: Binding<String>, _ placeholder: String, bold: Bool = false) -> some View {
        OverlayTextBox(id: id, text: text, placeholder: placeholder, fontSize: 11, multiline: false,
                       onReturn: bold ? { ReminderDraft.shared.apply() } : nil)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .frame(height: 20)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.08)))
    }


    @ViewBuilder private var options: some View {
        row("calendar", "Date") {
            HStack(spacing: 2) {
                step("chevron.left") { d.shiftDay(-1) }
                EmperDropdown(id: ids.base + "-day", options: [], selected: nil, pick: { _ in },
                             popSize: EmperCalendar.size,
                             popover: { close in
                                 AnyView(EmperCalendar(selected: ReminderDraft.shared.day) { day in
                                     ReminderDraft.shared.day = day
                                     close()
                                 })
                             }) { value(d.dayLabel) }
                    .help("Pick a date")
                step("chevron.right") { d.shiftDay(1) }
            }
        }
        row("clock", "Time") { timeEntry }
        row("repeat", "Repeat") {
            EmperDropdown(id: ids.base + "-repeat",
                         options: ReminderDraft.Repeat.allCases.map { DropdownOption(id: $0.rawValue, label: $0.rawValue) },
                         selected: d.repeats.rawValue) { v in
                d.repeats = ReminderDraft.Repeat(rawValue: v) ?? .never
            } label: { value(d.repeats.rawValue) }
        }
    }

    /// Hour and minute boxes typed on the keyboard (click the hour, type it, the minutes follow).
    /// 12-hour clocks add an AM/PM switch; the clock style follows macOS.
    private var timeEntry: some View {
        HStack(spacing: 2) {
            TimeBox(part: .hour, text: d.hourText).help("Type the hour")
            Text(":").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Color.primary.opacity(0.6))
            TimeBox(part: .minute, text: d.minuteText).help("Type the minutes")
            if ReminderDraft.uses12h {
                Button { TimeEntry.shared.end(); d.togglePM() } label: {
                    Text(d.isPM ? "PM" : "AM").font(.system(size: 9.5, weight: .semibold))
                        .frame(width: 26, height: 18)
                        .background(Capsule().fill(Color.primary.opacity(0.1)))
                        .contentShape(Capsule())
                }
                .buttonStyle(PressScaleStyle())
                .padding(.leading, 2)
                .help("Switch AM / PM")
            }
        }
    }

    private func row<C: View>(_ symbol: String, _ label: String, @ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 9, weight: .semibold)).foregroundStyle(Color.primary.opacity(0.5))
                .frame(width: 12)
            Text(label).font(.system(size: 10, weight: .medium)).foregroundStyle(Color.primary.opacity(0.55))
            Spacer(minLength: 2)
            content()
        }
        .frame(height: 20)
    }

    private func value(_ s: String) -> some View {
        Text(s).font(.system(size: 10, weight: .semibold)).lineLimit(1)
    }

    private func step(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 8, weight: .bold))
                .frame(width: 14, height: 16).contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .foregroundStyle(Color.primary.opacity(0.6))
    }

    @ViewBuilder private func footer(narrow: Bool) -> some View {
        status
        HStack(spacing: 5) {
            Button { ReminderService.openReminders() } label: {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.up.forward.app").font(.system(size: 10, weight: .semibold))
                    if !narrow { Text("Open Reminders").font(.system(size: 10, weight: .medium)) }
                }
                .padding(.horizontal, narrow ? 0 : 8).frame(minWidth: 22, minHeight: 22)
                .background(Capsule().fill(Color.primary.opacity(0.08)))
                .contentShape(Capsule())
            }
            .buttonStyle(PressScaleStyle())
            .help("Open Reminders for lists, tags, location and more")
            Spacer(minLength: 0)
            // Round 29: Reset is an icon; Apply says what it adds.
            Button { d.reset(); d.status = .idle } label: {
                Image(systemName: "arrow.counterclockwise").font(.system(size: 10, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.primary.opacity(0.08)))
                    .contentShape(Circle())
            }
            .buttonStyle(PressScaleStyle())
            .help("Reset")
            Button { d.apply() } label: {
                HStack(spacing: 4) {
                    if d.status == .saving { ProgressView().controlSize(.mini) }
                    Text("Apply Reminder").font(.system(size: 10, weight: .semibold)).lineLimit(1)
                }
                .foregroundStyle(Color.white)
                .padding(.horizontal, 10).frame(minHeight: 22)
                .background(Capsule().fill(EditPalette.accent.opacity(d.title.isEmpty ? 0.45 : 1)))
                .contentShape(Capsule())
            }
            .buttonStyle(PressScaleStyle())
            .help("Add to Apple Reminders")
        }
    }

    @ViewBuilder private var status: some View {
        switch d.status {
        case .added(let s):
            label("checkmark.circle.fill", s, Color(nsColor: .systemGreen)).transition(.opacity)
        case .failed(let s):
            label("exclamationmark.triangle.fill", s, Color(nsColor: .systemRed))
        case .denied:
            HStack(spacing: 4) {
                label("lock.fill", "Emper can't use Reminders.", Color(nsColor: .systemOrange))
                Button("Allow…") { ReminderService.openPrivacySettings() }
                    .buttonStyle(.plain).font(.system(size: 10, weight: .semibold)).foregroundStyle(EditPalette.accent)
            }
        default:
            EmptyView()
        }
    }

    private func label(_ symbol: String, _ text: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 10, weight: .semibold)).foregroundStyle(color)
            Text(text).font(.system(size: 10, weight: .medium)).lineLimit(2).minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
