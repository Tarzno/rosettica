#!/bin/bash
# Builds dist/Rosettica.saver, an Apple silicon (arm64) macOS screensaver
# bundle. SPM cannot emit loadable bundles, so this compiles the
# core and saver sources directly with swiftc and links them as a Mach-O
# bundle with clang. Pass --install to also copy it to ~/Library/Screen Savers.
set -euo pipefail
cd "$(dirname "$0")/.."

SDK=$(xcrun --show-sdk-path --sdk macosx)
WORK=dist/saver-work
SAVER=dist/Rosettica.saver
SOURCES=(Sources/RosetticaCore/*.swift Sources/RosetticaSaver/*.swift)

rm -rf "$WORK" "$SAVER"
mkdir -p "$WORK" "$SAVER/Contents/MacOS" "$SAVER/Contents/Resources"

for ARCH in arm64; do
  echo "==> Compiling (${ARCH})"
  xcrun swiftc -O -wmo -parse-as-library \
    -module-name RosetticaSaver \
    -target "${ARCH}-apple-macos13.0" -sdk "$SDK" \
    -emit-object -o "$WORK/saver-${ARCH}.o" \
    "${SOURCES[@]}"

  echo "==> Linking loadable bundle (${ARCH})"
  xcrun clang -bundle -target "${ARCH}-apple-macos13.0" -isysroot "$SDK" \
    -o "$WORK/saver-${ARCH}" "$WORK/saver-${ARCH}.o" \
    -framework ScreenSaver -framework AppKit -framework Foundation \
    -framework CoreGraphics \
    -L "$SDK/usr/lib/swift" -L /usr/lib/swift
done

echo "==> Assembling ${SAVER}"
cp "$WORK/saver-arm64" "$SAVER/Contents/MacOS/Rosettica"
cp Resources/Saver-Info.plist "$SAVER/Contents/Info.plist"
# Never ship a binary that names the builder's home folder.
if LC_ALL=C grep -q "$HOME" "$SAVER/Contents/MacOS/Rosettica"; then
  echo "error: the saver binary contains paths under $HOME" >&2
  exit 1
fi
rm -rf "$WORK"

echo "==> Code signing (ad hoc)"
codesign --force -s - "$SAVER"

echo "==> Architectures:"
lipo -archs "$SAVER/Contents/MacOS/Rosettica"
file "$SAVER/Contents/MacOS/Rosettica" | head -1

if [[ "${1:-}" == "--install" ]]; then
  DEST="$HOME/Library/Screen Savers"
  echo "==> Installing to ${DEST}"
  mkdir -p "$DEST"
  rm -rf "$DEST/Rosettica.saver"
  cp -R "$SAVER" "$DEST/"
  # System Settings caches loaded savers aggressively; make it reload.
  killall legacyScreenSaver 2>/dev/null || true
  echo "==> Installed. Select it under System Settings > Screen Saver."
fi

echo "==> Done: ${SAVER}"
