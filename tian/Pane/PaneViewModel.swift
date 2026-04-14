import AppKit
import Observation

/// Central coordinator for pane splitting within a single window.
///
/// Owns the `SplitTree` (value-type source of truth) and a registry
/// mapping pane UUIDs to `GhosttyTerminalSurface` instances.
@MainActor @Observable
final class PaneViewModel {
    // MARK: - State

    private(set) var splitTree: SplitTree
    private(set) var surfaces: [UUID: GhosttyTerminalSurface] = [:]
    /// Persistent NSViews keyed by pane ID. Survives SwiftUI view hierarchy changes.
    private(set) var surfaceViews: [UUID: TerminalSurfaceView] = [:]
    /// Per-pane lifecycle state (running, exited, spawn-failed).
    private(set) var paneStates: [UUID: PaneState] = [:]

    /// Per-pane restore commands registered via IPC. Persisted across sessions.
    private(set) var restoreCommands: [UUID: String] = [:]

    /// Panes that have an active bell notification (glow indicator).
    private(set) var bellNotifications: Set<UUID> = []

    /// The container size for the split tree view, updated from the view layer.
    /// Used to compute pane frames for spatial navigation.
    var containerSize: CGSize = .zero

    /// Window title from the focused pane's terminal.
    var title: String = "tian"

    /// Set to `true` when the last pane is closed; the window should dismiss.
    var shouldDismiss: Bool = false

    /// Called when the last pane is closed. Used by TabModel to trigger cascading close.
    var onEmpty: (() -> Void)?

    /// Provides the space/workspace default directory when pane-level resolution fails.
    /// Set by the owning SpaceModel so PaneViewModel doesn't need to know the hierarchy.
    var directoryFallback: (() -> String?)?

    /// Called when a pane's working directory changes (OSC 7).
    /// Parameters: (paneID, newDirectory).
    var onPaneDirectoryChanged: ((UUID, String) -> Void)?

    /// Called when a pane is closed. Parameter: paneID.
    var onPaneRemoved: ((UUID) -> Void)?

    /// Hierarchy IDs for building TIAN_* environment variables.
    /// Set by the owning SpaceModel via `wireHierarchyContext`.
    var hierarchyContext: PaneHierarchyContext?

    // MARK: - Private

    nonisolated(unsafe) private var observers: [NSObjectProtocol] = []

    // MARK: - Init

    init(workingDirectory: String = "~") {
        let initialID = UUID()
        let surface = GhosttyTerminalSurface()
        let surfaceView = TerminalSurfaceView()
        surfaceView.terminalSurface = surface
        surfaceView.initialWorkingDirectory = workingDirectory
        self.splitTree = SplitTree(paneID: initialID, workingDirectory: workingDirectory)
        self.surfaces[initialID] = surface
        self.surfaceViews[initialID] = surfaceView
        self.paneStates[initialID] = .running
        installObservers()
    }

    static func fromState(_ root: PaneNodeState, focusedPaneID: UUID) -> PaneViewModel {
        var surfaces: [UUID: GhosttyTerminalSurface] = [:]
        var surfaceViews: [UUID: TerminalSurfaceView] = [:]
        var restoreCommands: [UUID: String] = [:]
        var sessionStates: [UUID: ClaudeSessionState] = [:]
        let paneNode = Self.buildPaneNode(from: root, surfaces: &surfaces, surfaceViews: &surfaceViews, restoreCommands: &restoreCommands, sessionStates: &sessionStates)
        let splitTree = SplitTree(root: paneNode, focusedPaneID: focusedPaneID)
        let pvm = PaneViewModel(splitTree: splitTree, surfaces: surfaces, surfaceViews: surfaceViews)
        pvm.restoreCommands = restoreCommands
        for (paneID, state) in sessionStates {
            PaneStatusManager.shared.setSessionState(paneID: paneID, state: state)
        }
        return pvm
    }

