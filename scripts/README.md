# scripts

Build, release, and install helpers. Run from the repo root.

## What's here

| Script | Purpose |
| --- | --- |
| `build-ghostty.sh` | Build `GhosttyKit.xcframework` from `.ghostty-src` and vendor it into `tian/Vendor/`. Run after pulling new ghostty source. Requires `zig`. |
| `build.sh [Debug\|Release]` | `xcodegen generate` + `xcodebuild` for local development. Defaults to `Debug`. |
| `install.sh` | Copy the latest `Release` build from `.build/` to `/Applications/tian.app`. |
| `release.sh [version]` | Build → DMG → sign → notarize → staple → emit `.dmg` + `.sha256` in `.build/release/`. No git mutations. |
| `publish.sh <version\|patch\|minor\|major>` | Wraps `release.sh` with version resolution, git tag, push, and GitHub Release. |

## Day-to-day

```sh
scripts/build.sh           # Debug build
scripts/build.sh Release   # signed Release build (no DMG, no notarization)
scripts/install.sh         # install last Release build to /Applications
```

## Cutting a release

`publish.sh` is the entry point. It runs in this order:

1. **Resolve version** — explicit `X.Y.Z`, or bump from latest `v*` tag (`patch`/`minor`/`major`).
2. **Preflight** — `gh` authed, working tree clean, tag not already local/remote.
3. **Confirm** — interactive prompt (skip with `YES=1`).
4. **Build artifact** — calls `release.sh`, which:
   - `xcodegen generate`
   - signed `xcodebuild` Release with `MARKETING_VERSION` + `CURRENT_PROJECT_VERSION` baked in
   - `codesign --verify` the `.app`
   - `create-dmg` from a staging dir, then sign the DMG
   - `xcrun notarytool submit --wait` (skip with `SKIP_NOTARIZE=1`)
   - `xcrun stapler staple` + `spctl` Gatekeeper check
   - write `tian-<version>.dmg` + `.sha256`
5. **Tag** — `git tag -a vX.Y.Z` locally (rollback trap armed).
6. **Push tag** — `git push origin vX.Y.Z`.
7. **GitHub Release** — `gh release create` with the DMG + sha and `--generate-notes`.

Build + notarize happen **before** the tag is created. If notarization fails, no tag is pushed and nothing is published.

### Examples

```sh
scripts/publish.sh patch          # bump latest v* tag's patch component
scripts/publish.sh 0.5.0          # explicit version
SKIP_NOTARIZE=1 scripts/publish.sh 0.5.0   # local dry run (Gatekeeper warnings on first launch)
DRAFT=1 scripts/publish.sh patch  # GitHub Release as draft
YES=1 scripts/publish.sh patch    # skip the confirmation prompt
```

### Environment

- `NOTARY_PROFILE` — keychain profile for `xcrun notarytool` (default `tian-notary`). Set up once with `xcrun notarytool store-credentials`.
- `SKIP_NOTARIZE=1` — skip notarization + stapling.
- `DRAFT=1` / `PRERELEASE=1` — flags for `gh release create`.
- `YES=1` — skip the interactive `proceed?` prompt.

## Versioning

Source of truth is the git tag. `project.yml` does not store a version — `release.sh` injects `MARKETING_VERSION` (from the tag) and `CURRENT_PROJECT_VERSION` (from `git rev-list --count HEAD`) at build time.
