import Foundation
import UniformTypeIdentifiers
import CoreTransferable

extension UTType {
    static let tianTab = UTType(exportedAs: "com.tian.tab-drag-item")
}

struct TabDragItem: Codable, Transferable {
    let tabID: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .tianTab)
    }
}
