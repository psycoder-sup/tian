---
name: release
description: >-
  Cut a tian release end-to-end from the shell: bump the version, build → notarize → tag → push →
  GitHub Release → Sparkle appcast (all via scripts/publish.sh), then update the project record in
  docs/pm/status.json. Use when the user asks to ship/cut/publish a release, bump the version, or
  "release it". Handles the two things publish.sh can't: settling the graphify commit-hook churn so
  the tree is clean enough to publish, and the manual status.json shipped/now update. Trigger:
  /release [patch|minor|major|X.Y.Z].
model: sonnet
---

# Cutting a tian release with `/release`

Ship a new tian version. The heavy lifting already lives in **`scripts/publish.sh`**; this skill wraps
it with the two steps it doesn't do — **settling the tree** (the graphify commit hook re-dirties
`graphify-out/` after every commit, and `publish.sh` hard-fails on a dirty tree) and **updating
`docs/pm/status.json`** (the project's own rules require this before the job is "done").

**Invocation:** `/release [patch|minor|major|X.Y.Z]` — defaults to **`patch`**. `patch`/`minor`/`major`
bump from the latest `v*` tag; an explicit `X.Y.Z` sets it outright.

## Execution: delegate to a subagent

Don't run Preconditions/Steps/Escape hatches/Gotchas below in the main thread. Instead, spawn exactly one
`Agent` call (`model: "sonnet"`) and hand it this entire skill body verbatim — from **Preconditions** through
**Gotchas** — plus the resolved bump argument (`patch`/`minor`/`major`/`X.Y.Z`, defaulting to `patch`). The
subagent has no memory of this conversation, so the prompt must be self-contained: paste the full section
text, don't summarize or reference "the skill file." Run it in the foreground (`run_in_background: false`) —
this is a long, sequential, outward-facing operation (build → notarize → push → GitHub Release) and the main
thread needs its final report (release URL, version, notarize/appcast status, or the failing step) before
replying to the user. Relay that report back verbatim; don't re-run or hand-finish any step yourself.

> **What publish.sh already does — don't duplicate it.** In one run it: builds, notarizes, staples,
> tags `vX.Y.Z`, **pushes the tag**, creates the GitHub Release with the DMG, and **commits + pushes the
> Sparkle appcast to `main`**. The tag is created *after* a successful notarize, so a build/notarize
> failure ships nothing (and the script rolls its local tag back). The **only** release step it does
> **not** do is `docs/pm/status.json` — that's step 4 below.

## Preconditions

Publishing is a real, outward-facing release. Confirm before running:

- **Inside the repo, on `main`, synced** — `git rev-parse --abbrev-ref HEAD` is `main`; `git fetch` then
  confirm no divergence from `origin/main`. (publish.sh tags whatever HEAD is and pushes to the current
  branch — release from `main`.)
- **`gh` authenticated** — `gh auth status`. publish.sh preflights this and aborts otherwise.
- **Signing configured** — `.tian/signing.env` exists (or `DEVELOPMENT_TEAM` is exported). Without it
  `release.sh` exits with a "DEVELOPMENT_TEAM is unset" error.
- **Notary profile set up** — the `tian-notary` keychain profile (override with `NOTARY_PROFILE`). One-time
  setup is `xcrun notarytool store-credentials`.
- **A real, notarized release is intended.** If the user just wants a local artifact, use the dry run
  (`SKIP_NOTARIZE=1`, see Escape hatches) — that still tags/pushes, so only use it when a release is wanted.

Resolve the target version and **state it back to the user before publishing**:

```bash
LATEST=$(git tag --list 'v*' --sort=-v:refname | head -n1)   # e.g. v1.5.5
# patch/minor/major bump from ${LATEST#v}; explicit X.Y.Z overrides.
```

## Steps

### 1. Settle the tree (graphify churn)

`publish.sh` refuses a dirty tree. The graphify post-commit hook fires an async rebuild that re-dirties
`graphify-out/`, so a freshly-committed tree can still show dirty. Commit any *legitimate* pending work
first, then loop until clean — but only auto-commit when the **only** dirty paths are under
`graphify-out/`:

```bash
for _ in 1 2 3; do
  DIRTY=$(git status --porcelain)
  [ -z "$DIRTY" ] && break
  # If anything OUTSIDE graphify-out/ is dirty, STOP and surface it — don't blindly commit release-unrelated work.
  if git status --porcelain | grep -qv '^.. graphify-out/'; then
    echo "unexpected dirty paths — resolve before releasing"; git status --short; exit 1
  fi
  git add graphify-out && git commit -m "chore(graphify): rebuild graph"
  sleep 2   # let the async hook settle before re-checking
done
git status --porcelain   # must be empty before step 3
```

### 2. (Confirmed) — proceed once the version and a clean tree are both settled.

### 3. Publish

```bash
YES=1 scripts/publish.sh <patch|minor|major|X.Y.Z>
```

`YES=1` skips publish.sh's interactive `proceed?` prompt (you already confirmed the version in
Preconditions). This runs long — **notarization alone can take several minutes; do not cancel it.** On
any failure, publish.sh rolls back its local tag and exits non-zero: quote the shortest failing line,
stop, and report — do not retry blindly or hand-finish the release. On success it prints the release URL.

