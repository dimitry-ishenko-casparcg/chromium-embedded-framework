#!/bin/bash
# debian/scripts/get-orig-tarballs.sh
#
# Helper script to obtain MUT (Multiple Upstream Tarballs) component tarballs
# for chromium-embedded-framework.
#
# This script is provided for Debian Developers who need to recreate the
# orig tarballs from upstream sources. Once the package is in the Debian
# archive, use 'apt-get source' or 'dget' instead.
#
# Usage: ./debian/scripts/get-orig-tarballs.sh [VERSION] [CEF_BRANCH] [CHROMIUM_VERSION]
#
# Run from the PARENT directory of the package source.

set -e

VERSION="${1:-144.0.7}"
CEF_BRANCH="${2:-7559}"
CHROMIUM_VERSION="${3:-}"
PKG="chromium-embedded-framework"

echo "============================================================"
echo "Obtaining MUT tarballs for ${PKG} ${VERSION}"
echo "============================================================"
echo ""

# Check we're in the right directory
if [ ! -d "${PKG}" ] && [ ! -d "debian" ]; then
    echo "Run this script from the parent directory of the package,"
    echo "or from within the package directory."
    echo ""
    echo "Usage: ./debian/scripts/get-orig-tarballs.sh [VERSION] [CEF_BRANCH]"
    exit 1
fi

# If we're inside the package, go to parent
if [ -d "debian" ]; then
    cd ..
fi

# 1. CEF main tarball
echo "==> [1/3] CEF orig.tar.xz"
if [ -f "${PKG}_${VERSION}.orig.tar.xz" ]; then
    echo "    Already exists: ${PKG}_${VERSION}.orig.tar.xz"
else
    echo "    Cloning CEF branch ${CEF_BRANCH} from Bitbucket..."
    rm -rf cef-tmp
    git clone --depth 1 --branch "${CEF_BRANCH}" \
        https://bitbucket.org/chromiumembedded/cef.git cef-tmp

    # Package expects cef/ subdirectory inside tarball
    mkdir -p "${PKG}-${VERSION}"
    mv cef-tmp "${PKG}-${VERSION}/cef"

    echo "    Creating tarball..."
    tar --exclude='.git' -cJf "${PKG}_${VERSION}.orig.tar.xz" "${PKG}-${VERSION}"
    rm -rf "${PKG}-${VERSION}"
    echo "    Created: ${PKG}_${VERSION}.orig.tar.xz"
fi
echo ""

# 2. Chromium component tarball (from Debian)
echo "==> [2/3] Chromium orig-chromium.tar.xz (from Debian)"
if [ -f "${PKG}_${VERSION}.orig-chromium.tar.xz" ]; then
    echo "    Already exists: ${PKG}_${VERSION}.orig-chromium.tar.xz"
else
    echo "    Downloading Chromium source from Debian..."

    # Download specific version if provided, otherwise latest
    if [ -n "$CHROMIUM_VERSION" ]; then
        echo "    Requested: chromium=${CHROMIUM_VERSION}"
        APT_SOURCE_CMD="apt-get source --download-only chromium=${CHROMIUM_VERSION}"
    else
        APT_SOURCE_CMD="apt-get source --download-only chromium"
    fi

    if $APT_SOURCE_CMD 2>/dev/null; then
        echo "    Downloaded via apt-get source"
    elif [ -n "$CHROMIUM_VERSION" ]; then
        # Fallback: try dget from Debian servers
        echo "    apt-get source failed, trying dget..."
        CHROMIUM_BASE_VER=$(echo "$CHROMIUM_VERSION" | sed 's/~.*//')
        DOWNLOADED=false

        # Try security.debian.org first (often has newer versions)
        for SUFFIX in "~deb13u1" "~deb12u1" ""; do
            DSC_URL="https://security.debian.org/debian-security/pool/updates/main/c/chromium/chromium_${CHROMIUM_BASE_VER}${SUFFIX}.dsc"
            echo "    Trying: $DSC_URL"
            if dget -d "$DSC_URL" 2>/dev/null; then
                DOWNLOADED=true
                break
            fi
        done

        # Try main Debian archive if security failed
        if [ "$DOWNLOADED" = false ]; then
            for SUFFIX in "~deb13u1" "~deb12u1" ""; do
                DSC_URL="https://deb.debian.org/debian/pool/main/c/chromium/chromium_${CHROMIUM_BASE_VER}${SUFFIX}.dsc"
                echo "    Trying: $DSC_URL"
                if dget -d "$DSC_URL" 2>/dev/null; then
                    DOWNLOADED=true
                    break
                fi
            done
        fi

        if [ "$DOWNLOADED" = false ]; then
            echo "    ERROR: Could not download Chromium ${CHROMIUM_VERSION}"
            echo ""
            echo "    Find the correct .dsc URL at:"
            echo "      https://security.debian.org/debian-security/pool/updates/main/c/chromium/"
            echo "      https://deb.debian.org/debian/pool/main/c/chromium/"
            echo ""
            echo "    Then run: dget -d <URL>"
            exit 1
        fi
    else
        echo "    ERROR: apt-get source failed and no version specified."
        echo "    Please specify Chromium version as third parameter."
        exit 1
    fi

    CHROMIUM_ORIG=$(ls chromium_*.orig.tar.xz 2>/dev/null | head -1)
    CHROMIUM_DEBIAN=$(ls chromium_*.debian.tar.xz 2>/dev/null | head -1)
    if [ -n "$CHROMIUM_ORIG" ]; then
        mv "$CHROMIUM_ORIG" "${PKG}_${VERSION}.orig-chromium.tar.xz"
        echo "    Created: ${PKG}_${VERSION}.orig-chromium.tar.xz"

        if [ -n "$CHROMIUM_DEBIAN" ]; then
            echo "    Kept: ${CHROMIUM_DEBIAN} (needed for build)"
        fi
        rm -f chromium_*.dsc 2>/dev/null || true
    else
        echo "    ERROR: No chromium orig.tar.xz found after download"
        exit 1
    fi
