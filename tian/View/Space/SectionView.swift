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

    /// Horizontal insets applied only to the section tab bar so it clears
    /// the sidebar toggle (leading) and inspect-panel rail (trailing) when
    /// this section sits against the corresponding window edge. The pane
    /// surfaces below the tab bar still extend full-bleed.
    var leadingTabBarInset: CGFloat = 0
    var trailingTabBarInset: CGFloat = 0

    var body: some View {
        if section.kind == .claude && section.tabs.isEmpty {
            EmptyClaudePlaceholderView(
                onNewTab: {
                    let wd = resolveWorkingDirectory()
                    spaceModel.createTab(in: section, workingDirectory: wd)
                },
                onCloseSpace: {
                    // FR-07c — explicit Cmd+W closes the Space.
                    Task { await spaceModel.requestSpaceClose() }
                }
            )
        } else if let activeTab = section.activeTab {
            // Bar overlays terminal so its aurora glow isn't clipped by the opaque Metal layer.
            ZStack(alignment: .top) {
                // Terminal content for the active terminal tab. (Pane surfaces
                // are model-owned and re-parented, so this is cheap to rebuild.)
                if activeTab.isTerminalTab {
                    SplitTreeView(
                        node: activeTab.paneViewModel.splitTree.root,
                        viewModel: activeTab.paneViewModel,
                        isTabVisible: isSectionFocused
                    )
                    .padding(.top, SectionTabBarView.height(for: section.kind))
                }

                // Markdown readers are kept mounted across tab switches and just
                // shown/hidden — unlike a terminal there's no model-owned NSView
                // to re-parent, so tearing the view down would force MarkdownUI
                // to re-lay-out the whole document on every switch. Holding them
                // alive makes re-activation instant (mirrors surface reuse).
                ForEach(section.tabs.filter(\.isMarkdownReader)) { tab in
                    if let document = tab.markdownDocument {
                        let isActive = tab.id == activeTab.id
                        MarkdownReaderView(
                            document: document,
                            isFocused: isSectionFocused && isActive,
                            onClose: { section.removeTab(id: tab.id) }
                        )
                        .padding(.top, SectionTabBarView.height(for: section.kind))
                        .opacity(isActive ? 1 : 0)
                        .allowsHitTesting(isActive)
                        .accessibilityHidden(!isActive)
                    }
                }

                // Image readers are kept mounted and shown/hidden the same way
                // as markdown readers, so re-activation just draws the cached
                // (already-decoded) bitmap.
                ForEach(section.tabs.filter(\.isImageReader)) { tab in
                    if let document = tab.imageDocument {
                        let isActive = tab.id == activeTab.id
                        ImageReaderView(
                            document: document,
                            isFocused: isSectionFocused && isActive,
                            onClose: { section.removeTab(id: tab.id) }
                        )
                        .padding(.top, SectionTabBarView.height(for: section.kind))
                        .opacity(isActive ? 1 : 0)
                        .allowsHitTesting(isActive)
                        .accessibilityHidden(!isActive)
                    }
                }

                tabBar(for: activeTab)
                    .padding(.leading, leadingTabBarInset)
                    .padding(.trailing, trailingTabBarInset)
                    // Tab bar before terminal pane in VoiceOver order.
                    .accessibilitySortPriority(1)
            }
        } else {
            // Terminal section with no active tab — should not appear in
            // practice because FR-12 auto-hides before reaching zero.
            Color.clear
        }
    }

    /// Builds the section tab bar. Claude sections render no trailing
    /// toolbar — the show/hide-terminal toggle lives in the bottom status
    /// bar now. Terminal sections still get the dock-options menu.
    @ViewBuilder
    private func tabBar(for activeTab: TabModel) -> some View {
        if section.kind == .terminal {
            SectionTabBarView(
                section: section,
                onNewTab: addTab,
                trailingToolbar: {
                    SectionToolbarView(spaceModel: spaceModel, kind: section.kind)
                }
            )
        } else {
            // One SectionTabBarView for the Claude section regardless of the
            // active tab, so its new-tab capsule keeps identity and morphs
            // (circle ⇄ pill) as a markdown reader becomes/ceases active.
            SectionTabBarView(
                section: section,
                spaceModel: spaceModel,
                markdownReaderDocument: markdownReaderDocument(for: activeTab),
                onNewTab: addTab
            )
        }
    }

    private func addTab() {
        let wd = resolveWorkingDirectory()
        spaceModel.createTab(in: section, workingDirectory: wd)
    }

    /// The reader document driving the new-tab capsule's diff toggle and
    /// copy-all button: the active tab's reader document when it loaded
    /// cleanly, else `nil` (capsule stays a circle).
    private func markdownReaderDocument(for activeTab: TabModel) -> MarkdownDocument? {
        guard let document = activeTab.markdownDocument, document.loadError == nil else { return nil }
        return document
    }
}
