#!/usr/bin/env bash
# Builds "Home Widgets.app" into ./build using Swift Package Manager.
# Works with either full Xcode or just the Command Line Tools (xcode-select --install).
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="Home Widgets"
EXECUTABLE="HomeWidgets"
OUT_DIR="build"
APP="$OUT_DIR/$APP_NAME.app"

ARCH_ARGS=()
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  ARCH_ARGS=(--arch arm64 --arch x86_64)
fi

echo "› Compiling (release, optimised for size)…"
swift build -c release -Xswiftc -Osize ${ARCH_ARGS[@]+"${ARCH_ARGS[@]}"}
BIN_DIR="$(swift build -c release ${ARCH_ARGS[@]+"${ARCH_ARGS[@]}"} --show-bin-path)"

echo "› Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
# Keep Spotlight out of ./build so it never lists a second "Home Widgets".
touch "$OUT_DIR/.metadata_never_index"
cp "$BIN_DIR/$EXECUTABLE" "$APP/Contents/MacOS/$EXECUTABLE"
# Debug symbols are two thirds of the binary and never used by the app.
strip -x "$APP/Contents/MacOS/$EXECUTABLE"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [[ -f Resources/AppIcon.icns ]]; then
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "› Signing (ad-hoc)"
codesign --force --sign - --timestamp=none "$APP"

echo "✓ Built $APP"
