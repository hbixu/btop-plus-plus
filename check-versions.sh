#!/bin/bash
#
# check-versions.sh - Update checker for btop-plus-plus
#
# Purpose: Compare currently pinned versions (from build.sh) against the latest
#          available versions and report whether newer versions exist.
#
# Requirements: curl, tar, network access (Docker is NOT required)
#
# This script is READ-ONLY and does not modify any files.
# Exit codes: 0 = all up to date, 1 = newer versions available

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_SH="$SCRIPT_DIR/build.sh"

# Counters for summary
NEWER_BASE_IMAGE=0
NEW_BASE_LINE=0
NEWER_ALPINE=0
NEWER_GITHUB=0

echo -e "${BLUE}=== Checking for updates ===${NC}"
echo "Reading current versions from build.sh..."
echo ""

# ============================================================================
# Extract current versions from build.sh
# ============================================================================

if [ ! -f "$BUILD_SH" ]; then
    echo -e "${RED}ERROR: build.sh not found at $BUILD_SH${NC}"
    exit 1
fi

# Parse DEFAULT_* variables from build.sh
get_default_value() {
    local var_name="$1"
    grep "^${var_name}=" "$BUILD_SH" | head -1 | cut -d'=' -f2 | cut -d'#' -f1 | tr -d '"' | xargs
}

CURRENT_ALPINE=$(get_default_value "DEFAULT_ALPINE_VERSION")
CURRENT_BTOP=$(get_default_value "DEFAULT_BTOP_VERSION")

# Extract base line (e.g., "3.24" from "3.24.4")
CURRENT_BASE_LINE=$(echo "$CURRENT_ALPINE" | cut -d'.' -f1,2)

echo "Current versions from build.sh:"
echo "  Alpine: $CURRENT_ALPINE (line $CURRENT_BASE_LINE)"
echo "  btop++: $CURRENT_BTOP"
echo "  ttyd: (not pinned - latest in Alpine branch)"
echo ""

# ============================================================================
# Base Image Check
# ============================================================================

echo -e "${BLUE}--- Base Image ---${NC}"
echo "alpine (Docker Hub)"
echo "  Current: $CURRENT_ALPINE"

check_base_image() {
    local tags
    tags=$(curl -s "https://hub.docker.com/v2/repositories/library/alpine/tags?page_size=100" 2>/dev/null | \
        grep -oE '"name":"[0-9]+\.[0-9]+\.[0-9]+"' | cut -d'"' -f4 | sort -uV || echo "")

    if [ -z "$tags" ]; then
        echo -e "  ${YELLOW}WARNING: Could not fetch tags from Docker Hub${NC}"
        echo "  Manual check: https://hub.docker.com/_/alpine/tags"
        return
    fi

    # Latest patch in the same line (e.g., 3.24.x)
    local same_line_latest
    same_line_latest=$(echo "$tags" | grep "^${CURRENT_BASE_LINE}\." | tail -1)

    if [ -z "$same_line_latest" ]; then
        echo "  Same line ($CURRENT_BASE_LINE): $CURRENT_ALPINE (no newer found)"
    elif [ "$same_line_latest" = "$CURRENT_ALPINE" ]; then
        echo -e "  Same line ($CURRENT_BASE_LINE): $same_line_latest ${GREEN}(up to date)${NC}"
    else
        echo -e "  Same line ($CURRENT_BASE_LINE): current $CURRENT_ALPINE → available $same_line_latest ${YELLOW}(NEWER)${NC}"
        NEWER_BASE_IMAGE=1
    fi

    # New base line (e.g., 3.25.x)
    local latest
    latest=$(echo "$tags" | tail -1)
    local latest_line
    latest_line=$(echo "$latest" | cut -d'.' -f1,2)

    if [ "$latest_line" != "$CURRENT_BASE_LINE" ]; then
        echo -e "  ${YELLOW}New base line available: $latest (consider migrating)${NC}"
        NEW_BASE_LINE=1
    else
        echo "  No new base line available beyond $CURRENT_BASE_LINE"
    fi
}

