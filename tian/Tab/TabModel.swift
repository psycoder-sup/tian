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
    init(id: UUID, customName: String? = nil, paneViewModel: PaneViewModel, sectionKind: SectionKind = .terminal) {
        self.id = id
        self.customName = customName
        self.createdAt = Date()
        self.sectionKind = sectionKind
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

    /// Display name: user-assigned custom name, or the terminal title if none set.
    var displayName: String {
        customName ?? title
    }

    func cleanup() {
        paneViewModel.cleanup()
    }
}
