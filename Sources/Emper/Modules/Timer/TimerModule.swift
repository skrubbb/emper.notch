import SwiftUI
import EmperCore

/// Timer / stopwatch / focus in the B-tide look: progress is a liquid that fills the card.
/// The layout is identical in every mode (the −/+ space is always reserved, visible only for the
/// timer), so clicking through the modes never moves a button away from the pointer.
@MainActor
final class TimerModule: IslandModule {
    func makeView() -> AnyView { AnyView(TideMainView()) }
    func makeCompactView() -> AnyView? { AnyView(TideSideView()) }
}

@MainActor
enum Tide {
    static let light = Color(red: 0.39, green: 0.82, blue: 1)    // #64D2FF
    static let deep = Color(red: 0.04, green: 0.52, blue: 1)     // #0A84FF
    static let warn = Color(red: 1, green: 0.78, blue: 0.3)
    /// Drag distance for one 5-second step.
    static let scrubStep: CGFloat = 6

    static func label(_ t: TimerService) -> String {
        t.mode == .pomodoro ? (t.onBreak ? "Break" : "Focus") : t.mode.name
    }

    /// Redraw rate: once a second while running (the digits change per second). No progress ring (round 22: lighter).
    /// 8 fps re-laid out the whole open Emper, and a gliding ring animation redrew every frame (round 21).
    static func schedule(_ running: Bool) -> SecondTicks { SecondTicks(paused: !running) }

    /// Idle island: the same shared one-second tick.
    static func idleSchedule(_ running: Bool) -> SecondTicks { SecondTicks(paused: !running) }
}

/// One tick per wall-clock second, shared by every view that uses it (timer digits, seek-bar times), so
/// the open Emper is laid out once a second instead of once per view at scattered moments.
struct SecondTicks: TimelineSchedule {
    var paused = false

    func entries(from start: Date, mode: TimelineScheduleMode) -> AnyIterator<Date> {
        var next: Date? = start
        let paused = paused
        return AnyIterator {
            guard let d = next else { return nil }
            next = paused ? nil : Date(timeIntervalSinceReferenceDate: d.timeIntervalSinceReferenceDate.rounded(.down) + 1)
            return d
        }
    }
}


/// Liquid surface. `vertical` = fills bottom-up (side card); otherwise left-to-right (main).
struct TideLiquid: View {
    let level: Double
    let phase: Double
    let vertical: Bool
    var handle = true

    var body: some View {
        Canvas { ctx, size in
            let l = CGFloat(min(max(level, 0), 1))
            guard l > 0 else { return }
            let amp: CGFloat = 2.5
            var p = Path()
            if vertical {
                let top = size.height * (1 - l)
                p.move(to: CGPoint(x: 0, y: size.height))
                p.addLine(to: CGPoint(x: 0, y: top))
                for x in stride(from: CGFloat(0), through: size.width, by: 3) {
                    p.addLine(to: CGPoint(x: x, y: top + amp * sin(x / size.width * 2 * .pi * 1.5 + phase)))
                }
                p.addLine(to: CGPoint(x: size.width, y: size.height))
            } else {
                let edge = size.width * l
                p.move(to: CGPoint(x: 0, y: 0))
                p.addLine(to: CGPoint(x: edge, y: 0))
                for y in stride(from: CGFloat(0), through: size.height, by: 3) {
                    p.addLine(to: CGPoint(x: edge + amp * sin(y / size.height * 2 * .pi + phase), y: y))
                }
                p.addLine(to: CGPoint(x: 0, y: size.height))
            }
            p.closeSubpath()
            let g = Gradient(colors: [Tide.light.opacity(0.55), Tide.deep.opacity(0.35)])
            ctx.fill(p, with: .linearGradient(g, startPoint: .zero,
                                              endPoint: vertical ? CGPoint(x: 0, y: size.height) : CGPoint(x: size.width, y: 0)))
            // Surface line + handle.
            var surface = Path()
            if vertical {
                let top = size.height * (1 - l)
                surface.move(to: CGPoint(x: 0, y: top))
                for x in stride(from: CGFloat(0), through: size.width, by: 3) {
                    surface.addLine(to: CGPoint(x: x, y: top + amp * sin(x / size.width * 2 * .pi * 1.5 + phase)))
                }
            } else {
                let edge = size.width * l
                surface.move(to: CGPoint(x: edge, y: 0))
                for y in stride(from: CGFloat(0), through: size.height, by: 3) {
                    surface.addLine(to: CGPoint(x: edge + amp * sin(y / size.height * 2 * .pi + phase), y: y))
                }
            }
            ctx.stroke(surface, with: .color(Tide.light), lineWidth: 1.5)
            guard handle else { return }
            let knob = vertical
                ? CGRect(x: size.width / 2 - 10, y: size.height * (1 - l) - 2, width: 20, height: 4)
                : CGRect(x: size.width * l - 2, y: size.height / 2 - 10, width: 4, height: 20)
            ctx.fill(Path(roundedRect: knob, cornerRadius: 2), with: .color(Color.primary.opacity(0.9)))
        }
        .allowsHitTesting(false)
    }
}

