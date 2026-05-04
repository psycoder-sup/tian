import Testing
import Foundation
@testable import tian

struct SessionMigrationV3ToV4Tests {

    // Guard rail: non-identity migration must be registered.
    @Test func migrationForV3IsRegistered() {
        #expect(SessionStateMigrator.migrations[3] != nil)
    }

    // FR-25 — legacy tabs move into terminalSection, claudeSection synthesised.
    @Test func v3SpaceWithTabsMigratesIntoTerminalSection() throws {
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

        let migrated = try SessionStateMigrator.migrateIfNeeded(data: v3)!
        let json = try JSONSerialization.jsonObject(with: migrated) as! [String: Any]
        // Migration chain runs v3→v4→v5, so the result is the current version.
        #expect((json["version"] as? Int) == SessionStateMigrator.currentVersion)

        let ws = (json["workspaces"] as! [[String: Any]])[0]
        let space = (ws["spaces"] as! [[String: Any]])[0]

        // Legacy tabs must be gone.
        #expect(space["tabs"] == nil)
        #expect(space["activeTabId"] == nil)

        // Terminal section carries legacy tabs.
        let terminal = space["terminalSection"] as! [String: Any]
        #expect((terminal["kind"] as? String) == "terminal")
        let termTabs = terminal["tabs"] as! [[String: Any]]
        #expect(termTabs.count == 1)
        #expect((termTabs[0]["id"] as? String) == "33333333-3333-3333-3333-333333333333")
        #expect((termTabs[0]["sectionKind"] as? String) == "terminal")

        // Claude section synthesised with one fresh tab.
        let claude = space["claudeSection"] as! [String: Any]
        #expect((claude["kind"] as? String) == "claude")
        #expect((claude["tabs"] as! [[String: Any]]).count == 1)

        // Layout defaults.
        #expect((space["terminalVisible"] as? Bool) == false)
        #expect((space["dockPosition"] as? String) == "right")
        #expect((space["splitRatio"] as? Double) == 0.7)
        #expect((space["focusedSectionKind"] as? String) == "claude")
    }

    // FR-25b — corrupted JSON surfaces as an error.
    @Test func corruptedV3DataThrowsMigrationError() {
        let corrupted = "{".data(using: .utf8)!
        #expect(throws: Error.self) {
            _ = try SessionStateMigrator.migrateIfNeeded(data: corrupted)
        }
    }

    // FR-25c — claudeSessionState on migrated shell panes is preserved verbatim
    // so the claude-session-status feature keeps working after upgrade.
    @Test func claudeSessionStateSurvivesMigration() throws {
        let v3 = """
        {
          "version": 3, "savedAt": "2026-04-20T00:00:00Z",
          "activeWorkspaceId": "11111111-1111-1111-1111-111111111111",
          "workspaces": [{
            "id": "11111111-1111-1111-1111-111111111111",
            "name": "default", "activeSpaceId": "22222222-2222-2222-2222-222222222222",
            "defaultWorkingDirectory": "/tmp",
            "spaces": [{
              "id": "22222222-2222-2222-2222-222222222222", "name": "default",
              "activeTabId": "33333333-3333-3333-3333-333333333333",
              "defaultWorkingDirectory": "/tmp",
              "tabs": [{
                "id": "33333333-3333-3333-3333-333333333333", "name": null,
                "activePaneId": "44444444-4444-4444-4444-444444444444",
                "root": {"type":"pane","paneID":"44444444-4444-4444-4444-444444444444",
                         "workingDirectory":"/tmp","restoreCommand":null,
                         "claudeSessionState":{"status":"idle","sessionId":"s-123"}}
              }]
            }]
          }]
        }
        """.data(using: .utf8)!

        let migrated = try SessionStateMigrator.migrateIfNeeded(data: v3)!
        let json = try JSONSerialization.jsonObject(with: migrated) as! [String: Any]
        let ws = (json["workspaces"] as! [[String: Any]])[0]
        let space = (ws["spaces"] as! [[String: Any]])[0]
        let terminal = space["terminalSection"] as! [String: Any]
        let tab = (terminal["tabs"] as! [[String: Any]])[0]
        let root = tab["root"] as! [String: Any]
        let css = root["claudeSessionState"] as! [String: Any]
        #expect((css["sessionId"] as? String) == "s-123")
    }
}
