#!/usr/bin/env python3
"""Audit a tian *orchestrator* Claude session.

Given a parent Claude Code session id (full or prefix), this:
  1. locates the parent transcript under ~/.claude/projects,
  2. finds the child (worktree) sessions it spawned via /tian implement,
  3. measures token efficiency, parallelism, and orchestrator/implementer
     role hygiene, and
  4. prints a report + heuristic flags for the skill to narrate.

Usage:
    analyze.py <session-id-or-prefix> [--projects DIR]

It prints a human-readable report to stdout. The numbers are exact; the
"FLAGS" are heuristics — the skill turns them into prose + improvements.
"""
import sys, os, json, re, glob, datetime

PROJECTS_DEFAULT = os.path.expanduser("~/.claude/projects")
RUNLOG_DEFAULT = os.path.expanduser(
    os.environ.get("TIAN_IMPLEMENT_LOG", "~/.claude/tian/implement-runs.jsonl"))
BUCKET_MIN = 10  # timeline granularity


# ---------- low-level helpers ----------

def parse_ts(ts):
    if not ts:
        return None
    try:
        return datetime.datetime.fromisoformat(ts.replace("Z", "+00:00"))
    except Exception:
        return None


def load(path):
    rows = []
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


def quick_cwd(path):
    """Cheap cwd sniff — read only the head of the file."""
    try:
        with open(path) as fh:
            for i, line in enumerate(fh):
                if i > 40:
                    break
                if '"cwd"' in line:
                    try:
                        o = json.loads(line)
                        if o.get("cwd"):
                            return o["cwd"]
                    except Exception:
                        pass
    except Exception:
        pass
    return None


def first_cwd(rows):
    for r in rows:
        if r.get("cwd"):
            return r["cwd"]
    return None


def iter_tool_uses(rows):
    for i, r in enumerate(rows):
        if r.get("type") != "assistant":
            continue
        c = r.get("message", {}).get("content")
        if not isinstance(c, list):
            continue
        for b in c:
            if isinstance(b, dict) and b.get("type") == "tool_use":
                yield i, r, b


def find_session(sid, projects):
    hits = []
    for f in glob.glob(os.path.join(projects, "*", "*.jsonl")):
        base = os.path.basename(f)[:-6]
        if base == sid or base.startswith(sid):
            hits.append(f)
    return hits


# ---------- measurement ----------

def metrics(rows):
    inp = cc = cr = out = turns = 0
    first = last = None
    for r in rows:
        if r.get("type") == "assistant":
            u = r.get("message", {}).get("usage") or {}
            if u:
                turns += 1
                inp += u.get("input_tokens", 0)
                cc += u.get("cache_creation_input_tokens", 0)
                cr += u.get("cache_read_input_tokens", 0)
                out += u.get("output_tokens", 0)
        t = parse_ts(r.get("timestamp"))
        if t:
            first = first or t
            last = t
    dur = (last - first).total_seconds() / 60 if first and last else 0
    return dict(turns=turns, inp=inp, cc=cc, cr=cr, out=out, first=first,
                last=last, dur=dur, resident=(cr / turns if turns else 0))


def tool_blob(rows):
    """All tool inputs joined — used to detect which worktrees the parent touched."""
    return "\n".join(json.dumps(b.get("input", {})) for _, _, b in iter_tool_uses(rows))


def count_tools(rows):
    from collections import Counter
    c = Counter()
    for _, _, b in iter_tool_uses(rows):
        c[b.get("name")] += 1
    return c


def bash_commands(rows):
    out = []
    for _, _, b in iter_tool_uses(rows):
        if b.get("name") == "Bash":
            out.append(b.get("input", {}).get("command", "") or "")
    return out


def file_path_tools(rows, names):
    out = []
    for _, _, b in iter_tool_uses(rows):
        if b.get("name") in names:
            fp = b.get("input", {}).get("file_path", "") or ""
            out.append(fp)
    return out


