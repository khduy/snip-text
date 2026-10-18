#!/bin/zsh
# Sets up the self-signed "SnipText Dev" code-signing identity.
#
# The identity lives in .signing/ (git-ignored):
#   SnipTextDev.p12     certificate + private key; the same file is used by CI (GitHub Secrets)
#   p12-password.txt    password of the .p12
#   sniptext-dev.keychain-db   project-local keychain codesign reads from; the login keychain is untouched
#
# Signing every build with the same identity lets macOS keep the Screen Recording permission
# across rebuilds and updates. On a new machine, copy SnipTextDev.p12 + p12-password.txt into
# .signing/ before running this script so builds keep the same identity.
set -euo pipefail

ROOT=${0:A:h:h}
DIR="$ROOT/.signing"
P12="$DIR/SnipTextDev.p12"
P12_PASSWORD_FILE="$DIR/p12-password.txt"
KEYCHAIN="$DIR/sniptext-dev.keychain-db"
KEYCHAIN_PASSWORD=sniptext-dev

mkdir -p "$DIR"

if [[ ! -f "$P12" ]]; then
  TMP=$(mktemp -d)
  trap 'rm -rf "$TMP"' EXIT
  openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -subj "/CN=SnipText Dev" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
  openssl rand -hex 16 | tr -d '\n' > "$P12_PASSWORD_FILE"
  openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -out "$P12" -passout file:"$P12_PASSWORD_FILE"
  chmod 600 "$P12" "$P12_PASSWORD_FILE"
  echo "Created $P12"
fi

if [[ ! -f "$KEYCHAIN" ]]; then
  security create-keychain -p $KEYCHAIN_PASSWORD "$KEYCHAIN"
  security set-keychain-settings "$KEYCHAIN"   # no auto-lock
  security unlock-keychain -p $KEYCHAIN_PASSWORD "$KEYCHAIN"
  security import "$P12" -k "$KEYCHAIN" -P "$(cat "$P12_PASSWORD_FILE")" -T /usr/bin/codesign
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k $KEYCHAIN_PASSWORD "$KEYCHAIN" >/dev/null
  echo "Imported identity into $KEYCHAIN"
fi

echo "Signing identity 'SnipText Dev' is ready."
echo "For GitHub Actions, add these repository secrets:"
echo "  gh secret set SIGNING_CERT_P12 < <(base64 -i \"$P12\")"
echo "  gh secret set SIGNING_CERT_PASSWORD < \"$P12_PASSWORD_FILE\""
