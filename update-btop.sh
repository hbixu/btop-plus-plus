#!/bin/bash
#
# update-btop.sh - Check for a newer btop++ release and (optionally) build/push a new image
#
# Flow:
#   1. Reads the current btop++ and image versions from build.sh
#   2. Checks the latest btop++ release on GitHub
#   3. If newer: asks whether to build a new image (and which image version to use)
#   4. Asks whether to push the image to a registry (multi-platform) or build locally
#   5. Runs build.sh; on success updates build.sh, Dockerfile, VERSIONS.md,
#      CHANGELOG.md and internal/DOCKER-README.md with the new versions
#
# Nothing is committed: review the changes with `git diff`, then run ./release.sh.
#
# Usage: ./update-btop.sh [--force] [--registry REGISTRY]
#   --force              Offer to build even if btop++ is already up to date
#   --registry REGISTRY  Default registry for push (default: docker.io/hbixu)

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_SH="$SCRIPT_DIR/build.sh"
DOCKERFILE="$SCRIPT_DIR/Dockerfile"
VERSIONS_MD="$SCRIPT_DIR/VERSIONS.md"
CHANGELOG_MD="$SCRIPT_DIR/CHANGELOG.md"
DOCKER_README="$SCRIPT_DIR/internal/DOCKER-README.md"

FORCE=false
DEFAULT_PUSH_REGISTRY="docker.io/hbixu"

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --registry)
            DEFAULT_PUSH_REGISTRY="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1 (use --help)"
            exit 1
            ;;
    esac
done

# ============================================================================
# Helpers
# ============================================================================

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

# ask_value "Question" "default" -> prints the answer
ask_value() {
    local question="$1"
    local default="$2"
    local answer
    read -r -p "$question [$default]: " answer || answer=""
    echo "${answer:-$default}"
}

get_default_value() {
    grep "^$1=" "$BUILD_SH" | head -1 | cut -d'=' -f2 | cut -d'#' -f1 | tr -d '"' | xargs
}

# Portable in-place sed (GNU and BSD)
sed_in_place() {
    local expr="$1" file="$2" tmp
    tmp=$(mktemp)
    sed "$expr" "$file" > "$tmp" && cat "$tmp" > "$file"
    rm -f "$tmp"
}

# Insert a line after the first line matching a regex (if the file exists)
insert_after_match() {
    local file="$1" pattern="$2" new_line="$3" tmp
    [ -f "$file" ] || return 0
    tmp=$(mktemp)
    awk -v pat="$pattern" -v line="$new_line" '
        { print }
        !done && $0 ~ pat { print line; done=1 }
    ' "$file" > "$tmp" && cat "$tmp" > "$file"
    rm -f "$tmp"
}

# Latest version of an Alpine package in a branch (e.g. 3.24)
resolve_alpine_package() {
    local pkg_name="$1" branch="$2"
    curl -sf "https://dl-cdn.alpinelinux.org/alpine/v${branch}/community/x86_64/APKINDEX.tar.gz" 2>/dev/null | \
        tar -xzO APKINDEX 2>/dev/null | \
        awk -v p="$pkg_name" '/^P:/{n=substr($0,3)} /^V:/{if(n==p){print substr($0,3); exit}}' || true
}

# Suggest next image version: bump minor (1.0.0 -> 1.1.0)
next_minor_version() {
    local major minor
    IFS='.' read -r major minor _ <<< "$1"
    echo "${major}.$((minor + 1)).0"
}

# ============================================================================
# 1. Current versions
# ============================================================================

if [ ! -f "$BUILD_SH" ]; then
    echo -e "${RED}ERROR: build.sh not found at $BUILD_SH${NC}"
    exit 1
fi

CURRENT_IMAGE_VERSION=$(get_default_value "DEFAULT_VERSION")
CURRENT_BTOP=$(get_default_value "DEFAULT_BTOP_VERSION")
ALPINE_VERSION=$(get_default_value "DEFAULT_ALPINE_VERSION")
ALPINE_BRANCH=$(echo "$ALPINE_VERSION" | cut -d'.' -f1,2)

