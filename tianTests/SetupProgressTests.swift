import Testing
import Foundation
@testable import tian

@Suite("SetupProgress")
struct SetupProgressTests {

    @Test func equality_byAllFields() {
        let workspaceID = UUID()
        let spaceID = UUID()
        let a = SetupProgress(
            workspaceID: workspaceID,
            spaceID: spaceID,
            totalCommands: 3,
            currentIndex: 1,
            currentCommand: "echo hi",
            lastFailedIndex: nil
        )
        let b = a
        var c = a
        c.currentIndex = 2
        #expect(a == b)
        #expect(a != c)
    }

    @Test func startingValue_hasNegativeIndexAndNoFailure() {
        let progress = SetupProgress.starting(
            workspaceID: UUID(),
            spaceID: UUID(),
            totalCommands: 5
        )
        #expect(progress.currentIndex == -1)
        #expect(progress.currentCommand == nil)
        #expect(progress.lastFailedIndex == nil)
        #expect(progress.totalCommands == 5)
    }
}
