import SwiftUI

/// Overlay for entering a branch name when creating a new worktree Space.
struct BranchNameInputView: View {
    let repoRoot: URL
    let worktreeDir: String
    let onSubmit: (String, Bool, String?) -> Void
    let onCancel: () -> Void

    @State private var isExistingBranch: Bool = false
    @State private var viewModel = BranchListViewModel()
    @FocusState private var isFocused: Bool

    private var resolvedPath: String {
        let base = WorktreeService.resolveWorktreeBase(
            repoRoot: repoRoot.path, worktreeDir: worktreeDir
        )
        let name = viewModel.query.isEmpty ? "<branch>" : viewModel.query
        return (base as NSString).appendingPathComponent(name)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .onTapGesture { onCancel() }

            VStack(spacing: 12) {
                Text("New Worktree Space")
                    .font(.system(size: 15, weight: .semibold))

                Picker("", selection: $isExistingBranch) {
                    Text("New branch").tag(false)
                    Text("Existing branch").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: isExistingBranch) { _, new in
                    viewModel.mode = new ? .existingBranch : .newBranch
                }

                TextField("Branch name", text: $viewModel.query)
                    .textFieldStyle(.roundedBorder)
                    .focused($isFocused)
                    .onSubmit(handleSubmit)
                    .onExitCommand { onCancel() }
                    .onKeyPress(.upArrow) {
                        viewModel.moveHighlight(.up); return .handled
                    }
                    .onKeyPress(.downArrow) {
                        viewModel.moveHighlight(.down); return .handled
                    }

                if isExistingBranch {
                    branchList
                } else if let hit = viewModel.collision(for: viewModel.query) {
                    collisionRow(for: hit)
                }

                footer
            }
            .padding(20)
            .frame(width: 360)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        }
        .task {
            viewModel.mode = isExistingBranch ? .existingBranch : .newBranch
            await viewModel.load(repoRoot: repoRoot.path)
        }
        .onAppear {
            DispatchQueue.main.async { isFocused = true }
        }
    }

    // MARK: - Subviews

    private var branchList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if viewModel.rows.isEmpty {
                        Text(viewModel.loadError ?? "No matching branches")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                    } else {
                        ForEach(viewModel.rows) { row in
                            branchRow(row).id(row.id)
                        }
                    }
                }
            }
            .onChange(of: viewModel.highlightedID) { _, new in
                guard let new else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(new, anchor: .center)
                }
            }
        }
        .frame(maxHeight: 200)
        .background(Color.black.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private func branchRow(_ row: BranchRow) -> some View {
        let highlighted = row.id == viewModel.highlightedID
        HStack(spacing: 8) {
            badge(row.badge)
                .frame(width: 52, alignment: .leading)
            Text(row.displayName)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)
            if row.isCurrent {
                Text("(current)")
                    .font(.system(size: 10).italic())
                    .foregroundStyle(.secondary)
            } else if row.isInUse {
                Text("(in use)")
                    .font(.system(size: 10).italic())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(row.relativeDate)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(highlighted ? Color.accentColor.opacity(0.2) : Color.clear)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(highlighted ? Color.accentColor : .clear)
                .frame(width: 2)
        }
        .opacity(row.isInUse ? 0.45 : 1)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !row.isInUse else { return }
            submit(row: row)
        }
    }

    @ViewBuilder
    private func badge(_ b: BranchRow.Badge) -> some View {
        switch b {
        case .local:
            Text("local")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.blue)
        case .origin(let name):
            Text(name)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.orange)
        case .localAndOrigin:
            Text("local")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.blue)
        }
    }

    @ViewBuilder
    private func collisionRow(for row: BranchRow) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text("\u{201C}\(row.displayName)\u{201D} already exists")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.yellow.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: 6) {
            if viewModel.isFetching {
                ProgressView().controlSize(.mini)
                Text("Syncing remotes…")
            } else if viewModel.usedCachedRemotes {
                Text("Using cached remotes")
            } else {
                Text(resolvedPath)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Submit

    private func handleSubmit() {
        let trimmed = viewModel.query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        if isExistingBranch {
            guard let row = viewModel.selectedRow() else { return }   // no-op, prevents silent failure
            submit(row: row)
        } else {
            onSubmit(trimmed, false, nil)
        }
    }

    private func submit(row: BranchRow) {
        onSubmit(row.displayName, true, row.remoteRef)
    }
}
