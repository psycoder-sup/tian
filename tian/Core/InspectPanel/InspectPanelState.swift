import Foundation
import Observation
import SwiftUI

@MainActor @Observable
final class InspectPanelState {
    static let defaultWidth: CGFloat = 320
    static let minWidth: CGFloat = 240
    static let maxWidth: CGFloat = 480

    var isVisible: Bool
    var width: CGFloat

    init(isVisible: Bool = true, width: CGFloat = InspectPanelState.defaultWidth) {
        self.isVisible = isVisible
        self.width = min(max(width, Self.minWidth), Self.maxWidth)
    }

    func clampedWidth(_ proposed: CGFloat) -> CGFloat {
        min(max(proposed, Self.minWidth), Self.maxWidth)
    }
}
