import SwiftUI

/// Compact pill shown in a sidebar session row when the session has outstanding
/// background work — Claude subagents and/or `run_in_background` bash commands
/// still running after the foreground turn went quiet. Renders nothing when
/// `activities` is empty.
///
/// Sits quietly beside the row's other markers: an SF Symbol keyed to the
/// activity mix plus the count, in a subtle secondary pill matching
/// `ChangeBadgeView`'s sizing / corner-radius idiom.
struct BackgroundActivityBadgeView: View {
    let activities: [BackgroundActivity]

    /// SF Symbol for the current mix. When every activity shares one kind, defer
    /// to that kind's own glyph (`BackgroundActivity.Kind.systemName`); a mix of
    /// kinds collapses to a neutral "work in flight" glyph. Only the aggregate /
    /// mixed decision is view-specific — single-kind glyphs come from the model.
    private var systemName: String {
        guard let first = activities.first?.kind,
              activities.allSatisfy({ $0.kind == first }) else {
            return "bolt.horizontal.circle"
        }
        return first.systemName
    }

    var body: some View {
        if !activities.isEmpty {
            HStack(spacing: 3) {
                Image(systemName: systemName)
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
            .accessibilityLabel("\(activities.count) background \(activities.count == 1 ? "task" : "tasks") running")
        }
    }
}
