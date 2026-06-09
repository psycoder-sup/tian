import Foundation
import Observation

/// A single tab within a space. Each tab owns a PaneViewModel (split tree + surfaces).
@MainActor @Observable
final class TabModel: Identifiable {
    let id: UUID
    var customName: String?
    let paneViewModel: PaneViewModel
    let createdAt: Date

    /// Mirrors the owning SectionModel.kind. Set on construction, never
    /// changed — panes do not move sections (PRD NG5).
    let sectionKind: SectionKind

    /// Absolute path of the markdown file this tab renders, when the tab is a
    /// markdown reader rather than a terminal. `nil` for ordinary terminal /
    /// Claude tabs. A markdown tab is backed by a surface-less PaneViewModel
    /// (see `PaneViewModel.makeEmpty`) and renders `MarkdownReaderView`.
    var markdownFilePath: String?

    /// `true` when this tab renders a markdown file instead of a terminal.
    var isMarkdownReader: Bool { markdownFilePath != nil }

    /// Called when the tab's last pane is closed. The owning SpaceModel should remove this tab.
    var onEmpty: (() -> Void)?

    init(customName: String? = nil, workingDirectory: String = "~", sectionKind: SectionKind = .terminal) {
        self.id = UUID()
        self.customName = customName
        self.createdAt = Date()
        self.sectionKind = sectionKind
        self.paneViewModel = PaneViewModel(workingDirectory: workingDirectory, sectionKind: sectionKind)

        // Wire cascading close: last pane → tab empty → space removes tab
        self.paneViewModel.onEmpty = { [weak self] in
            self?.onEmpty?()
        }
    }

    /// Restore a tab with a specific ID and pre-built PaneViewModel.
    init(id: UUID = UUID(), customName: String? = nil, paneViewModel: PaneViewModel, sectionKind: SectionKind = .terminal, markdownFilePath: String? = nil) {
        self.id = id
        self.customName = customName
        self.createdAt = Date()
        self.sectionKind = sectionKind
        self.markdownFilePath = markdownFilePath
        self.paneViewModel = paneViewModel
        self.paneViewModel.sectionKind = sectionKind

        self.paneViewModel.onEmpty = { [weak self] in
            self?.onEmpty?()
        }
    }

    /// The title from the focused pane's terminal (set by the shell via OSC escape sequences).
    var title: String {
        paneViewModel.title
    }

    /// Display name: user-assigned custom name, the markdown file name for a
    /// markdown reader tab, or the terminal title if none set.
    var displayName: String {
        if let customName { return customName }
        if let markdownFilePath { return (markdownFilePath as NSString).lastPathComponent }
        return title
    }

    func cleanup() {
        paneViewModel.cleanup()
    }
}
