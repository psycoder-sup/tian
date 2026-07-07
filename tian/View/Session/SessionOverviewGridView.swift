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
    /// is kept valid (falls back to the first card) if the list changes.
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

    /// Inner padding around the scrolling grid content.
    private let contentPadding: CGFloat = 20

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

    /// Every card in render order (each workspace's `hierarchicalOrder()`,
    /// concatenated in `workspaces` order) flattened for index-based 2D nav.
    private var flatCards: [FlatCard] {
        workspaceCollection.workspaces.flatMap { workspace in
            workspace.sessionCollection.hierarchicalOrder().map { entry in
                FlatCard(workspaceID: workspace.id, sessionID: entry.session.id)
            }
        }
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
                gridContent
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
        // falls back to the first card — and stays nil only when there are none.
        .onChange(of: flatCards.map(\.id)) { _, ids in
            let stillValid = selectedSessionID.map(ids.contains) ?? false
            if !stillValid {
                selectedSessionID = ids.first
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

    /// The scrolling card grid, wrapped in a `ScrollViewReader` so keyboard
    /// navigation can scroll the selected card into view, and measuring its own
    /// width to keep `columnCount` in sync with the adaptive layout.
    @ViewBuilder
    private var gridContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(workspaceCollection.workspaces) { workspace in
                        workspaceSection(workspace)
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

    /// One workspace's cards, with a section header when more than one
    /// workspace is present (a single workspace needs no label).
    @ViewBuilder
    private func workspaceSection(_ workspace: Workspace) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if workspaceCollection.workspaces.count > 1 {
                Text(workspace.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                ForEach(workspace.sessionCollection.hierarchicalOrder(), id: \.session.id) { entry in
                    SessionOverviewCardView(
                        session: entry.session,
                        isActive: workspace.id == workspaceCollection.activeWorkspaceID
                            && entry.session.id == workspace.sessionCollection.activeSessionID,
                        isSelected: entry.session.id == selectedSessionID,
                        isOrchestrator: entry.isOrchestrator,
                        // Only the selected card renames; committing/cancelling
                        // clears the shared flag.
                        isRenaming: Binding(
                            get: { isRenamingSelection && entry.session.id == selectedSessionID },
                            set: { if !$0 { isRenamingSelection = false } }
                        ),
                        // Only the card whose id matches the armed confirm shows
                        // the popover; dismissing it (Cancel / click-away) clears
                        // the shared id.
                        isConfirmingDelete: Binding(
                            get: { confirmingDeleteSessionID == entry.session.id },
                            set: { if !$0 { confirmingDeleteSessionID = nil } }
                        ),
                        onConfirmDelete: confirmPendingDelete,
                        onSelect: { onSelect(workspace.id, entry.session.id) }
                    )
                }
            }
        }
    }

    // MARK: - Selection & navigation

    /// The card to select when the overview appears: the active workspace's
    /// active session if it's on screen, otherwise the first card.
    private func defaultSelection() -> UUID? {
        let cards = flatCards
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

    /// Move the selection one step in `direction` across the overview's stacked
    /// per-workspace grids (see `OverviewGridNavigation`): Left/Right walk the
    /// flat render order, Up/Down step between visual rows across workspace
    /// section boundaries preserving the column. Clamped to bounds (no wrap).
    private func move(_ direction: OverviewGridNavigation.Direction) {
        let sections = workspaceCollection.workspaces.map { workspace in
            workspace.sessionCollection.hierarchicalOrder().map(\.session.id)
        }
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
              let card = flatCards.first(where: { $0.id == id }) else { return }
        onSelect(card.workspaceID, card.sessionID)
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
        guard let card = flatCards.first(where: { $0.id == id }),
              let workspace = workspaceCollection.workspaces.first(where: { $0.id == card.workspaceID }),
              let session = workspace.sessionCollection.sessions.first(where: { $0.id == card.sessionID })
        else { return }
        SessionCloseFlow.run(
            session: session,
            in: workspace,
            worktreeOrchestrator: worktreeOrchestrator
        )
    }

    /// Dismiss the delete-confirmation popover without deleting (the popover's
    /// Cancel button / Escape).
    private func cancelPendingDelete() {
        confirmingDeleteSessionID = nil
    }

    /// Columns that fit `width` given the adaptive tile params (`cardMinWidth`
    /// minimum, `cardSpacing` gap). Guards a non-positive width by defaulting to
    /// a single column.
    nonisolated private func columnCount(forWidth width: CGFloat) -> Int {
        guard width > 0 else { return 1 }
        return max(1, Int((width + cardSpacing) / (cardMinWidth + cardSpacing)))
    }

    /// One card's place in the flat, render-order nav list.
    private struct FlatCard: Identifiable {
        let workspaceID: UUID
        let sessionID: UUID
        var id: UUID { sessionID }
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
                default: super.keyDown(with: event)
                }
            }
        }
    }
}
