import AppKit
import SwiftUI

/// A Mission-Control-style overview of every Claude session across all
/// workspaces, laid out as a grid of `SessionOverviewCardView` cards covering
/// the whole session area with a full-bleed `.ultraThinMaterial` frosted
/// backdrop that the session content behind blurs through.
///
/// Fully keyboard-driven: arrow keys — or vim-style `h`/`j`/`k`/`l` — move a
/// visible card selection in true 2D, Return/keypad Enter opens the selected
/// session, `R` renames the selected card inline, `D` arms a delete-confirmation
/// popover on the card (Return/Delete confirms and runs the shared close flow,
/// Escape/Cancel dismisses it), Escape otherwise dismisses the overview. Clicking
/// a card selects that session too.
struct SessionOverviewGridView: View {
    let workspaceCollection: WorkspaceCollection
    /// Used by `D` (delete) — routes through the same close flow as the sidebar
    /// so worktree teardown dialogs and cascade-close behave identically.
    let worktreeOrchestrator: WorktreeOrchestrator
    let onSelect: (_ workspaceID: UUID, _ sessionID: UUID) -> Void
    let onDismiss: () -> Void

    /// The keyboard-selected card. Defaults to the active session on appear and
    /// is kept valid (falls back to the adjacent card) if the list changes.
    @State private var selectedSessionID: UUID?
    /// `true` while the selected card's name is in inline-rename mode (driven by
    /// the `R` shortcut). While set, the keyboard responder yields first responder
    /// so the rename `TextField` can hold focus.
    @State private var isRenamingSelection = false
    /// The session whose delete-confirmation popover is currently armed (driven by
    /// the `D` shortcut), or `nil` when no confirm is pending. While set, the card
    /// shows a "Delete this session?" popover and the keyboard responder is in
    /// confirming mode (Return confirms, Escape cancels, everything else swallowed).
    @State private var confirmingDeleteSessionID: UUID?
    /// Live column count of the adaptive grid, measured from the overview's
    /// content width. Drives Up/Down (±one row) arrow navigation. Defaults to 1.
    @State private var columnCount = 1

    /// Persisted card order for the overview grid — survives app restarts.
    @AppStorage("sessionOverviewSortMode") private var sortMode: SessionOverviewSortMode = .defaultOrder

    /// Inner padding around the scrolling grid content. Must exceed the selected
    /// card's outer glow radius (`SessionOverviewCardView`'s 24pt shadow) or the
    /// `ScrollView` clips the glow flat at the top edge when a top-row card is
    /// selected. Also feeds `columnCount(forWidth:)`'s width calc, so this stays
    /// the single source of truth for both.
    private let contentPadding: CGFloat = 28

    /// Minimum card width and inter-card gap. Shared by both the adaptive
    /// `GridItem` below and the `columnCount(forWidth:)` nav math so the layout
    /// and arrow-key navigation can't drift out of sync.
    private let cardMinWidth: CGFloat = 300
    private let cardSpacing: CGFloat = 12

