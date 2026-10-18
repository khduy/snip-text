#!/bin/zsh
# Builds SnipText.app into ./build.
#   scripts/build-app.sh [debug|release]
# Environment:
#   UNIVERSAL=1        build for arm64 + x86_64
#   VERSION=1.2.3      stamp the version into Info.plist
#   SIGN_IDENTITY=...  signing identity (default: project-local "SnipText Dev", else ad-hoc)
#   SIGN_KEYCHAIN=...  keychain holding SIGN_IDENTITY (used by CI)
set -euo pipefail

CONFIG=${1:-release}
ROOT=${0:A:h:h}
APP="$ROOT/build/SnipText.app"

# Use full Xcode even when xcode-select points at the Command Line Tools.
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

BUILD_ARGS=(-c "$CONFIG")
if [[ "${UNIVERSAL:-0}" == 1 ]]; then
  BUILD_ARGS+=(--arch arm64 --arch x86_64)
fi

cd "$ROOT"
swift build "${BUILD_ARGS[@]}"
BIN_DIR=$(swift build "${BUILD_ARGS[@]}" --show-bin-path)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/SnipText" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
for bundle in "$BIN_DIR"/*.bundle(N); do
  cp -R "$bundle" "$APP/Contents/Resources/"
done

if [[ -n "${VERSION:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP/Contents/Info.plist"
fi

# Signing with the same certificate every time keeps the Screen Recording permission across
# rebuilds and updates; ad-hoc signing changes the code hash, so macOS treats each build as new.
# Run scripts/setup-signing.sh once to create the project-local "SnipText Dev" identity.
LOCAL_KEYCHAIN="$ROOT/.signing/sniptext-dev.keychain-db"
SIGN_ARGS=()
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  IDENTITY=$SIGN_IDENTITY
  [[ -n "${SIGN_KEYCHAIN:-}" ]] && SIGN_ARGS=(--keychain "$SIGN_KEYCHAIN")
elif [[ -f "$LOCAL_KEYCHAIN" ]]; then
  security unlock-keychain -p sniptext-dev "$LOCAL_KEYCHAIN"
  IDENTITY="SnipText Dev"
  SIGN_ARGS=(--keychain "$LOCAL_KEYCHAIN")
else
  IDENTITY=-
  echo "warning: no signing identity, signing ad-hoc (run scripts/setup-signing.sh to keep permissions)"
fi
codesign --force --options runtime --timestamp=none "${SIGN_ARGS[@]}" --sign "$IDENTITY" "$APP"
codesign --verify --strict "$APP"

echo "Built $APP (signed with: $IDENTITY)"
