import Testing
@testable import tian

@MainActor
struct SectionDividerViewTests {

    @Test func dividerIsHairline() {
        #expect(SectionDividerView.thickness == 1)
    }

    @Test func sectionDividerIsThinnerThanPaneDivider() {
        #expect(SectionDividerView.thickness < SplitLayout.dividerThickness)
    }
}
