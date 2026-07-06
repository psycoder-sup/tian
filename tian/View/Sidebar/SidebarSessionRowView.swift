import SwiftUI

struct SidebarSessionRowView: View {
    let session: Session
    let isActive: Bool
    /// `true` when this Session is nested under an orchestrator — draws the leading
    /// connector rule + `↳` glyph and indents the row.
    var isChild: Bool = false
    /// `true` when this Session has ≥1 implementer nested under it — shows the `⌂`
    /// orchestrator marker next to the name.
    var isOrchestrator: Bool = false
    let isKeyboardSelected: Bool
    let setupProgress: SetupProgress?
    let onSelect: () -> Void
    let onSetDirectory: (URL?) -> Void
    let onClose: () -> Void

    @State private var isHovering = false
    @State private var isRenaming = false
    @State private var lastClickTime: Date?

    /// Session-shaped voice-over summary: selection, Claude state, branch,
    /// diff counts, PR state, and the latest free-form status label. Reads the
    /// values the row already derived for its visible content, so it doesn't
    /// re-walk the pane mirrors or git status.
    private func accessibilityDescription(
        claudeState: ClaudeSessionState?,
        gitStatus: GitRepoStatus?,
        latestStatus: PaneStatus?
    ) -> String {
        var parts: [String] = [isActive ? "selected" : "not selected"]

        if let claudeState {
            parts.append("Claude \(claudeState.rawValue)")
        }

        if let gitStatus {
            if let branch = gitStatus.branchName, !branch.isEmpty {
                parts.append("\(branch) branch")
            }
            if !gitStatus.diffSummary.isEmpty {
                var changes: [String] = []
                if gitStatus.diffSummary.modified > 0 { changes.append("\(gitStatus.diffSummary.modified) modified") }
                if gitStatus.diffSummary.added > 0 { changes.append("\(gitStatus.diffSummary.added) added") }
                if gitStatus.diffSummary.deleted > 0 { changes.append("\(gitStatus.diffSummary.deleted) deleted") }
                if gitStatus.diffSummary.renamed > 0 { changes.append("\(gitStatus.diffSummary.renamed) renamed") }
                if gitStatus.diffSummary.unmerged > 0 { changes.append("\(gitStatus.diffSummary.unmerged) unmerged") }
                parts.append(changes.joined(separator: " "))
            }
            if let pr = gitStatus.prStatus {
                parts.append("pull request \(pr.state.rawValue)")
            }
        }

        if let latestStatus {
            parts.append(String(latestStatus.label.prefix(50)))
        }

        return parts.joined(separator: ". ")
    }

    private var isSettingUp: Bool { setupProgress != nil }

