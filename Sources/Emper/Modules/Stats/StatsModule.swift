import SwiftUI
import EmperCore

/// System Stats: CPU, memory and GPU. Full view = live line chart (own tab or main placeholder);
/// compact view = a card of three meters. Click opens Activity Monitor. Samples only while on screen.
@MainActor
final class StatsModule: IslandModule {
    func makeView() -> AnyView { AnyView(StatsChartView()) }
    func makeCompactView() -> AnyView? { AnyView(StatsCompactView()) }
}

enum StatsPalette {
    static let cpu = Color(red: 0.39, green: 0.82, blue: 1)
    static let mem = Color(red: 0.75, green: 0.55, blue: 1)
    static let gpu = Color(red: 0.4, green: 0.88, blue: 0.55)
    static let hot = Color(red: 1, green: 0.42, blue: 0.38)
}

/// Keeps `SystemStats` sampling while the view is visible.
private struct SamplesWhileVisible: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onAppear { SystemStats.shared.retain() }
            .onDisappear { SystemStats.shared.release() }
    }
}

struct StatsCompactView: View {
    @ObservedObject var stats = SystemStats.shared

    var body: some View {
        Button { SystemStats.openActivityMonitor() } label: {
            VStack(alignment: .leading, spacing: 0) {
                row("CPU", stats.cpu, StatsPalette.cpu)
                Spacer(minLength: 4)
                row("MEM", stats.memory, StatsPalette.mem)
                Spacer(minLength: 4)
                row("GPU", stats.gpu, StatsPalette.gpu)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .help("Open Activity Monitor")
        .font(.system(size: 10, weight: .medium).monospacedDigit())
        .foregroundStyle(Color.primary.opacity(0.9))
        .modifier(SamplesWhileVisible())
    }

    private func row(_ label: String, _ v: Double?, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label).foregroundStyle(Color.primary.opacity(0.55))
                Spacer(minLength: 0)
                Text(v.map(StatsChartView.pct) ?? "–")
            }
            // No easing: a 0.4 s animation every 1.5 s re-laid out the whole open Emper each frame (round 21).
            Meter(value: v ?? 0, tint: color)
        }
    }
}

struct StatsChartView: View {
    @ObservedObject var stats = SystemStats.shared

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                legend("CPU", StatsChartView.pct(stats.cpu), StatsPalette.cpu)
                legend("Memory", String(format: "%.1f GB · ", stats.memoryUsedGB) + StatsChartView.pct(stats.memory), StatsPalette.mem)
                legend("GPU", stats.gpu.map(StatsChartView.pct) ?? "–", StatsPalette.gpu)
                Spacer(minLength: 0)
                Button { SystemStats.openActivityMonitor() } label: {
                    Label("Activity Monitor", systemImage: "arrow.up.forward.app")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.primary.opacity(0.6))
                }
                .buttonStyle(PressScaleStyle())
            }
            .frame(width: 112, alignment: .leading)
            LineChart(history: stats.history)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .font(.system(size: 11, weight: .medium).monospacedDigit())
        .foregroundStyle(Color.primary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(SamplesWhileVisible())
    }

    private func legend(_ name: String, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(name).foregroundStyle(Color.primary.opacity(0.6))
            Spacer(minLength: 0)
            Text(value)
        }
    }

    static func pct(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }
}

/// Three lines over the last minute and a half, 0–100 %. Gridlines at 50 % and 100 %.
struct LineChart: View {
    let history: [SystemStats.Sample]

    var body: some View {
        Canvas { ctx, size in
            let n = SystemStats.historyLength
            let step = size.width / CGFloat(max(n - 1, 1))
            for g in [0.0, 0.5, 1.0] {
                let y = size.height * (1 - g)
                var p = Path()
                p.move(to: CGPoint(x: 0, y: y))
                p.addLine(to: CGPoint(x: size.width, y: y))
                ctx.stroke(p, with: .color(Color.primary.opacity(g == 0 ? 0.18 : 0.08)), style: StrokeStyle(lineWidth: 1, dash: g == 0 ? [] : [2, 3]))
            }
            // Newest sample on the right edge.
            let offset = CGFloat(n - history.count) * step
            func line(_ value: (SystemStats.Sample) -> Double?, _ color: Color, fill: Bool) {
                var p = Path()
                var started = false
                var lastX: CGFloat = 0
                for (i, s) in history.enumerated() {
                    guard let v = value(s) else { continue }
                    let pt = CGPoint(x: offset + CGFloat(i) * step, y: size.height * (1 - min(max(v, 0), 1)))
                    if started { p.addLine(to: pt) } else { p.move(to: pt); started = true }
                    lastX = pt.x
                }
                guard started else { return }
                if fill {
                    var area = p
                    area.addLine(to: CGPoint(x: lastX, y: size.height))
                    area.addLine(to: CGPoint(x: offset, y: size.height))
                    area.closeSubpath()
                    ctx.fill(area, with: .linearGradient(Gradient(colors: [color.opacity(0.35), color.opacity(0)]),
                                                         startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                }
                ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
            line({ $0.memory }, StatsPalette.mem, fill: false)
            line({ $0.gpu }, StatsPalette.gpu, fill: false)
            line({ $0.cpu }, StatsPalette.cpu, fill: true)
        }
        .overlay(alignment: .topLeading) {
            Text("100%").font(.system(size: 8)).foregroundStyle(Color.primary.opacity(0.35)).offset(y: -10)
        }
        .padding(.top, 10)
        .drawingGroup()
    }
}

struct Meter: View {
    let value: Double
    var tint: Color = Color.primary.opacity(0.85)

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.14))
                Capsule().fill(color).frame(width: max(g.size.width * min(max(value, 0), 1), 3))
            }
        }
        .frame(height: 4)
    }

    private var color: Color { value > 0.85 ? StatsPalette.hot : tint }
}
