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

VERSION="${1:-145.0.23+ds1}"
CEF_BRANCH="${2:-7632}"
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
echo "==> [1/4] CEF orig.tar.xz"
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

# 2. Chromium component tarballs (from Debian)
#    Downloads Chromium source and creates two MUT components:
#    - orig-chromium.tar.xz (vanilla Chromium source)
#    - orig-chromium-debian.tar.xz (Debian Chromium patches)
echo "==> [2/4] Chromium orig-chromium.tar.xz and orig-chromium-debian.tar.xz"
if [ -f "${PKG}_${VERSION}.orig-chromium.tar.xz" ] && [ -f "${PKG}_${VERSION}.orig-chromium-debian.tar.xz" ]; then
    echo "    Already exists: ${PKG}_${VERSION}.orig-chromium.tar.xz"
    echo "    Already exists: ${PKG}_${VERSION}.orig-chromium-debian.tar.xz"
else
    echo "    Downloading Chromium source from Debian..."

    if [ -n "$CHROMIUM_VERSION" ]; then
        echo "    Requested: chromium=${CHROMIUM_VERSION}"
        APT_SOURCE_CMD="apt-get source --download-only chromium=${CHROMIUM_VERSION}"
    else
        APT_SOURCE_CMD="apt-get source --download-only chromium"
    fi

    if $APT_SOURCE_CMD 2>/dev/null; then
        echo "    Downloaded via apt-get source"
    elif [ -n "$CHROMIUM_VERSION" ]; then
        echo "    apt-get source failed, trying dget..."
        DOWNLOADED=false
        for BASE_URL in "https://deb.debian.org/debian/pool/main/c/chromium" \
                        "https://security.debian.org/debian-security/pool/updates/main/c/chromium"; do
            DSC_URL="${BASE_URL}/chromium_${CHROMIUM_VERSION}.dsc"
            echo "    Trying: $DSC_URL"
            if dget -d "$DSC_URL" 2>/dev/null; then
                DOWNLOADED=true
                break
            fi
        done
        if [ "$DOWNLOADED" = false ]; then
            echo "    ERROR: Could not download Chromium ${CHROMIUM_VERSION}"
            echo "    Find the correct .dsc URL at:"
            echo "      https://security.debian.org/debian-security/pool/updates/main/c/chromium/"
            echo "      https://deb.debian.org/debian/pool/main/c/chromium/"
            exit 1
        fi
    else
        echo "    ERROR: apt-get source failed and no version specified."
        echo "    Please specify Chromium version as third parameter."
        exit 1
    fi

    # Create orig-chromium.tar.xz from vanilla Chromium source
    CHROMIUM_ORIG=$(ls chromium_*.orig.tar.xz 2>/dev/null | head -1)
    if [ -z "$CHROMIUM_ORIG" ]; then
        echo "    ERROR: No chromium orig.tar.xz found after download"
        exit 1
    fi
    mv "$CHROMIUM_ORIG" "${PKG}_${VERSION}.orig-chromium.tar.xz"
    echo "    Created: ${PKG}_${VERSION}.orig-chromium.tar.xz"

    # Create orig-chromium-debian.tar.xz from Debian Chromium patches
    CHROMIUM_DEBIAN=$(ls chromium_*.debian.tar.xz 2>/dev/null | head -1)
    if [ -z "$CHROMIUM_DEBIAN" ]; then
        echo "    ERROR: No chromium debian.tar.xz found after download"
        exit 1
    fi
    rm -rf chromium-debian
    mkdir chromium-debian
    tar -xf "$CHROMIUM_DEBIAN" --strip-components=1 -C chromium-debian
    tar -cJf "${PKG}_${VERSION}.orig-chromium-debian.tar.xz" chromium-debian
    rm -rf chromium-debian "$CHROMIUM_DEBIAN"
    echo "    Created: ${PKG}_${VERSION}.orig-chromium-debian.tar.xz"

    rm -f chromium_*.dsc 2>/dev/null || true
fi
echo ""

# 3. depot-tools component tarball
echo "==> [3/4] depot-tools orig-depot-tools.tar.xz"
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
echo ""
echo "Total size:"
du -ch "${PKG}_${VERSION}".orig*.tar.xz | tail -1
echo ""
echo "Next steps:"
echo "  cd ${PKG}"
echo "  dpkg-source -b ."
echo "  cd .."
echo "  dpkg-source -x ${PKG}_*.dsc build-dir"
echo "  cd build-dir"
echo "  dpkg-buildpackage -us -uc"