/// Main placeholder / own tab: 384×110 class.
struct TideMainView: View {
    @ObservedObject var t = TimerService.shared
    @StateObject private var scrub = ScrubState()

    var body: some View {
        TimelineView(Tide.schedule(t.isRunning)) { ctx in
            let now = ctx.date
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(Color.primary.opacity(0.05))
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 2) {
                        modeTabs
                        Text(TimerService.format(t.display(at: now)))
                            .font(.system(size: 40, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(t.finished ? Tide.warn : Color.primary)
                            .lineLimit(1).minimumScaleFactor(0.6)
                            .contentShape(Rectangle())
                            .gesture(scrubGesture)
                            .help(t.mode == .timer && !t.isRunning ? "Drag left/right: ±5 s" : "")
                    }
                    .padding(.leading, 14)
                    Spacer(minLength: 8)
                    controls.padding(.trailing, 14)
                }
            }
        }
        .foregroundStyle(Color.primary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var modeTabs: some View {
        HStack(spacing: 12) {
            ForEach(TimerService.Mode.allCases, id: \.self) { m in
                let on = m == t.mode
                Button { t.setMode(m) } label: {
                    Text(m.name)
                        .font(.system(size: 11, weight: on ? .semibold : .medium))
                        .foregroundStyle(Color.primary.opacity(on ? 1 : 0.5))
                        .padding(.vertical, 3)
                        .overlay(alignment: .bottom) {
                            Capsule().fill(Color.primary).frame(height: 2).opacity(on ? 1 : 0)
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var controls: some View {
        let adjustable = t.mode == .timer
        return HStack(spacing: 8) {
            // Always laid out; hidden outside timer mode so nothing shifts.
            VStack(spacing: 2) {
                HStack(spacing: 6) {
                    circle("minus") { t.adjust(minutes: -1) }
                    circle("plus") { t.adjust(minutes: 1) }
                }
                Text("−/+ min").font(.system(size: 8, weight: .medium)).foregroundStyle(Color.primary.opacity(0.45))
            }
            .opacity(adjustable ? 1 : 0)
            .allowsHitTesting(adjustable)
            circle("arrow.counterclockwise") { t.reset() }
                .opacity(t.isActive ? 1 : 0.45)
            Button { t.toggle() } label: {
                Image(systemName: t.isRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.islandFill)
                    .frame(width: 62, height: 32)
                    .background(Capsule().fill(Color.primary))
                    .contentShape(Capsule())
            }
            .buttonStyle(PressScaleStyle())
            .help(t.isRunning ? "Pause" : "Start")
        }
    }

    private var scrubGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { v in
                guard t.mode == .timer, !t.isRunning else { return }
                let steps = Int((v.translation.width / Tide.scrubStep).rounded(.towardZero))
                let base = scrub.base ?? t.timerLength
                scrub.base = base
                t.setLength(base + Double(steps) * 5)
            }
            .onEnded { _ in scrub.base = nil }
    }

    private func circle(_ s: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: s).font(.system(size: 11, weight: .bold))
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.primary.opacity(0.14)))
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle())
    }
}

final class ScrubState: ObservableObject {
    var base: TimeInterval?
}

/// Side placeholder card: liquid rises from the bottom.
struct TideSideView: View {
    @ObservedObject var t = TimerService.shared
    @StateObject private var scrub = ScrubState()

