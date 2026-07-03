import Testing
import Foundation
@testable import tian

@MainActor
struct SessionModelTests {

    // MARK: - Initial shape

    @Test func newSessionHasLiveClaudePaneAndHiddenTerminal() throws {
        let session = Session(customName: "s", workingDirectory: "/tmp")
        #expect(session.hasLiveClaudePane)
        let claude = try #require(session.claudePane)
        #expect(claude.kind == .claude)
        #expect(session.terminalPanel == nil)
        #expect(session.terminalVisible == false)
    }

    @Test func defaultDockPositionIsBottom() {
        let session = Session(customName: "s", workingDirectory: "/tmp")
        #expect(session.dockPosition == .bottom)
    }

    /// The seeded Claude pane autostarts `claude` via TIAN_AUTOSTART_CMD (run by
    /// the bundled `.zshrc`), not by injecting "claude\n" keystrokes.
    @Test func initialClaudePaneSeededWithClaudeAutostartCommand() throws {
        let session = Session(customName: "s", workingDirectory: "/tmp")
        let claude = try #require(session.claudePane)
        let paneID = claude.splitTree.focusedPaneID
        let view = claude.surfaceView(for: paneID)
        #expect(view?.environmentVariables["TIAN_AUTOSTART_CMD"] == "claude")
        #expect(view?.initialInput == nil)
    }

    // MARK: - Split gating (allowsSplits)

    /// A Claude pane is always a single leaf: `allowsSplits` is false and
    /// `splitPane` returns nil (the model backstop for IPC / [[layout]] / keyboard).
    @Test func claudePaneRejectsSplit() throws {
        let session = Session(customName: "s", workingDirectory: "/tmp")
        let claude = try #require(session.claudePane)
        #expect(claude.allowsSplits == false)
        #expect(claude.splitPane(direction: .horizontal) == nil)
        #expect(claude.splitTree.allLeaves().count == 1)
    }

    /// A terminal panel pane splits normally.
    @Test func terminalPanelAllowsSplit() throws {
        let session = Session(customName: "s", workingDirectory: "/tmp")
        session.showTerminal()
        let panel = try #require(session.terminalPanel)
        #expect(panel.allowsSplits == true)
        let newID = panel.splitPane(direction: .horizontal)
        #expect(newID != nil)
        #expect(panel.splitTree.allLeaves().count == 2)
    }

    // MARK: - Claude exit closes the session

    /// Closing the (single) Claude pane routes through the pane's `onEmpty`,
    /// which now closes the whole session (the Claude process already exited —
    /// no confirmation) by firing `onSessionClose`.
    @Test func closingClaudePaneClosesSession() throws {
        let session = Session(customName: "s", workingDirectory: "/tmp")
        var closed = false
        session.onSessionClose = { closed = true }

        let claude = try #require(session.claudePane)
        claude.closePane(paneID: claude.splitTree.focusedPaneID)

        #expect(closed == true)
    }

    // MARK: - Lazy terminal panel + onEmpty

    @Test func showTerminalLazilyCreatesPanelAndFocusesIt() throws {
        let session = Session(customName: "s", workingDirectory: "/tmp")
        #expect(session.terminalPanel == nil)

        session.showTerminal()

        let panel = try #require(session.terminalPanel)
        #expect(panel.kind == .terminal)
        #expect(session.terminalVisible == true)
        #expect(session.focusedArea == .terminal)
    }

    @Test func showTerminalInBackgroundCreatesPanelButKeepsFocusOnClaude() {
        let session = Session(customName: "s", workingDirectory: "/tmp")
        #expect(session.focusedArea == .claude)

        session.showTerminal(background: true)

        #expect(session.terminalPanel != nil)   // still created
        #expect(session.terminalVisible == true)
        #expect(session.focusedArea == .claude)  // focus untouched
    }

    /// Closing the last terminal pane routes through the panel's `onEmpty`, which
    /// drops the panel and auto-hides. The session (and Claude pane) stay alive.
    @Test func closingLastTerminalPaneDropsPanelAndHides() throws {
        let session = Session(customName: "s", workingDirectory: "/tmp")
        session.showTerminal()
        let panel = try #require(session.terminalPanel)

        panel.closePane(paneID: panel.splitTree.focusedPaneID)

        #expect(session.terminalPanel == nil)
        #expect(session.terminalVisible == false)
        #expect(session.hasLiveClaudePane)
    }