    /// Adaptive card columns — cards flow to fill the available width, each
    /// clamped to a tile-friendly size range.
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: cardMinWidth, maximum: 460), spacing: cardSpacing)]
    }

    /// `true` when no workspace holds any session — drives the empty state.
    private var isEmpty: Bool {
        workspaceCollection.workspaces.allSatisfy { $0.sessionCollection.sessions.isEmpty }
    }

    /// Every card in flat render order (each workspace's `hierarchicalOrder()`,
    /// concatenated in `workspaces` order), then reordered by `sortMode`. Drives
    /// both the single unified grid and the index-based 2D keyboard navigation,
    /// so both reflect the chosen sort. Carries the owning workspace so each
    /// card can render its workspace chip and route selection/close.
    private var cardEntries: [CardEntry] {
        let base = workspaceCollection.workspaces.flatMap { workspace in
            workspace.sessionCollection.hierarchicalOrder().map { entry in
                CardEntry(
                    workspace: workspace,
                    session: entry.session,
                    isOrchestrator: entry.isOrchestrator
                )
            }
        }
        return SessionOverviewSort.ordered(base, mode: sortMode) { $0.session.aggregateClaudeState }
    }

    var body: some View {
        ZStack {
            // Full-bleed frosted backdrop covering the whole session area — a
            // uniform .ultraThinMaterial blur of the content behind (no rounded
            // corners, no inset, no separate scrim). Replaces the old inset panel.
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            if isEmpty {
                Text("No sessions")
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    sortControl
                    gridContent
                }
            }
        }
        // The live terminal NSView behind this overlay stays the window's
        // first responder, so `.onExitCommand` never fires and a bare Escape
        // would leak into the running session's PTY. This 0×0 responder claims
        // first responder while the overview is mounted and drives all keyboard
        // control (arrows / Enter / Escape), swallowing the events itself.
        .background {
            OverviewKeyboardResponder(
                onArrow: move,
                onActivate: activateSelection,
                onEscape: onDismiss,
                onDelete: requestDeleteSelection,
                onRename: beginRenameSelection,
                onConfirmDelete: confirmPendingDelete,
                onCancelDelete: cancelPendingDelete,
                onCycleSort: cycleSort,
                isEditing: isRenamingSelection,
                isConfirming: confirmingDeleteSessionID != nil
            )
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
        }
        // Belt-and-suspenders: harmless if first-responder routing ever changes.
        .onExitCommand { onDismiss() }
        .onAppear { selectedSessionID = defaultSelection() }
        // Keep the selection valid as sessions come or go while the overview is
        // up: a missing (nil) selection, or one whose id is no longer present,
        // falls back to the adjacent card — the neighbor that slid into the
        // vanished card's slot (or the new last card, if it was the last one) —
        // and stays nil only when there are none.
        .onChange(of: cardEntries.map(\.id)) { oldIDs, ids in
            let stillValid = selectedSessionID.map(ids.contains) ?? false
            if !stillValid {
                selectedSessionID = OverviewGridNavigation.selectionAfterRemoval(
                    previous: selectedSessionID,
                    oldIDs: oldIDs,
                    newIDs: ids
                )
                // Drop any in-flight rename if its card disappeared (e.g. the
                // session was deleted mid-edit) so the responder reclaims focus.
                isRenamingSelection = false
            }
            // Likewise drop a pending delete confirm whose card is gone (the
            // session was closed — possibly by the confirm itself), so the
            // popover tears down and the responder leaves confirming mode.
            if let pending = confirmingDeleteSessionID, !ids.contains(pending) {
                confirmingDeleteSessionID = nil
            }
        }
    }

    /// Header row above the scrolling grid: a capsule segmented control picking
    /// `sortMode` (Default | Session State), trailing-aligned. Also toggleable
    /// via the `s` keyboard shortcut (`cycleSort()`).
    @ViewBuilder
    private var sortControl: some View {
        HStack {
            Spacer()
            HStack(spacing: 2) {
                sortSegment(.defaultOrder)
                sortSegment(.sessionState)
            }
            .padding(3)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
                    )
            )
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    /// One pill of `sortControl`, matching `InspectPanelTabRow`'s tab-button style.
    @ViewBuilder
    private func sortSegment(_ mode: SessionOverviewSortMode) -> some View {
        let isActive = sortMode == mode
        Button {
            sortMode = mode
        } label: {
            Text(mode.label)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(isActive ? Color.primary.opacity(0.9) : Color.primary.opacity(0.4))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background {
                    if isActive {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.10), Color.white.opacity(0.04)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .overlay(
                                Capsule()
                                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                            )
                    }
                }
        }
        .buttonStyle(.plain)
    }

    /// The scrolling card grid, wrapped in a `ScrollViewReader` so keyboard
    /// navigation can scroll the selected card into view, and measuring its own
    /// width to keep `columnCount` in sync with the adaptive layout.
    @ViewBuilder
    private var gridContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // One unified grid across every workspace — cards flow to fill the
                // width regardless of which workspace they belong to (each carries
                // its own workspace chip), replacing the old per-workspace bands.
                LazyVGrid(columns: columns, alignment: .leading, spacing: cardSpacing) {
                    ForEach(cardEntries) { entry in
                        card(for: entry)
                    }
                }
                .padding(contentPadding)
            }
            .onGeometryChange(for: Int.self) { geo in
                columnCount(forWidth: geo.size.width - contentPadding * 2)
            } action: { newCount in
                columnCount = newCount
            }
            .onChange(of: selectedSessionID) { _, newID in
                guard let newID else { return }
                withAnimation(.easeInOut(duration: 0.12)) {
                    proxy.scrollTo(newID, anchor: .center)
                }
            }
        }
    }

    /// One session's card, wired for selection, inline rename, and the
    /// delete-confirmation popover. Its workspace chip and active/selection state
    /// come from the `CardEntry`'s owning workspace.
    @ViewBuilder
    private func card(for entry: CardEntry) -> some View {
        let workspace = entry.workspace
        let session = entry.session
        SessionOverviewCardView(
            session: session,
            workspaceName: workspace.name,
            isActive: workspace.id == workspaceCollection.activeWorkspaceID
                && session.id == workspace.sessionCollection.activeSessionID,
            isSelected: session.id == selectedSessionID,
            isOrchestrator: entry.isOrchestrator,
            // Only the selected card renames; committing/cancelling clears the shared flag.
            isRenaming: Binding(
                get: { isRenamingSelection && session.id == selectedSessionID },
                set: { if !$0 { isRenamingSelection = false } }
            ),
            // Only the card whose id matches the armed confirm shows the popover;
            // dismissing it (Cancel / click-away) clears the shared id.
            isConfirmingDelete: Binding(
                get: { confirmingDeleteSessionID == session.id },
                set: { if !$0 { confirmingDeleteSessionID = nil } }
            ),
            onConfirmDelete: confirmPendingDelete,
            onSelect: { onSelect(workspace.id, session.id) }
        )
    }

    // MARK: - Selection & navigation

    /// The card to select when the overview appears: the active workspace's
    /// active session if it's on screen, otherwise the first card.
    private func defaultSelection() -> UUID? {
        let cards = cardEntries
        guard !cards.isEmpty else { return nil }
        if let activeWorkspace = workspaceCollection.workspaces.first(where: {
            $0.id == workspaceCollection.activeWorkspaceID
        }),
            let activeSessionID = activeWorkspace.sessionCollection.activeSessionID,
            cards.contains(where: { $0.id == activeSessionID }) {
            return activeSessionID
        }
        return cards.first?.id
    }

    /// Move the selection one step in `direction` across the single unified
    /// overview grid (see `OverviewGridNavigation`): Left/Right walk the flat
    /// render order, Up/Down step between visual rows preserving the column.
    /// Clamped to bounds (no wrap). Every card now flows into one continuous grid,
    /// so the nav is fed a single section spanning all workspaces.
    private func move(_ direction: OverviewGridNavigation.Direction) {
        let sections = [cardEntries.map(\.session.id)]
        if let next = OverviewGridNavigation.move(
            direction,
            from: selectedSessionID,
            sections: sections,
            columnCount: columnCount
        ) {
            selectedSessionID = next
        }
    }

    /// Open the currently selected session (activates it and dismisses the
    /// overlay via the existing `onSelect`). A no-op when nothing is selected.
    private func activateSelection() {
        guard let id = selectedSessionID,
              let card = cardEntries.first(where: { $0.id == id }) else { return }
        onSelect(card.workspace.id, card.session.id)
    }

    /// Put the selected card's name into inline-rename mode (the `R` shortcut).
    /// A no-op when nothing is selected.
    private func beginRenameSelection() {
        guard selectedSessionID != nil else { return }
        isRenamingSelection = true
    }

    /// Arm the delete-confirmation popover on the selected card (the `D`
    /// shortcut). Deleting no longer happens on a single keypress — the popover
    /// guards it, and `confirmPendingDelete()` performs the actual close. A no-op
    /// when nothing is selected.
    private func requestDeleteSelection() {
        guard let id = selectedSessionID else { return }
        confirmingDeleteSessionID = id
    }

    /// Confirm the armed delete (the popover's Delete button / Return) and run the
    /// shared close flow — worktree sessions then get the teardown dialog, plain
    /// sessions are removed immediately, exactly as the sidebar's close does. The
    /// pending id is cleared **first** so the popover tears down before any close
    /// dialog appears. Idempotent — a no-op once cleared or if the selection can
    /// no longer be resolved.
    private func confirmPendingDelete() {
        guard let id = confirmingDeleteSessionID else { return }
        confirmingDeleteSessionID = nil
        guard let card = cardEntries.first(where: { $0.id == id }) else { return }
        SessionCloseFlow.run(
            session: card.session,
            in: card.workspace,
            worktreeOrchestrator: worktreeOrchestrator
        )
    }

    /// Dismiss the delete-confirmation popover without deleting (the popover's
    /// Cancel button / Escape).
    private func cancelPendingDelete() {
        confirmingDeleteSessionID = nil
    }

    /// Cycle `sortMode` to the next case in `SessionOverviewSortMode.allCases`,
    /// wrapping around (the `s` shortcut). With today's two modes this is a
    /// plain toggle, but rotates cleanly if a third mode is ever added.
    private func cycleSort() {
        let cases = SessionOverviewSortMode.allCases
        guard let currentIndex = cases.firstIndex(of: sortMode) else {
            sortMode = .defaultOrder
            return
        }
        let nextIndex = cases.index(after: currentIndex)
        sortMode = nextIndex == cases.endIndex ? cases[cases.startIndex] : cases[nextIndex]
    }

    /// Columns that fit `width` given the adaptive tile params (`cardMinWidth`
    /// minimum, `cardSpacing` gap). Guards a non-positive width by defaulting to
    /// a single column.
    nonisolated private func columnCount(forWidth width: CGFloat) -> Int {
        guard width > 0 else { return 1 }
        return max(1, Int((width + cardSpacing) / (cardMinWidth + cardSpacing)))
    }

    /// One card's place in the flat, render-order list: the session plus the
    /// workspace that owns it (for the workspace chip and selection/close routing)
    /// and whether it orchestrates nested implementers.
    private struct CardEntry: Identifiable {
        let workspace: Workspace
        let session: Session
        let isOrchestrator: Bool
        var id: UUID { session.id }
    }
}

