import SwiftUI

/// Rainbow dot for the "busy" Claude session state — the same conic palette the
/// overview card's busy border spins, so the two read as one system.
///
/// Deliberately static. The animated version drove a `TimelineView`, and a
/// `TimelineView` costs far more than its tick rate suggests: SwiftUI re-walks
/// the whole window's view graph on *every* display cycle while one is alive,
/// not once per `minimumInterval`. With one dot per busy sidebar row that was
/// the app's single largest CPU draw (a full `NSHostingView.layout` pass at
/// ~60 Hz). The busy state is already unmistakable from the color.
struct BusyDotView: View {
    var body: some View {
        Circle()
            .fill(AngularGradient(colors: rainbowColors, center: .center))
            .frame(width: 8, height: 8)
    }
}
