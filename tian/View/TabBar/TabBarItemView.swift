import SwiftUI

struct TabBarItemView: View {
    @Bindable var tab: TabModel
    let isActive: Bool
    /// Compact pill (smaller height + tighter padding). Used by terminal
    /// section tab bars; Claude keeps the original full-size pill.
    var isCompact: Bool = false
    let namespace: Namespace.ID
    let onSelect: () -> Void
    let onClose: () -> Void
    let onCloseOthers: () -> Void
    let onCloseToRight: () -> Void

    @State private var isHovering = false
    @State private var isRenaming = false
    @State private var lastClickTime: Date?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Per-letter dwell time of the chasing brightness highlight on
    /// rainbow tab titles. Lowering it speeds up the chase.
    private static let rainbowLetterDwell: TimeInterval = 0.09

    /// 7-color cycle for the per-character rainbow tab title — hex
    /// palette tuned for readability on the dark tab-bar background.
    /// Cycle order: red → orange → yellow → green → blue → purple →
    /// pink, then wraps. RGB tuples (sRGB, 0…1) so the chase
    /// highlight can blend each color toward white without an HSB
    /// round-trip.
    private static let rainbowLetterPalette: [(r: Double, g: Double, b: Double)] = [
        (0.773, 0.306, 0.294),  // #C54E4B
        (0.953, 0.506, 0.325),  // #F38153
        (0.969, 0.733, 0.361),  // #F7BB5C
        (0.467, 0.663, 0.431),  // #77A96E
        (0.447, 0.600, 0.800),  // #7299CC
        (0.549, 0.451, 0.725),  // #8C73B9
        (0.753, 0.471, 0.667),  // #C078AA
    ]

    /// All Claude tabs observe busy state — the inactive rainbow
    /// text indicator needs it, not just the active aurora. Reading
    /// `PaneStatusManager.shared.sessionStates` subscribes the whole
    /// dictionary for change tracking; for typical tab counts (low
    /// single digits per space) the broader observation cost is
    /// acceptable.
    private var hasBusyPane: Bool {
        guard tab.sectionKind == .claude else { return false }
        return PaneStatusManager.shared.hasSessionState(.busy, in: tab)
    }

    /// True when this tab should render its title with per-character
    /// rainbow coloring. Under reduce-motion the rainbow stays but
    /// the chase highlight is suppressed — see the call site.
    private var showsRainbowText: Bool {
        !isRenaming && !isActive && hasBusyPane
    }

    /// Chase highlight blends the active letter's color toward white
    /// instead of scaling it up — preserves hue identity and avoids
    /// the HSB round-trip the user's hex palette would require.
    /// Pass `highlightIndex: -1` for the static (no-chase) variant.
    private func rainbowAttributedTitle(highlightIndex: Int) -> AttributedString {
        let chars = Array(tab.displayName)
        let highlightBlend = 0.35
        var attr = AttributedString()
        for (i, char) in chars.enumerated() {
            var piece = AttributedString(String(char))
            let (r, g, b) = Self.rainbowLetterPalette[i % Self.rainbowLetterPalette.count]
            if i == highlightIndex {
                piece.foregroundColor = Color(
                    red: r + (1.0 - r) * highlightBlend,
                    green: g + (1.0 - g) * highlightBlend,
                    blue: b + (1.0 - b) * highlightBlend
                )
            } else {
                piece.foregroundColor = Color(red: r, green: g, blue: b)
            }
            attr.append(piece)
        }
        return attr
    }

    var body: some View {
        tabContent
            .onHover { isHovering = $0 }
            .onTapGesture {
                let now = Date()
                if let last = lastClickTime, now.timeIntervalSince(last) < 0.3 {
                    lastClickTime = nil
                    isRenaming = true
                } else {
                    lastClickTime = now
                    onSelect()
                }
            }
            .draggable(TabDragItem(tabID: tab.id, sectionKind: tab.sectionKind))
            .contextMenu {
                Button("Rename") { isRenaming = true }
                Divider()
                Button("Close Tab", action: onClose)
                Button("Close Other Tabs", action: onCloseOthers)
                Button("Close Tabs to the Right", action: onCloseToRight)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(tab.displayName)
            .accessibilityValue(isActive ? "selected" : "not selected")
            .accessibilityHint("Double-tap to switch. Double-tap and hold to rename.")
    }

    @ViewBuilder
    private var tabContent: some View {
        let tint = tab.sectionKind.tint
        let showAurora = isActive && hasBusyPane
        let inner = HStack(spacing: 8) {
            if showsRainbowText {
                Group {
                    if reduceMotion {
                        Text(rainbowAttributedTitle(highlightIndex: -1))
                    } else {
                        TimelineView(.periodic(from: .now, by: Self.rainbowLetterDwell)) { context in
                            let count = max(tab.displayName.count, 1)
                            let step = Int(context.date.timeIntervalSinceReferenceDate / Self.rainbowLetterDwell)
                            let highlight = ((step % count) + count) % count
                            Text(rainbowAttributedTitle(highlightIndex: highlight))
                        }
                    }
                }
                .font(.system(size: 11.5, weight: .regular))
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                InlineRenameView(
                    text: tab.displayName,
                    isRenaming: $isRenaming,
                    onCommit: { tab.customName = $0 }
                )
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(isActive ? .primary : .secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if isActive || isHovering {
                Button(action: onClose) {
                    Text("\u{00D7}")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.secondary)
                        .opacity(isActive ? 0.9 : 0.5)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close tab \(tab.displayName)")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, isCompact ? 11 : 14)
        .frame(height: isCompact ? 24 : 30)
        .contentShape(Capsule())
        .overlay(
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            tint.opacity(0.22),
                            tint.opacity(0.06),
                            Color.clear,
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .opacity(isActive ? 1 : 0)
                .allowsHitTesting(false)
        )
        .overlay {
            if showAurora {
                AuroraCapsuleFill()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.45), value: showAurora)

        if isActive {
            inner
                .glassEffect(.regular.tint(tint.opacity(0.12)).interactive(), in: .capsule)
                .glassEffectID("activeTab", in: namespace)
        } else {
            inner
                .background {
                    Capsule()
                        .fill(Color.primary.opacity(isHovering ? 0.045 : 0.025))
                        .overlay(
                            Capsule()
                                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                        )
                }
        }
    }
}
