import Foundation
import Observation

@MainActor @Observable
final class InspectTabState {
    var activeTab: InspectTab
    var diffCollapse: [String: Bool] = [:]

    let diffViewModel: InspectDiffViewModel
    let branchViewModel: InspectBranchViewModel

    init(
        activeTab: InspectTab = .files,
        diffViewModel: InspectDiffViewModel = InspectDiffViewModel(),
        branchViewModel: InspectBranchViewModel = InspectBranchViewModel()
    ) {
        self.activeTab = activeTab
        self.diffViewModel = diffViewModel
        self.branchViewModel = branchViewModel
    }
}
