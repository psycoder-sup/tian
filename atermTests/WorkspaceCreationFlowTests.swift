import Testing
import Foundation
@testable import aterm

@MainActor
struct WorkspaceCreationFlowTests {

    @Test func deriveName_regularDirectory() {
        let url = URL(filePath: "/Users/foo/projects/aterm")
        #expect(WorkspaceCreationFlow.deriveWorkspaceName(from: url) == "aterm")
    }

    @Test func deriveName_dotfileDirectoryKeptAsIs() {
        let url = URL(filePath: "/Users/foo/.config")
        #expect(WorkspaceCreationFlow.deriveWorkspaceName(from: url) == ".config")
    }

    @Test func deriveName_trailingSlashStandardized() {
        let url = URL(filePath: "/Users/foo/projects/aterm/")
        #expect(WorkspaceCreationFlow.deriveWorkspaceName(from: url) == "aterm")
    }

    @Test func deriveName_rootReturnsNil() {
        let url = URL(filePath: "/")
        #expect(WorkspaceCreationFlow.deriveWorkspaceName(from: url) == nil)
    }

    @Test func deriveName_emptyBasenameReturnsNil() {
        let url = URL(filePath: "")
        #expect(WorkspaceCreationFlow.deriveWorkspaceName(from: url) == nil)
    }
}
