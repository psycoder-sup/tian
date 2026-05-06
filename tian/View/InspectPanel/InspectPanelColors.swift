import SwiftUI

/// Canonical diff-line / file-status color tokens for the Inspect panel.
///
/// All views that tint added/deleted/modified indicators (header chips,
/// diff-line markers, row backgrounds, info-strip counts) pull from this
/// single source of truth. Values are tuned for the dark inspect-panel
/// background — they match `InspectPanelFileRow.badgeColor`.
enum DiffColors {
    /// Soft green for added lines / files. #6ee19a at full opacity.
    static let added   = Color(red: 110/255, green: 225/255, blue: 154/255)
    /// Soft red for deleted lines / files. #ff9a9a at full opacity.
    static let deleted = Color(red: 255/255, green: 154/255, blue: 154/255)
    /// Amber for modified files. #f59e0b at full opacity.
    static let modified = Color(red: 245/255, green: 158/255, blue: 11/255)
    /// Blue for renamed files. #60a5fa at full opacity.
    static let renamed  = Color(red: 96/255,  green: 165/255, blue: 250/255)
    /// Orange for unmerged/conflict files.
    static let unmerged = Color(red: 251/255, green: 146/255, blue: 60/255)
}