    private init(
        splitTree: SplitTree,
        surfaces: [UUID: GhosttyTerminalSurface],
        surfaceViews: [UUID: TerminalSurfaceView]
    ) {
        self.splitTree = splitTree
        self.surfaces = surfaces
        self.surfaceViews = surfaceViews
        self.paneStates = Dictionary(uniqueKeysWithValues: surfaces.keys.map { ($0, PaneState.running) })
        installObservers()
    }

    private func installObservers() {
        observers.append(NotificationCenter.default.addObserver(
            forName: GhosttyApp.surfaceCloseNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let self,
                  let surfaceId = notification.userInfo?["surfaceId"] as? UUID else { return }
            guard let paneID = self.paneID(forSurfaceID: surfaceId) else { return }
            self.closePane(paneID: paneID)
        })

        observers.append(NotificationCenter.default.addObserver(
            forName: GhosttyApp.surfaceExitedNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let self,
                  let surfaceId = notification.userInfo?["surfaceId"] as? UUID,
                  let exitCode = notification.userInfo?["exitCode"] as? UInt32 else { return }
            guard let paneID = self.paneID(forSurfaceID: surfaceId) else { return }
            if exitCode == 0 {
                self.closePane(paneID: paneID)
            } else {
                self.paneStates[paneID] = .exited(code: exitCode)
            }
        })

        observers.append(NotificationCenter.default.addObserver(
            forName: GhosttyApp.surfaceSpawnFailedNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let self,
                  let surfaceId = notification.userInfo?["surfaceId"] as? UUID else { return }
            guard let paneID = self.paneID(forSurfaceID: surfaceId) else { return }
            self.paneStates[paneID] = .spawnFailed
        })

        observers.append(NotificationCenter.default.addObserver(
            forName: GhosttyApp.surfaceTitleNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let self,
                  let surfaceId = notification.userInfo?["surfaceId"] as? UUID,
                  let newTitle = notification.userInfo?["title"] as? String else { return }
            if let focusedSurface = self.surfaces[self.splitTree.focusedPaneID],
               focusedSurface.id == surfaceId {
                self.title = newTitle
            }
        })

        observers.append(NotificationCenter.default.addObserver(
            forName: GhosttyApp.surfacePwdNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let self,
                  let surfaceId = notification.userInfo?["surfaceId"] as? UUID,
                  let pwd = notification.userInfo?["pwd"] as? String else { return }
            guard let paneID = self.paneID(forSurfaceID: surfaceId) else { return }
            self.splitTree.updateWorkingDirectory(paneID: paneID, newWorkingDirectory: pwd)
            self.onPaneDirectoryChanged?(paneID, pwd)
        })

        observers.append(NotificationCenter.default.addObserver(
            forName: GhosttyApp.surfaceBellNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let paneID: UUID?
            if let directPaneId = notification.userInfo?["paneId"] as? UUID {
                // From IPC (tian-cli notify) — paneId provided directly
                paneID = self.surfaces.keys.contains(directPaneId) ? directPaneId : nil
            } else if let surfaceId = notification.userInfo?["surfaceId"] as? UUID {
                // From ghostty bell callback — resolve via surface ID
                paneID = self.paneID(forSurfaceID: surfaceId)
            } else {
                paneID = nil
            }
            guard let paneID, paneID != self.splitTree.focusedPaneID else { return }
            self.bellNotifications.insert(paneID)
        })
    }

