import Foundation

/// Basic immediate-execution calculator (like the macOS basic calculator, without precedence).
public struct CalculatorEngine: Equatable, Sendable {
    public enum Op: String, Sendable { case add = "+", subtract = "−", multiply = "×", divide = "÷" }

    public private(set) var display = "0"
    public private(set) var pending: Op?
    private var accumulator: Double?
    private var startNew = true        // next digit replaces the display
    private var operandEntered = false // user entered a value since the last operator

    public init() {}

    public var value: Double { Double(display) ?? 0 }

    public mutating func digit(_ d: Int) {
        guard (0...9).contains(d) else { return }
        if startNew || display == "0" || display == "Error" {
            display = String(d)
            startNew = false
        } else if display.filter(\.isNumber).count < 15 {
            display += String(d)
        }
        operandEntered = true
    }

    public mutating func decimal() {
        if startNew || display == "Error" {
            display = "0."
            startNew = false
        } else if !display.contains(".") {
            display += "."
        }
        operandEntered = true
    }

    public mutating func operation(_ op: Op) {
        if let p = pending, let acc = accumulator, operandEntered {
            let r = Self.apply(p, acc, value)
            show(r)
            accumulator = r.isFinite ? r : nil
        } else if pending == nil {
            accumulator = value
        }
        pending = op
        startNew = true
        operandEntered = false
    }

    public mutating func equals() {
        guard let p = pending, let acc = accumulator else { return }
        let r = Self.apply(p, acc, value)
        show(r)
        accumulator = r.isFinite ? r : nil
        pending = nil
        startNew = true
        operandEntered = false
    }

    public mutating func clear() { self = CalculatorEngine() }

    /// Delete the last typed digit (keyboard Delete). Does nothing on a result.
    public mutating func backspace() {
        guard !startNew, display != "Error" else { return }
        display.removeLast()
        if display.isEmpty || display == "-" || display == "-0" { display = "0" }
    }

    /// Keyboard input: digits, . or , , + - * x / , = or Return, % , c / Escape (clear), Delete.
    /// Returns false for keys the calculator does not use.
    public mutating func type(_ key: String) -> Bool {
        switch key {
        case "0"..."9" where key.count == 1: digit(Int(key)!)
        case ".", ",": decimal()
        case "+": operation(.add)
        case "-": operation(.subtract)
        case "*", "x", "X": operation(.multiply)
        case "/": operation(.divide)
        case "=", "\r", "enter": equals()
        case "%": percent()
        case "c", "C", "escape": clear()
        case "delete": backspace()
        default: return false
        }
        return true
    }

    public mutating func toggleSign() {
        guard display != "0", display != "Error" else { return }
        display = display.hasPrefix("-") ? String(display.dropFirst()) : "-" + display
        operandEntered = true
    }

    public mutating func percent() {
        show(value / 100)
        startNew = true
        operandEntered = true
    }

    private mutating func show(_ r: Double) {
        display = Self.format(r)
    }

    static func apply(_ op: Op, _ a: Double, _ b: Double) -> Double {
        switch op {
        case .add: a + b
        case .subtract: a - b
        case .multiply: a * b
        case .divide: b == 0 ? .nan : a / b
        }
    }

    public static func format(_ r: Double) -> String {
        guard r.isFinite else { return "Error" }
        if r == r.rounded(), abs(r) < 1e15 { return String(Int64(r)) }
        return String(format: "%.10g", r)
    }
}
