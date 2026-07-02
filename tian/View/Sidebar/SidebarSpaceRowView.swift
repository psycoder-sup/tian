import SwiftUI

struct SidebarSpaceRowView: View {
    let space: SpaceModel
    let isActive: Bool
    /// `true` when this Space is nested under an orchestrator — draws the leading
    /// connector rule + `↳` glyph and indents the row.
    var isChild: Bool = false
    /// `true` when this Space has ≥1 implementer nested under it — shows the `⌂`
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

    private func accessibilityDescription(sessions: [(paneID: UUID, state: ClaudeSessionState)]) -> String {
        var parts: [String] = [isActive ? "selected" : "not selected"]

        // Repo status descriptions (FR-070)
        for repoID in space.gitContext.pinnedRepoOrder {
            guard let status = space.gitContext.repoStatuses[repoID] else { continue }
            var repoParts: [String] = []

            if let branch = status.branchName {
                repoParts.append("\(branch) branch")
            }

            if !status.diffSummary.isEmpty {
                var changes: [String] = []
                if status.diffSummary.modified > 0 { changes.append("\(status.diffSummary.modified) modified") }
                if status.diffSummary.added > 0 { changes.append("\(status.diffSummary.added) added") }
                if status.diffSummary.deleted > 0 { changes.append("\(status.diffSummary.deleted) deleted") }
                if status.diffSummary.renamed > 0 { changes.append("\(status.diffSummary.renamed) renamed") }
                if status.diffSummary.unmerged > 0 { changes.append("\(status.diffSummary.unmerged) unmerged") }
                repoParts.append(changes.joined(separator: " "))
            }

            if let pr = status.prStatus {
                repoParts.append("pull request \(pr.state.rawValue)")
            }

            // Count Claude sessions in this repo
            let repoSessions = sessions.filter { space.gitContext.paneRepoAssignments[$0.paneID] == repoID }
            if !repoSessions.isEmpty {
                let needsAttention = repoSessions.filter { $0.state == .needsAttention }.count
                let desc = "\(repoSessions.count) Claude session\(repoSessions.count == 1 ? "" : "s")"
                if needsAttention > 0 {
                    repoParts.append("\(desc) \(needsAttention) needs attention")
                } else {
                    repoParts.append(desc)
                }
            }

            if !repoParts.isEmpty {
                parts.append(repoParts.joined(separator: ", "))
            }
        }

        // Non-repo sessions
        let nonRepoSessions = sessions.filter { space.gitContext.paneRepoAssignments[$0.paneID] == nil }
        if !nonRepoSessions.isEmpty {
            let descriptions = nonRepoSessions.map { $0.state.rawValue }
            parts.append("Claude sessions: \(descriptions.joined(separator: ", "))")
        }

        return parts.joined(separator: ". ")
    }

    private var tabCountLabel: String {
        let count = space.tabs.count
        return count == 1 ? "1 tab" : "\(count) tabs"
    }

    private var isSettingUp: Bool { setupProgress != nil }

    @ViewBuilder
    private func setupProgressRow(progress: SetupProgress) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.mini)

            Text(space.name)
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
        let sessions = PaneStatusManager.shared.sessionStates(in: space)

        rowContent(sessions: sessions)
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

    /// The Space row's content (name, tab count, status). Wrapped by `body`,
    /// which prepends `childConnector` when this row is a nested implementer.
    @ViewBuilder
    private func rowContent(sessions: [(paneID: UUID, state: ClaudeSessionState)]) -> some View {
        Group {
            if let progress = setupProgress {
                setupProgressRow(progress: progress)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        InlineRenameView(
                            text: space.name,
                            isRenaming: $isRenaming,
                            onCommit: { space.name = $0 }
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

                        Text(tabCountLabel)
                            .font(.system(size: 9))
                            .foregroundStyle(Color(white: 0.45))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.white.opacity(0.06))
                            )
                    }

                    SpaceStatusAreaView(space: space, isActive: isActive)
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
        .modifier(SidebarSpaceRowMutationGate(
            enabled: !isSettingUp,
            spaceID: space.id,
            spaceName: space.name,
            currentDirectory: space.defaultWorkingDirectory,
            onRename: { isRenaming = true },
            onSetDirectory: onSetDirectory,
            onClose: onClose
        ))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("space-row-\(space.id)")
        .accessibilityLabel(space.name)
        .accessibilityValue(accessibilityDescription(sessions: sessions))
        .accessibilityHint("Double-tap to switch. Double-tap and hold to rename.")
    }
}

/// Gates drag and context-menu interactions on the Space row. Both are
/// disabled while the row is rendering setup-progress so the user can't
/// rename, drag, or close a Space mid-creation. Tap-to-focus is handled
/// separately at the call site.
private struct SidebarSpaceRowMutationGate: ViewModifier {
    let enabled: Bool
    let spaceID: UUID
    let spaceName: String
    let currentDirectory: URL?
    let onRename: () -> Void
    let onSetDirectory: (URL?) -> Void
    let onClose: () -> Void

    func body(content: Content) -> some View {
        if enabled {
            content
                .draggable(SpaceDragItem(spaceID: spaceID))
                .contextMenu {
                    Button("Rename", action: onRename)
                    Divider()
                    DefaultDirectoryMenu(
                        name: spaceName,
                        currentDirectory: currentDirectory,
                        onSet: onSetDirectory
                    )
                    Divider()
                    Button("Close Space", action: onClose)
                }
        } else {
            content
        }
    }
}