def buckets(rows, base):
    """{bucket_start_minute: tool_call_count} relative to `base`."""
    b = {}
    for i, r, _b in iter_tool_uses(rows):
        t = parse_ts(r.get("timestamp"))
        if not t:
            continue
        m = int((t - base).total_seconds() // (BUCKET_MIN * 60)) * BUCKET_MIN
        b[m] = b.get(m, 0) + 1
    return b


# ---------- child discovery ----------

def worktree_branch(cwd):
    """`…/.worktrees/<repo>/feat/x` -> `feat/x` (the parent refers to it by branch)."""
    if "/.worktrees/" not in cwd:
        return None
    tail = cwd.split("/.worktrees/", 1)[1].split("/")
    return "/".join(tail[1:]) if len(tail) > 1 else None


def spawned_branches(rows):
    """Branches this parent actually delegated via `implement.sh <branch>`."""
    out = set()
    for c in bash_commands(rows):
        for m in re.finditer(r"implement\.sh\s+(\S+)", c):
            b = m.group(1)
            if not b.startswith("-"):
                out.add(b)
    return out


def load_runlog(path):
    """Load the /tian implement run log (JSONL). Silently empty if absent."""
    rows = []
    if not path or not os.path.exists(path):
        return rows
    try:
        with open(path) as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    rows.append(json.loads(line))
                except Exception:
                    pass
    except Exception:
        pass
    return rows


def mangle_worktree(wt):
    """Worktree path -> Claude project-dir name: every '/' and '.' becomes '-'."""
    return re.sub(r"[/.]", "-", wt or "")


def newest_transcript(projdir):
    """Newest *.jsonl under a Claude project dir (by mtime), or None."""
    files = glob.glob(os.path.join(projdir, "*.jsonl"))
    if not files:
        return None
    try:
        return max(files, key=lambda p: os.path.getmtime(p))
    except Exception:
        return files[0]


def resolve_from_runlog(runlog, spawned, projects):
    """{transcript_file: branch} for spawned branches resolvable from the run log.

    For each run-log record whose branch the parent spawned, resolve the child
    transcript authoritatively — by the recorded child_session_id (exact file),
    else by worktree + newest transcript. This removes the branch/cwd guessing
    for implement.sh children (including --no-wait fan-out and pane-send children
    that still went through implement.sh)."""
    out = {}
    for rec in runlog:
        br = rec.get("branch")
        if not br or br not in spawned:
            continue
        f = None
        csid = (rec.get("child_session_id") or "").strip()
        if csid:
            cand = glob.glob(os.path.join(projects, "*", csid + ".jsonl"))
            if cand:
                f = cand[0]
        if not f:
            wt = (rec.get("worktree") or "").strip()
            if wt:
                f = newest_transcript(os.path.join(projects, mangle_worktree(wt)))
        if f and os.path.exists(f):
            out[f] = br  # later records win (newest resolution for the branch)
    return out


def find_children(parent_rows, parent_m, projects, runlog):
    blob = tool_blob(parent_rows)
    spawned = spawned_branches(parent_rows)
    p_first, p_last = parent_m["first"], parent_m["last"]

    # 1) Authoritative: children resolved straight from the run log (no guessing).
    runlog_files = resolve_from_runlog(runlog, spawned, projects)
    resolved_branches = set(runlog_files.values())

    cands = []
    seen = set()
    for f, _br in runlog_files.items():
        if f in seen:
            continue
        rows = load(f)
        m = metrics(rows)
        if not m["first"]:
            continue
        cwd = first_cwd(rows) or quick_cwd(f) or ""
        cands.append((f, cwd, rows, m))
        seen.add(f)

    # 2) Heuristic supplement — only for worktrees the run log did NOT already
    # resolve (e.g. children delegated purely via `pane send`, or sessions from
    # runs predating the run log). Branch-matched candidates whose branch the run
    # log already resolved are skipped so we prefer the authoritative link.
    for f in glob.glob(os.path.join(projects, "*", "*.jsonl")):
        if f in seen:
            continue
        cwd = quick_cwd(f)
        if not cwd or "/.worktrees/" not in cwd:
            continue
        branch = worktree_branch(cwd)
        if cwd not in blob and not (branch and branch in spawned):
            continue
        if branch and branch in resolved_branches:
            continue
        rows = load(f)
        m = metrics(rows)
        if not m["first"]:
            continue
        if p_first and p_last and m["first"] and m["last"]:
            if not (m["first"] <= p_last and m["last"] >= p_first):
                continue
        cands.append((f, cwd, rows, m))
        seen.add(f)

    # de-dup by file, newest-overlap first
    cands.sort(key=lambda c: c[3]["first"] or datetime.datetime.max)
    return cands, runlog_files


def filter_zombies(cands):
    """Drop sessions that aren't real children, returning (kept, dropped_count):
      - 0-turn sessions (or out==0 with turns<=1) — never did anything; and
      - sessions whose cwd is a NESTED sub-path of another child's worktree
        (e.g. a `.../feat/x/apps/macos` session under `.../feat/x`), which the
        path-mangle / nested-worktree heuristics can otherwise pull in twice."""
    dropped = 0
    interim = []
    for f, cwd, rows, m in cands:
        if m["turns"] == 0 or (m["out"] == 0 and m["turns"] <= 1):
            dropped += 1
            continue
        interim.append((f, cwd, rows, m))

    cwds = [c[1] for c in interim if c[1]]
    kept = []
    for f, cwd, rows, m in interim:
        nested = bool(cwd) and any(
            other != cwd and cwd.startswith(other.rstrip("/") + "/") for other in cwds)
        if nested:
            dropped += 1
            continue
        kept.append((f, cwd, rows, m))
    return kept, dropped


def child_branch(f, cwd, runlog_files):
    """The branch for a linked child — run-log link wins, else infer from cwd."""
    return runlog_files.get(f) or worktree_branch(cwd or "")


def reconcile(branch, runlog):
    """Reconcile a child's run-log records into a one-line state.

    Returns ("STALL", final_state) when the LATEST record for the branch is a
    watcher `running`/`timeout` with no later self-verify record (a genuine
    stall the orchestrator should chase); otherwise ("ok", verdict) where the
    self-verify verdict supersedes the watcher's interim outcome. None when the
    run log has nothing for the branch."""
    if not branch:
        return None
    recs = [r for r in runlog if r.get("branch") == branch and r.get("ts")]
    if not recs:
        return None
    recs.sort(key=lambda r: r.get("ts", ""))
    latest = recs[-1]
    sv = [r for r in recs if r.get("source") == "self-verify"]
    sv_latest_ts = sv[-1].get("ts", "") if sv else ""
    if (latest.get("source") == "watcher"
            and latest.get("final_state") in ("running", "timeout")
            and (not sv or sv_latest_ts < latest.get("ts", ""))):
        return ("STALL", latest.get("final_state"))
    if sv:
        return ("ok", sv[-1].get("verdict") or "unknown")
    return ("ok", latest.get("final_state") or "?")


# ---------- role-hygiene heuristics ----------

WT = "/.worktrees/"


def failed_delegate_tasks(rows):
    """Parent task-notifications that FAILED and look like a delegate/watch step —
    usually a watcher timeout, not a real implementation failure."""
    n = 0
    for r in rows:
        if r.get("type") != "user":
            continue
        c = r.get("message", {}).get("content")
        blob = c if isinstance(c, str) else json.dumps(c)
        if "<status>failed</status>" in blob and re.search(
                r"[Dd]elegat|[Ww]atch|worktree|self-verify", blob):
            n += 1
    return n


def parent_hygiene(rows):
    bashes = bash_commands(rows)
    reads = file_path_tools(rows, {"Read"})
    edits = file_path_tools(rows, {"Edit", "Write", "NotebookEdit"})

    def has(cmd, *subs):
        return all(s in cmd for s in subs)

    return dict(
        failed_delegate_tasks=failed_delegate_tasks(rows),
        edits_in_worktree=sum(1 for p in edits if WT in p),
        reads_in_worktree=sum(1 for p in reads if WT in p),
        commits_in_worktree=sum(1 for c in bashes if WT in c and "commit" in c),
        git_inspect_worktree=sum(
            1 for c in bashes if WT in c and re.search(r"git (-C \S+ )?(show|diff|log|status)", c)),
        pane_capture_polls=sum(1 for c in bashes if "pane capture" in c and "help" not in c),
        pane_send=sum(1 for c in bashes if re.search(r"\btian\s+pane\s+send\b", c) and "help" not in c),
        # a real spawn is the backgrounded implement.sh run — not a foreground ls/grep of it
        implement_spawns=sum(
            1 for _, _, b in iter_tool_uses(rows)
            if b.get("name") == "Bash"
            and "implement.sh" in b.get("input", {}).get("command", "")
            and b.get("input", {}).get("run_in_background")),
    )


def child_hygiene(rows):
    bashes = bash_commands(rows)
    return dict(
        commits=sum(1 for c in bashes if re.search(r"git (-C \S+ )?commit", c)),
        status_signals=sum(1 for c in bashes if "tian status" in c),
        notify_signals=sum(1 for c in bashes if "tian notify" in c),
        builds=sum(1 for c in bashes if re.search(r"swift test|xcodebuild|xcodegen|pnpm|npm run|cargo", c)),
        pushed_or_pr=sum(1 for c in bashes if re.search(r"git push|gh pr create", c)),
    )


# ---------- reporting ----------

def fmt_tok(n):
    return f"{n:,}"


def hm(dt):
    return dt.strftime("%H:%M") if dt else "??:??"


def print_metrics_block(label, m):
    print(f"  {label}")
    print(f"    turns:            {m['turns']}")
    print(f"    wall clock:       {m['dur']:.0f} min ({hm(m['first'])}->{hm(m['last'])} UTC)")
    print(f"    output tokens:    {fmt_tok(m['out'])}")
    print(f"    cache_creation:   {fmt_tok(m['cc'])}")
    print(f"    cache_read:       {fmt_tok(m['cr'])}")
    print(f"    resident ctx/turn:{fmt_tok(int(m['resident']))}  (cache_read / turns)")


def main():
    args = [a for a in sys.argv[1:]]
    projects = PROJECTS_DEFAULT
    runlog_path = RUNLOG_DEFAULT
    if "--projects" in args:
        idx = args.index("--projects")
        projects = os.path.expanduser(args[idx + 1])
        del args[idx:idx + 2]
    if "--log" in args:
        idx = args.index("--log")
        runlog_path = os.path.expanduser(args[idx + 1])
        del args[idx:idx + 2]
    if not args:
        print("usage: analyze.py <session-id-or-prefix> [--projects DIR] [--log RUNLOG]",
              file=sys.stderr)
        sys.exit(2)
    sid = args[0]

    hits = find_session(sid, projects)
    if not hits:
        print(f"No session matching '{sid}' under {projects}", file=sys.stderr)
        sys.exit(1)
    if len(hits) > 1:
        print(f"Ambiguous prefix '{sid}' — {len(hits)} matches:", file=sys.stderr)
        for h in hits:
            print("   " + h, file=sys.stderr)
        sys.exit(1)

    pfile = hits[0]
    prows = load(pfile)
    pm = metrics(prows)
    pcwd = first_cwd(prows)
    phy = parent_hygiene(prows)

    print("=" * 72)
    print("TIAN ORCHESTRATOR SESSION AUDIT")
    print("=" * 72)
    print(f"parent session: {os.path.basename(pfile)[:-6]}")
    print(f"parent cwd:     {pcwd}")
    print(f"parent tools:   {dict(count_tools(prows))}")
    print()
    print("TOKENS")
    print_metrics_block("PARENT (orchestrator)", pm)

    runlog = load_runlog(runlog_path)
    children, runlog_files = find_children(prows, pm, projects, runlog)
    children, zdropped = filter_zombies(children)
    linked_n = sum(1 for f, _c, _r, _m in children if f in runlog_files)
    print(f"\n  child linkage: {len(children)} kept "
          f"({linked_n} via run log, {len(children) - linked_n} via heuristic)"
          + (f"; filtered {zdropped} zombie/nested session(s)" if zdropped else ""))
    if runlog:
        print(f"  run log: {runlog_path} ({len(runlog)} records)")
    else:
        print(f"  run log: none at {runlog_path} (heuristic linkage only)")

    child_ms = []
    for f, cwd, rows, m in children:
        chy = child_hygiene(rows)
        branch = child_branch(f, cwd, runlog_files)
        child_ms.append((f, cwd, m, chy, branch))
        print()
        print_metrics_block(f"CHILD  {os.path.basename(f)[:-6]}", m)
        print(f"      cwd: {cwd}")
        print(f"      branch: {branch or '?'}   linked: {'run-log' if f in runlog_files else 'heuristic'}")
        print(f"      hygiene: {chy}")

    # ---- combined + inversions ----
    print()
    print("ROLE-HYGIENE FLAGS (heuristic)")
    print(f"  parent edits inside a worktree:        {phy['edits_in_worktree']}   (>0 = orchestrator did implementer work)")
    print(f"  parent commits inside a worktree:      {phy['commits_in_worktree']}   (>0 = orchestrator owns child's git)")
    print(f"  parent reads of worktree files:        {phy['reads_in_worktree']}   (context duplication w/ child)")
    print(f"  parent git show/diff/log on worktree:  {phy['git_inspect_worktree']}   (reconstructing child's state)")
    print(f"  parent 'tian pane capture' polls:      {phy['pane_capture_polls']}   (polling instead of awaiting a signal)")
    print(f"  parent 'tian pane send' (route to child): {phy['pane_send']}")
    print(f"  parent implement.sh spawns:            {phy['implement_spawns']}")
    print(f"  parent FAILED delegate/watch tasks:    {phy['failed_delegate_tasks']}   (>0 = watcher likely timed out; verify child wasn't actually fine)")
    for f, cwd, m, chy, branch in child_ms:
        miss = []
        if chy["status_signals"] == 0 and chy["notify_signals"] == 0:
            miss.append("no done-signal (no tian status/notify)")
        if chy["commits"] == 0:
            miss.append("child never committed (orchestrator had to)")
        print(f"  child {os.path.basename(f)[:8]}: builds={chy['builds']} commits={chy['commits']} "
              f"signals={chy['status_signals']+chy['notify_signals']} "
              + (("FLAGS: " + "; ".join(miss)) if miss else "clean"))
        rec = reconcile(branch, runlog)
        if rec:
            kind, detail = rec
            if kind == "STALL":
                print(f"      reconcile: GENUINE STALL — latest run-log record is "
                      f"watcher '{detail}' with no later self-verify (chase this child)")
            else:
                print(f"      reconcile: self-verify supersedes watcher — verdict={detail}")

    if child_ms:
        cm = child_ms[0][2]
        print()
        print("INVERSION CHECK (a healthy orchestrator is LIGHTER than its implementer)")
        oi = "INVERTED" if pm["out"] > cm["out"] else "ok"
        ri = "INVERTED" if pm["resident"] > cm["resident"] else "ok"
        print(f"  output:        parent {fmt_tok(pm['out'])} vs child {fmt_tok(cm['out'])}   -> {oi}")
        print(f"  resident ctx:  parent {fmt_tok(int(pm['resident']))} vs child {fmt_tok(int(cm['resident']))}   -> {ri}")

    # ---- parallelism timeline ----
    all_starts = [pm["first"]] + [m["first"] for _, _, m, _, _ in child_ms]
    all_starts = [s for s in all_starts if s]
    if all_starts:
        base = min(all_starts)
        pb = buckets(prows, base)
        cbs = [(os.path.basename(f)[:8], buckets(load(f), base)) for f, _, _, _, _ in child_ms]
        all_b = set(pb)
        for _, cb in cbs:
            all_b |= set(cb)
        print()
        print(f"PARALLELISM TIMELINE ({BUCKET_MIN}-min buckets, tool-calls per bucket)")
        if not cbs:
            print("  (no child sessions found — single-track run)")
        maxb = max(all_b) if all_b else 0
        overlap_windows = 0
        parent_active = 0
        for mstart in range(0, maxb + BUCKET_MIN, BUCKET_MIN):
            clock = (base + datetime.timedelta(minutes=mstart)).strftime("%H:%M")
            p = pb.get(mstart, 0)
            line = f"  {clock}  P:{'#'*min(p,30):<30}({p:>2})"
            any_child = False
            for name, cb in cbs:
                c = cb.get(mstart, 0)
                if c:
                    any_child = True
                line += f"  {name}:{'#'*min(c,20):<20}({c:>2})"
            if p:
                parent_active += 1
            if p and any_child:
                overlap_windows += 1
            print(line)
        print()
        print(f"  windows where parent AND a child were active: {overlap_windows}")
        print(f"  parent-active windows total:                  {parent_active}")
        if cbs and parent_active:
            print(f"  -> {overlap_windows}/{parent_active} of the orchestrator's active windows overlapped a child.")
            print("     Low overlap = serial relay (babysitting). High overlap on the SAME")
            print("     branch = co-editing race; on DIFFERENT branches = true parallelism.")

    print()
    print("=" * 72)
    print("Heuristics only — read the numbers above and write the assessment.")
    print("=" * 72)


if __name__ == "__main__":
    main()
