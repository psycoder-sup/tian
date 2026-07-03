import Testing
import Foundation
@testable import tian

/// v6 → v7 flattens Workspace → Space → Section → Tab into a flat list of
/// Sessions. These cover the per-space carve-up rules driven off raw v6-shape
/// JSON (see `LegacyFixtures`).
struct SessionMigrationV6ToV7Tests {

    // MARK: - Helpers

    /// Runs only the v6 → v7 step (does not bump the version field).
    private func migrate(_ state: [String: Any]) throws -> [String: Any] {
        let migration = try #require(SessionStateMigrator.migrations[6])
        return try migration(state)
    }

    /// The `sessions` array of the first workspace in a migrated dict.
    private func sessions(in migrated: [String: Any]) -> [[String: Any]] {
        let workspaces = migrated["workspaces"] as! [[String: Any]]
        return workspaces[0]["sessions"] as! [[String: Any]]
    }

    // MARK: - Guard rail

    @Test func migrationForV6IsRegistered() {
        #expect(SessionStateMigrator.migrations[6] != nil)
    }

    // MARK: - (1) Single claude tab inherits the active terminal tab

    @Test func singleClaudeTabBecomesOneSessionInheritingActiveTerminalTab() throws {
        let spaceId = UUID().uuidString
        let claudePaneID = UUID().uuidString
        let termTab1Pane = UUID().uuidString
        let termTab2Pane = UUID().uuidString
        let termTab2Id = UUID().uuidString

        let claude = LegacyFixtures.claudeTab(
            paneID: claudePaneID,
            workingDirectory: "/repo",
            restoreCommand: "claude --resume xyz",
            claudeSessionState: ["status": "idle", "sessionId": "s-1"]
        )
        let claudeSection = LegacyFixtures.section(kind: "claude", activeTabId: claude["id"] as? String, tabs: [claude])

        let termTab1 = LegacyFixtures.terminalTab(paneID: termTab1Pane)
        let termTab2 = LegacyFixtures.terminalTab(id: termTab2Id, paneID: termTab2Pane)
        // Active terminal tab is the SECOND one.
        let terminalSection = LegacyFixtures.section(kind: "terminal", activeTabId: termTab2Id, tabs: [termTab1, termTab2])

        let space = LegacyFixtures.space(
            id: spaceId,
            name: "MySpace",
            worktreePath: "/wt",
            terminalVisible: true,
            claudeSection: claudeSection,
            terminalSection: terminalSection
        )
        let ws = LegacyFixtures.workspace(activeSpaceId: spaceId, spaces: [space])
        let state = LegacyFixtures.state(activeWorkspaceId: ws["id"] as! String, workspaces: [ws])

        let migrated = try migrate(state)
        let result = sessions(in: migrated)

        #expect(result.count == 1)
        let session = result[0]
        #expect(session["id"] as? String == spaceId)
        #expect(session["customName"] as? String == "MySpace")
        #expect(session["worktreePath"] as? String == "/wt")

        // Claude pane preserves paneID / restoreCommand / claudeSessionState.
        let claudePane = session["claudePane"] as! [String: Any]
        #expect(claudePane["paneID"] as? String == claudePaneID)
        #expect(claudePane["workingDirectory"] as? String == "/repo")
        #expect(claudePane["restoreCommand"] as? String == "claude --resume xyz")
        let css = claudePane["claudeSessionState"] as! [String: Any]
        #expect(css["sessionId"] as? String == "s-1")
        // The claude pane node is a clean leaf (its "type" discriminator is stripped).
        #expect(claudePane["type"] == nil)

        // Terminal tree = the ACTIVE terminal tab (second). The other is dropped.
        let terminalRoot = session["terminalRoot"] as! [String: Any]
        #expect(terminalRoot["paneID"] as? String == termTab2Pane)
        #expect(session["terminalFocusedPaneId"] as? String == termTab2Pane)
        #expect(session["terminalVisible"] as? Bool == true)
    }

    // MARK: - (1b) Space name → primary customName ("default" maps to nil)

