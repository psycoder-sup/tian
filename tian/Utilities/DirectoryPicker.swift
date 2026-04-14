import AppKit

enum DirectoryPicker {
    /// Shows an NSOpenPanel configured for directory selection.
    /// Returns the selected directory URL, or `nil` if the user cancelled.
    @MainActor
    static func chooseDirectory(
        title: String = "Choose Default Directory",
        prompt: String? = nil,
        message: String? = nil
    ) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        if let prompt { panel.prompt = prompt }
        if let message { panel.message = message }
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
}
