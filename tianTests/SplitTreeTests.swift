import Testing
import Foundation
@testable import tian

struct SplitTreeTests {
    // MARK: - Initialization

    @Test func singlePaneTree() {
        let id = UUID()
        let tree = SplitTree(paneID: id, workingDirectory: "/tmp")
        #expect(tree.root == .leaf(paneID: id, workingDirectory: "/tmp"))
        #expect(tree.leafCount == 1)
    }

    @Test func initialFocusIsTheOnlyPane() {
        let id = UUID()
        let tree = SplitTree(paneID: id, workingDirectory: "")
        #expect(tree.focusedPaneID == id)
    }

    // MARK: - Insert Split

    @Test func insertHorizontalSplit() {
        let original = UUID()
        var tree = SplitTree(paneID: original, workingDirectory: "/home")
        let newPane = UUID()

        let ok = tree.insertSplit(direction: .horizontal, newPaneID: newPane, newWorkingDirectory: "/home")
        #expect(ok)
        #expect(tree.leafCount == 2)

        if case .split(_, let dir, let ratio, let first, let second) = tree.root {
            #expect(dir == .horizontal)
            #expect(ratio == 0.5)
            #expect(first == .leaf(paneID: original, workingDirectory: "/home"))
            #expect(second == .leaf(paneID: newPane, workingDirectory: "/home"))
        } else {
            Issue.record("Expected root to be a split node")
        }
    }

    @Test func insertVerticalSplit() {
        let original = UUID()
        var tree = SplitTree(paneID: original, workingDirectory: "")
        let newPane = UUID()

        tree.insertSplit(direction: .vertical, newPaneID: newPane, newWorkingDirectory: "")

        if case .split(_, let dir, _, _, _) = tree.root {
            #expect(dir == .vertical)
        } else {
            Issue.record("Expected root to be a split node")
        }
    }

    @Test func insertSplitUpdatesFocus() {
        let original = UUID()
        var tree = SplitTree(paneID: original, workingDirectory: "")
        let newPane = UUID()

        tree.insertSplit(direction: .horizontal, newPaneID: newPane, newWorkingDirectory: "")
        #expect(tree.focusedPaneID == newPane)
    }

    @Test func insertSplitPreservesOriginalLeaf() {
        let original = UUID()
        var tree = SplitTree(paneID: original, workingDirectory: "/orig")
        let newPane = UUID()

        tree.insertSplit(direction: .horizontal, newPaneID: newPane, newWorkingDirectory: "/new")
        #expect(tree.findLeaf(paneID: original) != nil)
        #expect(tree.findLeaf(paneID: newPane) != nil)
    }

    @Test func nestedSplits() {
        let a = UUID()
        var tree = SplitTree(paneID: a, workingDirectory: "")
        let b = UUID()
        let c = UUID()

        // Split a -> a | b (focus on b)
        tree.insertSplit(direction: .horizontal, newPaneID: b, newWorkingDirectory: "")
        // Split b -> b / c (focus on c)
        tree.insertSplit(direction: .vertical, newPaneID: c, newWorkingDirectory: "")

        #expect(tree.leafCount == 3)
        #expect(tree.allLeaves() == [a, b, c])
    }

    @Test func splitFromNonRootFocusedPane() {
        let a = UUID()
        var tree = SplitTree(paneID: a, workingDirectory: "")
        let b = UUID()
        let c = UUID()

        // a | b, focus on b
        tree.insertSplit(direction: .horizontal, newPaneID: b, newWorkingDirectory: "")
        #expect(tree.focusedPaneID == b)

        // Split b vertically -> b / c, focus on c
        tree.insertSplit(direction: .vertical, newPaneID: c, newWorkingDirectory: "")
        #expect(tree.focusedPaneID == c)
        #expect(tree.leafCount == 3)

        // Verify structure: root is horizontal split with a on left, vertical split on right
        if case .split(_, .horizontal, _, let first, let second) = tree.root {
            #expect(first == .leaf(paneID: a, workingDirectory: ""))
            if case .split(_, .vertical, _, _, _) = second {
                // correct nested structure
            } else {
                Issue.record("Expected second child to be a vertical split")
            }
        } else {
            Issue.record("Expected root to be a horizontal split")
        }
    }

    // MARK: - Remove Leaf

    @Test func removeSecondLeafPromotesSibling() {
        let a = UUID()
        var tree = SplitTree(paneID: a, workingDirectory: "/home")
        let b = UUID()
        tree.insertSplit(direction: .horizontal, newPaneID: b, newWorkingDirectory: "/home")

        let result = tree.removeLeaf(paneID: b)

        #expect(result == .removed(newFocusID: a))
        #expect(tree.root == .leaf(paneID: a, workingDirectory: "/home"))
        #expect(tree.leafCount == 1)
    }

