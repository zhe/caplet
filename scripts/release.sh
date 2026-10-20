#!/usr/bin/env bash
# Builds Caplet VERSION and uploads it as a draft GitHub release, for example:
#   ./scripts/release.sh 0.1.0
# The draft's notes list the commits since the previous release, followed by GitHub's list of
# merged pull requests. Edit them on GitHub, then click Publish; the tag is created then.
set -euo pipefail

VERSION="${1:-}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "usage: $0 VERSION (like 1.2.3)" >&2; exit 64; }
TAG="v$VERSION"

cd "$(dirname "$0")/.."

# The release must be exactly what's on GitHub, so its tag points at the code it was built from.
git fetch --quiet --tags origin
[[ -z "$(git status --porcelain)" ]] || { echo "Commit or stash your changes first." >&2; exit 1; }
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] \
    || { echo "Release from main, in sync with origin/main (push or pull first)." >&2; exit 1; }
! git rev-parse --quiet --verify "refs/tags/$TAG" >/dev/null \
    || { echo "$TAG already exists." >&2; exit 1; }

swift test
./scripts/bundle.sh --release "$VERSION"

# Commits made straight on main; work merged from pull requests is listed by --generate-notes.
PREVIOUS="$(git describe --tags --abbrev=0 2>/dev/null || true)"
NOTES="## Changes

$(git log --first-parent --no-merges --format='- %s (%h)' ${PREVIOUS:+"$PREVIOUS..HEAD"})
"

URL="$(gh release create "$TAG" "build/Caplet-$VERSION.zip" --draft \
    --target "$(git rev-parse HEAD)" --title "Caplet $VERSION" \
    --notes "$NOTES" --generate-notes)"
echo "Draft release created. Edit the notes and publish it at:"
echo "  $URL"