// MARK: - Keyboard Responder

/// A 0×0 `NSView` that claims first responder while the overview is mounted so
/// its keyboard control (arrows / Enter / Escape) is handled here instead of
/// leaking to the live terminal surface behind the overlay. Mirrors
/// `SidebarKeyboardResponder`.
private struct OverviewKeyboardResponder: NSViewRepresentable {
    let onArrow: (OverviewGridNavigation.Direction) -> Void
    let onActivate: () -> Void
    let onEscape: () -> Void
    let onDelete: () -> Void
    let onRename: () -> Void
    /// Confirm the pending delete (Return / keypad Enter while a confirm is armed).
    let onConfirmDelete: () -> Void
    /// Cancel the pending delete (Escape while a confirm is armed).
    let onCancelDelete: () -> Void
    /// Cycle the grid's sort mode (the `s` shortcut).
    let onCycleSort: () -> Void
    /// `true` while the selected card is being renamed inline. The rename
    /// `TextField` then owns first responder, so this view must NOT reclaim it
    /// (reclaiming would drop the field's focus and cancel the edit).
    let isEditing: Bool
    /// `true` while a delete-confirmation popover is armed. Like `isEditing`, this
    /// view yields first responder (so it never steals focus back from a popover
    /// that grabbed it), and while set, `keyDown` routes Return→confirm,
    /// Escape→cancel and swallows everything else — covering the case where the
    /// popover did NOT take key focus and the events land here instead.
    let isConfirming: Bool

