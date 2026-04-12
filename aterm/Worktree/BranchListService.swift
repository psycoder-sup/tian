// aterm/Worktree/BranchListService.swift
import Foundation
import os

struct BranchEntry: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let kind: Kind
    let committerDate: Date
    let isInUse: Bool
    let isCurrent: Bool

    enum Kind: Hashable, Sendable {
        case local(upstream: String?)
        case remote(remoteName: String)
    }
}

enum BranchListService {

    // MARK: - Public API

    static func listBranches(repoRoot: String) async throws -> [BranchEntry] {
        let inUse = try await loadInUseBranchSet(repoRoot: repoRoot)
        let currentPerWorktree = try await loadCurrentHeads(repoRoot: repoRoot)

        // format: <refname>%00<upstream>%00<committerdate:iso-strict>
        let format = "%(refname)%00%(upstream)%00%(committerdate:iso-strict)"
        let result = try await runGit(
            [
                "for-each-ref",
                "--sort=-committerdate",
                "--format=\(format)",
                "refs/heads",
                "refs/remotes",
            ],
            workingDirectory: repoRoot
        )
        guard result.exitCode == 0 else {
            throw WorktreeError.gitError(
                command: "git for-each-ref", stderr: result.stderr
            )
        }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoNoFrac = ISO8601DateFormatter()
        isoNoFrac.formatOptions = [.withInternetDateTime]

        var entries: [BranchEntry] = []
        for line in result.stdout.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.split(separator: "\0", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 3 else { continue }
            let refname = parts[0]
            let upstream = parts[1].isEmpty ? nil : parts[1]
            let dateStr = parts[2]
            let committerDate = iso.date(from: dateStr) ?? isoNoFrac.date(from: dateStr) ?? .distantPast

            if refname.hasPrefix("refs/heads/") {
                let name = String(refname.dropFirst("refs/heads/".count))
                let upstreamDisplay = upstream.map {
                    $0.hasPrefix("refs/remotes/") ? String($0.dropFirst("refs/remotes/".count)) : $0
                }
                entries.append(
                    BranchEntry(
                        id: "local:\(name)",
                        displayName: name,
                        kind: .local(upstream: upstreamDisplay),
                        committerDate: committerDate,
                        isInUse: inUse.contains(name),
                        isCurrent: currentPerWorktree.contains(name)
                    )
                )
            } else if refname.hasPrefix("refs/remotes/") {
                let trimmed = String(refname.dropFirst("refs/remotes/".count))
                if trimmed.hasSuffix("/HEAD") { continue }
                guard let slash = trimmed.firstIndex(of: "/") else { continue }
                let remoteName = String(trimmed[..<slash])
                let branchName = String(trimmed[trimmed.index(after: slash)...])
                entries.append(
                    BranchEntry(
                        id: "\(remoteName):\(branchName)",
                        displayName: branchName,
                        kind: .remote(remoteName: remoteName),
                        committerDate: committerDate,
                        isInUse: false,
                        isCurrent: false
                    )
                )
            }
        }
        return entries
    }

    // MARK: - Internals

    private static func loadInUseBranchSet(repoRoot: String) async throws -> Set<String> {
        let result = try await runGit(
            ["worktree", "list", "--porcelain"], workingDirectory: repoRoot
        )
        guard result.exitCode == 0 else {
            throw WorktreeError.gitError(
                command: "git worktree list --porcelain", stderr: result.stderr
            )
        }
        var set: Set<String> = []
        for line in result.stdout.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("branch ") {
                let full = String(line.dropFirst("branch ".count))
                if full.hasPrefix("refs/heads/") {
                    set.insert(String(full.dropFirst("refs/heads/".count)))
                }
            }
        }
        return set
    }

    private static func loadCurrentHeads(repoRoot: String) async throws -> Set<String> {
        // Same source as loadInUseBranchSet — every non-bare worktree's HEAD is its "current" branch.
        return try await loadInUseBranchSet(repoRoot: repoRoot)
    }

    private static func runGit(
        _ arguments: [String],
        workingDirectory: String
    ) async throws -> (exitCode: Int32, stdout: String, stderr: String) {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(filePath: "/usr/bin/git")
                process.arguments = arguments
                process.currentDirectoryURL = URL(filePath: workingDirectory)
                let stdout = Pipe()
                let stderr = Pipe()
                process.standardOutput = stdout
                process.standardError = stderr
                do {
                    try process.run()
                    process.waitUntilExit()
                    let outData = stdout.fileHandleForReading.readDataToEndOfFile()
                    let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                    continuation.resume(returning: (
                        process.terminationStatus,
                        String(data: outData, encoding: .utf8) ?? "",
                        String(data: errData, encoding: .utf8) ?? ""
                    ))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
