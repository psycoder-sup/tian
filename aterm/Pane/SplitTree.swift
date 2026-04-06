import Foundation

/// Result of removing a leaf from the split tree.
enum RemoveResult: Sendable, Equatable {
    /// The leaf was removed and focus should move to the given pane.
    case removed(newFocusID: UUID)
    /// The tree had only one pane and it was the one being removed.
    case lastPane
    /// The pane ID was not found in the tree.
    case notFound
}

/// A split tree representing a pane layout within a single tab.
///
/// The tree is a value type — all mutations produce new values.
/// The owning view model holds a single `SplitTree` property and replaces it on every operation.
struct SplitTree: Sendable, Equatable {
    var root: PaneNode
    var focusedPaneID: UUID

    /// Create a tree with a single pane.
    init(paneID: UUID, workingDirectory: String) {
        self.root = .leaf(paneID: paneID, workingDirectory: workingDirectory)
        self.focusedPaneID = paneID
    }

    /// Restore a tree from a persisted root and focused pane ID.
    /// Falls back to the first leaf if `focusedPaneID` is not found in the tree.
    init(root: PaneNode, focusedPaneID: UUID) {
        self.root = root
        self.focusedPaneID = root.containsLeaf(paneID: focusedPaneID)
            ? focusedPaneID
            : root.firstLeaf()
    }
}

// MARK: - Query

extension SplitTree {
    /// Find a leaf node by pane ID.
    func findLeaf(paneID: UUID) -> PaneNode? {
        root.findLeaf(paneID: paneID)
    }

    /// All leaf pane IDs in depth-first, left-to-right order.
    func allLeaves() -> [UUID] {
        root.allLeaves()
    }

    /// The number of leaf panes in the tree.
    var leafCount: Int {
        root.leafCount
    }

    /// All leaf pane IDs with their working directories in depth-first order.
    func allLeafInfo() -> [(UUID, String)] {
        root.allLeafInfo()
    }
}

// MARK: - Mutation

extension SplitTree {
    /// Split the focused pane in the given direction.
    ///
    /// The original pane becomes the first child; the new pane becomes the second child.
    /// Focus moves to the new pane. Returns `true` on success.
    @discardableResult
    mutating func insertSplit(
        direction: SplitDirection,
        newPaneID: UUID,
        newWorkingDirectory: String
    ) -> Bool {
        guard let originalLeaf = root.findLeaf(paneID: focusedPaneID) else { return false }
        let newLeaf = PaneNode.leaf(paneID: newPaneID, workingDirectory: newWorkingDirectory)
        let splitNode = PaneNode.split(
            id: UUID(),
            direction: direction,
            ratio: 0.5,
            first: originalLeaf,
            second: newLeaf
        )

        root = root.replacingLeaf(paneID: focusedPaneID, with: splitNode)
        focusedPaneID = newPaneID
        return true
    }

    /// Remove a leaf pane from the tree, promoting its sibling.
    ///
    /// If the removed pane was focused, focus moves to the sibling's first leaf.
    /// Returns `.lastPane` if the tree has only one pane.
    mutating func removeLeaf(paneID: UUID) -> RemoveResult {
        // Single leaf — nothing to promote
        if case .leaf(let id, _) = root, id == paneID {
            return .lastPane
        }

        guard let newRoot = root.removingLeaf(paneID: paneID) else {
            return .lastPane
        }

        guard newRoot != root else {
            return .notFound
        }

        root = newRoot

        // Update focus if the removed pane was focused
        if focusedPaneID == paneID {
            focusedPaneID = root.firstLeaf()
        }

        return .removed(newFocusID: focusedPaneID)
    }

    /// Update the working directory of a leaf pane.
    mutating func updateWorkingDirectory(paneID: UUID, newWorkingDirectory: String) {
        root = root.updatingWorkingDirectory(paneID: paneID, newWorkingDirectory: newWorkingDirectory)
    }

    /// Update the ratio of a split node, clamped to 0.1...0.9.
    mutating func updateRatio(splitID: UUID, newRatio: Double) {
        let clamped = min(max(newRatio, 0.1), 0.9)
        root = root.updatingRatio(splitID: splitID, newRatio: clamped)
    }
}
