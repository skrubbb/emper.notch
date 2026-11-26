import AppKit
import SwiftUI
import EmperCore

@MainActor
final class CalculatorModule: ObservableObject, IslandModule {
    @Published var engine = CalculatorEngine()

    func makeView() -> AnyView { AnyView(CalculatorView(module: self)) }
    func makeCompactView() -> AnyView? { AnyView(CalculatorCompactView(module: self)) }

    /// Keyboard: digits, . , + - * x / = Return % c Escape Delete. False = not a calculator key.
    func type(_ event: NSEvent) -> Bool {
        if event.modifierFlags.intersection([.command, .control, .option]).isEmpty == false { return false }
        let key: String
        switch event.keyCode {
        case 36, 76: key = "enter"
        case 53: key = "escape"
        case 51, 117: key = "delete"
        default: key = event.charactersIgnoringModifiers ?? ""
        }
        return engine.type(key)
    }
}

struct CalculatorView: View {
    @ObservedObject var module: CalculatorModule

    private enum Key: Hashable {
        case digit(Int), dot, op(CalculatorEngine.Op), equals, clear, sign, percent

        var label: String {
            switch self {
            case .digit(let d): "\(d)"
            case .dot: "."
            case .op(let o): o.rawValue
            case .equals: "="
            case .clear: "AC"
            case .sign: "±"
            case .percent: "%"
            }
        }
    }

    var body: some View {
        GeometryReader { geo in
            let wide = CalculatorLayout.isWide(width: geo.size.width)
            let rows = wide ? Self.wideRows : Self.narrowRows
            let g = CalculatorLayout.gap
            let w = (geo.size.width - g * CGFloat(rows[0].count - 1)) / CGFloat(rows[0].count)
            // Keys share whatever height is left under the display (the island size is the same for every tab).
            let h = max((geo.size.height - CalculatorLayout.displayHeight - g * CGFloat(rows.count)) / CGFloat(rows.count), 14)
            VStack(spacing: g) {
                Text(module.engine.display)
                    .font(.system(size: 20, weight: .light, design: .rounded).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .frame(height: CalculatorLayout.displayHeight)
                    .padding(.horizontal, 4)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.18), value: module.engine.display)
                ForEach(rows.indices, id: \.self) { r in
                    HStack(spacing: g) {
                        ForEach(rows[r], id: \.self) { k in
                            key(k, width: k == .digit(0) && rows[r].count < rows[0].count ? w * 2 + g : w, height: h)
                        }
                    }
                }
            }
        }
        .foregroundStyle(Color.primary)
    }

    /// 4 columns: the classic layout.
    private static let narrowRows: [[Key]] = [
        [.clear, .sign, .percent, .op(.divide)],
        [.digit(7), .digit(8), .digit(9), .op(.multiply)],
        [.digit(4), .digit(5), .digit(6), .op(.subtract)],
        [.digit(1), .digit(2), .digit(3), .op(.add)],
        [.digit(0), .dot, .equals],
    ]

    /// 5 columns, one row less: for wide, shallow islands.
    private static let wideRows: [[Key]] = [
        [.digit(7), .digit(8), .digit(9), .op(.divide), .clear],
        [.digit(4), .digit(5), .digit(6), .op(.multiply), .sign],
        [.digit(1), .digit(2), .digit(3), .op(.subtract), .percent],
        [.digit(0), .dot, .op(.add), .equals],
    ]

    private func key(_ k: Key, width: CGFloat, height: CGFloat) -> some View {
        Button { press(k) } label: {
            Text(k.label)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .frame(width: width, height: height)
                .background(Capsule().fill(fill(k)))
                .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle())
    }

    private func fill(_ k: Key) -> Color {
        switch k {
        case .op(let o) where module.engine.pending == o: Color.primary.opacity(0.85)
        case .op, .equals: Color.orange
        case .clear, .sign, .percent: Color.primary.opacity(0.22)
        default: Color.primary.opacity(0.12)
        }
    }

    private func press(_ k: Key) {
        switch k {
        case .digit(let d): module.engine.digit(d)
        case .dot: module.engine.decimal()
        case .op(let o): module.engine.operation(o)
        case .equals: module.engine.equals()
        case .clear: module.engine.clear()
        case .sign: module.engine.toggleSign()
        case .percent: module.engine.percent()
        }
    }
}

/// Calculator layout: 5 columns (one row less) once the island is wide enough. Its size is the island's
/// shared module size (`ModuleRegistry.uniform`).
enum CalculatorLayout {
    static let gap: CGFloat = 4
    static let displayHeight: CGFloat = 22
    static let wideFrom: CGFloat = 250

    static func isWide(width: CGFloat) -> Bool { width >= wideFrom }

}

/// Side placeholder: display + 4×4 keypad (tap the display to clear). Typing works here too while Home is open.
struct CalculatorCompactView: View {
    @ObservedObject var module: CalculatorModule
    private static let keys: [[String]] = [["7", "8", "9", "÷"], ["4", "5", "6", "×"], ["1", "2", "3", "−"], ["0", ".", "=", "+"]]

    var body: some View {
        GeometryReader { g in
            let gap: CGFloat = 3, disp: CGFloat = 18
            let w = (g.size.width - 3 * gap) / 4
            let h = max((g.size.height - disp - 4 * gap) / 4, 10)
            VStack(spacing: gap) {
                Button { module.engine.clear() } label: {
                    Text(module.engine.display)
                        .font(.system(size: 13, weight: .medium, design: .rounded).monospacedDigit())
                        .lineLimit(1).minimumScaleFactor(0.4)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .frame(height: disp)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Click to clear")
                ForEach(Self.keys, id: \.self) { row in
                    HStack(spacing: gap) {
                        ForEach(row, id: \.self) { k in
                            Button { _ = module.engine.type(Self.engineKey(k)) } label: {
                                Text(k).font(.system(size: 10, weight: .medium, design: .rounded))
                                    .frame(width: w, height: h)
                                    .background(RoundedRectangle(cornerRadius: 5).fill(Self.isOp(k) ? Color.orange : Color.primary.opacity(0.12)))
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(PressScaleStyle())
                        }
                    }
                }
            }
        }
        .foregroundStyle(Color.primary)
    }

    private static func isOp(_ k: String) -> Bool { "÷×−+=".contains(k) }

    private static func engineKey(_ k: String) -> String {
        switch k {
        case "÷": "/"
        case "×": "*"
        case "−": "-"
        default: k
        }
    }
}
