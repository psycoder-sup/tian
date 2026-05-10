#!/bin/bash
set -euo pipefail

# Build → tag → push → create GitHub Release.
#
# Usage:
#   scripts/publish.sh <version>          # e.g. 0.4.2
#   scripts/publish.sh patch|minor|major  # bump from latest v* tag
#
# Environment:
#   NOTARY_PROFILE   Forwarded to release.sh (default: tian-notary)
#   SKIP_NOTARIZE=1  Forwarded to release.sh (skip notarization for dry runs)
#   DRAFT=1          Create the GitHub Release as a draft
#   PRERELEASE=1     Mark the GitHub Release as a prerelease
#   YES=1            Skip the interactive confirmation
#
# Source of truth: the git tag. Nothing in project.yml stores the version.

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <version|patch|minor|major>" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/.."

ARG="$1"

# ---- resolve version --------------------------------------------------------

bump_semver() {
  local current="$1" part="$2"
  local major minor patch
  IFS='.' read -r major minor patch <<<"$current"
  case "$part" in
    major) echo "$((major + 1)).0.0" ;;
    minor) echo "${major}.$((minor + 1)).0" ;;
    patch) echo "${major}.${minor}.$((patch + 1))" ;;
  esac
}

case "$ARG" in
  patch|minor|major)
    LATEST="$(git tag --list 'v*' --sort=-v:refname | head -n1 || true)"
    if [[ -z "$LATEST" ]]; then
      echo "no v* tag found — pass an explicit version like 0.1.0" >&2
      exit 1
    fi
    CURRENT="${LATEST#v}"
    if [[ ! "$CURRENT" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      echo "latest tag '$LATEST' is not X.Y.Z — pass an explicit version" >&2
      exit 1
    fi
    VERSION="$(bump_semver "$CURRENT" "$ARG")"
    ;;
  *)
    VERSION="${ARG#v}"
    if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      echo "version must be X.Y.Z (got '$ARG')" >&2
      exit 1
    fi
    ;;
esac

TAG="v$VERSION"

# ---- preflight --------------------------------------------------------------

command -v gh >/dev/null || { echo "gh CLI not found"; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "gh not authenticated — run 'gh auth login'"; exit 1; }

if [[ -n "$(git status --porcelain)" ]]; then
  echo "working tree is dirty — commit or stash first" >&2
  git status --short >&2
  exit 1
fi

if git rev-parse --verify "refs/tags/$TAG" >/dev/null 2>&1; then
  echo "tag $TAG already exists locally" >&2
  exit 1
fi
if git ls-remote --exit-code --tags origin "refs/tags/$TAG" >/dev/null 2>&1; then
  echo "tag $TAG already exists on origin" >&2
  exit 1
fi

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
SHA="$(git rev-parse --short HEAD)"

echo "==> publish $TAG"
echo "    branch: $BRANCH @ $SHA"
echo "    notarize: $([[ "${SKIP_NOTARIZE:-0}" == "1" ]] && echo no || echo yes)"
if [[ "${YES:-0}" != "1" ]]; then
  read -r -p "proceed? [y/N] " ANS
  [[ "$ANS" == "y" || "$ANS" == "Y" ]] || { echo "aborted"; exit 1; }
fi

# ---- build ------------------------------------------------------------------

"$SCRIPT_DIR/release.sh" "$VERSION"

DMG_PATH=".build/release/tian-$VERSION.dmg"
SHA_PATH="$DMG_PATH.sha256"
[[ -f "$DMG_PATH" ]] || { echo "expected $DMG_PATH after build" >&2; exit 1; }
[[ -f "$SHA_PATH" ]] || { echo "expected $SHA_PATH after build" >&2; exit 1; }

# ---- tag + push -------------------------------------------------------------

echo "==> git tag $TAG"
git tag -a "$TAG" -m "Release $TAG"

# Roll the tag back if pushing or releasing fails so re-runs work.
cleanup_tag() {
  if [[ "${PUBLISH_OK:-0}" != "1" ]]; then
    echo "==> rolling back local tag $TAG"
    git tag -d "$TAG" >/dev/null 2>&1 || true
  fi
}
trap cleanup_tag EXIT

echo "==> git push origin $TAG"
git push origin "$TAG"

# ---- gh release -------------------------------------------------------------

GH_FLAGS=(--title "$TAG" --generate-notes)
[[ "${DRAFT:-0}" == "1" ]] && GH_FLAGS+=(--draft)
[[ "${PRERELEASE:-0}" == "1" ]] && GH_FLAGS+=(--prerelease)

echo "==> gh release create $TAG"
gh release create "$TAG" "$DMG_PATH" "$SHA_PATH" "${GH_FLAGS[@]}"

PUBLISH_OK=1
echo
echo "Done: $(gh release view "$TAG" --json url --jq .url)"
