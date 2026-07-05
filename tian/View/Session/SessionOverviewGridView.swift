import AppKit
import SwiftUI

/// A Mission-Control-style overview of every Claude session across all
/// workspaces, laid out as a grid of `SessionOverviewCardView` cards over an
/// untinted Liquid Glass backdrop that the session content behind blurs
/// through. Tapping a card selects that session; Escape dismisses the overlay.
struct SessionOverviewGridView: View {
    let workspaceCollection: WorkspaceCollection
    let onSelect: (_ workspaceID: UUID, _ sessionID: UUID) -> Void
    let onDismiss: () -> Void

    /// Adaptive card columns — cards flow to fill the available width, each
    /// clamped to a tile-friendly size range.
    private let columns = [GridItem(.adaptive(minimum: 300, maximum: 460), spacing: 12)]

    /// `true` when no workspace holds any session — drives the empty state.
    private var isEmpty: Bool {
        workspaceCollection.workspaces.allSatisfy { $0.sessionCollection.sessions.isEmpty }
    }

    var body: some View {
        ZStack {
            // Liquid Glass backdrop (untinted) — the session content behind
            // blurs through the glass rather than being fully hidden.
            Rectangle()
                .fill(.clear)
                .glassEffect(.regular, in: Rectangle())
                .ignoresSafeArea()

            if isEmpty {
                Text("No sessions")
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(workspaceCollection.workspaces) { workspace in
                            workspaceSection(workspace)
                        }
                    }
                    .padding(20)
                }
            }
        }
        // The live terminal NSView behind this overlay stays the window's
        // first responder, so `.onExitCommand` never fires and a bare Escape
        // would leak into the running session's PTY. This 0×0 responder claims
        // first responder while the overview is mounted and intercepts Escape
        // itself, both dismissing the overview and swallowing the stray ESC.
        .background {
            OverviewKeyboardResponder(onEscape: onDismiss)
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
        }
        // Belt-and-suspenders: harmless if first-responder routing ever changes.
        .onExitCommand { onDismiss() }
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
                        isOrchestrator: entry.isOrchestrator,
                        onSelect: { onSelect(workspace.id, entry.session.id) }
                    )
                }
            }
        }
    }
}

// MARK: - Keyboard Responder

/// A 0×0 `NSView` that claims first responder while the overview is mounted so
/// Escape is intercepted here instead of leaking to the live terminal surface
/// behind the overlay. Mirrors `SidebarKeyboardResponder`.
private struct OverviewKeyboardResponder: NSViewRepresentable {
    let onEscape: () -> Void

    func makeNSView(context: Context) -> KeyView {
        KeyView()
    }

    func updateNSView(_ nsView: KeyView, context: Context) {
        nsView.onEscape = onEscape
        // The overview is only in the hierarchy while visible, so claim first
        // responder as soon as we're in a window (and keep it if it slips away).
        if let window = nsView.window, window.firstResponder !== nsView {
            window.makeFirstResponder(nsView)
        }
    }

    final class KeyView: NSView {
        var onEscape: (() -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.makeFirstResponder(self)
        }

        override func keyDown(with event: NSEvent) {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            switch event.keyCode {
            case 53 where flags.isEmpty:
                onEscape?()
            default:
                super.keyDown(with: event)
            }
        }
    }
}
