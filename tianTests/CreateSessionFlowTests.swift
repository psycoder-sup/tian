import Testing
import Foundation
@testable import tian

@MainActor
struct CreateSessionFlowTests {

    // MARK: - SessionCollection.createSession(name:)

    @Test func createSessionWithoutNameUsesAutoName() {
        // No explicit name → auto mode: `customName` stays nil and `displayName`
        // derives from the Claude pane title / working directory.
        let collection = SessionCollection(workingDirectory: "~")
        let session = collection.createSession(workingDirectory: "~")
        #expect(session.customName == nil)
    }

    @Test func createSessionWithNameUsesGivenName() {
        let collection = SessionCollection(workingDirectory: "~")
        let session = collection.createSession(name: "auth-refactor", workingDirectory: "~")
        #expect(session.customName == "auth-refactor")
        #expect(session.displayName == "auth-refactor")
    }

    @Test func createSessionWithNilNameStillAutoNames() {
        let collection = SessionCollection(workingDirectory: "~")
        let session = collection.createSession(name: nil, workingDirectory: "~")
        #expect(session.customName == nil)
    }

    @Test func createSessionAllowsDuplicateNames() {
        let collection = SessionCollection(workingDirectory: "~")
        let s1 = collection.createSession(name: "feature/auth", workingDirectory: "~")
        let s2 = collection.createSession(name: "feature/auth", workingDirectory: "~")
        #expect(s1.displayName == "feature/auth")
        #expect(s2.displayName == "feature/auth")
        #expect(s1.id != s2.id)
    }

    // MARK: - Branch name sanitization

    @Test func sanitizeReplacesSpacesWithDashes() {
        #expect(CreateSessionView.sanitizeBranchName("foo bar baz") == "foo-bar-baz")
        #expect(CreateSessionView.sanitizeBranchName(" leading") == "-leading")
        #expect(CreateSessionView.sanitizeBranchName("trailing ") == "trailing-")
        #expect(CreateSessionView.sanitizeBranchName("no-spaces") == "no-spaces")
    }

    @Test func sanitizeLeavesInvalidCharsAlone() {
        #expect(CreateSessionView.sanitizeBranchName("foo~bar") == "foo~bar")
        #expect(CreateSessionView.sanitizeBranchName("a:b") == "a:b")
    }

    @Test func invalidCharsDetected() {
        #expect(CreateSessionView.containsInvalidBranchChars("good-name") == false)
        #expect(CreateSessionView.containsInvalidBranchChars("nope~") == true)
        #expect(CreateSessionView.containsInvalidBranchChars("a^b") == true)
        #expect(CreateSessionView.containsInvalidBranchChars("a:b") == true)
        #expect(CreateSessionView.containsInvalidBranchChars("a..b") == true)
        #expect(CreateSessionView.containsInvalidBranchChars("-leading") == true)
        #expect(CreateSessionView.containsInvalidBranchChars("") == false)
    }

    // MARK: - resolveSubmitAction

    private func row(
        _ name: String,
        isInUse: Bool = false,
        remoteRef: String? = nil
    ) -> BranchRow {
        BranchRow(
            id: "local:\(name)",
            displayName: name,
            badge: remoteRef == nil ? .local : .origin("origin"),
            committerDate: Date(),
            relativeDate: "just now",
            isInUse: isInUse,
            isCurrent: false,
            remoteRef: remoteRef
        )
    }

    @Test func submitActionPlainModeAllowsEmptyInput() {
        // Plain mode: an empty field is allowed — it submits as an auto-named
        // session (`.plain(name: nil)`) rather than blocking.
        let action = CreateSessionView.resolveSubmitAction(
            sanitizedInput: "", worktreeEnabled: false, isGitRepo: true, claudeEngine: false,
            collision: nil, highlightedRow: nil
        )
        #expect(action == .plain(name: nil))
    }

    @Test func submitActionWorktreeModeBlocksOnEmptyInput() {
        // Worktree mode still requires a branch name, so an empty field blocks.
        let action = CreateSessionView.resolveSubmitAction(
            sanitizedInput: "", worktreeEnabled: true, isGitRepo: true, claudeEngine: false,
            collision: nil, highlightedRow: nil
        )
        #expect(action == .blocked)
    }

    @Test func submitActionPlainModeReturnsPlain() {
        let action = CreateSessionView.resolveSubmitAction(
            sanitizedInput: "my session", worktreeEnabled: false, isGitRepo: false, claudeEngine: false,
            collision: nil, highlightedRow: nil
        )
        #expect(action == .plain(name: "my session"))
    }

    @Test func submitActionWorktreeModeBlocksWhenNotGitRepo() {
        let action = CreateSessionView.resolveSubmitAction(
            sanitizedInput: "feature", worktreeEnabled: true, isGitRepo: false, claudeEngine: false,
            collision: nil, highlightedRow: nil
        )
        #expect(action == .blocked)
    }

