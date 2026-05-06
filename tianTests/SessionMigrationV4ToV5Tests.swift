import Testing
import Foundation
@testable import tian

struct SessionMigrationV4ToV5Tests {

    // PRD §7 — identity migration for v4 must be registered.
    @Test func migrationForV4IsRegistered() {
        #expect(SessionStateMigrator.migrations[4] != nil)
    }

    // PRD §7 — a v4 fixture (no inspect-panel fields) migrates to the current version;
    // the migrated JSON decodes into WorkspaceState with nil optional fields.
    @Test func v4FileDecodesAsV5WithDefaults() throws {
        let v4JSON = """
        {
          "version": 4,
          "savedAt": "2026-05-04T00:00:00Z",
          "activeWorkspaceId": "11111111-1111-1111-1111-111111111111",
          "workspaces": [{
            "id": "11111111-1111-1111-1111-111111111111",
            "name": "default",
            "activeSpaceId": "22222222-2222-2222-2222-222222222222",
            "defaultWorkingDirectory": "/tmp",
            "windowFrame": null,
            "isFullscreen": false,
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

        // Migration should succeed and bump version to 5.
        let migratedData = try SessionStateMigrator.migrateIfNeeded(data: v4JSON)!
        let json = try JSONSerialization.jsonObject(with: migratedData) as! [String: Any]
        #expect((json["version"] as? Int) == SessionSerializer.currentVersion)

        // Decode into typed model.
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let state = try decoder.decode(SessionState.self, from: migratedData)

        // The new optional fields should be nil (not present in v4 source).
        let ws = state.workspaces[0]
        #expect(ws.inspectPanelVisible == nil)
        #expect(ws.inspectPanelWidth == nil)
    }

    // PRD §7 — runtime restorer applies defaults when fields are nil.
    @MainActor
    @Test func runtimeAppliesDefaultsForNilInspectPanelFields() {
        // Verify InspectPanelState.restore applies correct defaults when both fields are nil.
        let state = InspectPanelState.restore(visible: nil, width: nil)
        #expect(state.isVisible == true)
        #expect(state.width == InspectPanelState.defaultWidth)
    }

    // PRD §7 — v5 round-trip: encode non-default values, decode, verify preservation.
    @Test func v5RoundTripPreservesValues() throws {
        let wsState = WorkspaceState(
            id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
            name: "myWorkspace",
            activeSpaceId: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!,
            defaultWorkingDirectory: nil,
            spaces: [],
            windowFrame: nil,
            isFullscreen: nil,
            inspectPanelVisible: false,
            inspectPanelWidth: 420.0
        )

        let sessionState = SessionState(
            version: 5,
            savedAt: Date(timeIntervalSince1970: 1_000_000),
            activeWorkspaceId: wsState.id,
            workspaces: [wsState]
        )

        // Encode and re-decode without migration (already at v5).
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(sessionState)

        let migratedData = try SessionStateMigrator.migrateIfNeeded(data: data)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(SessionState.self, from: migratedData)

        let decodedWs = decoded.workspaces[0]
        #expect(decodedWs.inspectPanelVisible == false)
        #expect(decodedWs.inspectPanelWidth == 420.0)
    }
}
