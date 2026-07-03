import SwiftUI

/// Root view for a Session's content area (replacing the old per-space
/// section render tree): a single Claude area (one pane, never split, topped
/// by a slim `SessionHeaderView`) plus a toggleable terminal panel that docks
/// right or bottom behind a draggable `SessionDividerView`. When the terminal
/// panel is hidden, Claude expands to fill (FR-17).
///
/// Performance: the live divider-drag state lives in `@State liveDragRatio` at
/// this view so per-frame drag updates do NOT invalidate terminal surfaces
/// (Spec Section 10). `Session.splitRatio` is committed only on gesture end.
struct SessionContentView: View {
    @Bindable var session: Session

    /// True only for the active session in the workspace. Inactive sessions
    /// stay mounted (opacity 0) so their surfaces survive switches, but they
    /// must not claim first responder — otherwise typing in the active session
    /// lands on a hidden surface from another session.
    var isActive: Bool = true

    /// Inset applied to the header content when the Claude region touches the
    /// window's leading edge (clears the traffic lights + sidebar toggle).
    var windowLeadingInset: CGFloat = 0
    /// Inset applied to the header content when the Claude region touches the
    /// window's trailing edge (clears the inspect-panel rail).
    var windowTrailingInset: CGFloat = 0

    /// Live ratio threaded from the divider drag gesture to the two sibling
    /// areas. `nil` when no drag is active.
    @State private var liveDragRatio: Double?