    @Test func defaultSpaceNameMapsToNilCustomName() throws {
        let spaceId = UUID().uuidString
        let claude = LegacyFixtures.claudeTab()
        let claudeSection = LegacyFixtures.section(kind: "claude", activeTabId: claude["id"] as? String, tabs: [claude])
        let terminalSection = LegacyFixtures.section(kind: "terminal", activeTabId: nil, tabs: [])

        let space = LegacyFixtures.space(id: spaceId, name: "default", claudeSection: claudeSection, terminalSection: terminalSection)
        let ws = LegacyFixtures.workspace(activeSpaceId: spaceId, spaces: [space])
        let state = LegacyFixtures.state(activeWorkspaceId: ws["id"] as! String, workspaces: [ws])

        let result = sessions(in: try migrate(state))
        #expect(result.count == 1)
        // The pre-flatten "default" placeholder name auto-derives (customName nil).
        #expect(result[0]["customName"] is NSNull)
    }

    @Test func nonDefaultSpaceNameBecomesPrimaryCustomName() throws {
        let spaceId = UUID().uuidString
        let claude = LegacyFixtures.claudeTab()
        let claudeSection = LegacyFixtures.section(kind: "claude", activeTabId: claude["id"] as? String, tabs: [claude])
        let terminalSection = LegacyFixtures.section(kind: "terminal", activeTabId: nil, tabs: [])

        let space = LegacyFixtures.space(id: spaceId, name: "Feature X", claudeSection: claudeSection, terminalSection: terminalSection)
        let ws = LegacyFixtures.workspace(activeSpaceId: spaceId, spaces: [space])
        let state = LegacyFixtures.state(activeWorkspaceId: ws["id"] as! String, workspaces: [ws])

        let result = sessions(in: try migrate(state))
        #expect(result[0]["customName"] as? String == "Feature X")
    }

    // MARK: - (2) Multiple claude tabs → primary + flat siblings

    @Test func multipleClaudeTabsBecomePrimaryPlusFlatSiblings() throws {
        let spaceId = UUID().uuidString
        let c1Id = UUID().uuidString
        let c2Id = UUID().uuidString  // active → primary
        let c3Id = UUID().uuidString

        let c1 = LegacyFixtures.claudeTab(id: c1Id, name: nil)                 // → auto (nil customName)
        let c2 = LegacyFixtures.claudeTab(id: c2Id, name: nil)                 // primary
        let c3 = LegacyFixtures.claudeTab(id: c3Id, name: "custom")           // named sibling
        let claudeSection = LegacyFixtures.section(kind: "claude", activeTabId: c2Id, tabs: [c1, c2, c3])

        let termPane = UUID().uuidString
        let termTab = LegacyFixtures.terminalTab(paneID: termPane)
        let terminalSection = LegacyFixtures.section(kind: "terminal", activeTabId: termTab["id"] as? String, tabs: [termTab])

        let space = LegacyFixtures.space(
            id: spaceId,
            name: "MySpace",
            terminalVisible: true,
            focusedSectionKind: "terminal",
            claudeSection: claudeSection,
            terminalSection: terminalSection
        )
        let ws = LegacyFixtures.workspace(activeSpaceId: spaceId, spaces: [space])
        let state = LegacyFixtures.state(activeWorkspaceId: ws["id"] as! String, workspaces: [ws])

        let migrated = try migrate(state)
        let result = sessions(in: migrated)

        #expect(result.count == 3)

        // Primary: id == space.id, has the terminal tree, keeps space focus.
        let primary = result.first { ($0["id"] as? String) == spaceId }!
        #expect(primary["customName"] as? String == "MySpace")
        #expect(primary["terminalRoot"] is [String: Any])
        #expect(primary["focusedArea"] as? String == "terminal")
        #expect(primary["parentSessionID"] is NSNull)

        // Sibling from the first (unnamed) tab: id == tab.id, no synthesized
        // name (customName null → auto), no terminal, claude focus, and NOT
        // nested under the primary.
        let sib1 = result.first { ($0["id"] as? String) == c1Id }!
        #expect(sib1["customName"] is NSNull)
        #expect(sib1["terminalRoot"] is NSNull)
        #expect(sib1["terminalVisible"] as? Bool == false)
        #expect(sib1["focusedArea"] as? String == "claude")
        #expect(sib1["parentSessionID"] is NSNull)

        // Sibling from the third tab keeps its explicit name.
        let sib3 = result.first { ($0["id"] as? String) == c3Id }!
        #expect(sib3["customName"] as? String == "custom")
        #expect(sib3["terminalRoot"] is NSNull)
    }

