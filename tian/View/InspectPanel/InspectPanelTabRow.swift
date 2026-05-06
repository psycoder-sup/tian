import SwiftUI

/// 38 px tab row for the Inspect panel header (FR-T01 / FR-T02 / FR-T03).
///
/// Layout (left → right):
///   - Capsule segmented control: Files / Diff / Branch — FR-T02
///   - Trailing hide button (sidebar.right icon) — FR-T03
///
/// During initial scan (`isInitialScan == true`), Diff and Branch pills are
/// muted and non-interactive (FR-T16a).
///
/// Accessibility (FR-T32):
///   - Container: `.accessibilityElement(children: .contain)`
///   - Each button: `.accessibilityLabel("Files" | "Diff" | "Branch")` +
///     `.accessibilityAddTraits(.isSelected)` when active.
struct InspectPanelTabRow: View {
    static let height: CGFloat = 38

    @Bindable var tabState: InspectTabState
    /// When `true`, Diff and Branch tabs are muted and non-interactive (FR-T16a).
    let isInitialScan: Bool
    /// Fires when the user taps the in-row hide button (FR-T03). The floating
    /// `InspectPanelRail` handles the re-open case.
    let onHide: () -> Void

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            tabCapsule
                .padding(.leading, 10)

            Spacer(minLength: 8)

            hideButton
                .padding(.trailing, 10)
        }
        .frame(height: Self.height)
        .background(
            Color(red: 8/255, green: 11/255, blue: 18/255).opacity(0.4)
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.05))
                .frame(height: 0.5)
        }
    }

    // MARK: - Capsule

    /// Three-pill segmented control (Files / Diff / Branch).
    private var tabCapsule: some View {
        HStack(spacing: 2) {
            tabButton(.files, label: "Files")
            tabButton(.diff,   label: "Diff")
            tabButton(.branch, label: "Branch")
        }
        .padding(3)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.04))
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
                )
        )
        .accessibilityElement(children: .contain)
    }

    // MARK: - Individual tab button

    @ViewBuilder
    private func tabButton(_ tab: InspectTab, label: String) -> some View {
        let isActive   = tabState.activeTab == tab
        let isDisabled = isInitialScan && (tab == .diff || tab == .branch)

        Button {
            if !isDisabled {
                tabState.activeTab = tab
            }
        } label: {
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(
                    isActive
                        ? Color.primary.opacity(0.9)
                        : Color.primary.opacity(isDisabled ? 0.2 : 0.4)
                )
                .padding(.horizontal, 9)
                .frame(height: 22)
                .background {
                    if isActive {
                        activeTabBackground
                    }
                }
        }
        .buttonStyle(.plain)
        .allowsHitTesting(!isDisabled)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isActive ? [.isSelected, .isButton] : .isButton)
    }

    /// Glass-gradient background for the active tab pill (FR-T02).
    private var activeTabBackground: some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.10),
                        Color.white.opacity(0.04)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                Capsule()
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
            )
    }

    // MARK: - Hide button

    private var hideButton: some View {
        Button(action: onHide) {
            Image(systemName: "sidebar.right")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Hide inspect panel")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Previews

#Preview("Tab row – files active") {
    let state = InspectTabState()
    InspectPanelTabRow(tabState: state, isInitialScan: false, onHide: {})
        .frame(width: 320)
        .background(Color(red: 8/255, green: 11/255, blue: 18/255, opacity: 0.95))
}

#Preview("Tab row – diff active") {
    let state = InspectTabState(activeTab: .diff)
    InspectPanelTabRow(tabState: state, isInitialScan: false, onHide: {})
        .frame(width: 320)
        .background(Color(red: 8/255, green: 11/255, blue: 18/255, opacity: 0.95))
}

#Preview("Tab row – initial scan (diff+branch muted)") {
    let state = InspectTabState()
    InspectPanelTabRow(tabState: state, isInitialScan: true, onHide: {})
        .frame(width: 320)
        .background(Color(red: 8/255, green: 11/255, blue: 18/255, opacity: 0.95))
}
