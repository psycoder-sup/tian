import Testing
@testable import tian

@MainActor
struct SessionDividerViewTests {

    @Test func dividerIsHairline() {
        #expect(SessionDividerView.thickness == 1)
    }

    @Test func sessionDividerIsThinnerThanPaneDivider() {
        #expect(SessionDividerView.thickness < SplitLayout.dividerThickness)
    }
}
