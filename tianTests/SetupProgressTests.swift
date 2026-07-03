import Testing
import Foundation
@testable import tian

@Suite("SetupProgress")
struct SetupProgressTests {

    @Test func equality_byAllFields() {
        let workspaceID = UUID()
        let sessionID = UUID()
        let a = SetupProgress(
            workspaceID: workspaceID,
            sessionID: sessionID,
            phase: .setup,
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
            sessionID: UUID(),
            phase: .setup,
            totalCommands: 5
        )
        #expect(progress.currentIndex == -1)
        #expect(progress.currentCommand == nil)
        #expect(progress.lastFailedIndex == nil)
        #expect(progress.totalCommands == 5)
        #expect(progress.phase == .setup)
    }

    // MARK: - Phase enum and labelPrefix (FR-004)

    @Test func labelPrefix_setup() {
        let progress = SetupProgress.starting(
            workspaceID: UUID(),
            sessionID: UUID(),
            phase: .setup,
            totalCommands: 3
        )
        #expect(progress.labelPrefix == "Setup")
    }

    @Test func labelPrefix_cleanup() {
        let progress = SetupProgress.starting(
            workspaceID: UUID(),
            sessionID: UUID(),
            phase: .cleanup,
            totalCommands: 3
        )
        #expect(progress.labelPrefix == "Cleanup")
    }

    @Test func labelPrefix_removing() {
        let progress = SetupProgress.removingPlaceholder(
            workspaceID: UUID(),
            sessionID: UUID()
        )
        #expect(progress.labelPrefix == "Removing...")
    }

    @Test func removingPlaceholder_hasCorrectValues() {
        let workspaceID = UUID()
        let sessionID = UUID()
        let progress = SetupProgress.removingPlaceholder(
            workspaceID: workspaceID,
            sessionID: sessionID
        )
        #expect(progress.phase == .removing)
        #expect(progress.totalCommands == 0)
        #expect(progress.currentIndex == -1)
        #expect(progress.currentCommand == nil)
        #expect(progress.lastFailedIndex == nil)
        #expect(progress.workspaceID == workspaceID)
        #expect(progress.sessionID == sessionID)
    }
}