echo -e "${BLUE}=== btop++ update check ===${NC}"
echo "Image version: $CURRENT_IMAGE_VERSION"
echo "btop++:        $CURRENT_BTOP"
echo "Alpine:        $ALPINE_VERSION"
echo ""

# ============================================================================
# 2. Latest btop++ release
# ============================================================================

LATEST_BTOP=$(curl -s "https://api.github.com/repos/aristocratos/btop/releases/latest" 2>/dev/null | \
    grep '"tag_name"' | head -1 | cut -d'"' -f4 | sed 's/^v//' || true)

if [ -z "$LATEST_BTOP" ]; then
    echo -e "${RED}ERROR: Could not fetch the latest btop++ release (API rate limit?)${NC}"
    echo "Manual check: https://github.com/aristocratos/btop/releases"
    exit 1
fi

echo "Latest btop++ release: $LATEST_BTOP"

if [ "$LATEST_BTOP" = "$CURRENT_BTOP" ]; then
    echo -e "${GREEN}btop++ is up to date.${NC}"
    if [ "$FORCE" = false ]; then
        exit 0
    fi
    echo ""
elif [ "$(printf '%s\n%s\n' "$CURRENT_BTOP" "$LATEST_BTOP" | sort -V | tail -1)" = "$LATEST_BTOP" ]; then
    echo -e "${YELLOW}New btop++ version available: $CURRENT_BTOP → $LATEST_BTOP${NC}"
    echo "Release notes: https://github.com/aristocratos/btop/releases/tag/v$LATEST_BTOP"
    echo ""
else
    echo -e "${YELLOW}build.sh uses $CURRENT_BTOP, which is newer than the latest release ($LATEST_BTOP).${NC}"
    if [ "$FORCE" = false ]; then
        exit 0
    fi
fi

# ============================================================================
# 3. Build a new image?
# ============================================================================

if ! ask_yes_no "Build a new image with btop++ $LATEST_BTOP?" "y"; then
    echo "Nothing to do."
    exit 0
fi

