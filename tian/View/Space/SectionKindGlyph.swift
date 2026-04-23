import SwiftUI

/// Small, per-kind glyph used in section tab bars (leading icon) and the
/// empty-Claude placeholder. FR-26: Claude uses a wordmark-style "C"
/// badge; Terminal uses a `>_` prompt glyph.
struct SectionKindGlyph: View {
    let kind: SectionKind
    var size: CGFloat = 16

    var body: some View {
        switch kind {
        case .claude:
            Text("C")
                .font(.system(size: size * 0.75, weight: .bold, design: .rounded))
                .foregroundStyle(.orange)
                .frame(width: size, height: size)
                .background(
                    Circle()
                        .fill(Color.orange.opacity(0.15))
                )
                .accessibilityLabel("Claude section")
        case .terminal:
            Text(">_")
                .font(.system(size: size * 0.6, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
                .accessibilityLabel("Terminal section")
        }
    }
}
