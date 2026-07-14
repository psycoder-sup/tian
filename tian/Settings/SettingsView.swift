import SwiftUI

/// The contents of the app's Settings window (Cmd+,). Exposes the command a
/// fresh Claude pane auto-runs, the worktree engine, and tian's Ghostty
/// preference overrides; structured as a grouped `Form` so future settings can
/// be added as additional sections.
struct SettingsView: View {
    /// Diagnostics from the last config build (bad key, unparseable value…).
    /// Refreshed whenever we apply, so a typo in the overrides box reports back
    /// instead of silently doing nothing.
    @State private var configDiagnostics: [String] = []
    @State private var showAdvancedOverrides = false

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

            Section {
                Picker("Option key", selection: $settings.optionAsAlt) {
                    ForEach(OptionAsAltSetting.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .onChange(of: settings.optionAsAlt) { applyOverrides() }

                DisclosureGroup("Advanced: Ghostty config overrides", isExpanded: $showAdvancedOverrides) {
                    TextEditor(text: $settings.ghosttyConfigOverrides)
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled()
                        .frame(minHeight: 90)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(.separator)
                        )

                    if !configDiagnostics.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(configDiagnostics, id: \.self) { message in
                                Text(message)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    HStack {
                        Text("One `key = value` per line — e.g. `font-size = 14`.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Apply") { applyOverrides() }
                    }
                }
            } header: {
                Text("Terminal")
            } footer: {
                Text(
                    "Ghostty preferences tian applies on top of ~/.config/ghostty/config — "
                    + "these win, and they don’t touch your Ghostty.app setup. "
                    + "Set the Option key to “Alt / Meta” so alt+… bindings (e.g. Claude Code’s "
                    + "alt+p) reach the terminal. Changes apply to open panes immediately."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Writes Settings out to tian's Ghostty override file and reloads the
    /// config — Ghostty pushes it to every live surface, so no relaunch.
    private func applyOverrides() {
        GhosttyApp.shared.applySettingsOverrides()
        configDiagnostics = GhosttyApp.shared.configDiagnostics
    }
}

#Preview {
    SettingsView()
}
