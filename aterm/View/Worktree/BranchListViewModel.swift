// aterm/View/Worktree/BranchListViewModel.swift
import Foundation
import Observation

struct BranchRow: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let badge: Badge
    let committerDate: Date
    let relativeDate: String
    let isInUse: Bool
    let isCurrent: Bool
    let remoteRef: String?    // non-nil only for remote-only rows

    enum Badge: Hashable, Sendable {
        case local
        case origin(String)           // e.g. "origin"
        case localAndOrigin(String)   // branch exists locally AND at remote
    }
}

@MainActor
@Observable
final class BranchListViewModel {
    enum Mode { case newBranch, existingBranch }
    enum Direction { case up, down }

    var query: String = "" {
        didSet { recomputeRows() }
    }
    var mode: Mode = .newBranch

    private(set) var rows: [BranchRow] = []
    private(set) var highlightedID: String?
    private(set) var isFetching: Bool = false
    private(set) var loadError: String?
    private(set) var usedCachedRemotes: Bool = false

    private var rawEntries: [BranchEntry] = []
    private let service: any BranchListProviding

    init(service: any BranchListProviding = BranchListServiceAdapter()) {
        self.service = service
    }

    func load(repoRoot: String) async {
        usedCachedRemotes = false
        // Step 1: cache-only read (fast path)
        do {
            rawEntries = try await service.listBranches(repoRoot: repoRoot)
            loadError = nil
        } catch {
            rawEntries = []
            loadError = error.localizedDescription
        }
        recomputeRows()

        // Step 2: background fetch, refresh list when it finishes
        isFetching = true
        defer { isFetching = false }
        do {
            try await service.fetchRemotes(repoRoot: repoRoot)
            usedCachedRemotes = false
            do {
                rawEntries = try await service.listBranches(repoRoot: repoRoot)
                loadError = nil   // step-2 success clears any stale error from step 1
                recomputeRows()
            } catch {
                // keep previously-loaded rows; surface the error
                loadError = error.localizedDescription
            }
        } catch {
            usedCachedRemotes = true
            // silent fallback — cached rows already displayed
        }
    }

    func moveHighlight(_ direction: Direction) {
        let selectable = rows.filter { !$0.isInUse }
        guard !selectable.isEmpty else { highlightedID = nil; return }

        if let current = highlightedID,
           let idx = selectable.firstIndex(where: { $0.id == current }) {
            let nextIdx: Int
            switch direction {
            case .down: nextIdx = (idx + 1) % selectable.count
            case .up:   nextIdx = (idx - 1 + selectable.count) % selectable.count
            }
            highlightedID = selectable[nextIdx].id
        } else {
            highlightedID = selectable.first?.id
        }
    }

    func selectedRow() -> BranchRow? {
        guard let id = highlightedID else { return nil }
        return rows.first { $0.id == id && !$0.isInUse }
    }

    func collision(for query: String) -> BranchRow? {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return nil }
        return rows.first { $0.displayName == q }
    }

    private func recomputeRows() {
        let deduped = Self.dedup(rawEntries)
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered: [BranchRow]
        if q.isEmpty {
            filtered = deduped
        } else {
            filtered = deduped.filter { $0.displayName.lowercased().contains(q) }
        }
        rows = filtered
        // Re-anchor highlight on the first selectable row in the new filtered list.
        if let first = filtered.first(where: { !$0.isInUse }) {
            highlightedID = first.id
        } else {
            highlightedID = nil
        }
    }

    // MARK: - Dedup (implemented below)

    static func dedup(_ entries: [BranchEntry]) -> [BranchRow] {
        // Sort input by committerDate desc first so local wins when picking a representative.
        let sorted = entries.sorted { $0.committerDate > $1.committerDate }

        var localsByName: [String: BranchEntry] = [:]
        var remotesByName: [String: [BranchEntry]] = [:]   // name -> [remote entries]

        for e in sorted {
            switch e.kind {
            case .local:
                localsByName[e.displayName] = e
            case .remote:
                remotesByName[e.displayName, default: []].append(e)
            }
        }

        // Build rows. Walk sorted entries so date order is preserved; skip duplicates.
        var seen: Set<String> = []
        var out: [BranchRow] = []
        for e in sorted {
            if seen.contains(e.displayName) { continue }
            seen.insert(e.displayName)

            if let local = localsByName[e.displayName] {
                let remotes = remotesByName[e.displayName] ?? []
                let badge: BranchRow.Badge
                if let firstRemote = remotes.first {
                    badge = .localAndOrigin(firstRemote.kind.remoteName)
                } else {
                    badge = .local
                }
                out.append(
                    BranchRow(
                        id: local.id,
                        displayName: local.displayName,
                        badge: badge,
                        committerDate: local.committerDate,
                        relativeDate: formatRelative(local.committerDate),
                        isInUse: local.isInUse,
                        isCurrent: local.isCurrent,
                        remoteRef: nil
                    )
                )
            } else if let remote = remotesByName[e.displayName]?.first {
                let remoteName = remote.kind.remoteName
                out.append(
                    BranchRow(
                        id: remote.id,
                        displayName: remote.displayName,
                        badge: .origin(remoteName),
                        committerDate: remote.committerDate,
                        relativeDate: formatRelative(remote.committerDate),
                        isInUse: false,
                        isCurrent: false,
                        remoteRef: "\(remoteName)/\(remote.displayName)"
                    )
                )
            }
        }
        return out
    }

    static func formatRelative(_ date: Date, now: Date = Date()) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m ago" }
        if seconds < 86_400 { return "\(Int(seconds / 3600))h ago" }
        if seconds < 86_400 * 2 { return "yesterday" }
        if seconds < 86_400 * 7 { return "\(Int(seconds / 86_400))d ago" }
        if seconds < 86_400 * 30 { return "\(Int(seconds / 86_400 / 7))w ago" }
        return "\(Int(seconds / 86_400 / 30))mo ago"
    }
}

private extension BranchEntry.Kind {
    /// Returns the remote name. Traps if called on a `.local` case —
    /// callers must guarantee they only pass remote kinds.
    var remoteName: String {
        switch self {
        case .remote(let name): return name
        case .local: preconditionFailure("remoteName called on .local kind")
        }
    }
}
