import Foundation
import UniformTypeIdentifiers
import CoreTransferable

extension UTType {
    static let tianWorkspace = UTType(exportedAs: "com.tian.workspace-drag-item")
}

struct WorkspaceDragItem: Codable, Transferable {
    let workspaceID: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .tianWorkspace)
    }
}
