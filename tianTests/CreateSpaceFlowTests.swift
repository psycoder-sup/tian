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
}
