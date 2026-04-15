import Testing
import Foundation
@testable import tian

@MainActor
struct CreateSpaceFlowTests {

    // MARK: - SpaceCollection.createSpace(name:)

    @Test func createSpaceWithoutNameUsesAutoName() {
        let collection = SpaceCollection(workingDirectory: "~")
        let space = collection.createSpace(workingDirectory: "~")
        #expect(space.name == "Space 2")
    }

    @Test func createSpaceWithNameUsesGivenName() {
        let collection = SpaceCollection(workingDirectory: "~")
        let space = collection.createSpace(name: "auth-refactor", workingDirectory: "~")
        #expect(space.name == "auth-refactor")
    }

    @Test func createSpaceWithNilNameStillAutoNames() {
        let collection = SpaceCollection(workingDirectory: "~")
        let space = collection.createSpace(name: nil, workingDirectory: "~")
        #expect(space.name == "Space 2")
    }

    @Test func createSpaceAllowsDuplicateNames() {
        let collection = SpaceCollection(workingDirectory: "~")
        let s1 = collection.createSpace(name: "feature/auth", workingDirectory: "~")
        let s2 = collection.createSpace(name: "feature/auth", workingDirectory: "~")
        #expect(s1.name == "feature/auth")
        #expect(s2.name == "feature/auth")
        #expect(s1.id != s2.id)
    }

    // MARK: - Branch name sanitization

    @Test func sanitizeReplacesSpacesWithDashes() {
        #expect(CreateSpaceView.sanitizeBranchName("foo bar baz") == "foo-bar-baz")
        #expect(CreateSpaceView.sanitizeBranchName(" leading") == "-leading")
        #expect(CreateSpaceView.sanitizeBranchName("trailing ") == "trailing-")
        #expect(CreateSpaceView.sanitizeBranchName("no-spaces") == "no-spaces")
    }

    @Test func sanitizeLeavesInvalidCharsAlone() {
        #expect(CreateSpaceView.sanitizeBranchName("foo~bar") == "foo~bar")
        #expect(CreateSpaceView.sanitizeBranchName("a:b") == "a:b")
    }

    @Test func invalidCharsDetected() {
        #expect(CreateSpaceView.containsInvalidBranchChars("good-name") == false)
        #expect(CreateSpaceView.containsInvalidBranchChars("nope~") == true)
        #expect(CreateSpaceView.containsInvalidBranchChars("a^b") == true)
        #expect(CreateSpaceView.containsInvalidBranchChars("a:b") == true)
        #expect(CreateSpaceView.containsInvalidBranchChars("a..b") == true)
        #expect(CreateSpaceView.containsInvalidBranchChars("-leading") == true)
        #expect(CreateSpaceView.containsInvalidBranchChars("") == false)
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

    @Test func submitActionBlocksOnEmptyInput() {
        let action = CreateSpaceView.resolveSubmitAction(
            sanitizedInput: "", worktreeEnabled: false, isGitRepo: true,
            collision: nil, highlightedRow: nil
        )
        #expect(action == .blocked)
    }

    @Test func submitActionPlainModeReturnsPlain() {
        let action = CreateSpaceView.resolveSubmitAction(
            sanitizedInput: "my space", worktreeEnabled: false, isGitRepo: false,
            collision: nil, highlightedRow: nil
        )
        #expect(action == .plain(name: "my space"))
    }

    @Test func submitActionWorktreeModeBlocksWhenNotGitRepo() {
        let action = CreateSpaceView.resolveSubmitAction(
            sanitizedInput: "feature", worktreeEnabled: true, isGitRepo: false,
            collision: nil, highlightedRow: nil
        )
        #expect(action == .blocked)
    }

    @Test func submitActionBlocksOnInvalidChars() {
        let action = CreateSpaceView.resolveSubmitAction(
            sanitizedInput: "bad~name", worktreeEnabled: true, isGitRepo: true,
            collision: nil, highlightedRow: nil
        )
        #expect(action == .blocked)
    }

    @Test func submitActionBlocksOnInUseCollision() {
        let inUse = row("feature/auth", isInUse: true)
        let action = CreateSpaceView.resolveSubmitAction(
            sanitizedInput: "feature/auth", worktreeEnabled: true, isGitRepo: true,
            collision: inUse, highlightedRow: nil
        )
        #expect(action == .blocked)
    }

    @Test func submitActionChecksOutCollisionWhenNotInUse() {
        let collision = row("feature/auth")
        let action = CreateSpaceView.resolveSubmitAction(
            sanitizedInput: "feature/auth", worktreeEnabled: true, isGitRepo: true,
            collision: collision, highlightedRow: nil
        )
        #expect(action == .checkoutExisting(branch: "feature/auth", remoteRef: nil))
    }

    @Test func submitActionPrefersExactCollisionOverHighlightedRow() {
        let collision = row("feature/auth")
        let highlighted = row("feature/auth-v2")
        let action = CreateSpaceView.resolveSubmitAction(
            sanitizedInput: "feature/auth", worktreeEnabled: true, isGitRepo: true,
            collision: collision, highlightedRow: highlighted
        )
        #expect(action == .checkoutExisting(branch: "feature/auth", remoteRef: nil))
    }

    @Test func submitActionUsesHighlightedRowWithoutCollision() {
        let highlighted = row("origin/feature/xyz", remoteRef: "origin/feature/xyz")
        let action = CreateSpaceView.resolveSubmitAction(
            sanitizedInput: "xyz", worktreeEnabled: true, isGitRepo: true,
            collision: nil, highlightedRow: highlighted
        )
        #expect(action == .checkoutExisting(
            branch: "origin/feature/xyz",
            remoteRef: "origin/feature/xyz"
        ))
    }

    @Test func submitActionCreatesNewBranchWhenNoCollisionAndNoHighlight() {
        let action = CreateSpaceView.resolveSubmitAction(
            sanitizedInput: "brand-new", worktreeEnabled: true, isGitRepo: true,
            collision: nil, highlightedRow: nil
        )
        #expect(action == .createBranch(name: "brand-new"))
    }

    @Test func submitActionPropagatesRemoteRefOnCollision() {
        let collision = row("feature/remote-only", remoteRef: "origin/feature/remote-only")
        let action = CreateSpaceView.resolveSubmitAction(
            sanitizedInput: "feature/remote-only", worktreeEnabled: true, isGitRepo: true,
            collision: collision, highlightedRow: nil
        )
        #expect(action == .checkoutExisting(
            branch: "feature/remote-only",
            remoteRef: "origin/feature/remote-only"
        ))
    }
}
