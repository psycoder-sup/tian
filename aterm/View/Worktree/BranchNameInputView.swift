import SwiftUI

/// Overlay for entering a branch name when creating a new worktree Space.
struct BranchNameInputView: View {
    let repoRoot: URL
    let worktreeDir: String
    let onSubmit: (String, Bool) -> Void
    let onCancel: () -> Void

    @State private var branchName: String = ""
    @State private var isExistingBranch: Bool = false
    @FocusState private var isFocused: Bool

    private var resolvedPath: String {
        let base = WorktreeService.resolveWorktreeBase(
            repoRoot: repoRoot.path, worktreeDir: worktreeDir
        )
        let name = branchName.isEmpty ? "<branch>" : branchName
        return (base as NSString).appendingPathComponent(name)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .onTapGesture { onCancel() }

            VStack(spacing: 16) {
                Text("New Worktree Space")
                    .font(.system(size: 15, weight: .semibold))

                Picker("", selection: $isExistingBranch) {
                    Text("New branch").tag(false)
                    Text("Existing branch").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                TextField("Branch name", text: $branchName)
                    .textFieldStyle(.roundedBorder)
                    .focused($isFocused)
                    .onSubmit(handleSubmit)
                    .onExitCommand { onCancel() }

                Text(resolvedPath)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            .padding(24)
            .frame(width: 320)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        }
        .onAppear {
            DispatchQueue.main.async { isFocused = true }
        }
    }

    private func handleSubmit() {
        let trimmed = branchName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        onSubmit(trimmed, isExistingBranch)
    }
}
