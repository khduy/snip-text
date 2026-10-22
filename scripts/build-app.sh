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

cd "$ROOT"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# Swift Build's generated `Bundle.module` finds package resource bundles in Contents/Resources.
# The older native build system (the default in Xcode 16.4) only looks next to the .app and at
# an absolute path on the build machine, so on any other Mac the app crashes when it opens
# Settings or onboarding.
SWIFT_BUILD_ARGS=()
if swift build --help 2>&1 | grep -q "swiftbuild"; then
  SWIFT_BUILD_ARGS=(--build-system swiftbuild)
fi

BUILD_ARGS=(-c "$CONFIG" "${SWIFT_BUILD_ARGS[@]}")
if [[ "${UNIVERSAL:-0}" == 1 ]]; then
  # Swift Build makes the fat binary itself. (Xcode 16.4's build system could not find the
  # KeyboardShortcuts module this way, and building per `--triple` gave Swift 6.2 two x86_64 slices;
  # a toolchain without Swift Build fails the resource check below anyway.)
  BUILD_ARGS+=(--arch arm64 --arch x86_64)
fi
swift build "${BUILD_ARGS[@]}"
BIN_DIR=$(swift build "${BUILD_ARGS[@]}" --show-bin-path)
cp "$BIN_DIR/SnipText" "$APP/Contents/MacOS/"

if [[ "${UNIVERSAL:-0}" == 1 ]]; then
  ARCHS=$(lipo -archs "$APP/Contents/MacOS/SnipText")
  if [[ " $ARCHS " != *" arm64 "* || " $ARCHS " != *" x86_64 "* ]]; then
    echo "error: expected arm64 and x86_64, got: $ARCHS" >&2
    exit 1
  fi
fi

# The native build system's accessor embeds the bundle's absolute build path; Swift Build's does not.
# Not `grep -q`: it stops at the first match, `strings` then dies of SIGPIPE, and with pipefail
# the failed pipeline would read as "no match".
if strings -a "$APP/Contents/MacOS/SnipText" | grep '/\.build/.*\.bundle$' >/dev/null; then
  if [[ -n "${VERSION:-}" ]]; then
    echo "error: built with a toolchain whose resource lookup fails outside this machine; use a toolchain with --build-system swiftbuild" >&2
    exit 1
  fi
  echo "warning: this build only finds its resource bundles on this machine; build with a toolchain that has --build-system swiftbuild to distribute it"
fi
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
