import Foundation
import UniformTypeIdentifiers
import CoreTransferable

extension UTType {
    static let tianSession = UTType(exportedAs: "com.tian.session-drag-item")
}

struct SessionDragItem: Codable, Transferable {
    let sessionID: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .tianSession)
    }
}