    @Test func removeFirstLeafPromotesSibling() {
        let a = UUID()
        var tree = SplitTree(paneID: a, workingDirectory: "")
        let b = UUID()
        tree.insertSplit(direction: .horizontal, newPaneID: b, newWorkingDirectory: "")

        // Focus back to a, then remove a
        tree.focusedPaneID = a
        let result = tree.removeLeaf(paneID: a)

        #expect(result == .removed(newFocusID: b))
        #expect(tree.root == .leaf(paneID: b, workingDirectory: ""))
    }

    @Test func removeLastPaneReturnsLastPane() {
        let a = UUID()
        var tree = SplitTree(paneID: a, workingDirectory: "")

        let result = tree.removeLeaf(paneID: a)
        #expect(result == .lastPane)
        // Tree should be unchanged
        #expect(tree.root == .leaf(paneID: a, workingDirectory: ""))
    }

    @Test func removePaneUpdatesFocusToSibling() {
        let a = UUID()
        var tree = SplitTree(paneID: a, workingDirectory: "")
        let b = UUID()
        tree.insertSplit(direction: .horizontal, newPaneID: b, newWorkingDirectory: "")
        #expect(tree.focusedPaneID == b)

        // Remove b (currently focused) -> focus should go to a
        let result = tree.removeLeaf(paneID: b)
        #expect(result == .removed(newFocusID: a))
        #expect(tree.focusedPaneID == a)
    }

    @Test func removeFromNestedTree() {
        let a = UUID()
        var tree = SplitTree(paneID: a, workingDirectory: "")
        let b = UUID()
        let c = UUID()

        // a | (b / c)
        tree.insertSplit(direction: .horizontal, newPaneID: b, newWorkingDirectory: "")
        tree.insertSplit(direction: .vertical, newPaneID: c, newWorkingDirectory: "")
        #expect(tree.leafCount == 3)

        // Remove b -> a | c
        tree.focusedPaneID = b
        let result = tree.removeLeaf(paneID: b)

        #expect(tree.leafCount == 2)
        #expect(tree.allLeaves().contains(a))
        #expect(tree.allLeaves().contains(c))
        #expect(!tree.allLeaves().contains(b))
        if case .removed = result {} else {
            Issue.record("Expected .removed result")
        }
    }

    @Test func removeNonExistentPaneReturnsNotFound() {
        let a = UUID()
        var tree = SplitTree(paneID: a, workingDirectory: "")
        let b = UUID()
        tree.insertSplit(direction: .horizontal, newPaneID: b, newWorkingDirectory: "")

        let treeBefore = tree
        let result = tree.removeLeaf(paneID: UUID())

        #expect(tree == treeBefore)
        #expect(result == .notFound)
    }

    // MARK: - Update Ratio

    @Test func updateRatio() {
        let a = UUID()
        var tree = SplitTree(paneID: a, workingDirectory: "")
        let b = UUID()
        tree.insertSplit(direction: .horizontal, newPaneID: b, newWorkingDirectory: "")

        // Get the split ID
        guard case .split(let splitID, _, _, _, _) = tree.root else {
            Issue.record("Expected split root")
            return
        }

        tree.updateRatio(splitID: splitID, newRatio: 0.7)

        if case .split(_, _, let ratio, _, _) = tree.root {
            #expect(ratio == 0.7)
        }
    }

    @Test func updateRatioClampsToMin() {
        let a = UUID()
        var tree = SplitTree(paneID: a, workingDirectory: "")
        let b = UUID()
        tree.insertSplit(direction: .horizontal, newPaneID: b, newWorkingDirectory: "")

        guard case .split(let splitID, _, _, _, _) = tree.root else { return }

        tree.updateRatio(splitID: splitID, newRatio: 0.01)

        if case .split(_, _, let ratio, _, _) = tree.root {
            #expect(ratio == 0.1)
        }
    }

    @Test func updateRatioClampsToMax() {
        let a = UUID()
        var tree = SplitTree(paneID: a, workingDirectory: "")
        let b = UUID()
        tree.insertSplit(direction: .horizontal, newPaneID: b, newWorkingDirectory: "")

        guard case .split(let splitID, _, _, _, _) = tree.root else { return }

        tree.updateRatio(splitID: splitID, newRatio: 0.99)

        if case .split(_, _, let ratio, _, _) = tree.root {
            #expect(ratio == 0.9)
        }
    }

