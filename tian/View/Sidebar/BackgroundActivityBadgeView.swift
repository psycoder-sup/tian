import SwiftUI

/// Compact pill shown in a sidebar session row when the session has outstanding
/// background work — Claude subagents, teammates, and/or `run_in_background`
/// bash commands still running after the foreground turn went quiet. Renders
/// nothing when `activities` is empty.
///
/// Sits quietly beside the row's other markers: an SF Symbol keyed to the
/// activity mix plus the count, in a subtle secondary pill matching
/// `ChangeBadgeView`'s sizing / corner-radius idiom.
struct BackgroundActivityBadgeView: View {
    let activities: [BackgroundActivity]

    /// SF Symbol for the current mix, chosen by *dominant semantic category*
    /// rather than requiring every activity to share one kind — an ordinary turn
    /// that has both a subagent and a teammate running must still read as
    /// team-mode busy, not collapse to the neutral glyph. Precedence: any
    /// `.teammate` present wins outright (a team is the strongest signal, even
    /// alongside agents/bash); else any `.agent` wins; else an all-`.bash` mix
    /// gets its own glyph; anything else (a genuine agent/teammate-less mix, or
    /// `.other`) falls back to the neutral "work in flight" glyph.
    ///
    /// Deliberately does not defer to `BackgroundActivity.Kind.systemName` for
    /// this decision — the model owns each kind's own single-kind glyph, this
    /// view owns the aggregate / mixed decision. `internal` (not `private`) so
    /// it's unit-testable without hosting the view.
    static func glyph(for activities: [BackgroundActivity]) -> String {
        guard !activities.isEmpty else { return "bolt.horizontal.circle" }
        if activities.contains(where: { $0.kind == .teammate }) {
            return "person.3.fill"
        }
        if activities.contains(where: { $0.kind == .agent }) {
            return "person.2.fill"
        }
        if activities.allSatisfy({ $0.kind == .bash }) {
            return "terminal"
        }
        return "bolt.horizontal.circle"
    }

    /// Aggregate VoiceOver label for the current mix — e.g. "2 subagents, 1
    /// teammate running" — instead of a flat "N background tasks running" that
    /// would erase exactly the agent-vs-teammate distinction the glyph now
    /// conveys. Groups by kind (declaration order: agent, teammate, bash,
    /// other), singular/plural per group, and joins the non-empty groups with
    /// ", ". `internal` (not `private`) so it's unit-testable without hosting
    /// the view.
    static func accessibilityText(for activities: [BackgroundActivity]) -> String {
        let order: [BackgroundActivity.Kind] = [.agent, .teammate, .bash, .other]
        let clauses = order.compactMap { kind -> String? in
            let count = activities.filter { $0.kind == kind }.count
            guard count > 0 else { return nil }
            return "\(count) \(kindNoun(kind, count: count))"
        }
        guard !clauses.isEmpty else { return "" }
        return "\(clauses.joined(separator: ", ")) running"
    }

    /// Singular/plural noun for one `accessibilityText` clause.
    private static func kindNoun(_ kind: BackgroundActivity.Kind, count: Int) -> String {
        switch kind {
        case .agent: count == 1 ? "subagent" : "subagents"
        case .teammate: count == 1 ? "teammate" : "teammates"
        case .bash: count == 1 ? "background task" : "background tasks"
        case .other: count == 1 ? "task" : "tasks"
        }
    }

    var body: some View {
        if !activities.isEmpty {
            HStack(spacing: 3) {
                Image(systemName: Self.glyph(for: activities))
                    .font(.system(size: 8, weight: .medium))

                Text("\(activities.count)")
                    .font(.system(size: 9, weight: .medium))
                    .monospacedDigit()
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            // Theme-adaptive neutral fill (matches ChangeBadgeView's badge +
            // clip idiom): visible in both Light and Dark, unlike a hardcoded
            // white wash that vanishes on a light row.
            .background(.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Self.accessibilityText(for: activities))
        }
    }
}
