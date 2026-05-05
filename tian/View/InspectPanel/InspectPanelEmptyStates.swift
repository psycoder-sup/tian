import SwiftUI

// MARK: - Empty state variants (FR-32, FR-34, FR-18, FR-18a)

/// Centered "Loading…" placeholder shown while the initial scan is in flight
/// and the slow-flag timer has not yet fired (FR-32).
struct InspectPanelLoadingView: View {
    var body: some View {
        Text("Loading…")
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(Color.primary.opacity(0.35))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Centered "Still loading…" placeholder shown after the 5-second slow-flag
/// fires while the initial scan is still in flight (FR-34).
struct InspectPanelSlowLoadingView: View {
    var body: some View {
        Text("Still loading…")
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(Color.primary.opacity(0.35))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Centered "Nothing to show." placeholder shown when the directory is
/// readable but has no non-ignored entries (FR-18a).
struct InspectPanelEmptyContentView: View {
    var body: some View {
        Text("Nothing to show.")
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(Color.primary.opacity(0.35))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Centered placeholder shown when the active space has no resolvable
/// working directory (FR-18).
struct InspectPanelNoDirectoryView: View {
    var body: some View {
        Text("No working directory for this space.")
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(Color.primary.opacity(0.35))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Previews

#Preview("Loading") {
    InspectPanelLoadingView()
        .frame(width: 320, height: 400)
        .background(Color(red: 8/255, green: 11/255, blue: 18/255, opacity: 0.95))
}

#Preview("Still loading") {
    InspectPanelSlowLoadingView()
        .frame(width: 320, height: 400)
        .background(Color(red: 8/255, green: 11/255, blue: 18/255, opacity: 0.95))
}

#Preview("Empty content") {
    InspectPanelEmptyContentView()
        .frame(width: 320, height: 400)
        .background(Color(red: 8/255, green: 11/255, blue: 18/255, opacity: 0.95))
}

#Preview("No directory") {
    InspectPanelNoDirectoryView()
        .frame(width: 320, height: 400)
        .background(Color(red: 8/255, green: 11/255, blue: 18/255, opacity: 0.95))
}
