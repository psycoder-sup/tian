import SwiftUI

enum SidebarFocusTarget {
    case terminal
    case sidebar
}

enum SidebarMode {
    case expanded
    case collapsed

    var width: CGFloat {
        switch self {
        case .expanded: 284
        case .collapsed: 0
        }
    }
}

@MainActor @Observable
final class SidebarState {
    var mode: SidebarMode = .expanded
    var isAnimating = false
    var focusTarget: SidebarFocusTarget = .terminal

    var isExpanded: Bool { mode == .expanded }

    func toggle() {
        guard !isAnimating else { return }
        isAnimating = true
        withAnimation(.easeInOut(duration: 0.2)) {
            mode = (mode == .expanded) ? .collapsed : .expanded
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in
            self?.isAnimating = false
        }
    }
}