    private static func buildPaneNode(
        from state: PaneNodeState,
        surfaces: inout [UUID: GhosttyTerminalSurface],
        surfaceViews: inout [UUID: TerminalSurfaceView],
        restoreCommands: inout [UUID: String],
        sessionStates: inout [UUID: ClaudeSessionState]
    ) -> PaneNode {
        switch state {
        case .pane(let leaf):
            let surface = GhosttyTerminalSurface()
            let surfaceView = TerminalSurfaceView()
            surfaceView.terminalSurface = surface
            surfaceView.initialWorkingDirectory = leaf.workingDirectory
            surfaces[leaf.paneID] = surface
            surfaceViews[leaf.paneID] = surfaceView
            if let cmd = leaf.restoreCommand {
                restoreCommands[leaf.paneID] = cmd
                surfaceView.initialInput = cmd + "\n"
            }
            if let state = leaf.claudeSessionState {
                sessionStates[leaf.paneID] = state
            }
            return .leaf(paneID: leaf.paneID, workingDirectory: leaf.workingDirectory)

        case .split(let split):
            guard let direction = SplitDirection.from(stateValue: split.direction) else {
                // Invalid direction — treat as a single pane with the first leaf
                return buildPaneNode(from: split.first, surfaces: &surfaces, surfaceViews: &surfaceViews, restoreCommands: &restoreCommands, sessionStates: &sessionStates)
            }
            let first = buildPaneNode(from: split.first, surfaces: &surfaces, surfaceViews: &surfaceViews, restoreCommands: &restoreCommands, sessionStates: &sessionStates)
            let second = buildPaneNode(from: split.second, surfaces: &surfaces, surfaceViews: &surfaceViews, restoreCommands: &restoreCommands, sessionStates: &sessionStates)
            return .split(id: UUID(), direction: direction, ratio: split.ratio, first: first, second: second)
        }
    }

    // MARK: - Lookup

    func surface(for paneID: UUID) -> GhosttyTerminalSurface? {
        surfaces[paneID]
    }

    func surfaceView(for paneID: UUID) -> TerminalSurfaceView? {
        surfaceViews[paneID]
    }

    func paneState(for paneID: UUID) -> PaneState {
        paneStates[paneID] ?? .running
    }

    // MARK: - Operations

    @discardableResult
    func splitPane(direction: SplitDirection, targetPaneID: UUID? = nil) -> UUID? {
        // If a specific target pane is requested, temporarily focus it for the split
        if let targetPaneID, targetPaneID != splitTree.focusedPaneID {
            splitTree.focusedPaneID = targetPaneID
        }

        let newPaneID = UUID()
        let newSurface = GhosttyTerminalSurface()
        let newSurfaceView = TerminalSurfaceView()
        newSurfaceView.terminalSurface = newSurface

        let workingDirectory = resolveWorkingDirectory(for: splitTree.focusedPaneID)

        newSurfaceView.initialWorkingDirectory = workingDirectory
        newSurfaceView.environmentVariables = buildEnvironmentVariables(forPaneID: newPaneID)

        guard splitTree.insertSplit(
            direction: direction,
            newPaneID: newPaneID,
            newWorkingDirectory: workingDirectory
        ) else { return nil }

        surfaces[newPaneID] = newSurface
        surfaceViews[newPaneID] = newSurfaceView
        paneStates[newPaneID] = .running
        return newPaneID
    }

    func closePane(paneID: UUID) {
        let result = splitTree.removeLeaf(paneID: paneID)
        guard result != .notFound else { return }

        surfaces[paneID]?.freeSurface()
        surfaces.removeValue(forKey: paneID)
        surfaceViews[paneID]?.removeFromSuperview()
        surfaceViews.removeValue(forKey: paneID)
        paneStates.removeValue(forKey: paneID)
        bellNotifications.remove(paneID)
        restoreCommands.removeValue(forKey: paneID)
        PaneStatusManager.shared.clearStatus(paneID: paneID)
        onPaneRemoved?(paneID)

        if result == .lastPane {
            if let onEmpty {
                onEmpty()
            } else {
                shouldDismiss = true
            }
        }
    }

    func focusPane(paneID: UUID) {
        guard splitTree.focusedPaneID != paneID else { return }
        splitTree.focusedPaneID = paneID
        bellNotifications.remove(paneID)
        // Update title from the newly focused pane
        // (title will update on next surfaceTitleNotification from that pane)
    }

    func focusDirection(_ direction: NavigationDirection) {
        guard containerSize.width > 0, containerSize.height > 0 else { return }
        let rect = CGRect(origin: .zero, size: containerSize)
        let layoutResult = SplitLayout.layout(node: splitTree.root, in: rect)
        guard let targetID = SplitNavigation.neighbor(
            of: splitTree.focusedPaneID,
            direction: direction,
            in: layoutResult.paneFrames
        ) else { return }
        focusPane(paneID: targetID)
    }

