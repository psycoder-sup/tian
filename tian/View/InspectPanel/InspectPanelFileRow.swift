import SwiftUI

/// Single tree row in the inspect panel file browser (FR-12).
///
/// Rendering:
/// - 24 px tall, monospace 11.5 px
/// - Leading inset = 10 + 12 * depth
/// - Chevron for directories (rotated when expanded)
/// - Tinted icon per extension (FR-14)
/// - Entry name with ellipsis truncation
/// - Optional single-letter status badge (FR-19)
/// - Hover / selection backgrounds (FR-24 / FR-25)
struct InspectPanelFileRow: View {
    let node: FileTreeNode
    let depth: Int
    let isExpanded: Bool
    let isSelected: Bool
    let status: GitFileStatus?
    let onTap: () -> Void

    @State private var isHovering = false

    // MARK: - Constants

    private static let rowHeight: CGFloat = 24
    private static let baseIndent: CGFloat = 10
    private static let depthIndent: CGFloat = 12
    private static let fontSize: CGFloat = 11.5

    // MARK: - Badge colors (FR-19)

    private var badgeColor: Color? {
        guard let status else { return nil }
        return status.color
    }

    // MARK: - Icon tint (FR-14)

    private var iconTint: Color {
        switch node.kind {
        case .directory:
            return Color(red: 96/255, green: 165/255, blue: 250/255)
        case .file(let ext):
            switch ext?.lowercased() {
            case "ts", "tsx":
                return Color(red: 96/255, green: 165/255, blue: 250/255)   // blue
            case "js", "jsx", "json":
                return Color(red: 245/255, green: 158/255, blue: 11/255)   // amber/yellow
            case "sh":
                return Color(red: 110/255, green: 225/255, blue: 154/255)  // green
            case "env":
                return Color(red: 167/255, green: 139/255, blue: 250/255)  // violet
            default:
                return Color.secondary
            }
        }
    }

    private var iconName: String {
        switch node.kind {
        case .directory(let canRead):
            return canRead ? "folder.fill" : "folder.fill.badge.minus"
        case .file(let ext):
            switch ext?.lowercased() {
            case "swift":       return "swift"
            case "md":          return "doc.text.fill"
            case "json":        return "curlybraces"
            case "sh":          return "terminal.fill"
            case "env":         return "lock.fill"
            default:            return "doc.fill"
            }
        }
    }

    // MARK: - Directory accessibility indicator

    private var isUnreadableDirectory: Bool {
        if case .directory(let canRead) = node.kind { return !canRead }
        return false
    }

    // MARK: - Accessibility label (FR-36)

    private var accessibilityLabelText: String {
        guard let status else { return node.name }
        return "\(node.name), \(status.accessibilityLabel)"
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            // Indentation
            Color.clear
                .frame(width: Self.baseIndent + Self.depthIndent * CGFloat(depth))

            // Chevron (directories only)
            if node.isDirectory {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.4))
                    .rotationEffect(isExpanded ? .degrees(90) : .zero)
                    .animation(.easeInOut(duration: 0.15), value: isExpanded)
                    .frame(width: 12, alignment: .center)
            } else {
                Color.clear.frame(width: 12)
            }

            Spacing(3)

            // Icon
            Image(systemName: iconName)
                .font(.system(size: 10))
                .foregroundStyle(iconTint)
                .frame(width: 12, alignment: .center)

            Spacing(4)

            // Name (+ unreadable suffix)
            if isUnreadableDirectory {
                Text(node.name)
                    .font(.system(size: Self.fontSize, design: .monospaced))
                    .foregroundStyle(rowForeground)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(" (no access)")
                    .font(.system(size: Self.fontSize, design: .monospaced))
                    .foregroundStyle(Color.primary.opacity(0.25))
                    .lineLimit(1)
            } else {
                Text(node.name)
                    .font(.system(size: Self.fontSize, design: .monospaced))
                    .foregroundStyle(rowForeground)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 4)

            // Status badge (FR-19). Directories inherit the highest-severity
            // status of their descendants.
            if let status, let color = badgeColor {
                Text(status.letter)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(color)
                    .frame(width: 14, alignment: .center)
                    .padding(.trailing, 8)
            }
        }
        .frame(height: Self.rowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture { onTap() }
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityElement(children: .ignore)
    }

    // MARK: - Styling helpers

    private var rowBackground: Color {
        if isSelected {
            // FR-24: rgba(96,165,250,0.12)
            return Color(red: 96/255, green: 165/255, blue: 250/255).opacity(0.12)
        } else if isHovering {
            // FR-25: rgba(255,255,255,0.025)
            return Color.white.opacity(0.025)
        }
        return Color.clear
    }

    private var rowForeground: Color {
        if isSelected {
            // FR-24: rgba(240,244,252,0.98)
            return Color(red: 240/255, green: 244/255, blue: 252/255).opacity(0.98)
        }
        return Color.primary.opacity(0.8)
    }
}

// MARK: - Spacing helper

private struct Spacing: View {
    let width: CGFloat
    init(_ width: CGFloat) { self.width = width }
    var body: some View { Color.clear.frame(width: width) }
}

// MARK: - Previews

#Preview("File rows") {
    let fileNode = FileTreeNode(
        id: "/repo/src/main.ts",
        name: "main.ts",
        kind: .file(ext: "ts"),
        relativePath: "src/main.ts",
        depth: 1
    )
    let dirNode = FileTreeNode(
        id: "/repo/src",
        name: "src",
        kind: .directory(canRead: true),
        relativePath: "src",
        depth: 0
    )
    let unreadNode = FileTreeNode(
        id: "/repo/private",
        name: "private",
        kind: .directory(canRead: false),
        relativePath: "private",
        depth: 0
    )

    VStack(spacing: 0) {
        InspectPanelFileRow(
            node: dirNode,
            depth: 0,
            isExpanded: true,
            isSelected: false,
            status: nil,
            onTap: {}
        )
        InspectPanelFileRow(
            node: fileNode,
            depth: 1,
            isExpanded: false,
            isSelected: true,
            status: .modified,
            onTap: {}
        )
        InspectPanelFileRow(
            node: FileTreeNode(id: "/repo/src/app.tsx", name: "app.tsx", kind: .file(ext: "tsx"), relativePath: "src/app.tsx", depth: 1),
            depth: 1,
            isExpanded: false,
            isSelected: false,
            status: .added,
            onTap: {}
        )
        InspectPanelFileRow(
            node: FileTreeNode(id: "/repo/src/old.ts", name: "old.ts", kind: .file(ext: "ts"), relativePath: "src/old.ts", depth: 1),
            depth: 1,
            isExpanded: false,
            isSelected: false,
            status: .deleted,
            onTap: {}
        )
        InspectPanelFileRow(
            node: FileTreeNode(id: "/repo/src/moved.ts", name: "moved.ts", kind: .file(ext: "ts"), relativePath: "src/moved.ts", depth: 1),
            depth: 1,
            isExpanded: false,
            isSelected: false,
            status: .renamed,
            onTap: {}
        )
        InspectPanelFileRow(
            node: unreadNode,
            depth: 0,
            isExpanded: false,
            isSelected: false,
            status: nil,
            onTap: {}
        )
    }
    .frame(width: 320)
    .background(Color(red: 8/255, green: 11/255, blue: 18/255, opacity: 0.95))
}
