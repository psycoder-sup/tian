import SwiftUI

/// Popover anchored to the Claude section's "+" button. Lets the user type a
/// one-off command for a new Claude tab (e.g. `claude --chrome`,
/// `headroom wrap claude`) without changing the saved default in Settings.
struct CustomClaudeCommandPopover: View {
    /// Command the field starts with — typically the current default.
    let initialCommand: String
    /// Called with the trimmed command when the user confirms.
    let onRun: (String) -> Void

    @State private var command: String
    @Environment(\.dismiss) private var dismiss
    @FocusState private var fieldFocused: Bool

    init(initialCommand: String, onRun: @escaping (String) -> Void) {
        self.initialCommand = initialCommand
        self.onRun = onRun
        _command = State(initialValue: initialCommand)
    }

    private var trimmed: String {
        command.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Run Custom Claude")
                .font(.headline)
            Text("Opens a new Claude tab running this command. tian appends “; exit” automatically.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("Command", text: $command)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .autocorrectionDisabled()
                .focused($fieldFocused)
                .onSubmit(run)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Run", action: run)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmed.isEmpty)
            }
        }
        .padding(16)
        .frame(width: 320)
        .onAppear { fieldFocused = true }
    }

    private func run() {
        guard !trimmed.isEmpty else { return }
        onRun(trimmed)
        dismiss()
    }
}

#Preview {
    CustomClaudeCommandPopover(initialCommand: "claude", onRun: { _ in })
}
