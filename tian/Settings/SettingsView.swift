import SwiftUI

/// The contents of the app's Settings window (Cmd+,). Currently exposes the
/// command a fresh Claude pane auto-runs; structured as a grouped `Form` so
/// future settings can be added as additional sections.
struct SettingsView: View {
    var body: some View {
        // `body` is MainActor-isolated, so binding to the shared (MainActor)
        // settings instance here is safe — and avoids touching the singleton
        // from a non-isolated stored-property initializer.
        @Bindable var settings = TianSettings.shared

        Form {
            Section {
                TextField(
                    "Command",
                    text: $settings.claudeCommand,
                    prompt: Text(TianSettings.defaultClaudeCommand)
                )
                .font(.system(.body, design: .monospaced))
                .autocorrectionDisabled()

                HStack {
                    Spacer()
                    Button("Reset to Default") {
                        settings.claudeCommand = TianSettings.defaultClaudeCommand
                    }
                    .disabled(settings.claudeCommand == TianSettings.defaultClaudeCommand)
                }
            } header: {
                Text("Claude Command")
            } footer: {
                Text(
                    "Run when a new Claude pane opens. Enter just the command — "
                    + "tian appends “; exit” automatically. "
                    + "Examples: claude · claude --chrome · headroom wrap claude. "
                    + "Already-open and resumed panes are unaffected."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            Section {
                Toggle(
                    "Use `claude --worktree` for worktree spaces",
                    isOn: $settings.useClaudeWorktreeEngine
                )
            } header: {
                Text("Worktree Engine")
            } footer: {
                Text(
                    "When on, checking “Create worktree” in the new-space dialog lets "
                    + "Claude create and name the worktree (.claude/worktrees/<name>). "
                    + "When off, you name the branch and tian creates the worktree."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview {
    SettingsView()
}
