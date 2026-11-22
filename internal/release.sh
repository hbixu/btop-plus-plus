#!/bin/bash
#
# release.sh - Create a git release for the current image version
#
# Flow:
#   1. Reads the image version from build.sh (DEFAULT_VERSION) -> tag vX.Y.Z
#   2. Checks: on branch main, up to date with origin, tag does not exist yet,
#      CHANGELOG.md has an entry for the version
#   3. If there are uncommitted changes: shows them and asks to commit them as "Release X.Y.Z"
#   4. Asks to create the tag and push main + tag to origin (Gitea),
#      which triggers the sync to GitHub
#
# The image itself is NOT built here: use ./internal/update-btop.sh (btop++ update)
# or ./build.sh --registry docker.io/hbixu --push (other changes) before running this script.
#
# Usage: ./internal/release.sh

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# This script lives in internal/; run everything from the repository root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
fi

# ask_yes_no "Question" [default y|n] -> returns 0 for yes, 1 for no
ask_yes_no() {
    local question="$1"
    local default="${2:-n}"
    local hint="[y/N]"
    [ "$default" = "y" ] && hint="[Y/n]"
    local answer
    while true; do
        read -r -p "$question $hint " answer || answer=""
        answer="${answer:-$default}"
        case "$answer" in
            [yY]|[yY][eE][sS]|[sS]|[sS][iI][mM]) return 0 ;;
            [nN]|[nN][oO]|[nN][aA][oO]) return 1 ;;
            *) echo "Please answer y or n." ;;
        esac
    done
}

fail() {
    echo -e "${RED}ERROR: $1${NC}"
    exit 1
}

# ============================================================================
# 1. Version
# ============================================================================

VERSION=$(grep '^DEFAULT_VERSION=' build.sh | head -1 | cut -d'=' -f2 | cut -d'#' -f1 | tr -d '"' | xargs)
[ -n "$VERSION" ] || fail "DEFAULT_VERSION not found in build.sh"
TAG="v$VERSION"

echo -e "${BLUE}=== Release $TAG ===${NC}"

# ============================================================================
# 2. Checks
# ============================================================================

BRANCH=$(git rev-parse --abbrev-ref HEAD)
[ "$BRANCH" = "main" ] || fail "Releases are created from 'main' (current branch: $BRANCH)"

if git rev-parse -q --verify "refs/tags/$TAG" > /dev/null; then
    fail "Tag $TAG already exists locally. Bump DEFAULT_VERSION in build.sh (or use ./internal/update-btop.sh)."
fi

echo "Fetching origin..."
git fetch --quiet origin
if git ls-remote --exit-code --tags origin "refs/tags/$TAG" > /dev/null 2>&1; then
    fail "Tag $TAG already exists on origin."
fi
if git rev-parse -q --verify origin/main > /dev/null; then
    BEHIND=$(git rev-list --count HEAD..origin/main)
    [ "$BEHIND" -eq 0 ] || fail "Local main is $BEHIND commit(s) behind origin/main. Run 'git pull' first."
fi

grep -q "^## \[$VERSION\]" CHANGELOG.md || fail "CHANGELOG.md has no entry '## [$VERSION]'"

echo -e "${GREEN}Checks passed.${NC}"
echo ""

# ============================================================================
# 3. Uncommitted changes
# ============================================================================

if [ -n "$(git status --porcelain)" ]; then
    echo -e "${YELLOW}Uncommitted changes:${NC}"
    git status --short
    echo ""
    if ask_yes_no "Commit all these changes as \"Release $VERSION\"?" "y"; then
        git add -A
        git commit -m "Release $VERSION"
    else
        fail "Commit or discard the changes before releasing."
    fi
    echo ""
fi

# ============================================================================
# 4. Tag and push
# ============================================================================

echo "Commits to push:"
if git rev-parse -q --verify origin/main > /dev/null; then
    git log --oneline origin/main..HEAD | sed 's/^/  /'
    [ -n "$(git log --oneline origin/main..HEAD)" ] || echo "  (none)"
else
    git log --oneline -5 | sed 's/^/  /'
fi
echo ""

if ! ask_yes_no "Create tag $TAG and push main + $TAG to origin (triggers the GitHub sync)?" "y"; then
    echo "Cancelled. Nothing was tagged or pushed."
    exit 0
fi

git tag -a "$TAG" -m "Release $VERSION"
git push origin main
git push origin "$TAG"

echo ""
echo -e "${GREEN}=== Release $TAG done ===${NC}"
echo "Next steps:"
echo "  - Check the 'Sync to GitHub' job in the Gitea Actions tab"
echo "  - Update the Docker Hub description with internal/DOCKER-README.md (if changed)"
