import AppKit

/// An `NSAlert` whose first button always keeps the Return-key equivalent.
///
/// `NSAlert` strips the Return binding from a button marked `hasDestructiveAction`
/// during its display-time `layout()`, so destructive confirm buttons
/// ("Close Anyway", "Quit Anyway", "Remove Worktree", …) otherwise wouldn't
/// respond to Enter. Re-applying the key equivalent after `super.layout()`
/// restores it deterministically on every layout pass, so Enter confirms.
/// Escape stays bound to the last button (Cancel), as `NSAlert` sets it up.
final class ConfirmAlert: NSAlert {
    override func layout() {
        super.layout()
        buttons.first?.keyEquivalent = "\r"
    }
}