    // MARK: - (3) Reader tabs dropped

    @Test func readerClaudeTabsAreDropped() throws {
        let spaceId = UUID().uuidString
        let realPaneID = UUID().uuidString
        let realTab = LegacyFixtures.claudeTab(paneID: realPaneID)
        let reader = LegacyFixtures.markdownReaderTab()
        // Active tab is the reader, but readers are dropped; the real tab wins.
        let claudeSection = LegacyFixtures.section(kind: "claude", activeTabId: reader["id"] as? String, tabs: [reader, realTab])
        let terminalSection = LegacyFixtures.section(kind: "terminal", activeTabId: nil, tabs: [])

        let space = LegacyFixtures.space(id: spaceId, claudeSection: claudeSection, terminalSection: terminalSection)
        let ws = LegacyFixtures.workspace(activeSpaceId: spaceId, spaces: [space])
        let state = LegacyFixtures.state(activeWorkspaceId: ws["id"] as! String, workspaces: [ws])

        let result = sessions(in: try migrate(state))

        #expect(result.count == 1)
        let claudePane = result[0]["claudePane"] as! [String: Any]
        #expect(claudePane["paneID"] as? String == realPaneID)
    }

    @Test func spaceWithOnlyReaderClaudeTabsGetsNullClaudePane() throws {
        let spaceId = UUID().uuidString
        let md = LegacyFixtures.markdownReaderTab()
        let img = LegacyFixtures.imageReaderTab()
        let claudeSection = LegacyFixtures.section(kind: "claude", activeTabId: md["id"] as? String, tabs: [md, img])
        let terminalSection = LegacyFixtures.section(kind: "terminal", activeTabId: nil, tabs: [])

        let space = LegacyFixtures.space(id: spaceId, claudeSection: claudeSection, terminalSection: terminalSection)
        let ws = LegacyFixtures.workspace(activeSpaceId: spaceId, spaces: [space])
        let state = LegacyFixtures.state(activeWorkspaceId: ws["id"] as! String, workspaces: [ws])

        let result = sessions(in: try migrate(state))

        #expect(result.count == 1)
        #expect(result[0]["id"] as? String == spaceId)
        #expect(result[0]["claudePane"] is NSNull)
    }

    // MARK: - (4) Zero claude tabs → one null-claudePane session

    @Test func zeroClaudeTabsBecomesOneNullClaudeSession() throws {
        let spaceId = UUID().uuidString
        let termPane = UUID().uuidString
        let claudeSection = LegacyFixtures.section(kind: "claude", activeTabId: nil, tabs: [])
        let termTab = LegacyFixtures.terminalTab(paneID: termPane)
        let terminalSection = LegacyFixtures.section(kind: "terminal", activeTabId: termTab["id"] as? String, tabs: [termTab])

        let space = LegacyFixtures.space(id: spaceId, name: "empty", terminalVisible: true, claudeSection: claudeSection, terminalSection: terminalSection)
        let ws = LegacyFixtures.workspace(activeSpaceId: spaceId, spaces: [space])
        let state = LegacyFixtures.state(activeWorkspaceId: ws["id"] as! String, workspaces: [ws])

        let result = sessions(in: try migrate(state))

        #expect(result.count == 1)
        let session = result[0]
        #expect(session["id"] as? String == spaceId)
        #expect(session["claudePane"] is NSNull)
        // The space's terminal tree is preserved on the null-claude session.
        let terminalRoot = session["terminalRoot"] as! [String: Any]
        #expect(terminalRoot["paneID"] as? String == termPane)
    }

