import SwiftUI

/// A single Mission-Control-style card in the Session Overview grid: the
/// session's name (+ orchestrator marker), a live preview of the Claude pane's
/// last output lines, and the shared sidebar status footer. The whole card is
/// tappable. The card's border color encodes the session's aggregate Claude
/// status; keyboard selection and the active session are shown via a subtle
/// background highlight (and, for selection, a slight scale-up + lift shadow)
/// rather than a competing accent ring.
struct SessionOverviewCardView: View {
    let session: Session
    let isActive: Bool
    /// `true` when this card is the keyboard-selected one in the overview grid.
    let isSelected: Bool
    /// `true` when this session has ≥1 implementer nested under it — shows the
    /// `house` orchestrator marker next to the name, mirroring the sidebar row.
    /// Defaulted like `SidebarSessionRowView`'s `isOrchestrator`; the grid
    /// supplies the real value from `hierarchicalOrder()`.
    var isOrchestrator: Bool = false
    /// Drives inline rename of the session name when the overview's `R` shortcut
    /// targets this (selected) card. Cleared on commit/cancel by `InlineRenameView`.
    @Binding var isRenaming: Bool
    /// Drives the delete-confirmation popover when the overview's `D` shortcut
    /// arms this (selected) card. Set to `false` by Cancel / click-away, which the
    /// grid observes to clear its pending id.
    @Binding var isConfirmingDelete: Bool
    /// Invoked by the popover's Delete button (and Return) to run the shared close
    /// flow. The grid clears `isConfirmingDelete` as part of this.
    let onConfirmDelete: () -> Void
    let onSelect: () -> Void

    /// Live preview of the Claude pane's last output lines, refreshed on a
    /// per-card timer (see `.task` below).
    @State private var previewText = ""
    @State private var isHovering = false

    /// The card's border color: the session's aggregate Claude status, or a
    /// faint neutral edge when inactive (no status to show).
    private var borderColor: Color {
        session.aggregateClaudeState?.overviewBorderColor ?? Color.white.opacity(0.12)
    }

    /// Background wash that signals "where you are": brightest for the
    /// keyboard-selected card, a clearly-perceptible-but-dimmer wash for the
    /// active session when it isn't selected, and the faintest whisper on hover.
    /// The ordering is deliberate — active must read stronger than a mere hover.
    /// Selection and active never both apply to the same card, so they can't stack.
    private var highlightColor: Color {
        if isSelected { return Color.white.opacity(0.09) }
        if isActive { return Color.white.opacity(0.05) }
        if isHovering { return Color.white.opacity(0.03) }
        return .clear
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header — name and the orchestrator marker (matches
            // `SidebarSessionRowView`'s rule: shown only for an orchestrator).
            // Status is carried by the card border, not a dot.
            HStack(spacing: 8) {
                InlineRenameView(
                    text: session.displayName,
                    isRenaming: $isRenaming,
                    font: .headline,
                    // Matches the sidebar row: empty resets to the auto-derived name.
                    onCommit: { session.customName = $0.isEmpty ? nil : $0 }
                )
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

            // Background work — outstanding subagents / backgrounded bash for this
            // session. Additive and self-hiding: renders nothing when there's no
            // background activity, so the footer above is unaffected.
            SessionOverviewActivityListView(activities: session.backgroundActivities)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 240, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(highlightColor)
                }
        }
        .overlay {
            // Status-as-border: the busy state animates a spinning rainbow edge
            // (reviving the early-stage pane highlight); every other state shows
            // its solid aggregate Claude status color (or a faint neutral edge
            // when inactive). Selection/active are conveyed by the highlight +
            // scale, so no accent ring competes here.
            if session.aggregateClaudeState == .busy {
                RainbowBorder(cornerRadius: 12)
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(borderColor, lineWidth: 2)
            }
        }
        .scaleEffect(isSelected ? 1.03 : 1.0)
        .shadow(
            color: isSelected ? Color.black.opacity(0.25) : .clear,
            radius: isSelected ? 10 : 0,
            y: isSelected ? 4 : 0
        )
        .animation(.easeInOut(duration: 0.12), value: isSelected)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture { onSelect() }
        // Delete-confirmation popover armed by the overview's `D` shortcut. Anchored
        // to this card so the confirm reads as "delete *this* session". Return
        // (default action) confirms, Escape (cancel action) dismisses; both are
        // also handled by the overview's keyboard responder if the popover does not
        // take key focus (see `OverviewKeyboardResponder`).
        .popover(isPresented: $isConfirmingDelete, arrowEdge: .top) {
            deleteConfirmationPopover
        }
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

    /// Compact confirmation shown in the delete popover. The Delete button carries
    /// the default-action shortcut (Return) and Cancel the cancel-action shortcut
    /// (Escape) for when the popover owns key focus; the overview's keyboard
    /// responder mirrors both for when it does not.
    private var deleteConfirmationPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Delete this session?")
                .font(.headline)
            Text(session.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            HStack {
                Spacer()
                Button("Cancel") { isConfirmingDelete = false }
                    .keyboardShortcut(.cancelAction)
                Button("Delete", role: .destructive) { onConfirmDelete() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 240)
    }
}
