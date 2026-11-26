import AppKit
import Foundation

/// One shared timer / stopwatch / pomodoro. Time is derived from dates, so nothing ticks while idle;
/// views redraw with a TimelineView. Look: B-tide (liquid fill), see `TimerModule`.
@MainActor
final class TimerService: ObservableObject {
    static let shared = TimerService()

    enum Mode: String, CaseIterable {
        case timer, stopwatch, pomodoro
        var symbol: String {
            switch self {
            case .timer: "timer"
            case .stopwatch: "stopwatch"
            case .pomodoro: "leaf"
            }
        }
        var name: String {
            switch self {
            case .timer: "Timer"
            case .stopwatch: "Stopwatch"
            case .pomodoro: "Focus"
            }
        }
    }

    @Published private(set) var mode: Mode = .timer
    @Published private(set) var startedAt: Date?
    /// Seconds counted before the current run (pause keeps them).
    @Published private(set) var banked: TimeInterval = 0
    /// Countdown length (timer mode) in seconds.
    @Published private(set) var timerLength: TimeInterval = 5 * 60
    /// Pomodoro: focus or break phase.
    @Published private(set) var onBreak = false
    @Published private(set) var finished = false

    static let focusLength: TimeInterval = 25 * 60
    static let breakLength: TimeInterval = 5 * 60
    private var endCheck: Timer?

    var isRunning: Bool { startedAt != nil }
    /// Something worth showing in the idle island (running, paused mid-way, or just finished).
    var isActive: Bool { isRunning || banked > 0 || finished }

    func elapsed(at now: Date = .now) -> TimeInterval {
        banked + (startedAt.map { now.timeIntervalSince($0) } ?? 0)
    }

    var length: TimeInterval? {
        switch mode {
        case .timer: timerLength
        case .stopwatch: nil
        case .pomodoro: onBreak ? Self.breakLength : Self.focusLength
        }
    }

    /// Shown value: remaining time for countdowns, elapsed for the stopwatch.
    func display(at now: Date = .now) -> TimeInterval {
        guard let l = length else { return elapsed(at: now) }
        return max(l - elapsed(at: now), 0)
    }

    /// 0...1 through the countdown (stopwatch: seconds within the minute).
    func progress(at now: Date = .now) -> Double {
        guard let l = length, l > 0 else { return elapsed(at: now).truncatingRemainder(dividingBy: 60) / 60 }
        return min(elapsed(at: now) / l, 1)
    }

    func toggle() {
        finished = false
        if let s = startedAt {
            banked += Date.now.timeIntervalSince(s)
            startedAt = nil
            endCheck?.invalidate()
        } else {
            startedAt = .now
            scheduleEnd()
        }
    }

    func reset() {
        startedAt = nil
        banked = 0
        finished = false
        onBreak = false
        endCheck?.invalidate()
    }

    func setMode(_ m: Mode) {
        guard m != mode else { return }
        reset()
        mode = m
    }

    func nextMode() {
        let all = Mode.allCases
        setMode(all[(all.firstIndex(of: mode)! + 1) % all.count])
    }

    static let minLength: TimeInterval = 5
    static let maxLength: TimeInterval = 180 * 60

    /// Timer mode: change the countdown by whole minutes (−/+ buttons).
    func adjust(minutes: Int) { adjust(seconds: Double(minutes * 60)) }

    /// Timer mode: change the countdown (drag scrub uses 5 s steps). Kept between 5 s and 3 h.
    func adjust(seconds: TimeInterval) {
        guard mode == .timer else { return }
        setLength(timerLength + seconds)
    }

    func setLength(_ l: TimeInterval) {
        guard mode == .timer else { return }
        let v = min(max((l / 5).rounded() * 5, Self.minLength), Self.maxLength)
        guard v != timerLength else { return }
        timerLength = v
        finished = false
        if isRunning { scheduleEnd() }
    }

    private func scheduleEnd() {
        endCheck?.invalidate()
        guard let l = length else { return }
        let left = l - elapsed()
        endCheck = Timer.scheduledTimer(withTimeInterval: max(left, 0), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.ended() }
        }
    }

    private func ended() {
        startedAt = nil
        banked = 0
        NSSound(named: "Glass")?.play()
        if mode == .pomodoro {
            onBreak.toggle()
            startedAt = .now
            scheduleEnd()
        } else {
            finished = true
        }
    }

    static func format(_ t: TimeInterval) -> String {
        let s = Int(t.rounded(.down))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }
}
