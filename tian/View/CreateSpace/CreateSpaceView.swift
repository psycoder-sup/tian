import SwiftUI

/// Unified modal for creating a space — with or without an associated git worktree.
/// Replaces the old `BranchNameInputView`.
struct CreateSpaceView: View {
    let workspace: Workspace
    let repoRoot: URL?           // nil when the workspace's working directory isn't a git repo
    let worktreeDir: String
    let onSubmitPlain: (String) -> Void
    let onSubmitWorktree: (CreateWorktreeSubmission) -> Void
    let onCancel: () -> Void

    @State private var inputText: String = ""
    @State private var worktreeEnabled: Bool
    @State private var viewModel = BranchListViewModel()
    @FocusState private var isFocused: Bool

    init(
        workspace: Workspace,
        repoRoot: URL?,
        worktreeDir: String,
        onSubmitPlain: @escaping (String) -> Void,
        onSubmitWorktree: @escaping (CreateWorktreeSubmission) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.workspace = workspace
        self.repoRoot = repoRoot
        self.worktreeDir = worktreeDir
        self.onSubmitPlain = onSubmitPlain
        self.onSubmitWorktree = onSubmitWorktree
        self.onCancel = onCancel
        // Initial checkbox state: last-used per workspace, defaulting to false.
        // If the workspace isn't a git repo, force false regardless of memory.
        let remembered = workspace.lastCreateWorktreeChoice ?? false
        self._worktreeEnabled = State(initialValue: repoRoot != nil && remembered)
    }

    private var isGitRepo: Bool { repoRoot != nil }

    private var sanitizedInput: String {
        worktreeEnabled ? Self.sanitizeBranchName(inputText) : inputText
    }

    private var invalidCharsInBranchName: Bool {
        guard worktreeEnabled else { return false }
        return Self.containsInvalidBranchChars(sanitizedInput)
    }

    private var currentCollision: BranchRow? {
        guard worktreeEnabled else { return nil }
        return viewModel.collision(for: sanitizedInput)
    }

    private var submitAction: SubmitAction {
        Self.resolveSubmitAction(
            sanitizedInput: sanitizedInput,
            worktreeEnabled: worktreeEnabled,
            isGitRepo: isGitRepo,
            collision: currentCollision,
            highlightedRow: worktreeEnabled ? viewModel.selectedRow() : nil
        )
    }

    private var canSubmit: Bool { submitAction != .blocked }

