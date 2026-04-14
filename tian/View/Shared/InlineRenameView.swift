import SwiftUI

/// A view that toggles between a text label and an inline text field for renaming.
/// Used by both space bar and tab bar items.
struct InlineRenameView: View {
    let text: String
    @Binding var isRenaming: Bool
    let onCommit: (String) -> Void

    @State private var editText: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        if isRenaming {
            TextField("", text: $editText)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
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
                .font(.system(size: 11))
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
