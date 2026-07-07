import Testing
import Foundation
@testable import tian

/// v7 → v8 adds an optional `remote: RemoteConnectionState?` to `WorkspaceState`.
/// The field is optional, so a v7 record (no `remote` key) decodes as a local
/// workspace with no transformation, and a v8 record round-trips the remote.
struct SessionMigrationV7ToV8Tests {

    @Test func migrationForV7IsRegistered() {
        #expect(SessionStateMigrator.migrations[7] != nil)
    }

    @Test func v7ToV8IsANoOpPassThrough() throws {
        let migration = try #require(SessionStateMigrator.migrations[7])
        let input: [String: Any] = [
            "workspaces": [["id": UUID().uuidString, "name": "ws"]]
        ]
        let output = try migration(input)
        let workspaces = output["workspaces"] as! [[String: Any]]
        // No `remote` key was added; the dict passes through untouched.
        #expect(workspaces[0]["remote"] == nil)
    }

    @Test func currentVersionIsEight() {
        #expect(SessionSerializer.currentVersion == 8)
    }

    // MARK: - WorkspaceState decode

    @Test func v7WorkspaceStateDecodesRemoteAsNil() throws {
        // A pre-v8 WorkspaceState JSON has no `remote` key.
        let json = Data("""
        {
          "id": "\(UUID().uuidString)",
          "name": "local-ws",
          "activeSessionId": "\(UUID().uuidString)",
          "sessions": [],
          "windowFrame": null,
          "isFullscreen": null
        }
        """.utf8)
        let decoded = try JSONDecoder().decode(WorkspaceState.self, from: json)
        #expect(decoded.remote == nil)
    }

    // MARK: - Validation skips local disk for remote

    @Test func remoteWorkspaceSkipsLocalDiskValidation() throws {
        // A remote path that will never exist on the local disk.
        let remotePath = "/remote/only/\(UUID().uuidString)"
        let sessionID = UUID()
        let record = SessionRecord(
            id: sessionID,
            customName: nil,
            defaultWorkingDirectory: remotePath,
            worktreePath: nil,
            claudePane: PaneLeafState(paneID: UUID(), workingDirectory: remotePath),
            terminalRoot: nil,
            terminalFocusedPaneId: nil,
            terminalVisible: false,
            dockPosition: .bottom,
            splitRatio: 0.7,
            focusedArea: .claude,
            parentSessionID: nil
        )
        let ws = WorkspaceState(
            id: UUID(),
            name: "remote",
            activeSessionId: sessionID,
            defaultWorkingDirectory: remotePath,
            sessions: [record],
            windowFrame: nil,
            isFullscreen: nil,
            remote: RemoteConnectionState(host: "h", remoteDirectory: remotePath)
        )
        let state = SessionState(
            version: SessionSerializer.currentVersion,
            savedAt: Date(timeIntervalSince1970: 1),
            activeWorkspaceId: ws.id,
            workspaces: [ws]
        )

        let validated = try SessionRestorer.validate(state)
        let vws = validated.workspaces[0]
        // Remote paths survive — they aren't resolved/nulled against local disk.
        #expect(vws.defaultWorkingDirectory == remotePath)
        #expect(vws.sessions[0].defaultWorkingDirectory == remotePath)
        #expect(vws.sessions[0].claudePane?.workingDirectory == remotePath)
        #expect(vws.remote?.remoteDirectory == remotePath)
    }

    @Test func v8WorkspaceStateRoundTripsRemote() throws {
        let original = WorkspaceState(
            id: UUID(),
            name: "remote-ws",
            activeSessionId: UUID(),
            defaultWorkingDirectory: "/srv/app",
            sessions: [],
            windowFrame: nil,
            isFullscreen: nil,
            remote: RemoteConnectionState(host: "myserver", remoteDirectory: "/srv/app")
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WorkspaceState.self, from: data)
        #expect(decoded.remote?.host == "myserver")
        #expect(decoded.remote?.remoteDirectory == "/srv/app")
        #expect(decoded == original)
    }
}
