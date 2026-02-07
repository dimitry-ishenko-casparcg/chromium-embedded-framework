#!/bin/bash
# debian/scripts/upgrade-helper.sh
#
# Helper script to update debian/ files when upgrading package versions.
# Run this after get-orig-tarballs.sh has created the new tarballs.
#
# Usage: ./debian/scripts/upgrade-helper.sh CEF_VERSION CHROMIUM_VERSION [CHROMIUM_REV]
#
# Example: ./debian/scripts/upgrade-helper.sh 144.0.7 144.0.7559.109 1
#
# This script updates:
#   - debian/changelog (version only, keeps existing entry for new packages)
#   - debian/rules (CHROMIUM_VERSION, CHROMIUM_DEBIAN_REV)
#   - debian/README.Debian (Chromium and CEF version references)
#   - debian/README.source (Chromium and CEF version references)
#   - debian/libcefN.lintian-overrides (library version in paths)
#   - debian/libcefN-dbgsym.lintian-overrides (renamed on major version change)

set -e

CEF_VERSION="${1:-}"
CHROMIUM_VERSION="${2:-}"
CHROMIUM_REV="${3:-2}"

if [ -z "$CEF_VERSION" ] || [ -z "$CHROMIUM_VERSION" ]; then
    echo "Usage: $0 CEF_VERSION CHROMIUM_VERSION [CHROMIUM_REV]"
    echo ""
    echo "Example: $0 144.0.7 144.0.7559.109 1"
    echo ""
    echo "Arguments:"
    echo "  CEF_VERSION      - New CEF version (e.g., 144.0.7)"
    echo "  CHROMIUM_VERSION - Debian Chromium version (e.g., 144.0.7559.109)"
    echo "  CHROMIUM_REV     - Debian revision (default: 2)"
    exit 1
fi

# Find the debian directory
if [ -d "debian" ]; then
    DEBIAN_DIR="debian"
elif [ -d "chromium-embedded-framework/debian" ]; then
    DEBIAN_DIR="chromium-embedded-framework/debian"
else
    echo "ERROR: Cannot find debian/ directory."
    echo "Run this script from the package directory or its parent."
    exit 1
fi

PKG_DIR=$(dirname "$DEBIAN_DIR")

echo "============================================================"
echo "Updating debian/ files for CEF ${CEF_VERSION}"
echo "Chromium: ${CHROMIUM_VERSION}-${CHROMIUM_REV}"
echo "============================================================"
echo ""

# Get current versions from files
CURRENT_CEF=$(dpkg-parsechangelog -l "${DEBIAN_DIR}/changelog" -S Version 2>/dev/null | cut -d- -f1 || echo "unknown")
CURRENT_CHROMIUM=$(grep "^CHROMIUM_VERSION :=" "${DEBIAN_DIR}/rules" 2>/dev/null | sed 's/.*:= *//' || echo "unknown")

echo "Current versions:"
echo "  CEF: ${CURRENT_CEF}"
echo "  Chromium: ${CURRENT_CHROMIUM}"
echo ""
echo "New versions:"
echo "  CEF: ${CEF_VERSION}"
echo "  Chromium: ${CHROMIUM_VERSION}-${CHROMIUM_REV}"
echo ""

# 1. Update debian/changelog version
echo "==> [1/5] Updating debian/changelog"
if [ "$CURRENT_CEF" != "$CEF_VERSION" ]; then
    # Update the version in the first line of changelog
    sed -i "1s/([^)]*)/($CEF_VERSION-1)/" "${DEBIAN_DIR}/changelog"
    # Update the timestamp
    sed -i "0,/^ -- .*$/s/^ -- \(.*<.*>\)  .*/ -- \1  $(date -R)/" "${DEBIAN_DIR}/changelog"
    echo "    Updated version: ${CURRENT_CEF} -> ${CEF_VERSION}-1"
else
    echo "    Already at version ${CEF_VERSION}"
fi

# 2. Update debian/rules CHROMIUM_VERSION and CHROMIUM_DEBIAN_REV
echo "==> [2/5] Updating debian/rules"
if grep -q "^CHROMIUM_VERSION := " "${DEBIAN_DIR}/rules"; then
    sed -i "s/^CHROMIUM_VERSION := .*/CHROMIUM_VERSION := ${CHROMIUM_VERSION}/" "${DEBIAN_DIR}/rules"
    sed -i "s/^CHROMIUM_DEBIAN_REV := .*/CHROMIUM_DEBIAN_REV := ${CHROMIUM_REV}/" "${DEBIAN_DIR}/rules"
    echo "    Updated CHROMIUM_VERSION: ${CURRENT_CHROMIUM} -> ${CHROMIUM_VERSION}"
    echo "    Updated CHROMIUM_DEBIAN_REV: ${CHROMIUM_REV}"