    @ViewBuilder
    private func setupProgressRow(progress: SetupProgress) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.mini)

            Text(session.displayName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(white: 0.85))
                .lineLimit(1)

            switch progress.phase {
            case .setup, .cleanup:
                Text("·")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                Text("\(progress.labelPrefix) \(progress.stepText)")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)

                if progress.didFailRun {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.red)
                        .accessibilityLabel("a step in this run failed")
                }

                Text(progress.commandLabel)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color(white: 0.55))
                    .lineLimit(1)
                    .truncationMode(.tail)

            case .removing:
                Text("·")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                Text(progress.labelPrefix)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
    }

    /// Connector rail colour, shared by the orchestrator stub and child rails.
    private static let railColor = Color.white.opacity(0.16)
    /// X of the vertical rail within each row's leading gutter — inside the
    /// row's horizontal padding, clear of text. Parent and children share it so
    /// their segments line up into one rail.
    private static let railX: CGFloat = 7

    var body: some View {
        rowContent
            // Children indent so their content clears the rail + elbow tick.
            .padding(.leading, isChild ? 22 : 0)
            // One continuous rail: the orchestrator contributes a bottom-half
            // stub from its centre, each child a full-height segment + elbow.
            // `spacing: 0` at the call site makes the segments abut.
            .overlay(alignment: .leading) { connectorRail }
    }

    /// The leading connector segment for this row. A child draws a full-height
    /// vertical rail plus a centred horizontal elbow; an orchestrator draws a
    /// bottom-half stub that meets the first child's segment directly below.
    /// Standalone rows draw nothing. Decorative — hidden from accessibility.
    @ViewBuilder
    private var connectorRail: some View {
        if isChild {
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Self.railColor)
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
                    .padding(.leading, Self.railX)
                Rectangle()
                    .fill(Self.railColor)
                    .frame(width: 12, height: 1)
                    .padding(.leading, Self.railX)
            }
            .accessibilityHidden(true)
        } else if isOrchestrator {
            VStack(spacing: 0) {
                Color.clear
                Rectangle().fill(Self.railColor).frame(width: 1)
            }
            .frame(width: 1)
            .frame(maxHeight: .infinity)
            .padding(.leading, Self.railX)
            .accessibilityHidden(true)
        }
    }

    /// The Session row's content (dot, name, status line). Wrapped by `body`,
    /// which prepends `connectorRail` when this row is a nested implementer.
    @ViewBuilder
    private var rowContent: some View {
        // Derive the row's status once per render — the dot, the status line,
        // and the accessibility string all read these, so a11y never re-walks
        // the pane mirrors or git status.
        let claudeState = session.aggregateClaudeState
        let gitStatus = session.resolvedGitStatus
        let latestStatus = session.latestPaneStatus
        let backgroundActivities = session.backgroundActivities

        Group {
            if let progress = setupProgress {
                setupProgressRow(progress: progress)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        SessionDotView(state: claudeState ?? .inactive)

                        InlineRenameView(
                            text: session.displayName,
                            isRenaming: $isRenaming,
                            // Empty commit resets to the auto-derived name;
                            // InlineRenameView already trims and rejects blanks,
                            // so the nil branch is defensive.
                            onCommit: { session.customName = $0.isEmpty ? nil : $0 }
                        )
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isActive ? Color(white: 0.9) : Color(red: 0.557, green: 0.557, blue: 0.576))

                        if isOrchestrator {
                            Image(systemName: "house")
                                .font(.system(size: 9))
                                .foregroundStyle(Color(white: 0.5))
                                .accessibilityLabel("orchestrator")
                        }

                        Spacer()

                        // Trailing badge: outstanding background work (subagents /
                        // backgrounded bash). Self-hides when there's none, so it
                        // only appears while work is in flight.
                        BackgroundActivityBadgeView(activities: backgroundActivities)
                    }

                    SessionStatusLineView(
                        isActive: isActive,
                        repoStatus: gitStatus,
                        latestStatus: latestStatus
                    )
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if isActive {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.accentColor.opacity(0.2), lineWidth: 1)
                    )
            } else if isHovering {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.04))
            }
        }
        .overlay {
            if isKeyboardSelected {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.accentColor.opacity(0.5), lineWidth: 1)
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture {
            if isSettingUp {
                lastClickTime = nil
                onSelect()
                return
            }
            let now = Date()
            if let last = lastClickTime, now.timeIntervalSince(last) < 0.3 {
                lastClickTime = nil
                isRenaming = true
            } else {
                lastClickTime = now
                onSelect()
            }
        }
        .modifier(SidebarSessionRowMutationGate(
            enabled: !isSettingUp,
            sessionID: session.id,
            sessionName: session.displayName,
            currentDirectory: session.defaultWorkingDirectory,
            onRename: { isRenaming = true },
            onSetDirectory: onSetDirectory,
            onClose: onClose
        ))
        // Cmd+R (posted by the window key monitor) enters inline-rename on the
        // active session's row. Matching on the globally-unique session UUID is
        // the correct guard — the row has no workspaceCollection reference.
        .onReceive(NotificationCenter.default.publisher(for: .renameSession)) { notification in
            if !isSettingUp,
               notification.userInfo?[Notification.renameSessionIDKey] as? UUID == session.id {
                isRenaming = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("session-row-\(session.id)")
        .accessibilityLabel(session.displayName)
        .accessibilityValue(accessibilityDescription(
            claudeState: claudeState,
            gitStatus: gitStatus,
            latestStatus: latestStatus
        ))
        .accessibilityHint("Double-tap to switch. Double-tap and hold to rename.")
    }
}

/// Gates the context menu on the Session row. It's disabled while the row is
/// rendering setup-progress so the user can't rename or close a Session
/// mid-creation. Session rows intentionally have no drag gesture — reordering is
/// a workspace-level interaction. Tap-to-focus is handled at the call site.
private struct SidebarSessionRowMutationGate: ViewModifier {
    let enabled: Bool
    let sessionID: UUID
    let sessionName: String
    let currentDirectory: URL?
    let onRename: () -> Void
    let onSetDirectory: (URL?) -> Void
    let onClose: () -> Void

    func body(content: Content) -> some View {
        if enabled {
            content
                .contextMenu {
                    Button("Rename", action: onRename)
                    Divider()
                    DefaultDirectoryMenu(
                        name: sessionName,
                        currentDirectory: currentDirectory,
                        onSet: onSetDirectory
                    )
                    Divider()
                    Button("Close Session", action: onClose)
                }
        } else {
            content
        }
    }
}