    private var resolvedPath: String {
        guard let repoRoot else { return "" }
        let base = WorktreeService.resolveWorktreeBase(
            repoRoot: repoRoot.path, worktreeDir: worktreeDir
        )
        let name = sanitizedInput.isEmpty ? "<branch>" : sanitizedInput
        return (base as NSString).appendingPathComponent(name)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .onTapGesture { onCancel() }

            VStack(spacing: 12) {
                Text("New space")
                    .font(.system(size: 15, weight: .semibold))

                TextField(worktreeEnabled ? "Branch name" : "Space name", text: $inputText)
                    .textFieldStyle(.roundedBorder)
                    .focused($isFocused)
                    .onChange(of: inputText) { _, new in
                        // Live sanitization (worktree mode only).
                        if worktreeEnabled {
                            let cleaned = Self.sanitizeBranchName(new)
                            if cleaned != new {
                                inputText = cleaned
                            }
                            viewModel.query = cleaned
                        }
                    }
                    .onSubmit(handleSubmit)
                    .onExitCommand { onCancel() }
                    .onKeyPress(.upArrow) {
                        guard worktreeEnabled else { return .ignored }
                        viewModel.moveHighlight(.up); return .handled
                    }
                    .onKeyPress(.downArrow) {
                        guard worktreeEnabled else { return .ignored }
                        viewModel.moveHighlight(.down); return .handled
                    }

                Toggle(isOn: $worktreeEnabled) {
                    Text("Create worktree")
                        .font(.system(size: 12))
                }
                .toggleStyle(.checkbox)
                .disabled(!isGitRepo)
                .help(isGitRepo ? "" : "Workspace is not a git repository")
                .onChange(of: worktreeEnabled) { _, new in
                    workspace.lastCreateWorktreeChoice = new
                    if new {
                        // Push current input through sanitization & feed the list filter.
                        let cleaned = Self.sanitizeBranchName(inputText)
                        if cleaned != inputText { inputText = cleaned }
                        viewModel.query = cleaned
                    } else {
                        viewModel.query = ""
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if worktreeEnabled {
                    branchList
                }

                footer

                HStack {
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
        .task {
            guard let repoRoot else { return }
            // Match what's in the field when the modal opens (usually empty).
            viewModel.query = sanitizedInput
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
            submit(branch: row.displayName, existing: true, remoteRef: row.remoteRef)
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
    private var footer: some View {
        HStack(spacing: 6) {
            if !worktreeEnabled {
                if !sanitizedInput.isEmpty {
                    Text("Will create plain space \u{201C}\(sanitizedInput)\u{201D}")
                }
            } else if !isGitRepo {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text("Workspace is not a git repository")
            } else if invalidCharsInBranchName {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text("Branch name contains invalid characters")
            } else if let collision = currentCollision, collision.isInUse {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text("\u{201C}\(collision.displayName)\u{201D} is already in use as a worktree")
            } else if let collision = currentCollision {
                Text("Will check out existing branch \u{201C}\(collision.displayName)\u{201D}")
            } else if viewModel.isFetching {
                ProgressView().controlSize(.mini)
                Text("Syncing remotes…")
            } else if viewModel.usedCachedRemotes {
                Text("Using cached remotes")
            } else {
                Text(resolvedPath)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer()
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Submit

    private func handleSubmit() {
        switch submitAction {
        case .blocked:
            return
        case .plain(let name):
            onSubmitPlain(name)
        case .createBranch(let name):
            submit(branch: name, existing: false, remoteRef: nil)
        case .checkoutExisting(let branch, let remoteRef):
            submit(branch: branch, existing: true, remoteRef: remoteRef)
        }
    }

    private func submit(branch: String, existing: Bool, remoteRef: String?) {
        onSubmitWorktree(
            CreateWorktreeSubmission(
                branchName: branch,
                existingBranch: existing,
                remoteRef: remoteRef
            )
        )
    }

    // MARK: - Submit resolution

    /// Prefers an exact-match collision over the currently highlighted row:
    /// when the substring-filtered list anchors on a different branch than
    /// the one the user fully typed, submit must still target the typed name.
    static func resolveSubmitAction(
        sanitizedInput: String,
        worktreeEnabled: Bool,
        isGitRepo: Bool,
        collision: BranchRow?,
        highlightedRow: BranchRow?
    ) -> SubmitAction {
        guard !sanitizedInput.isEmpty else { return .blocked }
        if !worktreeEnabled {
            return .plain(name: sanitizedInput)
        }
        guard isGitRepo else { return .blocked }
        if containsInvalidBranchChars(sanitizedInput) { return .blocked }
        if let collision, collision.isInUse { return .blocked }
        if let collision {
            return .checkoutExisting(
                branch: collision.displayName,
                remoteRef: collision.remoteRef
            )
        }
        if let row = highlightedRow {
            return .checkoutExisting(branch: row.displayName, remoteRef: row.remoteRef)
        }
        return .createBranch(name: sanitizedInput)
    }

    // MARK: - Sanitization

    /// Live sanitization rule: replace ASCII space with `-`. Other characters
    /// pass through untouched; invalid ones are flagged via `containsInvalidBranchChars`.
    static func sanitizeBranchName(_ raw: String) -> String {
        raw.replacingOccurrences(of: " ", with: "-")
    }

    /// Conservative subset of `git check-ref-format` — blocks the cases users
    /// actually hit; git's real rules are stricter.
    static func containsInvalidBranchChars(_ name: String) -> Bool {
        if name.isEmpty { return false }
        if name.first == "-" { return true }
        if name.contains("..") { return true }
        return name.contains(where: { bannedBranchChars.contains($0) })
    }

    private static let bannedBranchChars: Set<Character> = ["~", "^", ":", "?", "*", "[", "\\"]
}

/// Submission payload from the modal to the orchestrator.
struct CreateWorktreeSubmission {
    let branchName: String
    let existingBranch: Bool
    let remoteRef: String?
}

enum SubmitAction: Equatable {
    case blocked
    case plain(name: String)
    case createBranch(name: String)
    case checkoutExisting(branch: String, remoteRef: String?)
}
