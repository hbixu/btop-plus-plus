#!/bin/bash
#
# release-notes.sh - Print the release notes (markdown) for a version
#
# Content:
#   - The version's section from CHANGELOG.md
#   - The version's row from the "Version History" table in VERSIONS.md (with the table header)
#
# Usage: .gitea/scripts/release-notes.sh 1.0.0   (also accepts v1.0.0)
# Run from the repository root.

set -e

VERSION="${1#v}"
if [ -z "$VERSION" ]; then
    echo "Usage: $0 VERSION" >&2
    exit 1
fi

# CHANGELOG.md: lines after "## [VERSION]" until the next "---" or "## [" (blank lines trimmed)
changes=$(awk -v ver="$VERSION" '
    index($0, "## [" ver "]") == 1 { found=1; next }
    found && (/^---/ || /^## \[/) { exit }
    found { print }
' CHANGELOG.md | sed -e '/./,$!d' | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}')

# VERSIONS.md: header + separator of the version table, and the row of this version
table=$(awk -v ver="$VERSION" '
    /^\| Release \|/ { header=$0; getline sep; next }
    header && index($0, "| `" ver "` |") == 1 { print header; print sep; print; exit }
' VERSIONS.md)

if [ -z "$changes" ] && [ -z "$table" ]; then
    echo "No CHANGELOG.md entry or VERSIONS.md row found for $VERSION" >&2
    exit 1
fi

if [ -n "$changes" ]; then
    echo "$changes"
    echo ""
fi
if [ -n "$table" ]; then
    echo "### Versions"
    echo ""
    echo "$table"
fi
