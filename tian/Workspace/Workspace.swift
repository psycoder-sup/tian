import Foundation
import Observation

/// Serializable snapshot of a workspace's persisted fields.
struct WorkspaceSnapshot: Sendable, Codable {
    let id: UUID
    let name: String
    let defaultWorkingDirectory: URL?
    let createdAt: Date
    /// Added in schema v5. Optional for back-compat with older snapshots.
    let inspectPanelVisible: Bool?
    let inspectPanelWidth: Double?
    /// Added in schema v6. Optional for back-compat. Encodes the active
    /// inspect-panel tab (`InspectTab.rawValue`).
    let activeTab: String?
}

/// The top-level organizational unit in tian's 4-level hierarchy
/// (Workspace > Space > Tab > Pane). Each workspace maps to a project
/// and owns a collection of spaces.
@MainActor @Observable
final class Workspace: Identifiable {
    let id: UUID
    var name: String
    var defaultWorkingDirectory: URL?
    let createdAt: Date

    /// Remembers the last "Create worktree" checkbox state in the unified
    /// space-creation modal. Transient — not persisted in `WorkspaceSnapshot`,
    /// resets on app relaunch.
    var lastCreateWorktreeChoice: Bool?

    let spaceCollection: SpaceCollection

    /// Inspect panel visibility and width for this workspace's window.
    let inspectPanelState: InspectPanelState

    /// Workspace-scoped file tree view model for the inspect panel.
    /// Kept alive for the workspace lifetime so reopening the rail is
    /// instant — only `setRoot(_:)` is re-called when the active space
    /// changes. Torn down via `cleanup()` on workspace close.
    let inspectFileTreeViewModel: InspectFileTreeViewModel

    /// Holds the inspect panel's active tab + per-tab view-models
    /// (Diff / Branch). Lives above SwiftUI so the active tab survives
    /// space switches and the view-models survive panel hide/show.
    /// Persisted via `WorkspaceSnapshot.activeTab`.
    let inspectTabState: InspectTabState

    /// Called when the workspace's last space is closed.
    var onEmpty: (() -> Void)?

    // MARK: - Init

    convenience init(name: String, defaultWorkingDirectory: URL? = nil) {
        self.init(
            id: UUID(),
            name: name,
            defaultWorkingDirectory: defaultWorkingDirectory,
            createdAt: Date(),
            inspectPanelState: InspectPanelState(),
            inspectTabState: InspectTabState()
        )
    }

    private init(
        id: UUID,
        name: String,
        defaultWorkingDirectory: URL?,
        createdAt: Date,
        inspectPanelState: InspectPanelState = InspectPanelState(),
        inspectTabState: InspectTabState = InspectTabState()
    ) {
        self.id = id
        self.name = name
        self.defaultWorkingDirectory = defaultWorkingDirectory
        self.createdAt = createdAt
        self.inspectPanelState = inspectPanelState
        self.inspectTabState = inspectTabState
        self.inspectFileTreeViewModel = InspectFileTreeViewModel()

        let workingDir = defaultWorkingDirectory?.path
            ?? ProcessInfo.processInfo.environment["HOME"]
            ?? "~"
        self.spaceCollection = SpaceCollection(workingDirectory: workingDir)
        self.spaceCollection.propagateWorkspaceDefault(defaultWorkingDirectory)
        self.spaceCollection.propagateWorkspaceID(id)

        self.spaceCollection.onEmpty = { [weak self] in
            self?.onEmpty?()
        }
    }

    /// Restore a workspace with a pre-built SpaceCollection.
    init(
        id: UUID,
        name: String,
        defaultWorkingDirectory: URL?,
        spaceCollection: SpaceCollection,
        inspectPanelState: InspectPanelState = InspectPanelState(),
        inspectTabState: InspectTabState = InspectTabState()
    ) {
        self.id = id
        self.name = name
        self.defaultWorkingDirectory = defaultWorkingDirectory
        self.createdAt = Date()
        self.inspectPanelState = inspectPanelState
        self.inspectTabState = inspectTabState
        self.inspectFileTreeViewModel = InspectFileTreeViewModel()
        self.spaceCollection = spaceCollection
        self.spaceCollection.propagateWorkspaceDefault(defaultWorkingDirectory)
        self.spaceCollection.propagateWorkspaceID(id)

        self.spaceCollection.onEmpty = { [weak self] in
            self?.onEmpty?()
        }
    }

    /// Updates the default working directory and propagates to all spaces.
    func setDefaultWorkingDirectory(_ url: URL?) {
        defaultWorkingDirectory = url
        spaceCollection.propagateWorkspaceDefault(url)
    }

    // MARK: - Convenience Accessors

    var spaces: [SpaceModel] { spaceCollection.spaces }
    var activeSpaceID: UUID { spaceCollection.activeSpaceID }
    var activeSpace: SpaceModel? { spaceCollection.activeSpace }

    // MARK: - Lifecycle

    func cleanup() {
        inspectFileTreeViewModel.teardown()
        inspectTabState.diffViewModel.teardown()
        inspectTabState.branchViewModel.teardown()
        for space in spaceCollection.spaces {
            for tab in space.claudeSection.tabs {
                tab.cleanup()
            }
            for tab in space.terminalSection.tabs {
                tab.cleanup()
            }
        }
    }

    // MARK: - Inspect Panel

    /// Resolves the root directory the inspect panel should display for the
    /// given space. Per FR-10, the chain is space-level configured working
    /// directory → workspace's default working directory. Worktree-backed
    /// spaces (FR-10's "linked worktree") use `worktreePath` as their
    /// space-level directory. Returns `nil` when neither level has a
    /// configured directory — the panel renders the FR-18 empty state in
    /// that case (no `$HOME` fallback).
    func inspectPanelRoot(for space: SpaceModel?) -> URL? {
        guard let space else { return defaultWorkingDirectory }
        if let worktreePath = space.worktreePath {
            return worktreePath
        }
        if let spaceDir = space.defaultWorkingDirectory {
            return spaceDir
        }
        return defaultWorkingDirectory
    }

    // MARK: - Serialization

    var snapshot: WorkspaceSnapshot {
        WorkspaceSnapshot(
            id: id,
            name: name,
            defaultWorkingDirectory: defaultWorkingDirectory,
            createdAt: createdAt,
            inspectPanelVisible: inspectPanelState.isVisible,
            inspectPanelWidth: Double(inspectPanelState.width),
            activeTab: inspectTabState.activeTab.rawValue
        )
    }

    static func from(snapshot: WorkspaceSnapshot) -> Workspace {
        let initialTab: InspectTab = snapshot.activeTab
            .flatMap { InspectTab(rawValue: $0) } ?? .files
        return Workspace(
            id: snapshot.id,
            name: snapshot.name,
            defaultWorkingDirectory: snapshot.defaultWorkingDirectory,
            createdAt: snapshot.createdAt,
            inspectPanelState: InspectPanelState.restore(
                visible: snapshot.inspectPanelVisible,
                width: snapshot.inspectPanelWidth
            ),
            inspectTabState: InspectTabState(activeTab: initialTab)
        )
    }
}
