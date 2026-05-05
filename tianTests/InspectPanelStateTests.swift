import Testing
import Foundation
@testable import tian

@MainActor
struct InspectPanelStateTests {

    // FR-30 — width below minimum clamps to 240.
    @Test func widthClampsToMin() {
        let state = InspectPanelState(isVisible: true, width: 100)
        #expect(state.width == 240)
    }

    // FR-30 — width above maximum clamps to 480.
    @Test func widthClampsToMax() {
        let state = InspectPanelState(isVisible: true, width: 9999)
        #expect(state.width == 480)
    }

    // FR-29 / FR-30 — non-default values survive a WorkspaceSnapshot Codable round-trip.
    // Build a WorkspaceSnapshot with inspectPanelVisible=false, inspectPanelWidth=380,
    // encode/decode, then verify the decoded snapshot carries those values.
    @Test func snapshotRoundTripsValues() throws {
        let snapshot = WorkspaceSnapshot(
            id: UUID(),
            name: "test",
            defaultWorkingDirectory: nil,
            createdAt: Date(),
            inspectPanelVisible: false,
            inspectPanelWidth: 380
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WorkspaceSnapshot.self, from: data)

        #expect(decoded.inspectPanelVisible == false)
        #expect(decoded.inspectPanelWidth == 380)
    }

    // FR-29 / FR-30 — nil fields in snapshot produce defaults on Workspace init.
    @Test func snapshotNilFieldsProduceDefaults() {
        let snapshot = WorkspaceSnapshot(
            id: UUID(),
            name: "test",
            defaultWorkingDirectory: nil,
            createdAt: Date(),
            inspectPanelVisible: nil,
            inspectPanelWidth: nil
        )
        let workspace = Workspace.from(snapshot: snapshot)
        #expect(workspace.inspectPanelState.isVisible == true)
        #expect(workspace.inspectPanelState.width == 320)
    }

    // FR-29 / FR-30 — non-default values in snapshot are restored into Workspace.
    @Test func snapshotNonDefaultValuesRestored() {
        let snapshot = WorkspaceSnapshot(
            id: UUID(),
            name: "test",
            defaultWorkingDirectory: nil,
            createdAt: Date(),
            inspectPanelVisible: false,
            inspectPanelWidth: 400
        )
        let workspace = Workspace.from(snapshot: snapshot)
        #expect(workspace.inspectPanelState.isVisible == false)
        #expect(workspace.inspectPanelState.width == 400)
    }
}
