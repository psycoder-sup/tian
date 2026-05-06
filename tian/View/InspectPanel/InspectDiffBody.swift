import SwiftUI

/// Diff-tab body for the Inspect panel (FR-T10–T14, FR-T16, FR-T17, FR-T19).
///
/// Renders a virtualized `LazyVStack` of file groups against the working
/// tree's current `git diff HEAD` result. The view is purely presentational —
/// `InspectDiffViewModel` owns the debounced fetch + cancellation logic, and
/// `InspectTabState` owns the per-file collapse map.
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
            InspectPanelMutedMessage("Not in a git repository.")
        } else if viewModel.isLoadingInitial {
            InspectPanelMutedMessage("Loading…")
        } else if viewModel.files.isEmpty {
            InspectPanelMutedMessage("No changes against HEAD.")
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