check_base_image
echo ""

# ============================================================================
# Alpine Packages Check
# ============================================================================

echo -e "${BLUE}--- Alpine Packages (v$CURRENT_BASE_LINE) ---${NC}"

# Download the community APKINDEX once (no Docker needed)
APKINDEX=$(curl -s "https://dl-cdn.alpinelinux.org/alpine/v${CURRENT_BASE_LINE}/community/x86_64/APKINDEX.tar.gz" 2>/dev/null | \
    tar -xzO APKINDEX 2>/dev/null || echo "")

check_alpine_package() {
    local pkg_name="$1"
    local current_version="$2"
    local available=""

    if [ -n "$APKINDEX" ]; then
        available=$(echo "$APKINDEX" | awk -v p="$pkg_name" '/^P:/{n=substr($0,3)} /^V:/{if(n==p){print substr($0,3); exit}}')
    fi

    if [ -z "$available" ]; then
        echo -e "${pkg_name}: current ${current_version:-"(latest)"} → ${YELLOW}could not fetch available version${NC}"
        echo "  Manual check: https://pkgs.alpinelinux.org/packages?name=${pkg_name}&branch=v${CURRENT_BASE_LINE}"
        return
    fi

    if [ -z "$current_version" ]; then
        echo -e "${pkg_name}: current (latest) → available $available ${GREEN}(using latest)${NC}"
    elif [ "$current_version" = "$available" ]; then
        echo -e "${pkg_name}: current $current_version → available $available ${GREEN}(up to date)${NC}"
    else
        echo -e "${pkg_name}: current $current_version → available $available ${YELLOW}(NEWER)${NC}"
        NEWER_ALPINE=$((NEWER_ALPINE + 1))
    fi
}

check_alpine_package "ttyd" ""
echo ""

# ============================================================================
# GitHub Components Check
# ============================================================================

echo -e "${BLUE}--- GitHub Components ---${NC}"

check_github_release() {
    local component_name="$1"
    local repo="$2"
    local current_version="$3"

    local latest
    latest=$(curl -s "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null | \
        grep '"tag_name"' | head -1 | cut -d'"' -f4 | sed 's/^v//' || echo "")

    if [ -z "$latest" ]; then
        echo -e "${component_name}: current $current_version → ${YELLOW}could not fetch latest (API rate limit?)${NC}"
        echo "  Manual check: https://github.com/${repo}/releases"
        return
    fi

    if [ "${current_version#v}" = "$latest" ]; then
        echo -e "${component_name}: current $current_version → latest $latest ${GREEN}(up to date)${NC}"
    else
        echo -e "${component_name}: current $current_version → latest $latest ${YELLOW}(NEWER)${NC}"
        NEWER_GITHUB=$((NEWER_GITHUB + 1))
    fi
}

check_github_release "btop++" "aristocratos/btop" "$CURRENT_BTOP"
echo ""

# ============================================================================
# Summary
# ============================================================================

echo -e "${BLUE}=== Summary ===${NC}"

TOTAL_NEWER=$((NEWER_BASE_IMAGE + NEW_BASE_LINE + NEWER_ALPINE + NEWER_GITHUB))

[ $NEWER_BASE_IMAGE -gt 0 ] && echo -e "${YELLOW}Base image has a newer version available.${NC}"
[ $NEW_BASE_LINE -gt 0 ] && echo -e "${YELLOW}A new Alpine line is available (migration recommended; re-check package versions).${NC}"
[ $NEWER_ALPINE -gt 0 ] && echo -e "${YELLOW}$NEWER_ALPINE Alpine package(s) have newer versions.${NC}"
[ $NEWER_GITHUB -gt 0 ] && echo -e "${YELLOW}$NEWER_GITHUB GitHub component(s) have newer versions.${NC}"

if [ $TOTAL_NEWER -eq 0 ]; then
    echo -e "${GREEN}All components are up to date.${NC}"
    exit 0
else
    echo ""
    echo "Consider updating build.sh and releasing a new image."
    exit 1
fi