    func updateRatio(splitID: UUID, newRatio: Double) {
        splitTree.updateRatio(splitID: splitID, newRatio: newRatio)
    }

    func setRestoreCommand(paneID: UUID, command: String) {
        restoreCommands[paneID] = command
    }

    func restoreCommand(for paneID: UUID) -> String? {
        restoreCommands[paneID]
    }

    /// Restart the shell in an existing pane (destroy old surface, create new one).
    func restartShell(paneID: UUID) {
        guard let state = paneStates[paneID] else { return }
        switch state {
        case .exited, .spawnFailed: break
        case .running: return
        }
        guard let surfaceView = surfaceViews[paneID] else { return }

        surfaces[paneID]?.freeSurface()

        let newSurface = GhosttyTerminalSurface()
        surfaceView.terminalSurface = newSurface
        surfaces[paneID] = newSurface
        paneStates[paneID] = .running

        let workingDirectory = resolveWorkingDirectory(for: paneID)
        surfaceView.initialWorkingDirectory = workingDirectory
        surfaceView.environmentVariables = buildEnvironmentVariables(forPaneID: paneID)

        if surfaceView.window != nil {
            newSurface.createSurface(view: surfaceView, workingDirectory: workingDirectory, environmentVariables: surfaceView.environmentVariables)
        }
    }

    // MARK: - Cleanup

    func cleanup() {
        let paneIDs = splitTree.allLeaves()

        for surface in surfaces.values {
            surface.freeSurface()
        }
        surfaces.removeAll()
        surfaceViews.removeAll()
        paneStates.removeAll()
        restoreCommands.removeAll()

        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()

        for paneID in paneIDs {
            PaneStatusManager.shared.clearStatus(paneID: paneID)
            onPaneRemoved?(paneID)
        }
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Private

    /// Builds TIAN_* environment variables for a specific pane using the hierarchy context.
    private func buildEnvironmentVariables(forPaneID paneID: UUID) -> [String: String] {
        guard let ctx = hierarchyContext else { return [:] }
        return EnvironmentBuilder.buildPaneEnvironment(
            socketPath: ctx.socketPath,
            paneID: paneID,
            tabID: ctx.tabID,
            spaceID: ctx.spaceID,
            workspaceID: ctx.workspaceID,
            cliPath: ctx.cliPath
        )
    }

    /// Applies TIAN_* environment variables to all existing surface views.
    /// Called after `hierarchyContext` is set.
    func applyEnvironmentVariables() {
        guard hierarchyContext != nil else { return }
        for (paneID, surfaceView) in surfaceViews {
            surfaceView.environmentVariables = buildEnvironmentVariables(forPaneID: paneID)
        }
    }

    /// Resolve working directory for a pane: inherited config (OSC 7) -> tree -> space/workspace default -> $HOME.
    private func resolveWorkingDirectory(for paneID: UUID) -> String {
        if let surface = surfaces[paneID]?.surface {
            // working_directory is zig-allocated; C API has no free function (same in Ghostty's own app)
            let inherited = ghostty_surface_inherited_config(surface, GHOSTTY_SURFACE_CONTEXT_SPLIT)
            if let wdPtr = inherited.working_directory {
                return String(cString: wdPtr)
            }
        }

        if case .leaf(_, let wd) = splitTree.findLeaf(paneID: paneID),
           !wd.isEmpty, wd != "~" {
            return wd
        }

        if let fallback = directoryFallback?() {
            return fallback
        }

        return ProcessInfo.processInfo.environment["HOME"] ?? "~"
    }

    /// Find the pane UUID that owns a surface with the given surface ID.
    func paneID(forSurfaceID surfaceID: UUID) -> UUID? {
        surfaces.first(where: { $0.value.id == surfaceID })?.key
    }
}