    func makeNSView(context: Context) -> KeyView {
        KeyView()
    }

    func updateNSView(_ nsView: KeyView, context: Context) {
        // Reassign every update so the closures always capture the latest
        // selection + column count from the SwiftUI view.
        nsView.onArrow = onArrow
        nsView.onActivate = onActivate
        nsView.onEscape = onEscape
        nsView.onDelete = onDelete
        nsView.onRename = onRename
        nsView.onConfirmDelete = onConfirmDelete
        nsView.onCancelDelete = onCancelDelete
        nsView.onCycleSort = onCycleSort
        nsView.isConfirming = isConfirming
        // While a rename field or a delete-confirm popover is up, leave first
        // responder alone so the TextField / popover keeps focus.
        guard !isEditing && !isConfirming else { return }
        // Reclaim first responder on the next runloop tick rather than inline:
        // when a rename ends, this same update pass also tears down the rename
        // TextField, and reclaiming synchronously here can race that teardown and
        // leave the window with no first responder (dead keyboard). Deferring runs
        // after SwiftUI settles. `viewDidMoveToWindow` still claims focus
        // synchronously on first mount, so initial keyboard control isn't delayed.
        DispatchQueue.main.async { [weak nsView] in
            guard let nsView, let window = nsView.window else { return }
            // A live editor (e.g. a rename field) legitimately owns focus — never
            // steal it back; the `isEditing` guard above covers the common case,
            // this covers any stray editor that appears between updates.
            if window.firstResponder is NSText { return }
            if window.firstResponder !== nsView {
                window.makeFirstResponder(nsView)
            }
        }
    }

