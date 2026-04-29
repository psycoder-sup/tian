import SwiftUI

/// Bottom status bar with right-aligned CPU and RAM cells. Renders behind
/// the sidebar layer; the sidebar visually covers the bar on the left.
struct StatusBarView: View {
    /// Height of the bar in points. Exposed so the sidebar layer can pad its
    /// content area by the same amount.
    static let height: CGFloat = 26

    private static let bytesPerGB: Double = 1_073_741_824

    private let monitor = SystemMonitor.shared

    var body: some View {
        let s = monitor.snapshot
        return HStack(spacing: 0) {
            Spacer(minLength: 0)
            cell(label: "CPU", load: s.cpu, history: s.cpuHistory) {
                Text(percentString(s.cpu))
                    .frame(minWidth: 26, alignment: .trailing)
            }
            cell(label: "RAM", load: s.ram, history: s.ramHistory) {
                Text(ramString(used: s.ramUsedBytes, total: monitor.ramTotalBytes))
                    .frame(minWidth: 50, alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
        .background(Color(nsColor: .terminalBackground))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.separator)
                .frame(height: 0.5)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("status-bar")
        .accessibilityLabel("System monitor")
        .onAppear { monitor.start() }
    }

    @ViewBuilder
    private func cell<Value: View>(
        label: String,
        load: Double,
        history: [Double],
        @ViewBuilder value: () -> Value
    ) -> some View {
        let tint = StatusBarPalette.loadColor(load)
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(0.4)
                .foregroundStyle(.secondary)
            SparklineView(data: history, color: tint)
            value()
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 10)
        .frame(maxHeight: .infinity)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(.separator.opacity(0.5))
                .frame(width: 0.5)
        }
        .accessibilityElement(children: .combine)
    }

    private func percentString(_ load: Double) -> String {
        "\(Int((load * 100).rounded()))%"
    }

    private func ramString(used: UInt64, total: UInt64) -> String {
        let usedGB = Double(used) / Self.bytesPerGB
        let totalGB = Double(total) / Self.bytesPerGB
        return String(format: "%.1f/%.0fG", usedGB, totalGB)
    }
}

private enum StatusBarPalette {
    /// Tier colors are signal colors — they should read the same regardless
    /// of light/dark appearance, so they're explicit RGB rather than
    /// semantic.
    static func loadColor(_ value: Double) -> Color {
        if value >= 0.85 { return Color(red: 1.0, green: 154 / 255, blue: 154 / 255) }
        if value >= 0.65 { return Color(red: 245 / 255, green: 201 / 255, blue: 105 / 255) }
        if value >= 0.35 { return Color(red: 110 / 255, green: 225 / 255, blue: 154 / 255) }
        return Color.secondary
    }
}
