import SwiftUI

/// A single Mission-Control-style card in the Session Overview grid: the
/// session's status dot + name (+ orchestrator marker), a live preview of the
/// Claude pane's last output lines, and the shared sidebar status footer.
/// The whole card is tappable; the active session gets an accent stroke.
struct SessionOverviewCardView: View {
    let session: Session
    let isActive: Bool
    /// `true` when this session has ≥1 implementer nested under it — shows the
    /// `house` orchestrator marker next to the name, mirroring the sidebar row.
    /// Defaulted like `SidebarSessionRowView`'s `isOrchestrator`; the grid
    /// supplies the real value from `hierarchicalOrder()`.
    var isOrchestrator: Bool = false
    let onSelect: () -> Void

    /// Live preview of the Claude pane's last output lines, refreshed on a
    /// per-card timer (see `.task` below).
    @State private var previewText = ""
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header — status dot, name, and the orchestrator marker (matches
            // `SidebarSessionRowView`'s rule: shown only for an orchestrator).
            HStack(spacing: 8) {
                SessionDotView(state: session.aggregateClaudeState ?? .inactive)

                Text(session.displayName)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if isOrchestrator {
                    Image(systemName: "house")
                        .font(.system(size: 9))
                        .foregroundStyle(Color(white: 0.5))
                        .accessibilityLabel("orchestrator")
                }

                Spacer()
            }

            // Preview body — the Claude pane's last non-empty output lines; a
            // dimmed placeholder when there's no live surface / no output.
            let hasOutput = !previewText.isEmpty
            Text(hasOutput ? previewText : "No output")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(hasOutput ? Color.secondary : Color.secondary.opacity(0.5))
                .lineLimit(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()

            Spacer(minLength: 0)

            // Latest user prompt — the most recent question typed into the
            // Claude pane. A single truncated line with an input glyph so it
            // reads as "what the user asked", distinct from the monospaced
            // output preview above and the footer's branch text below. Omitted
            // entirely when no prompt has been captured.
            if let prompt = session.latestPrompt {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: 9))
                    Text(prompt)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Footer — the shared sidebar status line (branch + diff / PR badges
            // plus the latest free-form Claude status label).
            SessionStatusLineView(
                isActive: isActive,
                repoStatus: session.resolvedGitStatus,
                latestStatus: session.latestPaneStatus
            )
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 240, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay {
                    if isHovering {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.04))
                    }
                }
        }
        .overlay {
            if isActive {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.accentColor, lineWidth: 2)
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture { onSelect() }
        // Reads the Claude pane's visible VT text on the MainActor at ~1 Hz per
        // card — fine for a handful of sessions. If session counts grow large
        // this can move to a single shared timer tick driving every card.
        .task {
            while !Task.isCancelled {
                previewText = session.claudePreviewText(maxLines: 14)
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(session.displayName)
        .accessibilityHint("Double-tap to switch to this session.")
    }
}
