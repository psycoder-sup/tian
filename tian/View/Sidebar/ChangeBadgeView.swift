import SwiftUI

/// Combined +/- change badge showing additions and deletions.
/// Shows a hover popover with the full file list.
struct ChangeBadgeView: View {
    let diffSummary: GitDiffSummary
    var changedFiles: [GitChangedFile] = []

    @State private var isPopoverPresented = false
    @State private var hoverTask: Task<Void, Never>?

    private var additions: Int {
        diffSummary.added + diffSummary.modified + diffSummary.renamed + diffSummary.unmerged
    }

    private var deletions: Int {
        diffSummary.deleted
    }

    var body: some View {
        if !diffSummary.isEmpty {
            HStack(spacing: 0) {
                if additions > 0 {
                    Text("+\(additions)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color(red: 0.302, green: 0.698, blue: 0.4))
                        .padding(.leading, 5)
                        .padding(.trailing, 4)
                        .padding(.vertical, 2)
                        .background(Color(red: 0.2, green: 0.502, blue: 0.278).opacity(0.5))
                }

                if deletions > 0 {
                    Text("−\(deletions)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color(red: 0.8, green: 0.35, blue: 0.35))
                        .padding(.leading, 4)
                        .padding(.trailing, 5)
                        .padding(.vertical, 2)
                        .background(Color(red: 0.502, green: 0.2, blue: 0.2).opacity(0.5))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .onHover { hovering in
                hoverTask?.cancel()
                if hovering {
                    hoverTask = Task {
                        try? await Task.sleep(for: .milliseconds(400))
                        guard !Task.isCancelled else { return }
                        isPopoverPresented = true
                    }
                } else {
                    hoverTask = Task {
                        try? await Task.sleep(for: .milliseconds(200))
                        guard !Task.isCancelled else { return }
                        isPopoverPresented = false
                    }
                }
            }
            .popover(isPresented: $isPopoverPresented) {
                GitFileListPopover(changedFiles: changedFiles)
                    .onHover { hovering in
                        hoverTask?.cancel()
                        if !hovering {
                            hoverTask = Task {
                                try? await Task.sleep(for: .milliseconds(200))
                                guard !Task.isCancelled else { return }
                                isPopoverPresented = false
                            }
                        }
                    }
            }
        }
    }
}
