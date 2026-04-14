import Foundation

/// Direction of a split.
enum SplitDirection: Sendable, Equatable, Hashable {
    /// Left/right split (vertical divider line separates them).
    case horizontal
    /// Top/bottom split (horizontal divider line separates them).
    case vertical
}

/// A node in the binary split tree.
///
/// Leaf nodes represent terminal panes; split nodes divide space between two children.
/// Uses value semantics — all mutations produce new values.
indirect enum PaneNode: Sendable, Equatable {
    case leaf(paneID: UUID, workingDirectory: String)
    case split(id: UUID, direction: SplitDirection, ratio: Double,
               first: PaneNode, second: PaneNode)
}

// MARK: - Query Operations

extension PaneNode {
    /// Find a leaf node by pane ID.
    func findLeaf(paneID: UUID) -> PaneNode? {
        switch self {
        case .leaf(let id, _):
            return id == paneID ? self : nil
        case .split(_, _, _, let first, let second):
            return first.findLeaf(paneID: paneID) ?? second.findLeaf(paneID: paneID)
        }
    }

    /// Whether this subtree contains a leaf with the given pane ID.
    func containsLeaf(paneID: UUID) -> Bool {
        findLeaf(paneID: paneID) != nil
    }

    /// All leaf pane IDs in depth-first, left-to-right order.
    func allLeaves() -> [UUID] {
        var result: [UUID] = []
        collectLeaves(into: &result)
        return result
    }

    private func collectLeaves(into result: inout [UUID]) {
        switch self {
        case .leaf(let id, _):
            result.append(id)
        case .split(_, _, _, let first, let second):
            first.collectLeaves(into: &result)
            second.collectLeaves(into: &result)
        }
    }

    /// All leaf pane IDs with their working directories in depth-first order.
    func allLeafInfo() -> [(UUID, String)] {
        var result: [(UUID, String)] = []
        collectLeafInfo(into: &result)
        return result
    }

    private func collectLeafInfo(into result: inout [(UUID, String)]) {
        switch self {
        case .leaf(let id, let wd):
            result.append((id, wd))
        case .split(_, _, _, let first, let second):
            first.collectLeafInfo(into: &result)
            second.collectLeafInfo(into: &result)
        }
    }

    /// The number of leaf panes in this subtree.
    var leafCount: Int {
        switch self {
        case .leaf:
            return 1
        case .split(_, _, _, let first, let second):
            return first.leafCount + second.leafCount
        }
    }

    /// The first (leftmost/topmost) leaf pane ID.
    func firstLeaf() -> UUID {
        switch self {
        case .leaf(let id, _):
            return id
        case .split(_, _, _, let first, _):
            return first.firstLeaf()
        }
    }

    /// Finds the ID of the split node that directly contains a leaf with the given pane ID.
    /// Used after `splitPane()` to locate the newly created split for ratio updates.
    func findDirectParentSplitID(of paneID: UUID) -> UUID? {
        switch self {
        case .leaf:
            return nil
        case .split(let id, _, _, let first, let second):
            if case .leaf(let leafID, _) = first, leafID == paneID { return id }
            if case .leaf(let leafID, _) = second, leafID == paneID { return id }
            return first.findDirectParentSplitID(of: paneID)
                ?? second.findDirectParentSplitID(of: paneID)
        }
    }
}

// MARK: - Tree Transformation

extension PaneNode {
    /// Returns a new tree where the leaf matching `paneID` is replaced by `replacement`.
    /// If no matching leaf is found, returns self unchanged.
    func replacingLeaf(paneID: UUID, with replacement: PaneNode) -> PaneNode {
        switch self {
        case .leaf(let id, _):
            return id == paneID ? replacement : self
        case .split(let id, let direction, let ratio, let first, let second):
            return .split(
                id: id,
                direction: direction,
                ratio: ratio,
                first: first.replacingLeaf(paneID: paneID, with: replacement),
                second: second.replacingLeaf(paneID: paneID, with: replacement)
            )
        }
    }

    /// Returns a new tree with the leaf removed and its sibling promoted.
    /// Returns `nil` if this node itself is the leaf being removed (caller handles last-pane case).
    func removingLeaf(paneID: UUID) -> PaneNode? {
        switch self {
        case .leaf(let id, _):
            return id == paneID ? nil : self
        case .split(let id, let direction, let ratio, let first, let second):
            // Check if either direct child is the target leaf
            if case .leaf(let leafID, _) = first, leafID == paneID {
                return second
            }
            if case .leaf(let leafID, _) = second, leafID == paneID {
                return first
            }
            // Recurse into children — try first, then second
            if let newFirst = first.removingLeaf(paneID: paneID), newFirst != first {
                return .split(id: id, direction: direction, ratio: ratio,
                              first: newFirst, second: second)
            }
            if let newSecond = second.removingLeaf(paneID: paneID), newSecond != second {
                return .split(id: id, direction: direction, ratio: ratio,
                              first: first, second: newSecond)
            }
            return self
        }
    }

    /// Returns a new tree with the leaf's working directory updated.
    func updatingWorkingDirectory(paneID: UUID, newWorkingDirectory: String) -> PaneNode {
        switch self {
        case .leaf(let id, _):
            return id == paneID ? .leaf(paneID: id, workingDirectory: newWorkingDirectory) : self
        case .split(let id, let direction, let ratio, let first, let second):
            return .split(
                id: id, direction: direction, ratio: ratio,
                first: first.updatingWorkingDirectory(paneID: paneID, newWorkingDirectory: newWorkingDirectory),
                second: second.updatingWorkingDirectory(paneID: paneID, newWorkingDirectory: newWorkingDirectory)
            )
        }
    }

    /// Returns a new tree with the split node's ratio updated.
    func updatingRatio(splitID: UUID, newRatio: Double) -> PaneNode {
        switch self {
        case .leaf:
            return self
        case .split(let id, let direction, let ratio, let first, let second):
            if id == splitID {
                return .split(id: id, direction: direction, ratio: newRatio,
                              first: first, second: second)
            }
            return .split(
                id: id, direction: direction, ratio: ratio,
                first: first.updatingRatio(splitID: splitID, newRatio: newRatio),
                second: second.updatingRatio(splitID: splitID, newRatio: newRatio)
            )
        }
    }
}

