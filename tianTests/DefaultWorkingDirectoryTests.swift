import Testing
import Foundation
@testable import tian

@MainActor
struct DefaultWorkingDirectoryTests {
    // MARK: - Workspace Default Propagation

    @Test func workspaceDefaultPropagatedToSessionCollection() {
        let dir = URL(filePath: "/tmp/project")
        let ws = Workspace(name: "test", defaultWorkingDirectory: dir)
        #expect(ws.sessionCollection.workspaceDefaultDirectory == dir)
    }

    @Test func workspaceDefaultPropagatedToInitialSession() {
        let dir = URL(filePath: "/tmp/project")
        let ws = Workspace(name: "test", defaultWorkingDirectory: dir)
        #expect(ws.sessions[0].workspaceDefaultDirectory == dir)
    }

    @Test func setDefaultWorkingDirectoryPropagatesToAllSessions() {
        let ws = Workspace(name: "test")
        ws.sessionCollection.createSession()
        ws.sessionCollection.createSession()
        #expect(ws.sessions.count == 3)

        let dir = URL(filePath: "/tmp/new-project")
        ws.setDefaultWorkingDirectory(dir)

        #expect(ws.defaultWorkingDirectory == dir)
        #expect(ws.sessionCollection.workspaceDefaultDirectory == dir)
        for session in ws.sessions {
            #expect(session.workspaceDefaultDirectory == dir)
        }
    }

    @Test func clearDefaultWorkingDirectoryPropagatesToAllSessions() {
        let dir = URL(filePath: "/tmp/project")
        let ws = Workspace(name: "test", defaultWorkingDirectory: dir)
        ws.sessionCollection.createSession()

        ws.setDefaultWorkingDirectory(nil)

        #expect(ws.defaultWorkingDirectory == nil)
        #expect(ws.sessionCollection.workspaceDefaultDirectory == nil)
        for session in ws.sessions {
            #expect(session.workspaceDefaultDirectory == nil)
        }
    }

    @Test func newSessionInheritsWorkspaceDefault() {
        let dir = URL(filePath: "/tmp/project")
        let ws = Workspace(name: "test", defaultWorkingDirectory: dir)
        ws.sessionCollection.createSession()
        let newSession = ws.sessions.last!
        #expect(newSession.workspaceDefaultDirectory == dir)
    }

    // MARK: - PaneViewModel directoryFallback

    @Test func paneViewModelUsesDirectoryFallback() {
        let pvm = PaneViewModel()
        pvm.directoryFallback = { "/tmp/fallback" }
        // PaneViewModel doesn't expose resolveWorkingDirectory directly,
        // but we can verify the property is set.
        #expect(pvm.directoryFallback != nil)
        #expect(pvm.directoryFallback?() == "/tmp/fallback")
    }

    // MARK: - Session Directory Fallback Wiring

    @Test func sessionWiresDirectoryFallbackToClaudePane() throws {
        let session = Session(customName: "test", workingDirectory: "~")
        session.defaultWorkingDirectory = URL(filePath: "/tmp/session")
        session.workspaceDefaultDirectory = URL(filePath: "/tmp/workspace")
        // The fallback closure should resolve to the session default.
        let claude = try #require(session.claudePane)
        #expect(claude.directoryFallback?() == "/tmp/session")
    }

    @Test func sessionWiresDirectoryFallbackToTerminalPanel() throws {
        let session = Session(customName: "test", workingDirectory: "~")
        session.defaultWorkingDirectory = URL(filePath: "/tmp/session")
        session.showTerminal()
        let panel = try #require(session.terminalPanel)
        #expect(panel.directoryFallback?() == "/tmp/session")
    }

    @Test func sessionFallbackReturnsNilWhenNoDefaultsSet() throws {
        let session = Session(customName: "test", workingDirectory: "~")
        // No defaults set.
        let claude = try #require(session.claudePane)
        #expect(claude.directoryFallback?() == nil)
    }

    @Test func sessionFallbackUsesWorkspaceDefaultWhenNoSessionDefault() throws {
        let session = Session(customName: "test", workingDirectory: "~")
        session.workspaceDefaultDirectory = URL(filePath: "/tmp/workspace")
        let claude = try #require(session.claudePane)
        #expect(claude.directoryFallback?() == "/tmp/workspace")
    }

    // MARK: - End-to-End Hierarchy

    @Test func endToEndWorkspaceToSessionToPane() throws {
        let dir = URL(filePath: "/tmp/project")
        let ws = Workspace(name: "test", defaultWorkingDirectory: dir)

        // The seeded session's Claude pane carries a fallback that resolves to
        // the workspace default (inherited as the session default at create time).
        let session = ws.sessions[0]
        let claude = try #require(session.claudePane)
        #expect(claude.directoryFallback?() == "/tmp/project")
    }

    @Test func endToEndSessionDefaultOverridesWorkspace() throws {
        let wsDir = URL(filePath: "/tmp/workspace")
        let ws = Workspace(name: "test", defaultWorkingDirectory: wsDir)
        let session = ws.sessions[0]
        session.defaultWorkingDirectory = URL(filePath: "/tmp/session-override")

        let claude = try #require(session.claudePane)
        #expect(claude.directoryFallback?() == "/tmp/session-override")
    }
}