fi
echo ""

# 3. depot-tools component tarball
echo "==> [3/3] depot-tools orig-depot-tools.tar.xz"
if [ -f "${PKG}_${VERSION}.orig-depot-tools.tar.xz" ]; then
    echo "    Already exists: ${PKG}_${VERSION}.orig-depot-tools.tar.xz"
else
    echo "    Cloning depot_tools from Google..."
    rm -rf depot-tools
    git clone --depth 1 \
        https://chromium.googlesource.com/chromium/tools/depot_tools.git depot-tools

    # Clean binaries (matching Files-Excluded in debian/copyright)
    echo "    Cleaning binary files..."
    cd depot-tools
    rm -rf .git
    rm -f *.exe *.bat 2>/dev/null || true
    rm -rf win_tools* 2>/dev/null || true
    rm -rf .cipd_bin/*.exe .cipd_bin/*.dll 2>/dev/null || true
    find . -name "*.exe" -delete 2>/dev/null || true
    find . -name "*.dll" -delete 2>/dev/null || true
    cd ..

    echo "    Creating tarball..."
    tar -cJf "${PKG}_${VERSION}.orig-depot-tools.tar.xz" depot-tools
    rm -rf depot-tools
    echo "    Created: ${PKG}_${VERSION}.orig-depot-tools.tar.xz"
fi
echo ""

echo "============================================================"
echo "Summary"
echo "============================================================"
ls -lh "${PKG}_${VERSION}".orig*.tar.xz

# Detect Chromium version from debian.tar.xz filename
CHROMIUM_DEBIAN_TAR=$(ls chromium_*.debian.tar.xz 2>/dev/null | head -1)
if [ -n "$CHROMIUM_DEBIAN_TAR" ]; then
    ls -lh "$CHROMIUM_DEBIAN_TAR"
    # Extract version: chromium_144.0.7559.109-1.debian.tar.xz -> 144.0.7559.109-1
    CHROMIUM_FULL_VER=$(echo "$CHROMIUM_DEBIAN_TAR" | sed 's/chromium_\(.*\)\.debian\.tar\.xz/\1/')
    # Split into version and revision: 144.0.7559.109-1 -> 144.0.7559.109 and 1
    CHROMIUM_VER=$(echo "$CHROMIUM_FULL_VER" | cut -d- -f1)
    CHROMIUM_REV=$(echo "$CHROMIUM_FULL_VER" | cut -d- -f2)
fi
echo ""
echo "Total size:"
du -ch "${PKG}_${VERSION}".orig*.tar.xz | tail -1
echo ""

if [ -n "$CHROMIUM_VER" ]; then
    echo "Detected Chromium version: ${CHROMIUM_VER}-${CHROMIUM_REV}"
    echo ""
fi

echo "Next steps:"
echo "  1. Update debian/ files with version references:"
echo "     ./${PKG}/debian/scripts/upgrade-helper.sh ${VERSION} ${CHROMIUM_VER:-CHROMIUM_VERSION} ${CHROMIUM_REV:-DEBIAN_REV}"
echo ""
echo "  2. Build the package:"
echo "     cd ${PKG}"
echo "     debuild -S -sa          # Create signed source package for mentors"
echo "     debuild -S -sa -us -uc  # Create unsigned source package"
echo "     dpkg-buildpackage -us -uc  # Build binary packages"
