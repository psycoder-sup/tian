import Foundation
import UniformTypeIdentifiers
import CoreTransferable

extension UTType {
    static let tianSpace = UTType(exportedAs: "com.tian.space-drag-item")
}

struct SpaceDragItem: Codable, Transferable {
    let spaceID: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .tianSpace)
    }
}
