import Testing
import Foundation
@testable import tian

@MainActor
struct TabDragConstraintTests {

    // FR-22 — cross-section drops rejected.
    @Test func tabDragRejectedAcrossSections() {
        let space = SpaceCollection(workingDirectory: "/tmp").activeSpace!
        space.showTerminal()
        let claudeTabID = space.claudeSection.tabs[0].id
        let accepted = SectionTabBarDropCoordinator.canAccept(
            sourceSectionKind: .claude,
            destinationSectionKind: .terminal,
            tabID: claudeTabID
        )
        #expect(accepted == false)
    }

    // FR-22 — same-section drops accepted.
    @Test func tabDragAcceptedWithinSection() {
        let tabID = UUID()
        #expect(SectionTabBarDropCoordinator.canAccept(
            sourceSectionKind: .claude,
            destinationSectionKind: .claude,
            tabID: tabID
        ))
        #expect(SectionTabBarDropCoordinator.canAccept(
            sourceSectionKind: .terminal,
            destinationSectionKind: .terminal,
            tabID: tabID
        ))
    }

    // FR-22 — the drop item carries a sectionKind tag so the coordinator
    // has the context it needs at drop time.
    @Test func tabDragItemCarriesSectionKind() {
        let item = TabDragItem(tabID: UUID(), sectionKind: .claude)
        #expect(item.sectionKind == .claude)
    }
}
