import AppKit
import SwiftUI

/// A Mission-Control-style overview of every Claude session across all
/// workspaces, laid out as a grid of `SessionOverviewCardView` cards covering
/// the whole session area with a full-bleed `.ultraThinMaterial` frosted
/// backdrop that the session content behind blurs through.
///
/// Fully keyboard-driven: arrow keys move a visible card selection in true 2D,
/// Return/keypad Enter opens the selected session, Escape dismisses. Clicking a
/// card selects that session too.
struct SessionOverviewGridView: View {
    let workspaceCollection: WorkspaceCollection
    let onSelect: (_ workspaceID: UUID, _ sessionID: UUID) -> Void
    let onDismiss: () -> Void

    /// The keyboard-selected card. Defaults to the active session on appear and
    /// is kept valid (falls back to the first card) if the list changes.
    @State private var selectedSessionID: UUID?
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
                onEscape: onDismiss
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

    func makeNSView(context: Context) -> KeyView {
        KeyView()
    }

    func updateNSView(_ nsView: KeyView, context: Context) {
        // Reassign every update so the closures always capture the latest
        // selection + column count from the SwiftUI view.
        nsView.onArrow = onArrow
        nsView.onActivate = onActivate
        nsView.onEscape = onEscape
        // The overview is only in the hierarchy while visible, so claim first
        // responder as soon as we're in a window (and keep it if it slips away).
        if let window = nsView.window, window.firstResponder !== nsView {
            window.makeFirstResponder(nsView)
        }
    }

    final class KeyView: NSView {
        var onArrow: ((OverviewGridNavigation.Direction) -> Void)?
        var onActivate: (() -> Void)?
        var onEscape: (() -> Void)?

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
                super.keyDown(with: event)
            }
        }
    }
}
