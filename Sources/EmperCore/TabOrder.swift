import Foundation

/// Reordering of a Emper's tabs from the pencil mode.
public enum TabOrder {
    /// `ids` with the element at `from` moved to `to`.
    public static func moving(_ ids: [String], from: Int, to: Int) -> [String] {
        guard ids.indices.contains(from), ids.indices.contains(to) else { return ids }
        var r = ids
        let x = r.remove(at: from)
        r.insert(x, at: to)
        return r
    }

    /// Puts the visible `order` into the saved list, keeping every other saved id in its slot.
    public static func apply(_ order: [String], to saved: [String]) -> [String] {
        let moving = Set(order)
        var it = order.makeIterator()
        return saved.map { moving.contains($0) ? (it.next() ?? $0) : $0 }
    }
}
