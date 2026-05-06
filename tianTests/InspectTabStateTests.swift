import Testing
@testable import tian

@MainActor
struct InspectTabStateTests {

    // MARK: - InspectTab Enum

    @Test func caseIterableHasThreeCases() {
        #expect(InspectTab.allCases.count == 3)
        #expect(InspectTab.allCases.contains(.files))
        #expect(InspectTab.allCases.contains(.diff))
        #expect(InspectTab.allCases.contains(.branch))
    }

    @Test func filesHasCorrectRawValue() {
        #expect(InspectTab.files.rawValue == "files")
    }

    @Test func diffHasCorrectRawValue() {
        #expect(InspectTab.diff.rawValue == "diff")
    }

    @Test func branchHasCorrectRawValue() {
        #expect(InspectTab.branch.rawValue == "branch")
    }

    @Test func initFromValidRawValues() {
        #expect(InspectTab(rawValue: "files") == .files)
        #expect(InspectTab(rawValue: "diff") == .diff)
        #expect(InspectTab(rawValue: "branch") == .branch)
    }

    @Test func initFromInvalidRawValueReturnsNil() {
        #expect(InspectTab(rawValue: "garbage") == nil)
        #expect(InspectTab(rawValue: "invalid") == nil)
        #expect(InspectTab(rawValue: "") == nil)
    }

    // MARK: - InspectTabState

    @Test func defaultsToFiles() {
        let state = InspectTabState()
        #expect(state.activeTab == .files)
    }

    @Test func unknownRawValueFallsBackToFiles() {
        let raw = "garbage"
        let resolved = InspectTab(rawValue: raw) ?? .files
        #expect(resolved == .files)
    }

    @Test func diffCollapseDefaultsToEmpty() {
        let state = InspectTabState()
        #expect(state.diffCollapse.isEmpty)
    }

    @Test func initWithCustomActiveTab() {
        let state = InspectTabState(activeTab: .diff)
        #expect(state.activeTab == .diff)
    }

    @Test func activeTabCanBeChanged() {
        let state = InspectTabState()
        state.activeTab = .branch
        #expect(state.activeTab == .branch)
    }

    @Test func diffCollapseCanStoreValues() {
        let state = InspectTabState()
        state.diffCollapse["file1.swift"] = true
        state.diffCollapse["file2.swift"] = false
        #expect(state.diffCollapse["file1.swift"] == true)
        #expect(state.diffCollapse["file2.swift"] == false)
    }

    @Test func diffViewModelIsProvided() {
        let state = InspectTabState()
        // Just verify it's not nil and can be accessed
        _ = state.diffViewModel
    }

    @Test func branchViewModelIsProvided() {
        let state = InspectTabState()
        // Just verify it's not nil and can be accessed
        _ = state.branchViewModel
    }
}
