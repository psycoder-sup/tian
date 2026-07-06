import Foundation

/// One outstanding piece of background work reported by a Claude Code pane — a
/// launched subagent or a `run_in_background` bash command that is still running
/// after the foreground turn has gone quiet.
///
/// Ephemeral and value-typed: instances live only in `PaneStatusManager` (and its
/// per-PVM mirror) for the lifetime of the work and are never persisted. Their
/// presence floors a session's `aggregateClaudeState` to `.busy` so the sidebar
/// dot keeps reflecting in-flight work instead of reading `idle`.
struct BackgroundActivity: Identifiable, Equatable, Codable, Sendable {
    /// Whether the work is a subagent, a backgrounded bash command, or something
    /// else Claude reported.
    enum Kind: String, Codable, Sendable {
        case agent
        case bash
        case other

        /// SF Symbol name for this kind, shared by every view that renders a
        /// background-activity glyph (the sidebar badge and the overview list) so
        /// the `kind → symbol` mapping lives in exactly one place.
        var systemName: String {
            switch self {
            case .agent: "person.2.fill"
            case .bash: "terminal"
            case .other: "bolt.horizontal.circle"
            }
        }
    }

    /// Claude's `task_id` / `agent_id`. Stable for the life of the work, so it
    /// serves as the `Identifiable` key and the per-snapshot dedupe key.
    let id: String

    /// What kind of background work this is.
    var kind: Kind

    /// Human-readable label — the subagent type, the task description, or the
    /// command, whichever Claude provided.
    var label: String

    /// Optional status string as reported by Claude (e.g. "running").
    var status: String?

    /// Wall-clock time this activity was last observed in a Claude snapshot.
    /// Stamped to "now" whenever an activity is decoded/synced (`fromClaudeSnapshot`).
    /// Drives `isStale`: once Claude goes idle and stops syncing, the last
    /// snapshot's entries age out after `stalenessTTL`, so a background command
    /// that quietly finished during an idle session no longer pins it busy.
    /// Transient freshness metadata — deliberately excluded from `==`.
    var lastSeen: Date = Date()

    /// How long an un-refreshed activity stays "live" before it reads as stale.
    /// Claude only reports `background_tasks` on Stop/SubagentStop, so a session
    /// that stops syncing (ended, orphaned, or long-idle) never sends a shrinking
    /// snapshot; this backstop ages the last one out, and `PaneStatusManager`
    /// sweeps aged-out entries on a timer so the busy floor lifts on its own.
    /// Idle-for-TTL means idle even if a process technically lingers.
    static let stalenessTTL: TimeInterval = 180

    /// True once `lastSeen` is older than `stalenessTTL` — the activity hasn't
    /// appeared in a recent-enough snapshot to keep flooring the session busy.
    var isStale: Bool { Date().timeIntervalSince(lastSeen) > Self.stalenessTTL }

    /// Reported-field equality, deliberately ignoring `lastSeen` (freshness
    /// metadata, not identity): re-syncing the same work with a newer timestamp
    /// still compares equal, so the same task never looks "changed" just because
    /// it was seen again.
    static func == (lhs: BackgroundActivity, rhs: BackgroundActivity) -> Bool {
        lhs.id == rhs.id
            && lhs.kind == rhs.kind
            && lhs.label == rhs.label
            && lhs.status == rhs.status
    }
}

extension BackgroundActivity {
    /// Lenient decode of Claude Code's `background_tasks` array from a raw JSON
    /// string.
    ///
    /// Each element may carry any of: `task_id` (or `id`), `type`/`kind`/`tool`,
    /// `agent_type`, `description`, `command`, `status`. Missing or extra keys are
    /// tolerated and malformed input never throws — a snapshot that is not a JSON
    /// array (or is outright garbage) yields `[]`, and non-object / id-less elements
    /// are skipped rather than aborting the whole decode.
    ///
    /// Kind mapping: an element with an `agent_type` — or a type-ish value
    /// containing "agent" — becomes `.agent`; a "bash"/"shell" type becomes `.bash`;
    /// anything else is `.other`. Label prefers `description` (the task-specific
    /// summary Claude sends for both subagents and background bash), then
    /// `agent_type`, then `command`, falling back to the id — the `kind` glyph
    /// already conveys agent-vs-bash, so the label surfaces *what* the work is.
    /// Elements with no usable id are dropped.
    ///
    /// Every decoded item's `lastSeen` is stamped to now — the snapshot is when
    /// this work was observed — so idle-time staleness ages from this call.
    static func fromClaudeSnapshot(json: String) -> [BackgroundActivity] {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data),
              let array = root as? [Any] else {
            return []
        }

        // Accept a String or a numeric scalar; ignore anything else (nested
        // arrays/objects) so a stray non-string value never becomes a label/id.
        func string(_ value: Any?) -> String? {
            if let s = value as? String { return s }
            if let n = value as? NSNumber { return n.stringValue }
            return nil
        }

        return array.compactMap { element -> BackgroundActivity? in
            guard let dict = element as? [String: Any] else { return nil }

            // No usable id → nothing to key or dedupe the activity on; skip it.
            guard let id = string(dict["task_id"]) ?? string(dict["id"]),
                  !id.isEmpty else { return nil }

            let typeHint = (string(dict["type"]) ?? string(dict["kind"]) ?? string(dict["tool"]))?
                .lowercased()
            let agentType = string(dict["agent_type"])
            let description = string(dict["description"])
            let command = string(dict["command"])

            let kind: Kind
            if agentType != nil || (typeHint?.contains("agent") ?? false) {
                kind = .agent
            } else if let typeHint, typeHint.contains("bash") || typeHint.contains("shell") {
                kind = .bash
            } else {
                kind = .other
            }

            // Description first: it's the human-readable task summary ("Implement
            // sidebar reorder", "Run the test suite"). `agent_type`/`command` are
            // fallbacks for the rare element that omits it; the glyph carries kind.
            let label = description ?? agentType ?? command ?? id
            return BackgroundActivity(
                id: id,
                kind: kind,
                label: label,
                status: string(dict["status"]),
                lastSeen: Date()
            )
        }
    }
}