    // MARK: - Toggle / hide / reset

    @Test func toggleTerminalShowsThenHidesPreservingPanel() throws {
        let session = Session(customName: "s", workingDirectory: "/tmp")
        #expect(session.terminalVisible == false)

        session.toggleTerminal()
        #expect(session.terminalVisible == true)
        let panel = try #require(session.terminalPanel)
        let panelID = ObjectIdentifier(panel)

        session.toggleTerminal()
        #expect(session.terminalVisible == false)
        // Hide preserves the panel (only visibility flips).
        let stillThere = try #require(session.terminalPanel)
        #expect(ObjectIdentifier(stillThere) == panelID)
    }

    @Test func hideThenShowReusesSamePanel() throws {
        let session = Session(customName: "s", workingDirectory: "/tmp")
        session.showTerminal()
        let panelID = ObjectIdentifier(try #require(session.terminalPanel))

        session.hideTerminal()
        #expect(session.terminalVisible == false)
        #expect(session.terminalPanel != nil)

        session.showTerminal()
        #expect(ObjectIdentifier(try #require(session.terminalPanel)) == panelID)
    }

    @Test func resetTerminalPanelKillsPanelAndReturnsToClaude() {
        let session = Session(customName: "s", workingDirectory: "/tmp")
        session.showTerminal()
        #expect(session.terminalPanel != nil)

        session.resetTerminalPanel()

        #expect(session.terminalPanel == nil)
        #expect(session.terminalVisible == false)
        #expect(session.focusedArea == .claude)
    }

    // MARK: - startClaude respawn

    @Test func startClaudeReplacesExistingPane() throws {
        let session = Session(customName: "s", workingDirectory: "/tmp")
        let original = try #require(session.claudePane)

        let pane = session.startClaude()

        #expect(session.claudePane === pane)
        #expect(pane !== original)
        #expect(session.hasLiveClaudePane)
        #expect(session.focusedArea == .claude)
    }

    /// A default-command Claude pane records the resolved default as its launch
    /// command but shows no badge (plain `claude` sessions stay unmarked). Pin
    /// the setting to the bare default so the "no badge" outcome is deterministic
    /// regardless of any persisted custom command.
    @Test func startClaudeDefaultRecordsCommandWithoutBadge() {
        let original = TianSettings.shared.claudeCommand
        defer { TianSettings.shared.claudeCommand = original }
        TianSettings.shared.claudeCommand = ""   // → effectiveClaudeCommand == "claude"

        let session = Session(customName: "s", workingDirectory: "/tmp")
        #expect(session.claudeLaunchCommand == "claude")
        #expect(session.claudeLaunchBadge == nil)
    }

    /// A custom command is recorded, drives the badge, and seeds the pane's
    /// autostart env + per-pane restore override.
    @Test func startClaudeCustomCommandRecordsBadgeAndSeedsEnv() throws {
        let session = Session(customName: "s", workingDirectory: "/tmp")
        session.startClaude(customCommand: "claude --chrome")

        #expect(session.claudeLaunchCommand == "claude --chrome")
        #expect(session.claudeLaunchBadge?.symbol == "globe")

        let claude = try #require(session.claudePane)
        let paneID = claude.splitTree.focusedPaneID
        #expect(claude.surfaceView(for: paneID)?.environmentVariables["TIAN_AUTOSTART_CMD"] == "claude --chrome")
        #expect(claude.restoreCommand(for: paneID) == "claude --chrome")
    }

    @Test func claudeLaunchBadgeNilWhenNoClaudePane() {
        let session = Session(customName: "s", claudePane: nil, terminalPanel: nil)
        // No live Claude pane → no badge even if a launch command lingers.
        #expect(session.claudeLaunchBadge == nil)
    }

    // MARK: - effectiveFocusedArea / effectiveFocusedPane matrix

    @Test func effectiveFocusedAreaIsTerminalWhenVisibleAndPresent() {
        let session = Session(customName: "s", workingDirectory: "/tmp")
        session.showTerminal()
        #expect(session.effectiveFocusedArea == .terminal)
        #expect(session.effectiveFocusedPane === session.terminalPanel)
    }

    @Test func effectiveFocusedAreaFallsBackToClaudeWhenTerminalHidden() {
        let session = Session(customName: "s", workingDirectory: "/tmp")
        session.showTerminal()      // focusedArea := .terminal
        session.hideTerminal()      // hidden, but focusedArea stays .terminal
        #expect(session.focusedArea == .terminal)
        #expect(session.effectiveFocusedArea == .claude)
        #expect(session.effectiveFocusedPane === session.claudePane)
    }

    @Test func effectiveFocusedAreaFallsBackToClaudeWhenNoTerminalPanel() {
        let session = Session(customName: "s", workingDirectory: "/tmp")
        session.focusedArea = .terminal    // but no panel was ever created
        #expect(session.terminalPanel == nil)
        #expect(session.effectiveFocusedArea == .claude)
        #expect(session.effectiveFocusedPane === session.claudePane)
    }

    @Test func effectiveFocusedPaneNilWhenClaudeEmpty() {
        let session = Session(customName: "s", claudePane: nil, terminalPanel: nil)
        #expect(session.effectiveFocusedArea == .claude)
        #expect(session.effectiveFocusedPane == nil)
    }

    // MARK: - cycleFocusedArea guards

    @Test func cycleFocusedAreaMovesToTerminalWhenPresent() {
        let session = Session(customName: "s", workingDirectory: "/tmp")
        session.showTerminal(background: true)   // panel present, focus stays Claude
        #expect(session.focusedArea == .claude)

        session.cycleFocusedArea()
        #expect(session.focusedArea == .terminal)
    }

    @Test func cycleFocusedAreaNoOpWhenTerminalAbsent() {
        let session = Session(customName: "s", workingDirectory: "/tmp")
        #expect(session.terminalPanel == nil)
        #expect(session.focusedArea == .claude)

        session.cycleFocusedArea()   // no terminal panel → guard blocks
        #expect(session.focusedArea == .claude)
    }

    /// From the terminal area with the Claude pane empty, the guard blocks the
    /// cross-back (the target pane is nil).
    @Test func cycleFocusedAreaNoOpWhenTargetClaudeEmpty() {
        let terminal = PaneViewModel(kind: .terminal)
        let session = Session(
            customName: "s",
            claudePane: nil,
            terminalPanel: terminal,
            terminalVisible: true,
            focusedArea: .terminal
        )
        session.cycleFocusedArea()
        #expect(session.focusedArea == .terminal)
    }

    /// A terminal panel that exists but is hidden must never become the focused
    /// area — cycling from Claude stays on Claude (FR-20 hidden-area guard).
    @Test func cycleFocusedAreaNoOpWhenTerminalHidden() {
        let session = Session(customName: "s", workingDirectory: "/tmp")
        session.showTerminal(background: true)   // panel present + visible
        session.hideTerminal()                    // panel kept, now hidden
        #expect(session.terminalPanel != nil)
        #expect(session.terminalVisible == false)
        #expect(session.focusedArea == .claude)

        session.cycleFocusedArea()   // target terminal is hidden → guard blocks
        #expect(session.focusedArea == .claude)
    }

    // MARK: - PaneKind raw-value stability

    /// Raw values are persisted (session state) and emitted over IPC, so they
    /// must stay "claude" / "terminal".
    @Test func paneKindRawValuesAreStable() {
        #expect(PaneKind.claude.rawValue == "claude")
        #expect(PaneKind.terminal.rawValue == "terminal")
        #expect(PaneKind(rawValue: "claude") == .claude)
        #expect(PaneKind(rawValue: "terminal") == .terminal)
        #expect(PaneKind(rawValue: "reader") == nil)
        #expect(PaneKind.allCases.count == 2)
    }

    // MARK: - PaneSpawner

    @Test func paneSpawnerConfiguresClaudeAutostartEnv() {
        let view = TerminalSurfaceView()
        let env: [String: String] = ["TIAN_PANE_ID": "abc"]
        PaneSpawner.configure(view: view, kind: .claude, workingDirectory: "/tmp", environmentVariables: env)
        // Claude launches via TIAN_AUTOSTART_CMD (run by the bundled .zshrc),
        // not by injecting "claude\n" as keystrokes — so initialInput stays nil.
        #expect(view.initialInput == nil)
        #expect(view.environmentVariables["TIAN_AUTOSTART_CMD"] == "claude")
        #expect(view.initialWorkingDirectory == "/tmp")
        #expect(view.environmentVariables["TIAN_PANE_ID"] == "abc")
    }

    @Test func paneSpawnerTerminalLeavesInitialInputNilAndNoAutostart() {
        let view = TerminalSurfaceView()
        PaneSpawner.configure(view: view, kind: .terminal, workingDirectory: "/tmp", environmentVariables: ["TIAN_PANE_ID": "xyz"])
        #expect(view.initialInput == nil)
        #expect(view.environmentVariables["TIAN_AUTOSTART_CMD"] == nil)
        #expect(view.environmentVariables["TIAN_PANE_ID"] == "xyz")
    }

    @Test func customClaudeCommandFlowsIntoAutostartEnv() {
        let original = TianSettings.shared.claudeCommand
        defer { TianSettings.shared.claudeCommand = original }

        TianSettings.shared.claudeCommand = "claude --chrome"
        let env = PaneSpawner.autostartEnvironment(kind: .claude, base: [:])
        #expect(env["TIAN_AUTOSTART_CMD"] == "claude --chrome")
    }

    // MARK: - ClaudeLaunchBadge

    @Test func launchBadgeIsNilForDefaultAndEmptyCommands() {
        #expect(ClaudeLaunchBadge.forCommand("claude") == nil)
        #expect(ClaudeLaunchBadge.forCommand("  claude  ") == nil)
        #expect(ClaudeLaunchBadge.forCommand("") == nil)
        #expect(ClaudeLaunchBadge.forCommand("   ") == nil)
    }

    @Test func launchBadgeMapsKnownAndUnknownVariants() {
        #expect(ClaudeLaunchBadge.forCommand("claude --chrome")?.symbol == "globe")
        #expect(ClaudeLaunchBadge.forCommand("headroom wrap claude")?.symbol == "rectangle.compress.vertical")
        #expect(ClaudeLaunchBadge.forCommand("some-other-wrapper claude")?.symbol == "wand.and.stars")
        // The full (trimmed) command is preserved for the tooltip / a11y label.
        #expect(ClaudeLaunchBadge.forCommand("  claude --chrome ")?.command == "claude --chrome")
    }

    // MARK: - Exit-code behaviour

    /// FR-06: a Claude pane closes on any exit code. Closing the single Claude
    /// pane now closes the whole session (fires `onSessionClose`).
    @Test func claudeExitWithNonZeroCodeClosesSession() async throws {
        let session = Session(customName: "s", workingDirectory: "/tmp")
        var closed = false
        session.onSessionClose = { closed = true }
        let claude = try #require(session.claudePane)
        let paneID = claude.splitTree.focusedPaneID
        let surfaceID = try #require(claude.surface(for: paneID)?.id)

        NotificationCenter.default.post(
            name: GhosttyApp.surfaceExitedNotification,
            object: nil,
            userInfo: ["surfaceId": surfaceID, "exitCode": UInt32(1)]
        )
        try await Task.sleep(for: .milliseconds(10))

        #expect(closed == true)
    }

    /// A terminal pane keeps the exit-code overlay for a non-zero exit; the pane
    /// (and panel) stay in place.
    @Test func terminalExitWithNonZeroCodeKeepsPaneInExitedState() async throws {
        let session = Session(customName: "s", workingDirectory: "/tmp")
        session.showTerminal()
        let panel = try #require(session.terminalPanel)
        let paneID = panel.splitTree.focusedPaneID
        let surfaceID = try #require(panel.surface(for: paneID)?.id)

        NotificationCenter.default.post(
            name: GhosttyApp.surfaceExitedNotification,
            object: nil,
            userInfo: ["surfaceId": surfaceID, "exitCode": UInt32(1)]
        )
        try await Task.sleep(for: .milliseconds(10))

        if case .exited(let code) = panel.paneState(for: paneID) {
            #expect(code == 1)
        } else {
            Issue.record("Expected .exited state")
        }
        #expect(session.terminalPanel != nil)
    }

    // MARK: - Aggregates

    @Test func allPanesReflectsLiveClaudeAndTerminal() {
        let session = Session(customName: "s", workingDirectory: "/tmp")
        #expect(session.allPanes.count == 1)   // Claude only
        session.showTerminal()
        #expect(session.allPanes.count == 2)   // Claude + terminal panel
    }

    @Test func allPanesExcludesAbsentClaudePane() {
        let terminal = PaneViewModel(kind: .terminal)
        let session = Session(customName: "s", claudePane: nil, terminalPanel: terminal)
        #expect(session.allPanes.count == 1)   // terminal panel only
    }

    // MARK: - Naming (customName / displayName)

    @Test func displayNameUsesCustomNameWhenSet() {
        let session = Session(customName: "my-branch", workingDirectory: "/tmp/repo")
        #expect(session.displayName == "my-branch")
    }

    /// With no custom name and no live Claude title, the auto name falls through
    /// to the worktree path's last component.
    @Test func displayNameFallsBackToWorktreeLeaf() {
        let session = Session(
            customName: nil, claudePane: nil, terminalPanel: nil,
            worktreePath: "/tmp/worktrees/feature-x"
        )
        #expect(session.displayName == "feature-x")
    }

    /// Next fallback: the default working directory's last component.
    @Test func displayNameFallsBackToWorkingDirectoryLeaf() {
        let session = Session(
            customName: nil, claudePane: nil, terminalPanel: nil,
            defaultWorkingDirectory: URL(fileURLWithPath: "/tmp/my-project")
        )
        #expect(session.displayName == "my-project")
    }

    /// Final fallback when nothing else is available.
    @Test func displayNameFallsBackToSessionLiteral() {
        let session = Session(customName: nil, claudePane: nil, terminalPanel: nil)
        #expect(session.displayName == "session")
    }

    /// Clearing a rename (empty / whitespace-only) normalizes `customName` back
    /// to nil so the session returns to its auto-derived name.
    @Test func settingCustomNameToEmptyNormalizesToNil() {
        let session = Session(customName: "named", workingDirectory: "/tmp/repo")
        #expect(session.customName == "named")

        session.customName = ""
        #expect(session.customName == nil)

        session.customName = "   "
        #expect(session.customName == nil)
    }

    // MARK: - Worktree follow (claudeWorktreeRoot)

    /// `claudeWorktreeRoot` surfaces the git worktree the Claude pane resolved
    /// through its `SessionGitContext` (`paneWorktreeRoot`, keyed by the Claude
    /// pane's id).
    @Test func claudeWorktreeRootReflectsGitContextWorktree() async throws {
        let repo = try makeTempGitRepo()
        defer { try? FileManager.default.removeItem(atPath: repo) }

        let session = Session(customName: "s", workingDirectory: repo)
        let paneID = try #require(session.claudePaneID)
        try await pollUntil(timeout: 5.0) {
            session.gitContext.paneWorktreeRoot[paneID] != nil
        }

        let root = try #require(session.claudeWorktreeRoot)
        #expect(root.path == session.gitContext.paneWorktreeRoot[paneID])
    }

    /// A lazily-created terminal panel follows the Claude pane into its current
    /// worktree — the spawn directory prefers `claudeWorktreeRoot`.
    @Test func showTerminalFollowsClaudeIntoWorktree() async throws {
        let repo = try makeTempGitRepo()
        defer { try? FileManager.default.removeItem(atPath: repo) }

        let session = Session(customName: "s", workingDirectory: repo)
        let paneID = try #require(session.claudePaneID)
        try await pollUntil(timeout: 5.0) {
            session.gitContext.paneWorktreeRoot[paneID] != nil
        }
        let worktreeRoot = try #require(session.claudeWorktreeRoot).path

        session.showTerminal()
        let panel = try #require(session.terminalPanel)
        let terminalWD = panel.splitTree.allLeafInfo().first?.1
        #expect(terminalWD == worktreeRoot)
    }

    // MARK: - Git test helpers

    private func pollUntil(timeout: Double, condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(timeout)
        while ContinuousClock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        Issue.record("Timed out waiting for condition after \(timeout)s")
    }

    private func makeTempGitRepo() throws -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tian-test-\(UUID().uuidString)")
            .path
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try runGitSync(["init"], in: dir)
        try runGitSync(["config", "user.email", "test@test.com"], in: dir)
        try runGitSync(["config", "user.name", "Test"], in: dir)
        let readmePath = (dir as NSString).appendingPathComponent("README.md")
        try "# Test".write(toFile: readmePath, atomically: true, encoding: .utf8)
        try runGitSync(["add", "."], in: dir)
        try runGitSync(["commit", "-m", "Initial commit"], in: dir)
        return dir
    }

    private func runGitSync(_ args: [String], in dir: String) throws {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = URL(filePath: dir)
        let stderr = Pipe()
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let msg = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw SessionModelTestError.git("git \(args.joined(separator: " ")) failed: \(msg)")
        }
    }

    private enum SessionModelTestError: Error { case git(String) }
}
