#!/bin/zsh
# Writes Casks/sniptext.rb for a release and pushes it to the Homebrew tap.
#   scripts/update-tap.sh <version> [zip]            update khduy/homebrew-tap via the GitHub API
#   scripts/update-tap.sh <version> [zip] --print    only print the cask
# Without [zip], the release asset is downloaded from GitHub to compute its checksum.
# Needs a GitHub token with write access to the tap (gh auth, or GH_TOKEN in CI).
set -euo pipefail

VERSION=${1:?usage: scripts/update-tap.sh <version> [zip] [--print]}
ZIP=${2:-}
[[ "$ZIP" == --print ]] && ZIP=""
REPO=khduy/snip-text
TAP=khduy/homebrew-tap
CASK_PATH=Casks/sniptext.rb

if [[ -z "$ZIP" ]]; then
  ZIP=$(mktemp -d)/SnipText-$VERSION.zip
  curl -fsSL -o "$ZIP" "https://github.com/$REPO/releases/download/v$VERSION/SnipText-$VERSION.zip"
fi
SHA256=$(shasum -a 256 "$ZIP" | cut -d' ' -f1)

CASK=$(cat <<EOF
cask "sniptext" do
  version "$VERSION"
  sha256 "$SHA256"

  url "https://github.com/$REPO/releases/download/v#{version}/SnipText-#{version}.zip"
  name "SnipText"
  desc "Menu bar OCR: select a screen region and copy its text"
  homepage "https://github.com/$REPO"

  depends_on macos: ">= :sequoia"

  app "SnipText.app"

  # The app is not notarized; drop the quarantine flag so Gatekeeper does not block it.
  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/SnipText.app"]
  end

  uninstall quit: "vn.posapp.sniptext"

  zap trash: [
    "~/Library/Application Support/SnipText",
    "~/Library/Caches/SnipText",
    "~/Library/Caches/vn.posapp.sniptext",
    "~/Library/Preferences/vn.posapp.sniptext.plist",
  ]

  caveats <<~EOS
    SnipText needs Screen Recording permission. After enabling it in
    System Settings → Privacy & Security, restart SnipText.

    If macOS still blocks the app on first launch, run:
      xattr -dr com.apple.quarantine #{appdir}/SnipText.app
  EOS
end
EOF
)

if [[ " $* " == *" --print "* ]]; then
  print -r -- "$CASK"
  exit 0
fi

CURRENT_SHA=$(gh api "repos/$TAP/contents/$CASK_PATH" --jq .sha 2>/dev/null || true)
gh api -X PUT "repos/$TAP/contents/$CASK_PATH" \
  -f message="sniptext $VERSION" \
  -f content="$(print -r -- "$CASK" | base64)" \
  ${CURRENT_SHA:+-f sha="$CURRENT_SHA"} \
  --jq '.commit.html_url'