else
    echo "    WARNING: Could not find CHROMIUM_VERSION in debian/rules"
fi

# Derive CEF major version and branch from version strings
# CEF 144.0.7 -> major=144, Chromium 144.0.7559.109 -> branch=7559
CURRENT_CEF_MAJOR=$(echo "$CURRENT_CEF" | cut -d. -f1)
NEW_CEF_MAJOR=$(echo "$CEF_VERSION" | cut -d. -f1)
CURRENT_BRANCH=$(echo "$CURRENT_CHROMIUM" | cut -d. -f3)
NEW_BRANCH=$(echo "$CHROMIUM_VERSION" | cut -d. -f3)

# Helper: update Chromium and CEF version references in a file
update_version_refs() {
    local file="$1"
    local label="$2"
    if [ ! -f "$file" ]; then
        echo "    Skipped (file not found)"
        return
    fi
    if [ -n "$CURRENT_CHROMIUM" ] && [ "$CURRENT_CHROMIUM" != "unknown" ]; then
        sed -i "s/${CURRENT_CHROMIUM}/${CHROMIUM_VERSION}/g" "$file"
        echo "    Updated Chromium references: ${CURRENT_CHROMIUM} -> ${CHROMIUM_VERSION}"
    fi
    # On major version changes, update CEF major references (e.g., CEF 144 -> 145)
    if [ "$CURRENT_CEF_MAJOR" != "$NEW_CEF_MAJOR" ]; then
        sed -i "s/CEF ${CURRENT_CEF_MAJOR}/CEF ${NEW_CEF_MAJOR}/g" "$file"
        sed -i "s/libcef${CURRENT_CEF_MAJOR}/libcef${NEW_CEF_MAJOR}/g" "$file"
        echo "    Updated CEF major: ${CURRENT_CEF_MAJOR} -> ${NEW_CEF_MAJOR}"
    fi
    if [ "$CURRENT_BRANCH" != "$NEW_BRANCH" ]; then
        sed -i "s/branch ${CURRENT_BRANCH}/branch ${NEW_BRANCH}/g" "$file"
        echo "    Updated branch: ${CURRENT_BRANCH} -> ${NEW_BRANCH}"
    fi
}

# 3. Update debian/README.Debian
echo "==> [3/5] Updating debian/README.Debian"
update_version_refs "${DEBIAN_DIR}/README.Debian" "README.Debian"

# 4. Update debian/README.source
echo "==> [4/5] Updating debian/README.source"
update_version_refs "${DEBIAN_DIR}/README.source" "README.source"

# 5. Update lintian-overrides files
echo "==> [5/5] Updating lintian-overrides"
for LINTIAN_FILE in "${DEBIAN_DIR}/libcef${CURRENT_CEF_MAJOR}.lintian-overrides" \
                    "${DEBIAN_DIR}/libcef${CURRENT_CEF_MAJOR}-dbgsym.lintian-overrides"; do
    if [ -f "$LINTIAN_FILE" ]; then
        # Update CEF version in library paths (e.g., libcef.so.144.0.7 -> libcef.so.145.0.1)
        if [ -n "$CURRENT_CEF" ] && [ "$CURRENT_CEF" != "unknown" ]; then
            sed -i "s/libcef\.so\.${CURRENT_CEF}/libcef.so.${CEF_VERSION}/g" "$LINTIAN_FILE"
        fi
        # On major version change, update package name references and rename file
        if [ "$CURRENT_CEF_MAJOR" != "$NEW_CEF_MAJOR" ]; then
            sed -i "s/libcef${CURRENT_CEF_MAJOR}/libcef${NEW_CEF_MAJOR}/g" "$LINTIAN_FILE"
            NEW_LINTIAN_FILE=$(echo "$LINTIAN_FILE" | sed "s/libcef${CURRENT_CEF_MAJOR}/libcef${NEW_CEF_MAJOR}/")
            mv "$LINTIAN_FILE" "$NEW_LINTIAN_FILE"
            echo "    Renamed: $(basename "$LINTIAN_FILE") -> $(basename "$NEW_LINTIAN_FILE")"
        fi
        echo "    Updated: $(basename "${LINTIAN_FILE}")"
    fi
done

echo ""
echo "============================================================"
echo "Summary of changes"
echo "============================================================"
cd "$PKG_DIR"
git diff --stat debian/ 2>/dev/null || echo "(not a git repository)"
echo ""
echo "Review changes with: git diff debian/"
echo ""
echo "Next steps:"
echo "  cd ${PKG_DIR}"
echo "  dpkg-buildpackage -us -uc  # Build binary packages"
