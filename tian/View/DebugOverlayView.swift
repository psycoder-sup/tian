import SwiftUI

/// Corner HUD displaying app-level performance metrics.
/// Toggled per-window via Cmd+Shift+P. Does not steal focus from the terminal.
struct DebugOverlayView: View {
    @State private var memoryRSS = ""
    @State private var refreshTimer: Timer?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("tian debug")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)

            Divider()

            LabeledMetric(label: "Init", value: formatted(AppMetrics.shared.ghosttyTotalInitMs))
            LabeledMetric(label: "Sfc avg", value: formatted(AppMetrics.shared.surfaceCreationAvgMs))
            LabeledMetric(label: "Sfc n", value: "\(AppMetrics.shared.surfaceCreationCount)")
            if AppMetrics.shared.restoreDurationMs > 0 {
                LabeledMetric(label: "Restore", value: "\(AppMetrics.shared.restoreDurationMs) ms")
            }
            LabeledMetric(label: "RSS", value: memoryRSS)
        }
        .padding(10)
        .frame(width: 180, alignment: .leading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        .allowsHitTesting(false)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Debug Overlay")
        .onAppear {
            updateMemory()
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
                Task { @MainActor in updateMemory() }
            }
        }
        .onDisappear {
            refreshTimer?.invalidate()
            refreshTimer = nil
        }
    }

    private func updateMemory() {
        memoryRSS = AppMetrics.shared.memoryRSSFormatted
    }

    private func formatted(_ ms: Double) -> String {
        String(format: "%.1f ms", ms)
    }
}

// MARK: - Labeled Metric Row

private struct LabeledMetric: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .leading)
            Text(value)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
        }
    }
}