    var body: some View {
        TimelineView(Tide.schedule(t.isRunning)) { ctx in
            let now = ctx.date
            ZStack {
                VStack(spacing: 4) {
                    Text(Tide.label(t).uppercased())
                        .font(.system(size: 9, weight: .semibold)).tracking(0.8)
                        .foregroundStyle(Color.primary.opacity(0.6))
                    Text(TimerService.format(t.display(at: now)))
                        .font(.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(t.finished ? Tide.warn : Color.primary)
                        .lineLimit(1).minimumScaleFactor(0.5)
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 2)
                            .onChanged { v in
                                guard t.mode == .timer, !t.isRunning else { return }
                                let base = scrub.base ?? t.timerLength
                                scrub.base = base
                                t.setLength(base + Double(Int((v.translation.width / Tide.scrubStep).rounded(.towardZero))) * 5)
                            }
                            .onEnded { _ in scrub.base = nil })
                    Spacer(minLength: 0)
                    HStack(spacing: 4) {
                        small("arrow.counterclockwise") { t.reset() }.opacity(t.isActive ? 1 : 0.45)
                        Button { t.toggle() } label: {
                            Image(systemName: t.isRunning ? "pause.fill" : "play.fill")
                                .font(.system(size: 10, weight: .bold)).foregroundStyle(Color.islandFill)
                                .frame(width: 30, height: 20)
                                .background(Capsule().fill(Color.primary))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(PressScaleStyle())
                        small(t.mode.symbol) { t.nextMode() }.help("Timer · Stopwatch · Focus")
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .foregroundStyle(Color.primary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func small(_ s: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: s).font(.system(size: 9, weight: .bold))
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.primary.opacity(0.14)))
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle())
    }
}

/// Idle island while the timer is active: the liquid wave across the pill, the label on the left
/// wing, time + play/pause together on the right (the centre may sit under a physical notch). The wave redraws only while
/// running. The play/pause button is outside the hover zone: it works without opening the island.
struct TideIdleStrip: View {
    @ObservedObject var t = TimerService.shared
    let config: IslandConfig
    /// Bottom Emper: idle length kept, time centred, play/pause at the end.
    var compact = false

    private func time(_ now: Date) -> some View {
        Text(TimerService.format(t.display(at: now)))
            .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(t.finished ? Tide.warn : Color.primary)
            .multilineTextAlignment(.center)
            .lineLimit(1).minimumScaleFactor(0.7)
    }

    var body: some View {
        TimelineView(Tide.idleSchedule(t.isRunning)) { ctx in
            let now = ctx.date
            if compact {
                ZStack {
                    time(now).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    HStack { Spacer(minLength: 0); TimerPlayButton() }.padding(.trailing, 6)
                }
            } else {
                // Each wing centres its own content: label on the left, time (+ play/pause) on the right.
                HStack(spacing: 0) {
                    Text(Tide.label(t).uppercased())
                        .font(.system(size: 9, weight: .semibold)).tracking(0.6)
                        .foregroundStyle(Color.primary.opacity(0.6))
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, alignment: .center)
                    Color.clear.frame(width: CGFloat(config.collapsedWidth))
                    HStack(spacing: 4) {
                        time(now).frame(maxWidth: .infinity, alignment: .center)
                        TimerPlayButton()
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 8)
                .frame(maxHeight: .infinity)
            }
        }
    }
}

/// Idle liquid, same look as the open timer: two water layers that fill bottom-up and only roll
/// sideways (no vertical motion). A low base level shows the wave from the first second; elapsed time
/// raises it.
struct TideIdleWave: View {
    let level: Double
    let phase: Double

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let l = 0.28 + 0.5 * CGFloat(min(max(level, 0), 1))
            let top = h * (1 - l)
            func surface(_ base: CGFloat, amp: CGFloat, shift: Double) -> Path {
                var p = Path()
                p.move(to: CGPoint(x: 0, y: base + amp * sin(phase + shift)))
                for x in stride(from: CGFloat(3), through: w + 3, by: 3) {
                    p.addLine(to: CGPoint(x: x, y: base + amp * sin(x / max(w, 1) * 2 * .pi * max(w / 60, 1.5) + phase + shift)))
                }
                return p
            }
            func body(_ s: Path) -> Path {
                var p = s
                p.addLine(to: CGPoint(x: w + 3, y: h))
                p.addLine(to: CGPoint(x: 0, y: h))
                p.closeSubpath()
                return p
            }
            let back = surface(top - 2, amp: 2, shift: 1.6)
            ctx.fill(body(back), with: .color(Tide.deep.opacity(0.35)))
            let front = surface(top, amp: 2.2, shift: 0)
            ctx.fill(body(front), with: .linearGradient(Gradient(colors: [Tide.light.opacity(0.5), Tide.deep.opacity(0.4)]),
                                                        startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: h)))
            ctx.stroke(front, with: .color(Tide.light.opacity(0.9)), lineWidth: 1.2)
        }
        .allowsHitTesting(false)
    }
}

