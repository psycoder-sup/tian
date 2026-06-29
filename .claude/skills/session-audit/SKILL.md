---
name: session-audit
description: >-
  Audit a tian *orchestrator* Claude Code session for token efficiency, parallelism, and
  orchestrator/implementer role hygiene. Give it a parent session id (full or prefix); it locates the
  transcript, finds the child worktree sessions spawned via /tian implement, measures the numbers, and
  reports concrete improvements to the orchestrator↔implementer harness. Use when asked to analyze /
  audit / review how a session used tian or the /tian implement workflow, or to find out where tokens
  and parallelism leaked.
---

# session-audit — audit a tian orchestrator session

Diagnoses how a parent (orchestrator) session drove `/tian implement` and its child (implementer)
worktree sessions, then proposes harness improvements. The point of the harness is: **the orchestrator
stays lean and asynchronous; the implementer is self-sufficient and isolated; parallelism lives across
worktrees, never inside one.** This skill measures how far a real session fell from that.

## Input

A parent Claude Code session id — full or a unique prefix (e.g. `cddcb284`). The user usually pastes
it. If they give a worktree/child id instead, that's fine — the script still measures it; just note the
session it found is the implementer, not the orchestrator.

## Run

```bash
python3 "$CLAUDE_PROJECT_DIR/.claude/skills/session-audit/analyze.py" <session-id-or-prefix>
```

(Default transcript root is `~/.claude/projects`; pass `--projects DIR` to override.) The script prints
exact token/parallelism numbers and heuristic FLAGS. It does **not** write the assessment — you do, from
the numbers. If it reports "no child sessions found," it was a single-track run; assess the orchestrator
alone and say so.

## How to read the output

**Tokens.** `cache_read` is the resident context re-billed every turn — cheap per token, huge in volume,
and the real efficiency lever is keeping it small. `resident ctx/turn = cache_read / turns` is the
orchestrator's average context size; `output tokens` is the expensive line. Compare parent vs child.

**Inversion check (the headline).** A healthy orchestrator is *lighter* than its implementer — it
decomposes and integrates, it doesn't write code. If the script prints `INVERTED` for output or resident
context, the orchestrator was doing the implementer's job and/or hoarding context. That is the single
most important signal.

**Role-hygiene flags.** Each `>0` is the orchestrator crossing the line into the implementer's worktree:
- `edits/commits inside a worktree` — orchestrator did implementer work / owns the child's git → write
  race + the inversion above.
- `reads of worktree files` + `git show/diff/log on worktree` — context duplication: the orchestrator
  re-reads and reconstructs state the child already had loaded.
- `pane capture polls` with `0` child `tian status/notify` signals — the child never announced "done,"
  so the orchestrator polled (or a human relayed). No async signal ⇒ no real parallelism.
- child `commits=0` — the guardrail forced the orchestrator into the git path.

**Parallelism timeline.** Few overlap windows ⇒ a serial relay (babysitting). Overlap on the *same*
branch ⇒ a co-editing race. The only good overlap is two tracks active on *different* branches.

## What to produce

Write a short, falsifiable assessment grounded in the printed numbers (cite the actual figures), in
three parts:

1. **How the session used tian / `/tian implement`** — the workflow it actually ran (spawn → who edited
   → who committed → how completion was signalled → integrate/PR).
2. **Diagnosis** — lead with the inversion verdict, then the role-hygiene and parallelism findings, each
   tied to a number from the report.
3. **Improvements** — pick from the catalog below the ones the flags actually justify; don't recite all
   of them. Prefer the smallest change with the biggest payoff.

### Improvement catalog (map flags → fixes)

- **Async done-signal** (child signals=0, parent polls>0): child wrapper ends with `tian status set
  --state done` + `tian notify`; orchestrator *awaits* it instead of polling. Precondition for parallelism.
- **Child owns its commits** (child commits=0, parent commits-in-worktree>0): flip the guardrail to
  "commit freely, never push/PR/merge." Removes the orchestrator from git → no reconstruct tax, no race.
- **Single-writer worktree** (parent edits-in-worktree>0): orchestrator never edits a child's worktree;
  route follow-ups with `tian pane send` to the live child that already has the context.
- **Structured handoff, not re-reading** (parent reads/git-inspect-worktree high): child emits a compact
  "files changed + rationale + test results" summary; orchestrator consumes only that.
- **Fresh base, single-owner hot files** (duplicate status.json / rebase pain): cut the worktree branch
  fresh from current main; keep shared hot files (status.json, project.yml) owned by one track only.
- **Parallelism is across worktrees** (low overlap / same-branch overlap): N independent slices ⇒ N
  worktrees on N branches; the orchestrator stays a thin scheduler. Don't put N writers in one tree.
- **Collapse the inner split when degenerate** (1 orchestrator → 1 idle implementer): if a milestone is
  one atomic slice, let the orchestrator *be* the implementer in its own worktree — don't pay for a
  second idle context.

### Litmus test to report

Re-running this audit on a healthier session should show: orchestrator output < implementer output;
orchestrator resident context < implementer's; and timeline overlap on *different* branches. State
whether the audited session passes or fails each.
