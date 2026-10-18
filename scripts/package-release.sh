#!/bin/zsh
# Builds a universal, signed SnipText.app and zips it for a GitHub release.
#   scripts/package-release.sh 0.2.0   →   build/SnipText-0.2.0.zip
set -euo pipefail

VERSION=${1:?usage: scripts/package-release.sh <version>}
ROOT=${0:A:h:h}
ZIP="$ROOT/build/SnipText-$VERSION.zip"

UNIVERSAL=1 VERSION=$VERSION "$ROOT/scripts/build-app.sh" release

lipo -archs "$ROOT/build/SnipText.app/Contents/MacOS/SnipText"
rm -f "$ZIP"
# ditto keeps the bundle's symlinks, permissions and signature intact (plain zip may not).
ditto -c -k --keepParent "$ROOT/build/SnipText.app" "$ZIP"

shasum -a 256 "$ZIP"
echo "Packaged $ZIP"
