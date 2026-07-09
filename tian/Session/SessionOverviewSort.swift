import Foundation

/// Card ordering for the session overview grid. Raw values are the segment labels.
enum SessionOverviewSortMode: String, CaseIterable, Identifiable {
    case defaultOrder = "Default"
    case sessionState = "Session State"
    var id: String { rawValue }
    var label: String { rawValue }
}

enum SessionOverviewSort {
    /// Stable ordering of `items` for `mode`.
    /// - `.defaultOrder` → `items` unchanged (the caller's default order).
    /// - `.sessionState` → by `ClaudeSessionState` priority, most-urgent first
    ///   (needsAttention > failed > busy > active > idle), with `nil` ("fresh") last.
    ///   Stable: equal-state items keep their input (default-order) relative order.
    static func ordered<T>(
        _ items: [T],
        mode: SessionOverviewSortMode,
        state: (T) -> ClaudeSessionState?
    ) -> [T] {
        guard mode == .sessionState else { return items }
        return items.enumerated()
            .map { (offset: $0.offset, element: $0.element, key: state($0.element)) }
            .sorted { lhs, rhs in
                if lhs.key == rhs.key { return lhs.offset < rhs.offset }   // stability
                guard let a = lhs.key else { return false }                // nil == fresh == last
                guard let b = rhs.key else { return true }
                return a > b                                               // higher-priority state first
            }
            .map(\.element)
    }
}
