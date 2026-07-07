import SwiftUI

/// Modal for creating a remote (SSH) workspace. Collects an ssh host (alias or
/// `user@host`) and an absolute remote directory; auth is handled entirely by
/// the user's `~/.ssh/config` + ssh-agent (no credential UI here).
struct CreateWorkspaceView: View {
    /// Called with the target and an optional custom name (nil = auto-derived
    /// `dir @ host`).
    let onSubmit: (RemoteConnection, String?) -> Void
    let onCancel: () -> Void

    @State private var host: String = ""
    @State private var remoteDirectory: String = ""
    @State private var name: String = ""
    @FocusState private var focus: Field?

    private enum Field { case host, directory, name }

    private var trimmedHost: String {
        host.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var trimmedDirectory: String {
        remoteDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The remote directory must be an absolute POSIX path: it's stored verbatim
    /// as the workspace's working directory and used as the registry root that
    /// makes git/file-tree lookups resolve remotely, so a `~`/relative path
    /// wouldn't match the absolute paths git reports back.
    private var directoryIsAbsolute: Bool { trimmedDirectory.hasPrefix("/") }

    /// A host starting with `-` would be parsed by ssh as an option
    /// (argument-injection risk), so it's rejected here too.
    private var hostIsSafe: Bool { !trimmedHost.isEmpty && !trimmedHost.hasPrefix("-") }

    private var canSubmit: Bool {
        hostIsSafe && !trimmedDirectory.isEmpty && directoryIsAbsolute
    }

    private var derivedName: String {
        RemoteConnection.deriveWorkspaceName(host: trimmedHost, remoteDirectory: trimmedDirectory)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .onTapGesture { onCancel() }

            VStack(alignment: .leading, spacing: 12) {
                Text("New SSH Workspace")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)

                field(label: "Host", placeholder: "ssh alias or user@host", text: $host, focus: .host)
                    .onSubmit { focus = .directory }

                field(label: "Remote directory", placeholder: "/absolute/path", text: $remoteDirectory, focus: .directory)
                    .onSubmit { focus = .name }

                if !trimmedDirectory.isEmpty && !directoryIsAbsolute {
                    Text("Remote directory must be an absolute path (start with /).")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }

                field(
                    label: "Name",
                    placeholder: trimmedHost.isEmpty ? "Workspace name (optional)" : derivedName,
                    text: $name,
                    focus: .name
                )
                .onSubmit { if canSubmit { handleSubmit() } }

                HStack {
                    Text("Auth uses your ~/.ssh/config + ssh-agent.")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button("Cancel", action: onCancel)
                        .keyboardShortcut(.cancelAction)
                    Button("Create", action: handleSubmit)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canSubmit)
                }
            }
            .padding(20)
            .frame(width: 360)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        }
        .onAppear {
            DispatchQueue.main.async { focus = .host }
        }
    }

    @ViewBuilder
    private func field(label: String, placeholder: String, text: Binding<String>, focus: Field) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .focused($focus, equals: focus)
        }
    }

    private func handleSubmit() {
        guard canSubmit else { return }
        let remote = RemoteConnection(host: trimmedHost, remoteDirectory: trimmedDirectory)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        onSubmit(remote, trimmedName.isEmpty ? nil : trimmedName)
    }
}