    @Test func updateRatioNonExistentSplitIsNoOp() {
        let a = UUID()
        var tree = SplitTree(paneID: a, workingDirectory: "")
        let b = UUID()
        tree.insertSplit(direction: .horizontal, newPaneID: b, newWorkingDirectory: "")

        let treeBefore = tree
        tree.updateRatio(splitID: UUID(), newRatio: 0.7)
        #expect(tree == treeBefore)
    }

    // MARK: - Update Working Directory

    @Test func updateWorkingDirectoryUpdatesCorrectLeaf() {
        let a = UUID()
        var tree = SplitTree(paneID: a, workingDirectory: "~")
        let b = UUID()
        tree.insertSplit(direction: .horizontal, newPaneID: b, newWorkingDirectory: "~")

        tree.updateWorkingDirectory(paneID: a, newWorkingDirectory: "/tmp")

        #expect(tree.findLeaf(paneID: a) == .leaf(paneID: a, workingDirectory: "/tmp"))
        #expect(tree.findLeaf(paneID: b) == .leaf(paneID: b, workingDirectory: "~"))
    }

    @Test func updateWorkingDirectoryNoOpForNonExistentPane() {
        let a = UUID()
        var tree = SplitTree(paneID: a, workingDirectory: "/home")

        let treeBefore = tree
        tree.updateWorkingDirectory(paneID: UUID(), newWorkingDirectory: "/tmp")
        #expect(tree == treeBefore)
    }

    @Test func updateWorkingDirectoryPreservedAcrossSplit() {
        let a = UUID()
        var tree = SplitTree(paneID: a, workingDirectory: "~")

        // Update a's wd, then split from a
        tree.updateWorkingDirectory(paneID: a, newWorkingDirectory: "/var")
        tree.focusedPaneID = a
        let b = UUID()
        tree.insertSplit(direction: .horizontal, newPaneID: b, newWorkingDirectory: "/var")

        #expect(tree.findLeaf(paneID: a) == .leaf(paneID: a, workingDirectory: "/var"))
        #expect(tree.findLeaf(paneID: b) == .leaf(paneID: b, workingDirectory: "/var"))
    }

    // MARK: - Find Leaf

    @Test func findExistingLeaf() {
        let a = UUID()
        let tree = SplitTree(paneID: a, workingDirectory: "/home")
        let found = tree.findLeaf(paneID: a)
        #expect(found == .leaf(paneID: a, workingDirectory: "/home"))
    }

    @Test func findNonExistentLeafReturnsNil() {
        let a = UUID()
        let tree = SplitTree(paneID: a, workingDirectory: "")
        #expect(tree.findLeaf(paneID: UUID()) == nil)
    }

    // MARK: - Enumerate Leaves

    @Test func allLeavesOnSinglePane() {
        let a = UUID()
        let tree = SplitTree(paneID: a, workingDirectory: "")
        #expect(tree.allLeaves() == [a])
    }

    @Test func allLeavesOnSplitTree() {
        let a = UUID()
        var tree = SplitTree(paneID: a, workingDirectory: "")
        let b = UUID()
        tree.insertSplit(direction: .horizontal, newPaneID: b, newWorkingDirectory: "")

        let leaves = tree.allLeaves()
        #expect(leaves.count == 2)
        #expect(leaves.contains(a))
        #expect(leaves.contains(b))
    }

    @Test func allLeavesOrderIsDepthFirst() {
        let a = UUID()
        var tree = SplitTree(paneID: a, workingDirectory: "")
        let b = UUID()
        let c = UUID()
        let d = UUID()

        // Build: (a | b), focus on b, then split b -> (b / c), focus on c, then split c -> (c | d)
        tree.insertSplit(direction: .horizontal, newPaneID: b, newWorkingDirectory: "")
        tree.insertSplit(direction: .vertical, newPaneID: c, newWorkingDirectory: "")
        tree.insertSplit(direction: .horizontal, newPaneID: d, newWorkingDirectory: "")

        // Tree structure: a | ((b / (c | d)))
        // Depth-first left-to-right: a, b, c, d
        #expect(tree.allLeaves() == [a, b, c, d])
    }

    @Test func leafCountMatchesAllLeaves() {
        let a = UUID()
        var tree = SplitTree(paneID: a, workingDirectory: "")
        #expect(tree.leafCount == tree.allLeaves().count)

        let b = UUID()
        tree.insertSplit(direction: .horizontal, newPaneID: b, newWorkingDirectory: "")
        #expect(tree.leafCount == tree.allLeaves().count)

        let c = UUID()
        tree.insertSplit(direction: .vertical, newPaneID: c, newWorkingDirectory: "")
        #expect(tree.leafCount == tree.allLeaves().count)
    }
}