    /// Last measured container size, used by the layout-parameter change
    /// handlers so they can re-push region sizes without a fresh geometry pass.
    @State private var lastContainerSize: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            content(containerSize: geo.size)
                .animation(.easeInOut(duration: 0.2), value: session.terminalVisible)
                .animation(.easeInOut(duration: 0.2), value: session.dockPosition)
                .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                    // Always remember the size so activation can refresh nav
                    // metadata, but only inactive→active pushes touch the panes:
                    // an inactive session must not churn container sizes when the
                    // window resizes behind it.
                    lastContainerSize = size
                    guard isActive else { return }
                    pushContainerSizes(size)
                }
                .onChange(of: isActive) { _, nowActive in
                    // Geometry won't re-fire on activation (size is unchanged),
                    // so refresh region sizes from the last measured geometry.
                    if nowActive { pushContainerSizes(lastContainerSize) }
                }
                .onChange(of: session.terminalVisible) { _, _ in pushContainerSizes(lastContainerSize) }
                .onChange(of: session.dockPosition) { _, _ in pushContainerSizes(lastContainerSize) }
                .onChange(of: session.splitRatio) { _, _ in pushContainerSizes(lastContainerSize) }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(containerSize: CGSize) -> some View {
        let ratio = liveDragRatio ?? session.splitRatio
        let showTerminal = session.terminalVisible && session.terminalPanel != nil
        let layout: SessionLayout? = showTerminal
            ? SessionLayout.computeFrames(
                containerSize: containerSize,
                ratio: ratio,
                dock: session.dockPosition,
                claudeMin: SessionDividerClamper.defaultClaudeMin,
                terminalMin: SessionDividerClamper.defaultTerminalMin,
                dividerThickness: SessionDividerView.thickness
            )
            : nil
        let axis: CGFloat = session.dockPosition == .right
            ? containerSize.width
            : containerSize.height

        // Claude is the leading/topmost area in every layout, so it always pays
        // the leading window inset. The trailing inset only applies when no
        // terminal sits between Claude and the trailing edge — i.e. terminal
        // hidden, or terminal docked at the bottom.
        let terminalDockedRight = showTerminal && session.dockPosition == .right
        let claudeTrailing: CGFloat = terminalDockedRight ? 0 : windowTrailingInset

        // Inactive sessions never report focus — they're rendered only to keep
        // their surfaces alive for the next switch.
        let isClaudeFocused = isActive && session.effectiveFocusedArea == .claude
        let isTerminalFocused = isActive && session.effectiveFocusedArea == .terminal

        ZStack(alignment: .topLeading) {
            // Keep the Claude region at a single, stable position in the view
            // tree (always the first child of this ZStack) so its underlying
            // NSView/Metal surface is preserved across `terminalVisible`
            // toggles. Branching this between the ZStack and a top-level view
            // would give SwiftUI two structural identities for Claude, tearing
            // down and recreating the surface on every toggle (visible flicker).
            claudeRegion(
                isFocused: isClaudeFocused,
                leadingInset: windowLeadingInset,
                trailingInset: claudeTrailing
            )
            .frame(
                width: layout?.claude.width ?? containerSize.width,
                height: layout?.claude.height ?? containerSize.height
            )
            .offset(
                x: layout?.claude.minX ?? 0,
                y: layout?.claude.minY ?? 0
            )

            if let layout, let terminalPanel = session.terminalPanel {
                // Terminal panel — no header/tab bar; its panes can split.
                SplitTreeView(
                    node: terminalPanel.splitTree.root,
                    viewModel: terminalPanel,
                    isTabVisible: isTerminalFocused
                )
                .frame(width: layout.terminal.width, height: layout.terminal.height)
                .offset(x: layout.terminal.minX, y: layout.terminal.minY)

                SessionDividerView(
                    session: session,
                    dock: session.dockPosition,
                    containerAxis: axis,
                    liveDragRatio: $liveDragRatio
                )
                .frame(width: layout.divider.width, height: layout.divider.height)
                .offset(x: layout.divider.minX, y: layout.divider.minY)
            }
        }
        .frame(width: containerSize.width, height: containerSize.height, alignment: .topLeading)
    }

    /// The Claude area: a single-leaf split tree (or a plain background during
    /// the brief teardown window as the session closes), a replace-on-open
    /// reader overlay, and the slim header — stacked so the header stays pinned
    /// above both.
    @ViewBuilder
    private func claudeRegion(isFocused: Bool, leadingInset: CGFloat, trailingInset: CGFloat) -> some View {
        ZStack(alignment: .top) {
            // Claude content, inset below the header. A live Claude pane is a
            // single leaf, so this renders one PaneView. There is no empty-Claude
            // placeholder: a Claude exit closes the session, so the else-branch
            // only paints a plain background for the brief teardown frame.
            Group {
                if session.hasLiveClaudePane, let claudePane = session.claudePane {
                    SplitTreeView(
                        node: claudePane.splitTree.root,
                        viewModel: claudePane,
                        // While a reader overlay is open it owns the region:
                        // the live surface must not report visible (so it never
                        // reclaims first responder) and must not receive clicks
                        // through the opaque overlay. It stays mounted so its
                        // Metal surface survives.
                        isTabVisible: isFocused && session.readerState.current == nil
                    )
                    .allowsHitTesting(session.readerState.current == nil)
                } else {
                    Color(nsColor: .terminalBackground)
                }
            }
            .padding(.top, SessionHeaderView.height)

            // Single replace-on-open reader overlay layered over the Claude
            // region, kept below the header so the session name/branch stay
            // visible. `ReaderOverlayView` is provided by the readers wave.
            if let reader = session.readerState.current {
                ReaderOverlayView(
                    content: reader,
                    isFocused: isFocused,
                    onClose: { session.readerState.close() }
                )
                .padding(.top, SessionHeaderView.height)
            }

            SessionHeaderView(
                session: session,
                leadingContentInset: leadingInset,
                trailingContentInset: trailingInset
            )
            // Header before pane content in VoiceOver order.
            .accessibilitySortPriority(1)
        }
    }

    // MARK: - Container-size pushing

    /// Pushes the current region sizes into the two panes' `containerSize` and
    /// the full container size into `session.contentContainerSize`. The pane
    /// sizes feed within-area spatial navigation; `contentContainerSize` feeds
    /// cross-area navigation (`SessionSplitNavigation`).
    private func pushContainerSizes(_ containerSize: CGSize) {
        guard containerSize.width > 0, containerSize.height > 0 else { return }
        session.contentContainerSize = containerSize

        let showTerminal = session.terminalVisible && session.terminalPanel != nil
        if showTerminal {
            let layout = SessionLayout.computeFrames(
                containerSize: containerSize,
                ratio: session.splitRatio,
                dock: session.dockPosition,
                claudeMin: SessionDividerClamper.defaultClaudeMin,
                terminalMin: SessionDividerClamper.defaultTerminalMin,
                dividerThickness: SessionDividerView.thickness
            )
            session.claudePane?.containerSize = layout.claude.size
            session.terminalPanel?.containerSize = layout.terminal.size
        } else {
            session.claudePane?.containerSize = containerSize
        }
    }
}