    @Test func submitActionBlocksOnInvalidChars() {
        let action = CreateSessionView.resolveSubmitAction(
            sanitizedInput: "bad~name", worktreeEnabled: true, isGitRepo: true, claudeEngine: false,
            collision: nil, highlightedRow: nil
        )
        #expect(action == .blocked)
    }

    @Test func submitActionBlocksOnInUseCollision() {
        let inUse = row("feature/auth", isInUse: true)
        let action = CreateSessionView.resolveSubmitAction(
            sanitizedInput: "feature/auth", worktreeEnabled: true, isGitRepo: true, claudeEngine: false,
            collision: inUse, highlightedRow: nil
        )
        #expect(action == .blocked)
    }

    @Test func submitActionChecksOutCollisionWhenNotInUse() {
        let collision = row("feature/auth")
        let action = CreateSessionView.resolveSubmitAction(
            sanitizedInput: "feature/auth", worktreeEnabled: true, isGitRepo: true, claudeEngine: false,
            collision: collision, highlightedRow: nil
        )
        #expect(action == .checkoutExisting(branch: "feature/auth", remoteRef: nil))
    }

    @Test func submitActionPrefersExactCollisionOverHighlightedRow() {
        let collision = row("feature/auth")
        let highlighted = row("feature/auth-v2")
        let action = CreateSessionView.resolveSubmitAction(
            sanitizedInput: "feature/auth", worktreeEnabled: true, isGitRepo: true, claudeEngine: false,
            collision: collision, highlightedRow: highlighted
        )
        #expect(action == .checkoutExisting(branch: "feature/auth", remoteRef: nil))
    }

    @Test func submitActionUsesHighlightedRowWithoutCollision() {
        let highlighted = row("origin/feature/xyz", remoteRef: "origin/feature/xyz")
        let action = CreateSessionView.resolveSubmitAction(
            sanitizedInput: "xyz", worktreeEnabled: true, isGitRepo: true, claudeEngine: false,
            collision: nil, highlightedRow: highlighted
        )
        #expect(action == .checkoutExisting(
            branch: "origin/feature/xyz",
            remoteRef: "origin/feature/xyz"
        ))
    }

    @Test func submitActionCreatesNewBranchWhenNoCollisionAndNoHighlight() {
        let action = CreateSessionView.resolveSubmitAction(
            sanitizedInput: "brand-new", worktreeEnabled: true, isGitRepo: true, claudeEngine: false,
            collision: nil, highlightedRow: nil
        )
        #expect(action == .createBranch(name: "brand-new"))
    }

    @Test func submitActionPropagatesRemoteRefOnCollision() {
        let collision = row("feature/remote-only", remoteRef: "origin/feature/remote-only")
        let action = CreateSessionView.resolveSubmitAction(
            sanitizedInput: "feature/remote-only", worktreeEnabled: true, isGitRepo: true, claudeEngine: false,
            collision: collision, highlightedRow: nil
        )
        #expect(action == .checkoutExisting(
            branch: "feature/remote-only",
            remoteRef: "origin/feature/remote-only"
        ))
    }

    // MARK: - resolveSubmitAction (claude --worktree engine)

    @Test func submitActionClaudeEngineSubmitsOnEmptyInput() {
        // Claude names the worktree, so an empty field still submits.
        let action = CreateSessionView.resolveSubmitAction(
            sanitizedInput: "", worktreeEnabled: true, isGitRepo: true, claudeEngine: true,
            collision: nil, highlightedRow: nil
        )
        #expect(action == .claudeWorktree)
    }

    @Test func submitActionClaudeEngineTakesPrecedenceOverTypedInput() {
        // Even with leftover text, claude-engine mode routes to .claudeWorktree
        // (the branch field is hidden, so this is just defensive).
        let action = CreateSessionView.resolveSubmitAction(
            sanitizedInput: "ignored", worktreeEnabled: true, isGitRepo: true, claudeEngine: true,
            collision: nil, highlightedRow: nil
        )
        #expect(action == .claudeWorktree)
    }

    @Test func submitActionClaudeEngineIgnoredWhenWorktreeDisabled() {
        // With the worktree checkbox off, the engine setting is irrelevant —
        // a plain session is created.
        let action = CreateSessionView.resolveSubmitAction(
            sanitizedInput: "my session", worktreeEnabled: false, isGitRepo: true, claudeEngine: true,
            collision: nil, highlightedRow: nil
        )
        #expect(action == .plain(name: "my session"))
    }

    @Test func submitActionClaudeEngineBlockedWhenNotGitRepo() {
        // claudeEngine only applies in a git repo; an empty field outside one
        // is blocked, not submitted.
        let action = CreateSessionView.resolveSubmitAction(
            sanitizedInput: "", worktreeEnabled: true, isGitRepo: false, claudeEngine: true,
            collision: nil, highlightedRow: nil
        )
        #expect(action == .blocked)
    }
}