Artifacts land at `.build/release/tian-<version>.dmg` (+ `.sha256`); the appcast commit is
`release: appcast for vX.Y.Z` pushed to `main`.

### 4. Update the release record — `docs/pm/status.json`

publish.sh does **not** touch this; the project rules do. Edit `docs/pm/status.json`:

- **Prepend** a `shipped` entry: `date` (today, `YYYY-MM-DD`), a human `summary` (what shipped — features,
  PRs, notarize/Gatekeeper status), `commit` (short SHA of the release HEAD), and `link`
  (`https://github.com/<owner>/tian/releases/tag/vX.Y.Z`). Trim `shipped` to the newest ~3.
- **Reset `now`** (a shipped item leaves `now`), refresh `next`, clear any `blocked` the release resolved,
  flip a milestone `done` if one completed, and bump `lastUpdated` to today.
- Keep it lean (whole file ≤ ~150 lines; `now`/`next` ≤3 items). Match `docs/pm/schema/status.schema.json`.

Then commit + push, and settle graphify churn once more so the tree ends clean:

```bash
git add docs/pm/status.json && git commit -m "release: status.json for vX.Y.Z"
git push origin main
# re-run the step-1 settle loop so graphify-out/ churn doesn't leave the tree dirty
```

### 5. Verify

```bash
gh release view vX.Y.Z --json url,name --jq '.url'   # release exists, DMG attached
grep -c "vX.Y.Z" docs/appcast.xml                    # new <item> is in the appcast
git status --porcelain                               # tree clean
```

Report to the user: the release URL, the version + build number
(`git rev-list --count HEAD` — publish.sh uses this as `CFBundleVersion`), and that notarize/appcast are live.

## Escape hatches (env vars, forwarded to publish.sh)

- `SKIP_NOTARIZE=1` — skip notarization + stapling. **Dry run only** — still tags and pushes, and users get
  Gatekeeper warnings on first launch. Never ship a real release with this.
- `DRAFT=1` — create the GitHub Release as a draft.
- `PRERELEASE=1` — mark the GitHub Release as a prerelease.
- `NOTARY_PROFILE=<name>` — override the `tian-notary` keychain profile.

## Gotchas

- **publish.sh already pushes to `main`** (the appcast commit) and pushes the tag — you don't push those
  yourself. The *only* manual push is the `status.json` commit in step 4.
- **Dirty tree = instant abort.** Always run the settle loop (step 1) first, and again after step 4.
- **Notarize is slow and must not be interrupted** — `xcrun notarytool submit --wait` blocks for minutes.
- **The version source of truth is the git tag**, not `project.yml`. `release.sh` injects
  `MARKETING_VERSION` (from the tag) and `CURRENT_PROJECT_VERSION` (= `git rev-list --count HEAD`) at build.
- **`scripts/README.md`** is the authoritative reference for publish.sh flags and ordering — consult it if a
  flag here looks stale.
