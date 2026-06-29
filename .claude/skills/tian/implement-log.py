#!/usr/bin/env python3
"""Summarize the /tian implement run log.

implement.sh and the delegated session both append JSONL records (via
implement-logrec.sh) to ~/.claude/tian/implement-runs.jsonl (override with
$TIAN_IMPLEMENT_LOG). A delegation can produce two records: the watcher's
(source=watcher — the outcome implement.sh observed, possibly `running` with no
verdict) and the implementer's own (source=self-verify — the final verdict,
written after it finishes). For per-delegation stats we collapse to one record,
preferring self-verify.

Usage:
    implement-log.py [--log FILE] [--recent N] [--branch SUBSTR]
                     [--since YYYY-MM-DD] [--version V] [--raw]
"""
import sys, os, json
from collections import Counter

DEFAULT_LOG = os.path.expanduser(
    os.environ.get("TIAN_IMPLEMENT_LOG", "~/.claude/tian/implement-runs.jsonl"))


def load(path):
    rows = []
    if not os.path.exists(path):
        return rows
    with open(path) as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                rows.append(json.loads(line))
            except Exception:
                pass
    return rows


def commit_count(rec):
    c = rec.get("commits")
    if isinstance(c, list):
        return len(c)
    s = (c or "").strip().lower()
    if not s or s.startswith("none"):
        return 0
    return s.count(";") + 1  # best-effort for the legacy free-text form


def committed(rec):
    return commit_count(rec) > 0


def rank(r):
    # prefer the implementer's own final record; then the latest timestamp
    return (1 if r.get("source") == "self-verify" else 0, r.get("ts", ""))


def dedup(rows):
    """One record per delegation (keyed by space_id, else branch+pane)."""
    groups = {}
    for r in rows:
        key = r.get("space_id") or f"{r.get('branch')}|{r.get('claude_pane_id')}"
        if key not in groups or rank(r) > rank(groups[key]):
            groups[key] = r
    return sorted(groups.values(), key=lambda r: r.get("ts", ""))


def pct(n, d):
    return f"{(100*n/d):.0f}%" if d else "—"


def main():
    args = sys.argv[1:]
    path, recent, raw = DEFAULT_LOG, 12, False
    branch_f = since = version_f = None
    i = 0
    while i < len(args):
        a = args[i]
        if a == "--log":       path = os.path.expanduser(args[i+1]); i += 2
        elif a == "--recent":  recent = int(args[i+1]); i += 2
        elif a == "--branch":  branch_f = args[i+1]; i += 2
        elif a == "--since":   since = args[i+1]; i += 2
        elif a == "--version": version_f = args[i+1]; i += 2
        elif a == "--raw":     raw = True; i += 1
        else:
            print(f"unknown arg: {a}", file=sys.stderr); sys.exit(2)

    rows = load(path)
    if branch_f:  rows = [r for r in rows if branch_f in (r.get("branch") or "")]
    if since:     rows = [r for r in rows if (r.get("ts") or "") >= since]
    if version_f: rows = [r for r in rows if (r.get("workflow_version") or "") == version_f]

    print(f"log: {path}")
    if not rows:
        print("(no records yet — run /tian implement to populate it)")
        return

    delegations = dedup(rows)
    n = len(delegations)
    states = Counter(r.get("final_state", "?") for r in delegations)
    verdicts = Counter((r.get("verdict") or "unknown") for r in delegations)
    versions = Counter((r.get("workflow_version") or "unknown") for r in delegations)
    elapsed = sorted(r.get("elapsed_s") or 0 for r in delegations)
    median = elapsed[len(elapsed)//2] if elapsed else 0
    committed_n = sum(1 for r in delegations if committed(r))
    ceiling_n = states.get("running", 0) + states.get("timeout", 0)
    clean_n = states.get("idle", 0)

    print(f"\ndelegations: {n}   (from {len(rows)} raw records)")
    print(f"  workflow_version: " + ", ".join(f"{k}={v}" for k, v in versions.most_common()))
    print(f"  final_state:      " + ", ".join(f"{k}={v}" for k, v in states.most_common()))
    print(f"  verdict:          " + ", ".join(f"{k}={v}" for k, v in verdicts.most_common()))
    print(f"  child committed own work: {committed_n}/{n} ({pct(committed_n, n)})")
    print(f"  hit ceiling (running/timeout): {ceiling_n}/{n} ({pct(ceiling_n, n)})")
    print(f"  clean settle (idle): {clean_n}/{n} ({pct(clean_n, n)})")
    print(f"  elapsed median: {median//60}m{median % 60:02d}s   "
          f"(min {elapsed[0]//60}m / max {elapsed[-1]//60}m)")

    table_rows = rows if raw else delegations
    label = "raw records" if raw else "delegations"
    print(f"\nrecent {min(recent, len(table_rows))} {label} (newest last):")
    print(f"  {'when':<17} {'ver':<7} {'src':<11} {'state':<12} {'verdict':<13} "
          f"{'elapsed':>7} {'cmt':>3}  branch")
    for r in table_rows[-recent:]:
        ts = (r.get("ts") or "")[:16].replace("T", " ")
        el = r.get("elapsed_s") or 0
        print(f"  {ts:<17} {(r.get('workflow_version') or '?'):<7} "
              f"{(r.get('source') or '?'):<11} {r.get('final_state','?'):<12} "
              f"{(r.get('verdict') or '?'):<13} {el//60:>4}m{el % 60:02d} "
              f"{commit_count(r):>3}  {r.get('branch','?')}")


if __name__ == "__main__":
    main()
