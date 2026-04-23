import Foundation
import UniformTypeIdentifiers
import CoreTransferable

extension UTType {
    static let tianTab = UTType(exportedAs: "com.tian.tab-drag-item")
}

struct TabDragItem: Codable, Transferable {
    let tabID: UUID
    /// FR-22 — the SectionKind of the tab being dragged. Optional for
    /// back-compat with drag items produced before the space-sections
    /// feature; when nil, the drop coordinator falls back to
    /// "unknown source — reject cross-section".
    var sectionKind: SectionKind?

    init(tabID: UUID, sectionKind: SectionKind? = nil) {
        self.tabID = tabID
        self.sectionKind = sectionKind
    }

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .tianTab)
    }
}
