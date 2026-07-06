import SwiftUI

/// A compact list of a session's outstanding background work, shown on its
/// Session Overview card directly beneath the status footer. Each row is a small
/// kind icon plus the activity's label; the list caps at `maxVisible` rows and
/// summarizes any remainder as a "+N more" line so a busy session can't push the
/// card's layout around. Renders nothing when there's no background work.
struct SessionOverviewActivityListView: View {
    /// The session's aggregate background activities (subagents + backgrounded
    /// bash). Passed from `session.backgroundActivities` so the list tracks the
    /// `@Observable` aggregate and updates live.
    let activities: [BackgroundActivity]

    /// How many rows to render before collapsing the rest into "+N more".
    private let maxVisible = 4

    var body: some View {
        if !activities.isEmpty {
            let visible = activities.prefix(maxVisible)
            let overflow = activities.count - visible.count

            VStack(alignment: .leading, spacing: 2) {
                // Key rows by position, not by `BackgroundActivity.id`: two panes
                // can report the same underlying id, which would trip SwiftUI's
                // duplicate-id warning and shuffle rows.
                ForEach(Array(visible.enumerated()), id: \.offset) { _, activity in
                    HStack(spacing: 4) {
                        Image(systemName: activity.kind.systemName)
                            .font(.system(size: 9))
                        Text(activity.label)
                            .font(.system(size: 10))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if overflow > 0 {
                    Text("+\(overflow) more")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}
