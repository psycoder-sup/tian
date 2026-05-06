import SwiftUI

/// Diff-tab body for the Inspect panel (FR-T10–T14, FR-T16, FR-T17, FR-T19).
///
/// Renders a virtualized `LazyVStack` of file groups against the working
/// tree's current `git diff HEAD` result. The view is purely presentational —
/// `InspectDiffViewModel` (Task 7) owns the debounced fetch + cancellation
/// logic, and `InspectTabState` (Task 2) owns the per-file collapse map.
///
/// ScrollViewReader uses the named anchor `"diff-top"` so tab activation can
/// rebuild scroll position cheaply (FR-T04). The collapse map survives a
/// round-trip via `InspectTabState.diffCollapse`.
struct InspectDiffBody: View {
    @Bindable var viewModel: InspectDiffViewModel
    @Bindable var tabState: InspectTabState
    /// `true` when the active space's working directory is not inside a git
    /// repo. Per FR-T19 the body shows the centered "Not in a git repository."
    /// placeholder in that case.
    let isNoRepo: Bool

    // MARK: - Body

    var body: some View {
        if isNoRepo {
            CenteredMutedText("Not in a git repository.")
        } else if viewModel.isLoadingInitial {
            CenteredMutedText("Loading…")
        } else if viewModel.files.isEmpty {
            CenteredMutedText("No changes against HEAD.")
        } else {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        // Anchor for FR-T04: scroll position is rebuilt cheaply
                        // on tab activation rather than preserved per-pixel.
                        Color.clear.frame(height: 0).id("diff-top")

                        ForEach(viewModel.files, id: \.path) { file in
                            GitDiffFileGroup(
                                file: file,
                                isCollapsed: Binding(
                                    get: { tabState.diffCollapse[file.path] ?? false },
                                    set: { tabState.diffCollapse[file.path] = $0 }
                                )
                            )
                            Divider()
                                .background(Color.white.opacity(0.04))
                        }
                    }
                }
                .onAppear { proxy.scrollTo("diff-top", anchor: .top) }
            }
        }
    }
}

// MARK: - Centered muted text helper

/// Centered, dim placeholder used by Diff and Branch bodies for empty,
/// loading, and no-repo states (FR-T17 / FR-T19 / FR-T26 / FR-T27).
struct CenteredMutedText: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(Color.primary.opacity(0.35))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Previews

#Preview("Diff body – loading") {
    let vm = InspectDiffViewModel()
    let state = InspectTabState(activeTab: .diff)
    InspectDiffBody(viewModel: vm, tabState: state, isNoRepo: false)
        .frame(width: 320, height: 400)
        .background(Color(red: 8/255, green: 11/255, blue: 18/255, opacity: 0.95))
}

#Preview("Diff body – no-repo") {
    let vm = InspectDiffViewModel()
    let state = InspectTabState(activeTab: .diff)
    InspectDiffBody(viewModel: vm, tabState: state, isNoRepo: true)
        .frame(width: 320, height: 400)
        .background(Color(red: 8/255, green: 11/255, blue: 18/255, opacity: 0.95))
}