    final class KeyView: NSView {
        var onArrow: ((OverviewGridNavigation.Direction) -> Void)?
        var onActivate: (() -> Void)?
        var onEscape: (() -> Void)?
        var onDelete: (() -> Void)?
        var onRename: (() -> Void)?
        var onConfirmDelete: (() -> Void)?
        var onCancelDelete: (() -> Void)?
        var onCycleSort: (() -> Void)?
        var isConfirming = false

        override var acceptsFirstResponder: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.makeFirstResponder(self)
        }

        override func keyDown(with event: NSEvent) {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            // Arrow keys carry the .numericPad (and often .function) flag even
            // without a real modifier held; subtract those before the empty check.
            let bareFlags = flags.subtracting([.numericPad, .function])

            // While a delete confirm is armed the responder is modal: Return
            // confirms, Escape cancels, and every other key is swallowed so no
            // navigation / activation leaks through. (Normally the popover owns
            // key focus and handles Return/Escape itself; this covers the case
            // where it didn't and the events arrive here.)
            if isConfirming {
                switch event.keyCode {
                case 36, 76: onConfirmDelete?()
                case 53: onCancelDelete?()
                default: break
                }
                return
            }

            switch event.keyCode {
            case 123 where bareFlags.isEmpty:
                onArrow?(.left)
            case 124 where bareFlags.isEmpty:
                onArrow?(.right)
            case 125 where bareFlags.isEmpty:
                onArrow?(.down)
            case 126 where bareFlags.isEmpty:
                onArrow?(.up)
            case 36 where bareFlags.isEmpty, 76 where bareFlags.isEmpty:
                onActivate?()
            case 53 where flags.isEmpty:
                onEscape?()
            default:
                // Letter shortcuts match the typed character (layout-independent)
                // with no Cmd/Ctrl/Opt/Shift held. Never reached mid-rename: the
                // TextField owns first responder then, so these keys go to it.
                // h/j/k/l mirror the arrow keys (vim-style) for card navigation.
                switch bareFlags.isEmpty ? event.charactersIgnoringModifiers?.lowercased() : nil {
                case "h": onArrow?(.left)
                case "j": onArrow?(.down)
                case "k": onArrow?(.up)
                case "l": onArrow?(.right)
                case "d": onDelete?()
                case "r": onRename?()
                case "s": onCycleSort?()
                default: super.keyDown(with: event)
                }
            }
        }
    }
}