    // MARK: - (5) Split claude root collapses to depth-first first leaf

    @Test func splitClaudeRootCollapsesToFirstLeaf() throws {
        let spaceId = UUID().uuidString
        let leafA = UUID().uuidString
        let leafB = UUID().uuidString
        let splitRoot = LegacyFixtures.splitNode(
            first: LegacyFixtures.paneNode(paneID: leafA, workingDirectory: "/a"),
            second: LegacyFixtures.paneNode(paneID: leafB, workingDirectory: "/b")
        )
        let claudeTabId = UUID().uuidString
        let claude = LegacyFixtures.tab(id: claudeTabId, activePaneId: leafB, root: splitRoot, sectionKind: "claude")
        let claudeSection = LegacyFixtures.section(kind: "claude", activeTabId: claudeTabId, tabs: [claude])
        let terminalSection = LegacyFixtures.section(kind: "terminal", activeTabId: nil, tabs: [])

        let space = LegacyFixtures.space(id: spaceId, claudeSection: claudeSection, terminalSection: terminalSection)
        let ws = LegacyFixtures.workspace(activeSpaceId: spaceId, spaces: [space])
        let state = LegacyFixtures.state(activeWorkspaceId: ws["id"] as! String, workspaces: [ws])

        let result = sessions(in: try migrate(state))

        #expect(result.count == 1)
        let claudePane = result[0]["claudePane"] as! [String: Any]
        // Depth-first first leaf of the stray split.
        #expect(claudePane["paneID"] as? String == leafA)
        #expect(claudePane["workingDirectory"] as? String == "/a")
        #expect(claudePane["type"] == nil)
    }

    // MARK: - (6) Focus coercion when the terminal section is empty

    @Test func terminalFocusWithEmptyTerminalSectionCoercesToClaude() throws {
        let spaceId = UUID().uuidString
        let claude = LegacyFixtures.claudeTab()
        let claudeSection = LegacyFixtures.section(kind: "claude", activeTabId: claude["id"] as? String, tabs: [claude])
        let terminalSection = LegacyFixtures.section(kind: "terminal", activeTabId: nil, tabs: [])

        let space = LegacyFixtures.space(
            id: spaceId,
            terminalVisible: true,
            focusedSectionKind: "terminal",  // focus can't rest on an absent terminal
            claudeSection: claudeSection,
            terminalSection: terminalSection
        )
        let ws = LegacyFixtures.workspace(activeSpaceId: spaceId, spaces: [space])
        let state = LegacyFixtures.state(activeWorkspaceId: ws["id"] as! String, workspaces: [ws])

        let result = sessions(in: try migrate(state))

        let session = result[0]
        #expect(session["focusedArea"] as? String == "claude")
        #expect(session["terminalVisible"] as? Bool == false)
        #expect(session["terminalRoot"] is NSNull)
    }

    // MARK: - (7) parentSpaceID → parentSessionID

    @Test func parentSpaceIDBecomesParentSessionID() throws {
        let parentId = UUID().uuidString
        let spaceId = UUID().uuidString
        let claude = LegacyFixtures.claudeTab()
        let claudeSection = LegacyFixtures.section(kind: "claude", activeTabId: claude["id"] as? String, tabs: [claude])
        let terminalSection = LegacyFixtures.section(kind: "terminal", activeTabId: nil, tabs: [])

        let space = LegacyFixtures.space(id: spaceId, parentSpaceID: parentId, claudeSection: claudeSection, terminalSection: terminalSection)
        let ws = LegacyFixtures.workspace(activeSpaceId: spaceId, spaces: [space])
        let state = LegacyFixtures.state(activeWorkspaceId: ws["id"] as! String, workspaces: [ws])

        let result = sessions(in: try migrate(state))
        #expect(result[0]["parentSessionID"] as? String == parentId)
    }

