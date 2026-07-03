import Testing
import AppKit
@testable import tian

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

    @Test func confirmIfNeededRunsActionForSessionTargetWithZeroProcesses() {
        var ran = false
        CloseConfirmationDialog.confirmIfNeeded(
            processCount: 0,
            target: .session(paneCount: 1),
            action: { ran = true }
        )
        #expect(ran)
    }

    @Test func confirmIfNeededRunsActionForMultiPaneSessionTargetWithZeroProcesses() {
        var ran = false
        CloseConfirmationDialog.confirmIfNeeded(
            processCount: 0,
            target: .session(paneCount: 3),
            action: { ran = true }
        )
        #expect(ran)
    }
}
