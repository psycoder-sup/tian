import Foundation
import Observation

/// A single tab within a space. Each tab owns a PaneViewModel (split tree + surfaces).
@MainActor @Observable
final class TabModel: Identifiable {
    let id: UUID
    var customName: String?

    /// The command this tab's Claude pane launched with — a custom command
    /// ("Run Custom Claude" / preset) or the user's configured default. Drives
    /// the tab's launch-variant badge (`claudeLaunchBadge`). `nil` for terminal
    /// tabs and reader tabs. In-memory only: a restored session resumes via
    /// `claude --resume <id>` (bare claude), so the original variant no longer
    /// applies and the badge is intentionally not persisted.
    var launchCommand: String?

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

    /// Tab-lived backing store for a markdown reader tab. Holds the pre-parsed
    /// content so switching to this tab doesn't re-read or re-parse the file.
    /// `nil` for terminal / Claude tabs. Set together with `markdownFilePath`.
    let markdownDocument: MarkdownDocument?

    /// `true` when this tab renders a markdown file instead of a terminal.
    var isMarkdownReader: Bool { markdownFilePath != nil }

    /// Absolute path of the image file this tab renders, when the tab is an
    /// image reader rather than a terminal. `nil` for ordinary tabs. Like a
    /// markdown tab, backed by a surface-less PaneViewModel and rendered by
    /// `ImageReaderView`.
    var imageFilePath: String?

    /// Tab-lived backing store for an image reader tab. Holds the decoded image
    /// so switching to this tab doesn't re-read or re-decode the file. `nil`
    /// for non-image tabs. Set together with `imageFilePath`.
    let imageDocument: ImageDocument?

    /// `true` when this tab renders an image file instead of a terminal.
    var isImageReader: Bool { imageFilePath != nil }

    /// `true` only for real terminal tabs — those that render a `SplitTreeView`
    /// of ghostty surfaces. Reader tabs (markdown / image) are surface-less.
    var isTerminalTab: Bool { markdownDocument == nil && imageDocument == nil }

    /// Called when the tab's last pane is closed. The owning SpaceModel should remove this tab.
    var onEmpty: (() -> Void)?

    init(customName: String? = nil, workingDirectory: String = "~", sectionKind: SectionKind = .terminal) {
        self.id = UUID()
        self.customName = customName
        self.createdAt = Date()
        self.sectionKind = sectionKind
        self.markdownDocument = nil
        self.imageDocument = nil
        self.paneViewModel = PaneViewModel(workingDirectory: workingDirectory, sectionKind: sectionKind)

        // Wire cascading close: last pane → tab empty → space removes tab
        self.paneViewModel.onEmpty = { [weak self] in
            self?.onEmpty?()
        }
    }

    /// Restore a tab with a specific ID and pre-built PaneViewModel.
    init(id: UUID = UUID(), customName: String? = nil, paneViewModel: PaneViewModel, sectionKind: SectionKind = .terminal, markdownFilePath: String? = nil, imageFilePath: String? = nil) {
        self.id = id
        self.customName = customName
        self.createdAt = Date()
        self.sectionKind = sectionKind
        self.markdownFilePath = markdownFilePath
        self.markdownDocument = markdownFilePath.map(MarkdownDocument.init(filePath:))
        self.imageFilePath = imageFilePath
        self.imageDocument = imageFilePath.map(ImageDocument.init(filePath:))
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
        if let imageFilePath { return (imageFilePath as NSString).lastPathComponent }
        return title
    }

    /// Leading badge distinguishing which Claude variant this tab runs, or
    /// `nil` for plain `claude`, terminal tabs, and reader tabs.
    var claudeLaunchBadge: ClaudeLaunchBadge? {
        guard sectionKind == .claude, let launchCommand else { return nil }
        return ClaudeLaunchBadge.forCommand(launchCommand)
    }

    func cleanup() {
        paneViewModel.cleanup()
    }
}

/// A small per-variant indicator shown on a Claude tab so the launched command
/// (`claude --chrome`, `headroom wrap claude`, …) is distinguishable at a glance.
struct ClaudeLaunchBadge: Equatable {
    /// SF Symbol name rendered in the tab's leading slot.
    let symbol: String
    /// Full launch command, surfaced as the tab's tooltip / accessibility text.
    let command: String

    /// Maps a launch command to its badge, or `nil` when the command is empty or
    /// the bare default (`TianSettings.defaultClaudeCommand`) — plain `claude`
    /// tabs stay unmarked. Known variants get a recognizable glyph; any other
    /// custom command gets a generic one.
    @MainActor
    static func forCommand(_ command: String) -> ClaudeLaunchBadge? {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != TianSettings.defaultClaudeCommand else { return nil }

        let lower = trimmed.lowercased()
        let symbol: String
        if lower.contains("--chrome") {
            symbol = "globe"
        } else if lower.contains("headroom") {
            symbol = "rectangle.compress.vertical"
        } else {
            symbol = "wand.and.stars"
        }
        return ClaudeLaunchBadge(symbol: symbol, command: trimmed)
    }
}
