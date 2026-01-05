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
# Usage: ./debian/scripts/get-orig-tarballs.sh [VERSION]
#
# Run from the PARENT directory of the package source.

set -e

VERSION="${1:-138.0.1}"
CEF_BRANCH="${2:-7499}"
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

    # Try apt-get source first
    if apt-get source --download-only chromium 2>/dev/null; then
        CHROMIUM_ORIG=$(ls chromium_*.orig.tar.xz 2>/dev/null | head -1)
        if [ -n "$CHROMIUM_ORIG" ]; then
            mv "$CHROMIUM_ORIG" "${PKG}_${VERSION}.orig-chromium.tar.xz"
            rm -f chromium_*.dsc chromium_*.debian.tar.xz 2>/dev/null || true
            echo "    Created: ${PKG}_${VERSION}.orig-chromium.tar.xz"
        fi
    else
        echo "    ERROR: Could not download Chromium source."
        echo "    Make sure you have 'deb-src' lines in /etc/apt/sources.list"
        echo "    and run 'apt-get update' first."
        echo ""
        echo "    Alternatively, download manually from:"
        echo "    https://deb.debian.org/debian/pool/main/c/chromium/"
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
echo ""
echo "Total size:"
du -ch "${PKG}_${VERSION}".orig*.tar.xz | tail -1
echo ""
echo "Next steps:"
echo "  cd ${PKG}"
echo "  debuild -S -sa        # Create signed source package for mentors"
echo "  debuild -S -sa -us -uc  # Create unsigned source package"
echo "  dpkg-buildpackage -us -uc  # Build binary packages"
