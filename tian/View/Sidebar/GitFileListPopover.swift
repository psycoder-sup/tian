import SwiftUI

/// Hover popover showing changed files with color-coded status letters.
/// Capped at 30 files with a "+N more files..." footer (FR-043).
struct GitFileListPopover: View {
    let changedFiles: [GitChangedFile]

    private let maxDisplayed = 30

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(changedFiles.prefix(maxDisplayed)), id: \.self) { file in
                HStack(spacing: 6) {
                    Text(file.status.letter)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(file.status.color)
                        .frame(width: 12, alignment: .center)

                    Text(file.path)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .accessibilityLabel("\(file.status.accessibilityLabel) \(file.path)")
            }

            if changedFiles.count > maxDisplayed {
                Text("and \(changedFiles.count - maxDisplayed) more files...")
                    .font(.system(size: 9))
                    .foregroundStyle(Color(white: 0.45))
                    .padding(.top, 2)
            }
        }
        .padding(8)
        .frame(minWidth: 200, maxWidth: 350)
    }
}
