import AppKit
import Foundation

/// Turns Claude session-state transitions into precise, focus-gated macOS
/// banners — the counterpart to the sidebar dot. Fires only on the three
/// moments the user asked for (task done, input needed, a question), never on
/// intermediate progress, and never for a session the user is already looking
/// at. This replaces the old firehose where every OSC desktop notification
/// Claude emitted was forwarded verbatim (now suppressed for Claude panes in
/// `GhosttyApp`).
///
/// `ClaudeNotificationPolicy` decides *whether* to notify; this type owns the
/// side-effecting parts: the focus gate, debounce, and delivery.
@MainActor
final class ClaudeSessionNotifier {
    private let windowCoordinator: WindowCoordinator
    private let statusManager: PaneStatusManager
    private let notificationManager: NotificationManager

    /// How long `idle` must persist before it counts as "done". Long enough to
    /// absorb the idle→busy flap and the sibling-hook ordering race, short
    /// enough to still feel immediate.
    private static let doneDebounce: Duration = .milliseconds(400)

    /// Debounces "done" notifications, keyed by pane. A turn-end (`idle`) is
    /// debounced because Claude reports `idle` for a beat between turns while a
    /// subagent is still running, and because the `Stop` hook sets `idle`
    /// *before* its sibling `activity.sync` hook updates background work — so we
    /// wait, then re-check, before declaring the session done.
    private lazy var doneCoalescer = EventCoalescer<UUID, (Session, PaneViewModel)>(interval: Self.doneDebounce) { [weak self] paneID, ctx in
        self?.fireDoneIfStillIdle(paneID: paneID, session: ctx.0, pvm: ctx.1)
    }

    init(
        windowCoordinator: WindowCoordinator,
        statusManager: PaneStatusManager = .shared,
        notificationManager: NotificationManager
    ) {
        self.windowCoordinator = windowCoordinator
        self.statusManager = statusManager
        self.notificationManager = notificationManager
    }

    /// Called on every Claude session-state write (from `IPCCommandHandler`),
    /// with the effective transition (`old`/`new` already reflect
    /// `ClaudeSessionState.canReplace`).
    func sessionStateChanged(
        paneID: UUID,
        session: Session,
        pvm: PaneViewModel,
        old: ClaudeSessionState?,
        new: ClaudeSessionState,
        hasBackgroundWork: Bool
    ) {
        guard pvm.kind == .claude else { return }

        // Any move off idle means the turn wasn't really over — drop a pending
        // "done" so it can't fire late.
        if new != .idle {
            doneCoalescer.cancel(key: paneID)
        }

        switch ClaudeNotificationPolicy.trigger(old: old, new: new, hasBackgroundWork: hasBackgroundWork) {
        case .needsAttention:
            // Urgent and non-flapping — fire immediately (the focus gate still
            // applies inside `deliver`).
            deliver(.needsAttention, paneID: paneID, session: session, pvm: pvm)
        case .done:
            doneCoalescer.submit(key: paneID, value: (session, pvm))
        case nil:
            break
        }
    }

    // MARK: - Done debounce

    /// Re-verifies the world still warrants "done" once the debounce elapses:
    /// still idle, and no background work slipped in during the debounce window.
    private func fireDoneIfStillIdle(paneID: UUID, session: Session, pvm: PaneViewModel) {
        guard statusManager.sessionState(for: paneID) == .idle,
              (statusManager.backgroundActivities[paneID] ?? []).isEmpty
        else { return }
        deliver(.done, paneID: paneID, session: session, pvm: pvm)
    }

    // MARK: - Delivery

    private func deliver(
        _ trigger: ClaudeNotificationTrigger,
        paneID: UUID,
        session: Session,
        pvm: PaneViewModel
    ) {
        // If the user is already looking right at this session, the banner is
        // pure noise — they can see the change.
        guard !isViewing(session: session, pvm: pvm) else { return }

        let title = session.displayName
        let body: String
        switch trigger {
        case .needsAttention: body = "Needs your input"
        case .done: body = "Finished — waiting for you"
        }

        let mgr = notificationManager
        Task { @MainActor in
            try? await mgr.sendNotification(message: body, title: title, subtitle: nil, paneID: paneID)
        }
    }

    /// Whether the user is currently viewing this exact session: tian is the
    /// active app, the session is the one visible in the key window, and its
    /// pane area holds focus. The complete form of the partial `focused` bool
    /// computed in `IPCCommandHandler.handlePaneList`.
    private func isViewing(session: Session, pvm: PaneViewModel) -> Bool {
        guard NSApp.isActive,
              let controller = windowCoordinator.controllerForKeyWindow(),
              controller.workspaceCollection.activeSessionCollection?.activeSession === session
        else { return false }
        return session.effectiveFocusedArea == pvm.kind
    }
}