/// Idle play/pause for the timer (bell when it has finished: click resets).
struct TimerPlayButton: View {
    @ObservedObject var t = TimerService.shared
    @StateObject private var hover = HoverFlag()

    /// Idle: a timer mark until the pointer is on it (so it never reads as the song's play/pause).
    private var symbol: String {
        if t.finished { return "bell.fill" }
        if !hover.on { return "timer" }
        return t.isRunning ? "pause.fill" : "play.fill"
    }

    var body: some View {
        Button { t.finished ? t.reset() : t.toggle() } label: {
            Group {
                // Own drawing: the SF "timer" symbol sat low in the circle (round 22).
                if symbol == "timer" { StopwatchGlyph(size: 11) }
                else { Image(systemName: symbol).font(.system(size: 10, weight: .bold)) }
            }
                .foregroundStyle(Color.primary.opacity(0.9))
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.primary.opacity(0.14)))
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle())
        .onHover { hover.on = $0 }
        .help(t.isRunning ? "Pause timer" : "Start timer")
    }
}

/// Timer body joined to the music live activity: wave, time and play/pause together.
struct TimerChip: View {
    @ObservedObject var t = TimerService.shared

    var body: some View {
        TimelineView(Tide.idleSchedule(t.isRunning)) { ctx in
            let now = ctx.date
            ZStack {
                HStack(spacing: 2) {
                    // Time centred in the room left of the play/pause button.
                    Text(TimerService.format(t.display(at: now)))
                        .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(t.finished ? Tide.warn : Color.primary)
                        .multilineTextAlignment(.center)
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, alignment: .center)
                    TimerPlayButton()
                }
                .padding(.leading, 12).padding(.trailing, 7)
                .frame(maxHeight: .infinity)
            }
        }
    }
}

/// Stopwatch mark drawn from shapes so the whole mark (crown + dial) sits exactly in the middle of
/// its frame, like CrossGlyph. `size` is the full height including the crown.
struct StopwatchGlyph: View {
    let size: CGFloat

    var body: some View {
        let line = max(size * 0.15, 1.4)
        let crown = size * 0.16
        let dial = size - crown - line * 0.3
        ZStack(alignment: .top) {
            Capsule().frame(width: size * 0.34, height: line)
            Circle().strokeBorder(lineWidth: line)
                .frame(width: dial, height: dial)
                .overlay {
                    // Hand from the centre toward 12 o'clock.
                    Capsule().frame(width: line, height: dial * 0.32)
                        .offset(y: -dial * 0.14)
                }
                .padding(.top, size - dial)
        }
        .frame(width: size, height: size)
    }
}
