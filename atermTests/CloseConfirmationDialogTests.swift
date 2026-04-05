import Testing
import AppKit
@testable import aterm

@MainActor
struct CloseConfirmationDialogTests {

    // MARK: - confirmIfNeeded skips dialog when processCount is zero

    @Test func confirmIfNeededRunsActionImmediatelyWhenNoProcesses() {
        var ran = false
        CloseConfirmationDialog.confirmIfNeeded(
            processCount: 0,
            target: .pane,
            action: { ran = true }
        )
        #expect(ran)
    }

    @Test func confirmIfNeededRunsActionForTabTargetWithZeroProcesses() {
        var ran = false
        CloseConfirmationDialog.confirmIfNeeded(
            processCount: 0,
            target: .tab,
            action: { ran = true }
        )
        #expect(ran)
    }

    @Test func confirmIfNeededRunsActionForBatchTargetWithZeroProcesses() {
        var ran = false
        CloseConfirmationDialog.confirmIfNeeded(
            processCount: 0,
            target: .tabs(count: 3),
            action: { ran = true }
        )
        #expect(ran)
    }
}