SUGGESTED_VERSION=$(next_minor_version "$CURRENT_IMAGE_VERSION")
while true; do
    NEW_IMAGE_VERSION=$(ask_value "New image version" "$SUGGESTED_VERSION")
    if [[ "$NEW_IMAGE_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        break
    fi
    echo "Invalid version (expected MAJOR.MINOR.PATCH, e.g. $SUGGESTED_VERSION)."
done

# Resolve ttyd now so the same version is built and documented
TTYD_VERSION=$(resolve_alpine_package "ttyd" "$ALPINE_BRANCH")

# ============================================================================
# 4. Push to registry?
# ============================================================================

PUSH=false
REGISTRY=""
if ask_yes_no "Push the image to a registry (linux/amd64 + linux/arm64)?" "n"; then
    PUSH=true
    REGISTRY=$(ask_value "Registry" "$DEFAULT_PUSH_REGISTRY")
fi

echo ""
echo -e "${BLUE}=== Summary ===${NC}"
echo "Image version: $CURRENT_IMAGE_VERSION → $NEW_IMAGE_VERSION"
echo "btop++:        $CURRENT_BTOP → $LATEST_BTOP"
echo "Alpine:        $ALPINE_VERSION"
echo "ttyd:          ${TTYD_VERSION:-latest from Alpine repo}"
if [ "$PUSH" = true ]; then
    echo "Mode:          build and push to $REGISTRY (multi-platform)"
else
    echo "Mode:          local build"
fi
echo ""

if ! ask_yes_no "Continue?" "y"; then
    echo "Cancelled."
    exit 0
fi

# ============================================================================
# 5. Build (and push)
# ============================================================================

BUILD_ARGS=(--version "$NEW_IMAGE_VERSION" --btop-version "$LATEST_BTOP")
[ -n "$TTYD_VERSION" ] && BUILD_ARGS+=(--ttyd-version "$TTYD_VERSION")
if [ "$PUSH" = true ]; then
    BUILD_ARGS+=(--registry "$REGISTRY" --push)
    echo -e "${YELLOW}Make sure you are logged in to the registry (docker login).${NC}"
fi

echo ""
if ! bash "$BUILD_SH" "${BUILD_ARGS[@]}"; then
    echo ""
    echo -e "${RED}Build failed. No files were changed.${NC}"
    exit 1
fi

# ============================================================================
# 6. Update project files with the new versions
# ============================================================================

echo ""
echo -e "${BLUE}=== Updating project files ===${NC}"

TODAY=$(date +%Y-%m-%d)
TTYD_DOC="${TTYD_VERSION:-latest}"

# build.sh defaults
sed_in_place "s/^DEFAULT_VERSION=\"[^\"]*\"/DEFAULT_VERSION=\"$NEW_IMAGE_VERSION\"/" "$BUILD_SH"
sed_in_place "s/^DEFAULT_BTOP_VERSION=\"[^\"]*\"/DEFAULT_BTOP_VERSION=\"$LATEST_BTOP\"/" "$BUILD_SH"
echo "  build.sh"

# Dockerfile defaults
sed_in_place "s/^ARG BTOP_VERSION=.*/ARG BTOP_VERSION=$LATEST_BTOP/" "$DOCKERFILE"
sed_in_place "s/^ARG VERSION=.*/ARG VERSION=$NEW_IMAGE_VERSION/" "$DOCKERFILE"
echo "  Dockerfile"

# VERSIONS.md: default version + new row at the top of the history table
sed_in_place "s/(default: \`$CURRENT_IMAGE_VERSION\`)/(default: \`$NEW_IMAGE_VERSION\`)/" "$VERSIONS_MD"
insert_after_match "$VERSIONS_MD" '^[|]:-+:[|]' "| \`$NEW_IMAGE_VERSION\` | \`$ALPINE_VERSION\` | \`$LATEST_BTOP\` | \`$TTYD_DOC\` |"
echo "  VERSIONS.md"

# internal/DOCKER-README.md: new row at the top of the image versions table
if [ -f "$DOCKER_README" ]; then
    tmp=$(mktemp)
    awk -v line="| \`$NEW_IMAGE_VERSION\`   | \`$ALPINE_VERSION\` | \`$LATEST_BTOP\` | \`$TTYD_DOC\` |" '
        { print }
        !done && prev ~ /^[|] Image tag/ && $0 ~ /^[|]-/ { print line; done=1 }
        { prev = $0 }
    ' "$DOCKER_README" > "$tmp" && cat "$tmp" > "$DOCKER_README"
    rm -f "$tmp"
    echo "  internal/DOCKER-README.md"
fi

# CHANGELOG.md: new entry before the first release
if [ -f "$CHANGELOG_MD" ]; then
    tmp=$(mktemp)
    awk -v ver="$NEW_IMAGE_VERSION" -v date="$TODAY" -v old="$CURRENT_BTOP" -v new="$LATEST_BTOP" '
        !done && /^## \[/ {
            print "## [" ver "] - " date
            print ""
            print "### Changed"
            print "- btop++: " old " → " new
            print ""
            print "---"
            print ""
            done=1
        }
        { print }
    ' "$CHANGELOG_MD" > "$tmp" && cat "$tmp" > "$CHANGELOG_MD"
    rm -f "$tmp"
    echo "  CHANGELOG.md"
fi

echo ""
echo -e "${GREEN}=== Done ===${NC}"
if [ "$PUSH" = true ]; then
    echo "Image pushed: ${REGISTRY%/}/btop-plus-plus:$NEW_IMAGE_VERSION (and :latest)"
    if [ -f "$DOCKER_README" ]; then
        echo "Remember to update the Docker Hub description with internal/DOCKER-README.md"
    fi
else
    echo "Image built locally: btop-plus-plus:$NEW_IMAGE_VERSION (and :latest)"
fi
echo ""
echo "Next steps:"
echo "  git diff        # review the changes"
echo "  ./release.sh    # commit, tag v$NEW_IMAGE_VERSION and push"
