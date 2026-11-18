#!/bin/bash
# Builds Rosettica.app for Apple silicon (arm64 only) into dist/.
# macOS 27 is the last macOS with Intel support, so no x86_64 slice is built.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> Building release binary (arm64)"
swift build -c release --arch arm64

# Ask SwiftPM where it put the product: build directories have moved
# between toolchains (.build/apple → .build/out), and a hard-coded path once
# silently packaged a stale binary.
BINARY="$(swift build -c release --arch arm64 --show-bin-path)/Rosettica"
APP=dist/Rosettica.app

# The License window shows a copy of the license compiled into the binary;
# never ship a bundle whose copy differs from the LICENSE file.
if ! "${BINARY}" --license | diff -q - LICENSE >/dev/null; then
    echo "error: LICENSE differs from License.text in Sources/Rosettica/LicenseView.swift" >&2
    exit 1
fi

echo "==> Assembling ${APP}"
rm -rf "${APP}" dist/icon-work
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
cp Resources/Info.plist "${APP}/Contents/Info.plist"
printf 'APPL????' > "${APP}/Contents/PkgInfo"
cp "${BINARY}" "${APP}/Contents/MacOS/Rosettica"
# Release builds embed absolute build paths (user name, folders) in debug
# info; strip it and refuse to ship a binary that still names $HOME.
strip -S "${APP}/Contents/MacOS/Rosettica"
if LC_ALL=C grep -q "$HOME" "${APP}/Contents/MacOS/Rosettica"; then
    echo "error: the app binary still contains paths under $HOME" >&2
    exit 1
fi

echo "==> Rendering app icon"
swift Scripts/make-icon.swift dist/icon-work
iconutil -c icns dist/icon-work/AppIcon.iconset -o "${APP}/Contents/Resources/AppIcon.icns"
rm -rf dist/icon-work

echo "==> Code signing (ad hoc)"
codesign --force -s - "${APP}"

echo "==> Architectures:"
lipo -archs "${APP}/Contents/MacOS/Rosettica"
echo "==> Done: ${APP}"
