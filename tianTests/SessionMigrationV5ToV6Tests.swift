import Testing
import Foundation
@testable import tian

struct SessionMigrationV5ToV6Tests {

    // FR-T29 / FR-T31 — migration for v5 must be registered.
    @Test func migrationForV5IsRegistered() {
        #expect(SessionStateMigrator.migrations[5] != nil)
    }

    // FR-T31 — current schema version is 6.
    @Test func currentVersionIsSix() {
        #expect(SessionSerializer.currentVersion == 6)
    }

    // FR-T29 / FR-T31 — a v5 fixture (no activeTab field) migrates to v6;
    // the migrated JSON decodes into WorkspaceState with nil activeTab.
    @Test func v5FileMigratesToV6Defaults() throws {
        let v5JSON = """
        {
          "version": 5,
          "savedAt": "2026-05-07T00:00:00Z",
          "activeWorkspaceId": "11111111-1111-1111-1111-111111111111",
          "workspaces": [{
            "id": "11111111-1111-1111-1111-111111111111",
            "name": "default",
            "activeSpaceId": "22222222-2222-2222-2222-222222222222",
            "defaultWorkingDirectory": "/tmp",
            "windowFrame": null,
            "isFullscreen": false,
            "inspectPanelVisible": true,
            "inspectPanelWidth": 320.0,
            "spaces": [{
              "id": "22222222-2222-2222-2222-222222222222",
              "name": "default",
              "defaultWorkingDirectory": "/tmp",
              "worktreePath": null,
              "terminalVisible": false,
              "dockPosition": "right",
              "splitRatio": 0.7,
              "focusedSectionKind": "claude",
              "claudeSection": {
                "id": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
                "kind": "claude",
                "activeTabId": "33333333-3333-3333-3333-333333333333",
                "tabs": [{
                  "id": "33333333-3333-3333-3333-333333333333",
                  "name": null,
                  "activePaneId": "44444444-4444-4444-4444-444444444444",
                  "sectionKind": "claude",
                  "root": {"type":"pane","paneID":"44444444-4444-4444-4444-444444444444","workingDirectory":"/tmp","restoreCommand":null,"claudeSessionState":null}
                }]
              },
              "terminalSection": {
                "id": "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
                "kind": "terminal",
                "activeTabId": null,
                "tabs": []
              }
            }]
          }]
        }
        """.data(using: .utf8)!

        // Migration should succeed and bump version to 6.
        let migratedData = try SessionStateMigrator.migrateIfNeeded(data: v5JSON)!
        let json = try JSONSerialization.jsonObject(with: migratedData) as! [String: Any]
        #expect((json["version"] as? Int) == 6)

        // Decode into typed model.
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let state = try decoder.decode(SessionState.self, from: migratedData)

        // The new optional field should be nil (not present in v5 source).
        let ws = state.workspaces[0]
        #expect(ws.activeTab == nil)
    }

    // FR-T29 — v6 round-trip: encode non-default activeTab value, decode, verify preservation.
    @Test func roundTripPreservesNonDefault() throws {
        let wsState = WorkspaceState(
            id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
            name: "myWorkspace",
            activeSpaceId: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!,
            defaultWorkingDirectory: nil,
            spaces: [],
            windowFrame: nil,
            isFullscreen: nil,
            inspectPanelVisible: true,
            inspectPanelWidth: 320.0,
            activeTab: "diff"
        )

        let sessionState = SessionState(
            version: 6,
            savedAt: Date(timeIntervalSince1970: 1_000_000),
            activeWorkspaceId: wsState.id,
            workspaces: [wsState]
        )

        // Encode and re-decode without migration (already at v6).
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(sessionState)

        let migratedData = try SessionStateMigrator.migrateIfNeeded(data: data)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(SessionState.self, from: migratedData)

        let decodedWs = decoded.workspaces[0]
        #expect(decodedWs.activeTab == "diff")
    }
}
