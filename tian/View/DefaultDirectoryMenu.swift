import SwiftUI

/// Reusable context menu items for setting/clearing a default working directory.
struct DefaultDirectoryMenu: View {
    let name: String
    let currentDirectory: URL?
    let onSet: (URL?) -> Void

    var body: some View {
        Button("Set Default Directory\u{2026}") {
            if let url = DirectoryPicker.chooseDirectory(
                title: "Default Directory for \"\(name)\""
            ) {
                onSet(url)
            }
        }
        if currentDirectory != nil {
            Button("Clear Default Directory") {
                onSet(nil)
            }
        }
    }
}
