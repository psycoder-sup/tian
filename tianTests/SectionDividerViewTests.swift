import Testing
@testable import tian

@MainActor
struct SectionDividerViewTests {

    @Test func dividerThicknessIsSixPoints() {
        #expect(SectionDividerView.thickness == 6)
    }

    @Test func paneDividerIsThinnerThanSectionDivider() {
        #expect(SplitLayout.dividerThickness < SectionDividerView.thickness)
    }
}
