import SwiftUI
import AppKit

struct TerminalContentView: NSViewRepresentable {
    let paneID: UUID
    let viewModel: PaneViewModel
    let isFocused: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(paneID: paneID, viewModel: viewModel)
    }

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true

        embedSurfaceView(in: container, coordinator: context.coordinator)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        context.coordinator.paneID = paneID
        context.coordinator.viewModel = viewModel

        // NOTE: Do NOT call embedSurfaceView here. During SwiftUI view transitions
        // (e.g., split→leaf after close), the dying view's updateNSView can fire
        // AFTER the new view's makeNSView, stealing the surfaceView back into the
        // dying container. Embedding only happens in makeNSView.

        guard let surfaceView = viewModel.surfaceView(for: paneID) else { return }

        // Sync input suppression for exited/failed panes
        let shouldSuppress = viewModel.paneState(for: paneID) != .running
        if surfaceView.isInputSuppressed != shouldSuppress {
            surfaceView.isInputSuppressed = shouldSuppress
        }

        // Sync frame — the initial embed may have happened when the container had zero bounds.
        if surfaceView.superview === container,
           container.bounds.size.width > 0,
           surfaceView.frame.size != container.bounds.size {
            surfaceView.frame = container.bounds
        }

        // Sync focus state. TerminalSurfaceView.shouldBeFocused defers the
        // actual makeFirstResponder to the next runloop tick — calling it
        // synchronously here re-entered SwiftUI's view graph via KVO and
        // hung the main thread.
        surfaceView.shouldBeFocused = isFocused
    }

    private func embedSurfaceView(in container: NSView, coordinator: Coordinator) {
        guard let surfaceView = viewModel.surfaceView(for: paneID) else { return }

        if surfaceView.superview === container {
            return
        }

        surfaceView.removeFromSuperview()
        surfaceView.frame = container.bounds
        surfaceView.autoresizingMask = [.width, .height]
        surfaceView.delegate = coordinator
        container.addSubview(surfaceView)
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: TerminalSurfaceViewDelegate {
        var paneID: UUID
        var viewModel: PaneViewModel

        init(paneID: UUID, viewModel: PaneViewModel) {
            self.paneID = paneID
            self.viewModel = viewModel
        }

        func terminalSurfaceViewRequestSplit(_ view: TerminalSurfaceView, direction: SplitDirection) {
            viewModel.splitPane(direction: direction)
        }

        func terminalSurfaceViewRequestClose(_ view: TerminalSurfaceView) {
            if let surface = viewModel.surface(for: paneID),
               ProcessDetector.needsConfirmation(surface: surface),
               let window = view.window {
                CloseConfirmationDialog.showSheet(
                    on: window,
                    target: .pane,
                    processCount: 1,
                    onCloseAnyway: { [self] in viewModel.closePane(paneID: paneID) }
                )
            } else {
                viewModel.closePane(paneID: paneID)
            }
        }

        func terminalSurfaceViewRequestFocusDirection(_ view: TerminalSurfaceView, direction: NavigationDirection) {
            viewModel.focusDirection(direction)
        }

        func terminalSurfaceViewDidFocus(_ view: TerminalSurfaceView) {
            viewModel.focusPane(paneID: paneID)
        }
    }
}