    @Test func absentParentSpaceIDLeavesParentSessionIDNull() throws {
        let spaceId = UUID().uuidString
        let claude = LegacyFixtures.claudeTab()
        let claudeSection = LegacyFixtures.section(kind: "claude", activeTabId: claude["id"] as? String, tabs: [claude])
        let terminalSection = LegacyFixtures.section(kind: "terminal", activeTabId: nil, tabs: [])

        let space = LegacyFixtures.space(id: spaceId, claudeSection: claudeSection, terminalSection: terminalSection)
        let ws = LegacyFixtures.workspace(activeSpaceId: spaceId, spaces: [space])
        let state = LegacyFixtures.state(activeWorkspaceId: ws["id"] as! String, workspaces: [ws])

        let result = sessions(in: try migrate(state))
        #expect(result[0]["parentSessionID"] is NSNull)
    }

    // MARK: - (8) Workspace key renames

    @Test func workspaceKeysAreRenamedAndSpacesReplaced() throws {
        let spaceId = UUID().uuidString
        let claude = LegacyFixtures.claudeTab()
        let claudeSection = LegacyFixtures.section(kind: "claude", activeTabId: claude["id"] as? String, tabs: [claude])
        let terminalSection = LegacyFixtures.section(kind: "terminal", activeTabId: nil, tabs: [])

        let space = LegacyFixtures.space(id: spaceId, claudeSection: claudeSection, terminalSection: terminalSection)
        let ws = LegacyFixtures.workspace(activeSpaceId: spaceId, spaces: [space])
        let state = LegacyFixtures.state(activeWorkspaceId: ws["id"] as! String, workspaces: [ws])

        let migrated = try migrate(state)
        let workspace = (migrated["workspaces"] as! [[String: Any]])[0]

        // activeSpaceId → activeSessionId (points at the primary session, id == space.id).
        #expect(workspace["activeSessionId"] as? String == spaceId)
        #expect(workspace["activeSpaceId"] == nil)
        // spaces → sessions.
        #expect(workspace["sessions"] is [[String: Any]])
        #expect(workspace["spaces"] == nil)
    }

    // MARK: - (9) Full-chain v3 → v7 smoke

    @Test func fullChainV3ToV7DecodesAndValidates() throws {
        let v3 = """
        {
          "version": 3,
          "savedAt": "2026-04-20T00:00:00Z",
          "activeWorkspaceId": "11111111-1111-1111-1111-111111111111",
          "workspaces": [{
            "id": "11111111-1111-1111-1111-111111111111",
            "name": "default",
            "activeSpaceId": "22222222-2222-2222-2222-222222222222",
            "defaultWorkingDirectory": "/tmp",
            "spaces": [{
              "id": "22222222-2222-2222-2222-222222222222",
              "name": "default",
              "activeTabId": "33333333-3333-3333-3333-333333333333",
              "defaultWorkingDirectory": "/tmp",
              "tabs": [{
                "id": "33333333-3333-3333-3333-333333333333",
                "name": null,
                "activePaneId": "44444444-4444-4444-4444-444444444444",
                "root": {"type":"pane","paneID":"44444444-4444-4444-4444-444444444444","workingDirectory":"/tmp","restoreCommand":null,"claudeSessionState":null}
              }]
            }]
          }]
        }
        """.data(using: .utf8)!

        let migratedData = try #require(try SessionStateMigrator.migrateIfNeeded(data: v3))
        let json = try JSONSerialization.jsonObject(with: migratedData) as! [String: Any]
        #expect(json["version"] as? Int == SessionSerializer.currentVersion)

        // Decodes into the v7 typed model and passes validation.
        let decoded = try SessionRestorer.decode(from: migratedData)
        #expect(decoded.workspaces.count == 1)
        #expect(decoded.workspaces[0].sessions.count == 1)
        // The v3→v4 step synthesised a fresh Claude section, so the flattened
        // session has a live Claude pane.
        #expect(decoded.workspaces[0].sessions[0].claudePane != nil)

        let validated = try SessionRestorer.validate(decoded)
        #expect(validated.workspaces[0].sessions.count == 1)
        // activeSpaceId became activeSessionId, pointing at the primary session.
        #expect(validated.workspaces[0].activeSessionId == validated.workspaces[0].sessions[0].id)
    }
}
