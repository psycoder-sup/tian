import CoreGraphics
import Foundation

/// Cardinal direction for focus navigation between panes.
enum NavigationDirection: Sendable {
    case left, right, up, down
}

/// Spatial navigation algorithm for finding the nearest pane in a given direction.
///
/// Uses concrete pane frames (from `SplitLayout`) rather than tree traversal,
/// so it works correctly for any tree shape.
enum SplitNavigation {
    /// Find the nearest neighbor pane in the given direction from the focused pane.
    ///
    /// Returns `nil` if there is no neighbor in that direction, the focused pane
    /// is not found, or there is only one pane.
    static func neighbor(
        of focusedPaneID: UUID,
        direction: NavigationDirection,
        in paneFrames: [UUID: CGRect]
    ) -> UUID? {
        guard paneFrames.count > 1,
              let focusedFrame = paneFrames[focusedPaneID] else { return nil }

        // Filter candidates that are in the requested direction
        let candidates = paneFrames.filter { id, frame in
            guard id != focusedPaneID else { return false }
            switch direction {
            case .left:  return frame.maxX <= focusedFrame.minX + 1
            case .right: return frame.minX >= focusedFrame.maxX - 1
            case .up:    return frame.maxY <= focusedFrame.minY + 1
            case .down:  return frame.minY >= focusedFrame.maxY - 1
            }
        }

        guard !candidates.isEmpty else { return nil }

        // Pick the nearest candidate by edge-center distance,
        // breaking ties by perpendicular overlap.
        return candidates.min(by: { a, b in
            let distA = edgeDistanceSquared(from: focusedFrame, to: a.value, direction: direction)
            let distB = edgeDistanceSquared(from: focusedFrame, to: b.value, direction: direction)
            if abs(distA - distB) > 0.5 {
                return distA < distB
            }
            // Tie-break: prefer the candidate with more perpendicular overlap
            let overlapA = perpendicularOverlap(focusedFrame, a.value, direction: direction)
            let overlapB = perpendicularOverlap(focusedFrame, b.value, direction: direction)
            return overlapA > overlapB
        })?.key
    }

    // MARK: - Private

    /// Squared distance from the center of the focused pane's relevant edge
    /// to the center of the candidate's opposite edge. Squared avoids sqrt
    /// since we only need relative ordering.
    private static func edgeDistanceSquared(
        from focused: CGRect,
        to candidate: CGRect,
        direction: NavigationDirection
    ) -> CGFloat {
        let fromPoint: CGPoint
        let toPoint: CGPoint

        switch direction {
        case .right:
            fromPoint = CGPoint(x: focused.maxX, y: focused.midY)
            toPoint = CGPoint(x: candidate.minX, y: candidate.midY)
        case .left:
            fromPoint = CGPoint(x: focused.minX, y: focused.midY)
            toPoint = CGPoint(x: candidate.maxX, y: candidate.midY)
        case .down:
            fromPoint = CGPoint(x: focused.midX, y: focused.maxY)
            toPoint = CGPoint(x: candidate.midX, y: candidate.minY)
        case .up:
            fromPoint = CGPoint(x: focused.midX, y: focused.minY)
            toPoint = CGPoint(x: candidate.midX, y: candidate.maxY)
        }

        let dx = toPoint.x - fromPoint.x
        let dy = toPoint.y - fromPoint.y
        return dx * dx + dy * dy
    }

    /// Length of overlap on the axis perpendicular to the navigation direction.
    private static func perpendicularOverlap(
        _ a: CGRect,
        _ b: CGRect,
        direction: NavigationDirection
    ) -> CGFloat {
        switch direction {
        case .left, .right:
            // Overlap on Y axis
            let overlapStart = max(a.minY, b.minY)
            let overlapEnd = min(a.maxY, b.maxY)
            return max(overlapEnd - overlapStart, 0)
        case .up, .down:
            // Overlap on X axis
            let overlapStart = max(a.minX, b.minX)
            let overlapEnd = min(a.maxX, b.maxX)
            return max(overlapEnd - overlapStart, 0)
        }
    }
}
