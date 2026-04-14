import SwiftUI

/// PR status badge showing #number and state indicator, tappable to open PR URL.
struct PRStatusIndicatorView: View {
    let prStatus: PRStatus

    private var label: String {
        switch prStatus.state {
        case .open, .merged: "#\(prStatus.number) \u{2713}"
        case .draft: "#\(prStatus.number) draft \u{2717}"
        case .closed: "#\(prStatus.number) \u{2717}"
        }
    }

    private var color: Color {
        switch prStatus.state {
        case .open, .merged: Color(red: 0.251, green: 0.651, blue: 0.349)
        case .draft, .closed: Color(red: 0.749, green: 0.302, blue: 0.302)
        }
    }

    var body: some View {
        Text(label)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.06))
            )
            .onTapGesture {
                NSWorkspace.shared.open(prStatus.url)
            }
            .accessibilityLabel("Pull request #\(prStatus.number) \(prStatus.state.rawValue)")
            .accessibilityHint("Tap to open in browser")
    }
}
