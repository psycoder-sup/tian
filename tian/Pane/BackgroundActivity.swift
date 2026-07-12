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
    /// Whether the work is a subagent, a teammate, a backgrounded bash command,
    /// or something else Claude reported.
    enum Kind: String, Codable, Sendable {
        case agent
        case teammate
        case bash
        case other

        /// SF Symbol name for this kind, shared by every view that renders a
        /// background-activity glyph (the sidebar badge and the overview list) so
        /// the `kind → symbol` mapping lives in exactly one place.
        var systemName: String {
            switch self {
            case .agent: "person.2.fill"
            case .teammate: "person.3.fill"
            case .bash: "terminal"
            case .other: "bolt.horizontal.circle"
            }
        }
    }

    /// Which of the two feeds produced this entry — the thing that decides who is
    /// allowed to remove it and how long it may sit un-refreshed.
    ///
    /// - `lifecycle`: minted from a `SubagentStart` / teammate hook. Authoritative
    ///   for subagents and teammates (foreground ones included, which the snapshot
    ///   never sees). Cleared by *events* — `SubagentStop`, the turn-end reconcile,
    ///   a new prompt, idle, session end.
    /// - `snapshot`: decoded from Claude's `background_tasks` full-set array.
    ///   Authoritative for backgrounded bash / background tasks, and replaced
    ///   wholesale by the next snapshot.
    ///
    /// Kept out of neither `==` nor the dedupe key by accident: the same work must
    /// never be counted twice, so when a lifecycle id and a snapshot id collide the
    /// lifecycle entry wins (see `PaneStatusManager.syncActivities`).
    enum Source: String, Codable, Sendable {
        case lifecycle
        case snapshot
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

    /// Wall-clock time this activity was last observed — the snapshot it was
    /// decoded from, or the lifecycle hook that minted it.
    /// Drives `isStale`: once Claude goes idle and stops syncing, the last
    /// snapshot's entries age out after `stalenessTTL`, so a background command
    /// that quietly finished during an idle session no longer pins it busy.
    /// Transient freshness metadata — deliberately excluded from `==`.
    var lastSeen: Date = Date()

    /// Which feed minted this entry. Defaults to `.snapshot` so every existing
    /// `background_tasks` construction site keeps its meaning unchanged.
    var source: Source = .snapshot

    /// How long an un-refreshed **snapshot** activity stays "live" before it reads
    /// as stale. Claude only reports `background_tasks` on Stop/SubagentStop, so a
    /// session that stops syncing (ended, orphaned, or long-idle) never sends a
    /// shrinking snapshot; this backstop ages the last one out, and
    /// `PaneStatusManager` sweeps aged-out entries on a timer so the busy floor
    /// lifts on its own. Idle-for-TTL means idle even if a process technically
    /// lingers.
    static let stalenessTTL: TimeInterval = 180

    /// The same backstop for **lifecycle** activities — deliberately far longer.
    ///
    /// Lifecycle entries are meant to be cleared by *events* (`SubagentStop`, the
    /// turn-end Stop reconcile, a new prompt, idle, session end), never by the
    /// clock: a genuine foreground subagent can legitimately grind for 10+ minutes
    /// with no intervening hook to refresh its `lastSeen`, and silently dropping a
    /// live agent (under-counting the badge) is a worse failure than clearing a
    /// dead one slowly. So this TTL is a last-resort backstop for the one case no
    /// event can cover — a hard-killed CLI that never gets to send its stop hook —
    /// and is sized to sit well past any plausible agent run.
    static let lifecycleStalenessTTL: TimeInterval = 900

    /// The staleness backstop that applies to this entry, chosen by `source`.
    var stalenessTTL: TimeInterval {
        switch source {
        case .lifecycle: Self.lifecycleStalenessTTL
        case .snapshot: Self.stalenessTTL
        }
    }

    /// True once `lastSeen` is older than this entry's own `stalenessTTL` — it
    /// hasn't been refreshed recently enough to keep flooring the session busy.
    var isStale: Bool { Date().timeIntervalSince(lastSeen) > stalenessTTL }

    /// Reported-field equality, deliberately ignoring `lastSeen` (freshness
    /// metadata, not identity): re-syncing the same work with a newer timestamp
    /// still compares equal, so the same task never looks "changed" just because
    /// it was seen again. `source` *is* compared — the same id arriving from the
    /// other feed is a different fact about who may remove it.
    static func == (lhs: BackgroundActivity, rhs: BackgroundActivity) -> Bool {
        lhs.id == rhs.id
            && lhs.kind == rhs.kind
            && lhs.label == rhs.label
            && lhs.status == rhs.status
            && lhs.source == rhs.source
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
    /// this work was observed — so idle-time staleness ages from this call, and
    /// every item is stamped `source = .snapshot`: `background_tasks` is a full-set
    /// array, so these entries are the ones a later snapshot may replace wholesale.
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
                lastSeen: Date(),
                source: .snapshot
            )
        }
    }

    /// An activity minted from a lifecycle hook (`SubagentStart` and friends) —
    /// the authoritative feed for subagents and teammates, including the
    /// *foreground* ones `background_tasks` never reports.
    ///
    /// Lenient on purpose, mirroring `fromClaudeSnapshot`: the caller passes
    /// whatever the hook payload happened to carry and gets a usable entry back.
    /// An empty `label` falls back to the id so the badge/list always has something
    /// to render.
    ///
    /// `lastSeen` is stamped to now and `source` to `.lifecycle`, which is what
    /// buys the entry the long `lifecycleStalenessTTL` backstop and protects it
    /// from being swept away by an unrelated `background_tasks` snapshot.
    static func lifecycle(
        id: String,
        kind: Kind,
        label: String,
        status: String? = nil
    ) -> BackgroundActivity {
        BackgroundActivity(
            id: id,
            kind: kind,
            label: label.isEmpty ? id : label,
            status: status,
            lastSeen: Date(),
            source: .lifecycle
        )
    }
}
