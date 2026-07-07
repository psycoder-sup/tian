import SwiftUI

/// A view that toggles between a text label and an inline text field for renaming.
/// Used by the sidebar (workspace header, session row) and the session-overview card.
struct InlineRenameView: View {
    let text: String
    @Binding var isRenaming: Bool
    /// Font for both the label and the edit field. Defaults to the sidebar's
    /// size-11 style; callers with a larger name (e.g. the overview card) pass
    /// their own so the field matches the label it replaces.
    var font: Font = .system(size: 11)
    let onCommit: (String) -> Void

    @State private var editText: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        if isRenaming {
            TextField("", text: $editText)
                .textFieldStyle(.plain)
                .font(font)
                .focused($isFocused)
                .onSubmit(commit)
                .onExitCommand(perform: cancel)
                .onAppear {
                    editText = text
                    // Defer focus to next run loop tick so the TextField
                    // is fully in the responder chain before we focus it.
                    DispatchQueue.main.async {
                        isFocused = true
                    }
                }
                .onChange(of: isFocused) { _, focused in
                    if !focused {
                        cancel()
                    }
                }
        } else {
            Text(text)
                .font(font)
                .lineLimit(1)
        }
    }

    private func commit() {
        let trimmed = editText.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            cancel()
        } else {
            isRenaming = false
            onCommit(trimmed)
        }
    }

    private func cancel() {
        isRenaming = false
    }
}
