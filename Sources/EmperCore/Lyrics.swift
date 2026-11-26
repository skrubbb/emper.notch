import Foundation

public struct LyricLine: Equatable, Sendable {
    public let time: Double
    public let text: String
    /// A second line some LRC files carry at the same timestamp (usually a translation or romanization).
    public let translation: String?
    public init(time: Double, text: String, translation: String? = nil) {
        self.time = time; self.text = text; self.translation = translation
    }
}

/// Parser for LRC synced lyrics ("[01:23.45] line"). Multiple time tags per line are allowed.
public enum LRC {
    public static func parse(_ s: String) -> [LyricLine] {
        var out: [LyricLine] = []
        for raw in s.split(whereSeparator: \.isNewline) {
            var rest = Substring(raw)
            var times: [Double] = []
            while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
                let tag = rest[rest.index(after: rest.startIndex)..<close]
                let parts = tag.split(separator: ":")
                if parts.count == 2, let m = Double(parts[0]), let sec = Double(parts[1]) {
                    times.append(m * 60 + sec)
                }
                rest = rest[rest.index(after: close)...]
            }
            var text = rest.trimmingCharacters(in: .whitespaces)
            var translation: String?
            // lrclib files often carry "original^translation" on one line.
            if let caret = text.firstIndex(of: "^") {
                let a = text[..<caret].trimmingCharacters(in: .whitespaces)
                let b = text[text.index(after: caret)...].trimmingCharacters(in: .whitespaces)
                if !a.isEmpty, !b.isEmpty { text = a; translation = b }
            }
            for t in times { out.append(LyricLine(time: t, text: text, translation: translation)) }
        }
        // Stable sort, then fold lines sharing a timestamp: the first is the lyric, the rest its translation.
        let sorted = out.enumerated().sorted { ($0.element.time, $0.offset) < ($1.element.time, $1.offset) }.map(\.element)
        var merged: [LyricLine] = []
        for l in sorted {
            if let last = merged.last, abs(last.time - l.time) < 0.005, !l.text.isEmpty, !last.text.isEmpty {
                let t = [last.translation, l.text].compactMap { $0 }.joined(separator: " / ")
                merged[merged.count - 1] = LyricLine(time: last.time, text: last.text, translation: t)
            } else {
                merged.append(l)
            }
        }
        return merged
    }

    /// Index of the line being sung at `time`, or nil before the first line.
    public static func index(at time: Double, in lines: [LyricLine]) -> Int? {
        var lo = 0, hi = lines.count - 1, found: Int?
        while lo <= hi {
            let mid = (lo + hi) / 2
            if lines[mid].time <= time { found = mid; lo = mid + 1 } else { hi = mid - 1 }
        }
        return found
    }
}
