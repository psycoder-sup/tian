import SwiftUI

/// Per-section container. Renders the section tab bar + active tab's
/// split-tree. When a Claude section has zero tabs, the
/// `EmptyClaudePlaceholderView` stands in (FR-07) — Terminal sections
/// auto-hide before ever reaching zero tabs (FR-12).
struct SectionView: View {
    @Bindable var spaceModel: SpaceModel
    let section: SectionModel

    /// Source-of-truth for the active Space's working directory. Used
    /// by the empty-Claude placeholder "New Claude pane" button.
    var resolveWorkingDirectory: () -> String

    /// Flag whether this section currently owns focus within its Space.
    /// Passed down to `SplitTreeView` so pane surfaces can render their
    /// focus ring / cursor accordingly.
    var isSectionFocused: Bool

    var body: some View {
        Group {
            if section.kind == .claude && section.tabs.isEmpty {
                EmptyClaudePlaceholderView(onNewTab: {
                    let wd = resolveWorkingDirectory()
                    section.createTab(workingDirectory: wd)
                })
            } else if let activeTab = section.activeTab {
                VStack(spacing: 0) {
                    SectionTabBarView(
                        section: section,
                        onNewTab: {
                            let wd = resolveWorkingDirectory()
                            section.createTab(workingDirectory: wd)
                        },
                        trailingToolbar: {
                            SectionToolbarView(spaceModel: spaceModel, kind: section.kind)
                        }
                    )

                    SplitTreeView(
                        node: activeTab.paneViewModel.splitTree.root,
                        viewModel: activeTab.paneViewModel,
                        isTabVisible: isSectionFocused
                            || spaceModel.focusedSectionKind != section.kind
                    )
                }
            } else {
                // Terminal section with no active tab — should not appear in
                // practice because FR-12 auto-hides before reaching zero.
                Color.clear
            }
        }
    }
}
