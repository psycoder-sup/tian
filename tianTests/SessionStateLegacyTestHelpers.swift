import Foundation
@testable import tian

// Raw-JSON fixture builders for pre-v7 (v6-shape) session state.
//
// The v6→v7 migration operates on raw `[String: Any]` dictionaries (the v6
// Workspace → Space → Section → Tab typed models — `SpaceState`,
// `SectionState`, `TabState` — were deleted in the flatten refactor), so the
// migration suites drive it with these builders instead of typed models. A
// space carries a `claudeSection` and a `terminalSection`, each holding an
// ordered list of tabs; reader tabs additionally carry a `markdownFilePath` or
// `imageFilePath`.
enum LegacyFixtures {

    // MARK: - Pane nodes

    /// A leaf pane node dict (`"type": "pane"`).
    static func paneNode(
        paneID: String = UUID().uuidString,
        workingDirectory: String = "/tmp",
        restoreCommand: String? = nil,
        claudeSessionState: [String: Any]? = nil
    ) -> [String: Any] {
        [
            "type": "pane",
            "paneID": paneID,
            "workingDirectory": workingDirectory,
            "restoreCommand": restoreCommand ?? NSNull(),
            "claudeSessionState": claudeSessionState ?? NSNull(),
        ]
    }

    /// A split pane node dict (`"type": "split"`).
    static func splitNode(
        direction: String = "horizontal",
        ratio: Double = 0.5,
        first: [String: Any],
        second: [String: Any]
    ) -> [String: Any] {
        [
            "type": "split",
            "direction": direction,
            "ratio": ratio,
            "first": first,
            "second": second,
        ]
    }

    // MARK: - Tabs

    /// A tab dict. Pass `markdownFilePath` / `imageFilePath` to make it a reader
    /// tab (which the v7 migration drops).
    static func tab(
        id: String = UUID().uuidString,
        name: String? = nil,
        activePaneId: String,
        root: [String: Any],
        sectionKind: String,
        markdownFilePath: String? = nil,
        imageFilePath: String? = nil
    ) -> [String: Any] {
        var t: [String: Any] = [
            "id": id,
            "name": name ?? NSNull(),
            "activePaneId": activePaneId,
            "root": root,
            "sectionKind": sectionKind,
        ]
        if let markdownFilePath { t["markdownFilePath"] = markdownFilePath }
        if let imageFilePath { t["imageFilePath"] = imageFilePath }
        return t
    }

    /// A Claude tab whose root is a single pane leaf.
    static func claudeTab(
        id: String = UUID().uuidString,
        name: String? = nil,
        paneID: String = UUID().uuidString,
        workingDirectory: String = "/tmp",
        restoreCommand: String? = nil,
        claudeSessionState: [String: Any]? = nil
    ) -> [String: Any] {
        tab(
            id: id,
            name: name,
            activePaneId: paneID,
            root: paneNode(
                paneID: paneID,
                workingDirectory: workingDirectory,
                restoreCommand: restoreCommand,
                claudeSessionState: claudeSessionState
            ),
            sectionKind: "claude"
        )
    }

    /// A Terminal tab. Pass an explicit `root` for a split tree.
    static func terminalTab(
        id: String = UUID().uuidString,
        name: String? = nil,
        paneID: String = UUID().uuidString,
        workingDirectory: String = "/tmp",
        root: [String: Any]? = nil
    ) -> [String: Any] {
        tab(
            id: id,
            name: name,
            activePaneId: paneID,
            root: root ?? paneNode(paneID: paneID, workingDirectory: workingDirectory),
            sectionKind: "terminal"
        )
    }

    /// A reader (Markdown) tab — dropped by the v7 migration.
    static func markdownReaderTab(
        id: String = UUID().uuidString,
        paneID: String = UUID().uuidString,
        markdownFilePath: String = "/tmp/readme.md"
    ) -> [String: Any] {
        tab(
            id: id,
            name: "readme.md",
            activePaneId: paneID,
            root: paneNode(paneID: paneID),
            sectionKind: "claude",
            markdownFilePath: markdownFilePath
        )
    }

    /// A reader (image) tab — dropped by the v7 migration.
    static func imageReaderTab(
        id: String = UUID().uuidString,
        paneID: String = UUID().uuidString,
        imageFilePath: String = "/tmp/pic.png"
    ) -> [String: Any] {
        tab(
            id: id,
            name: "pic.png",
            activePaneId: paneID,
            root: paneNode(paneID: paneID),
            sectionKind: "claude",
            imageFilePath: imageFilePath
        )
    }

    // MARK: - Sections / spaces / workspaces

    static func section(kind: String, activeTabId: String?, tabs: [[String: Any]]) -> [String: Any] {
        [
            "id": UUID().uuidString,
            "kind": kind,
            "activeTabId": activeTabId ?? NSNull(),
            "tabs": tabs,
        ]
    }

    static func space(
        id: String = UUID().uuidString,
        name: String = "space",
        defaultWorkingDirectory: String? = "/tmp",
        worktreePath: String? = nil,
        parentSpaceID: String? = nil,
        terminalVisible: Bool = false,
        dockPosition: String = "right",
        splitRatio: Double = 0.7,
        focusedSectionKind: String = "claude",
        claudeSection: [String: Any],
        terminalSection: [String: Any]
    ) -> [String: Any] {
        var s: [String: Any] = [
            "id": id,
            "name": name,
            "defaultWorkingDirectory": defaultWorkingDirectory ?? NSNull(),
            "worktreePath": worktreePath ?? NSNull(),
            "terminalVisible": terminalVisible,
            "dockPosition": dockPosition,
            "splitRatio": splitRatio,
            "focusedSectionKind": focusedSectionKind,
            "claudeSection": claudeSection,
            "terminalSection": terminalSection,
        ]
        if let parentSpaceID { s["parentSpaceID"] = parentSpaceID }
        return s
    }

    static func workspace(
        id: String = UUID().uuidString,
        name: String = "default",
        activeSpaceId: String,
        defaultWorkingDirectory: String? = "/tmp",
        spaces: [[String: Any]]
    ) -> [String: Any] {
        [
            "id": id,
            "name": name,
            "activeSpaceId": activeSpaceId,
            "defaultWorkingDirectory": defaultWorkingDirectory ?? NSNull(),
            "windowFrame": NSNull(),
            "isFullscreen": false,
            "spaces": spaces,
        ]
    }

    static func state(
        version: Int = 6,
        activeWorkspaceId: String,
        workspaces: [[String: Any]]
    ) -> [String: Any] {
        [
            "version": version,
            "savedAt": "2026-06-01T00:00:00Z",
            "activeWorkspaceId": activeWorkspaceId,
            "workspaces": workspaces,
        ]
    }
}
