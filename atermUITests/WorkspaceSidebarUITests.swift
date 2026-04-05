import XCTest

final class WorkspaceSidebarUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments.append("--ui-testing")
        app.launch()
        _ = app.windows.firstMatch.waitForExistence(timeout: 5)
    }

    override func tearDown() {
        app = nil
    }

    // MARK: - Helpers

    /// Workspace headers are button elements (with .isButton trait) with identifier
    /// "workspace-header-<UUID>" and label containing the workspace name.
    private func workspaceHeader(containing name: String) -> XCUIElement {
        app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", name)
        ).firstMatch
    }

    /// Space rows are button elements (with .isButton trait) with label matching space name.
    private func spaceRow(named name: String, selected: Bool? = nil) -> XCUIElement {
        if let selected {
            let value = selected ? "selected" : "not selected"
            return app.buttons.matching(
                NSPredicate(format: "label == %@ AND value == %@", name, value)
            ).firstMatch
        }
        return app.buttons.matching(
            NSPredicate(format: "label == %@", name)
        ).firstMatch
    }

    private var sidebarPanel: XCUIElement {
        app.groups["sidebar-panel"]
    }

    private var newWorkspaceButton: XCUIElement {
        app.buttons["new-workspace-button"]
    }

    /// Ensures the app window has keyboard focus, then sends a shortcut.
    private func typeShortcut(_ key: String, modifiers: XCUIElement.KeyModifierFlags) {
        app.windows.firstMatch.tap()
        app.typeKey(key, modifierFlags: modifiers)
    }

    private func typeShortcut(_ key: XCUIKeyboardKey, modifiers: XCUIElement.KeyModifierFlags) {
        app.windows.firstMatch.tap()
        app.typeKey(key, modifierFlags: modifiers)
    }

    /// Creates a new workspace via Cmd+Shift+N and waits for it.
    @discardableResult
    private func createWorkspace() -> XCUIElement {
        typeShortcut("n", modifiers: [.command, .shift])
        let header = workspaceHeader(containing: "Workspace")
        _ = header.waitForExistence(timeout: 5)
        return header
    }

    // MARK: - Launch

    func testAppLaunchShowsSidebarWithDefaultWorkspace() {
        XCTAssertTrue(sidebarPanel.waitForExistence(timeout: 5),
                       "Sidebar panel should be visible")

        let header = workspaceHeader(containing: "default")
        XCTAssertTrue(header.waitForExistence(timeout: 3),
                       "Default workspace header should be visible")
    }

    // MARK: - Workspace Creation

    func testCmdShiftNCreatesWorkspace() {
        typeShortcut("n", modifiers: [.command, .shift])

        let header = workspaceHeader(containing: "Workspace 2")
        XCTAssertTrue(header.waitForExistence(timeout: 5),
                       "Workspace 2 should appear after Cmd+Shift+N")
    }

    func testNewWorkspaceButton() {
        XCTAssertTrue(newWorkspaceButton.waitForExistence(timeout: 5))

        newWorkspaceButton.tap()

        let header = workspaceHeader(containing: "Workspace 2")
        XCTAssertTrue(header.waitForExistence(timeout: 3),
                       "Workspace 2 should appear after clicking New Workspace")
    }

    // MARK: - Sidebar Toggle

    func testSidebarToggle() {
        XCTAssertTrue(sidebarPanel.waitForExistence(timeout: 5))

        // Toggle off
        typeShortcut("s", modifiers: [.command, .shift])
        sleep(1)

        XCTAssertFalse(sidebarPanel.exists,
                        "Sidebar should be hidden after toggle")

        // Toggle back on
        typeShortcut("s", modifiers: [.command, .shift])
        sleep(1)

        XCTAssertTrue(sidebarPanel.waitForExistence(timeout: 3),
                       "Sidebar should reappear after second toggle")
    }

    // MARK: - Workspace Switching

    func testInPlaceWorkspaceSwitching() {
        // Create second workspace
        typeShortcut("n", modifiers: [.command, .shift])
        _ = workspaceHeader(containing: "Workspace 2").waitForExistence(timeout: 3)

        // The "default" space in the first workspace should be "not selected"
        let defaultSpace = spaceRow(named: "default", selected: false)
        XCTAssertTrue(defaultSpace.waitForExistence(timeout: 3),
                       "Default space should be not selected")

        // Click to switch in-place
        defaultSpace.tap()

        // Now it should become selected
        let activeDefault = spaceRow(named: "default", selected: true)
        XCTAssertTrue(activeDefault.waitForExistence(timeout: 3),
                       "Default space should become selected after click")
    }

    // MARK: - Workspace Close

    func testCmdShiftBackspaceClosesWorkspace() {
        // Create second workspace
        typeShortcut("n", modifiers: [.command, .shift])
        let ws2 = workspaceHeader(containing: "Workspace 2")
        XCTAssertTrue(ws2.waitForExistence(timeout: 3))

        // Close active workspace
        typeShortcut(.delete, modifiers: [.command, .shift])

        // Default workspace should remain
        let defaultHeader = workspaceHeader(containing: "default")
        XCTAssertTrue(defaultHeader.waitForExistence(timeout: 3))

        // Workspace 2 should be gone
        let ws2After = workspaceHeader(containing: "Workspace 2")
        XCTAssertFalse(ws2After.waitForExistence(timeout: 1))
    }

    func testCloseLastWorkspaceQuitsApp() {
        typeShortcut(.delete, modifiers: [.command, .shift])

        let terminated = app.wait(for: .notRunning, timeout: 5)
        XCTAssertTrue(terminated, "App should quit after closing last workspace")
    }

    // MARK: - Space Management

    func testCmdShiftTAddsSpace() {
        typeShortcut("t", modifiers: [.command, .shift])

        let space2 = spaceRow(named: "Space 2")
        XCTAssertTrue(space2.waitForExistence(timeout: 3),
                       "Space 2 should appear after Cmd+Shift+T")
    }

    func testSpaceNavigation() {
        // Create second space
        typeShortcut("t", modifiers: [.command, .shift])
        let space2Active = spaceRow(named: "Space 2", selected: true)
        XCTAssertTrue(space2Active.waitForExistence(timeout: 3))

        // Navigate to previous space
        typeShortcut(.leftArrow, modifiers: [.command, .shift])

        // Default should now be selected
        let activeDefault = spaceRow(named: "default", selected: true)
        XCTAssertTrue(activeDefault.waitForExistence(timeout: 3),
                       "Default space should be selected after Cmd+Shift+Left")
    }

    // MARK: - Disclosure

    func testDisclosureToggle() {
        // Create second workspace (starts collapsed — no space rows visible)
        typeShortcut("n", modifiers: [.command, .shift])
        let ws2 = workspaceHeader(containing: "Workspace 2")
        XCTAssertTrue(ws2.waitForExistence(timeout: 3))

        // Count space rows with identifier prefix before expanding
        // (only the first workspace's space row should have value "not selected")
        let spaceRowsBefore = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'space-row-'")
        ).count

        // Click header to expand disclosure
        ws2.tap()
        sleep(1)

        // After expansion, more space rows should appear
        let spaceRowsAfter = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'space-row-'")
        ).count
        XCTAssertGreaterThan(spaceRowsAfter, spaceRowsBefore,
                              "More space rows should be visible after expanding Workspace 2")
    }

    // MARK: - Keyboard Navigation

    func testKeyboardNavigationCmd0() {
        // Enter sidebar focus
        typeShortcut("0", modifiers: [.command])

        // Navigate down to first space row and activate
        typeShortcut(.downArrow, modifiers: [])
        typeShortcut(.return, modifiers: [])

        // Re-enter sidebar focus and escape
        typeShortcut("0", modifiers: [.command])
        typeShortcut(.escape, modifiers: [])
    }
}
