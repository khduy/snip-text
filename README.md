<p align="center"><img src="docs/icon.png" width="128" alt="SnipText icon"></p>

# SnipText

A macOS menu bar app that copies the text from any region of your screen.

- Offline OCR with Apple Vision
- Reads QR codes and barcodes
- Keeps indentation when capturing code

Requires macOS 15 or later.

## Install

```bash
brew install --cask khduy/tap/sniptext
```

Or download the zip from [Releases](https://github.com/khduy/snip-text/releases). The app is not notarized, so remove the quarantine flag before opening it:

```bash
xattr -dr com.apple.quarantine /Applications/SnipText.app
```

## Building

```bash
scripts/setup-signing.sh
scripts/build-app.sh
swift test
```

`setup-signing.sh` creates a local signing certificate in `.signing/` so macOS keeps the Screen Recording permission across builds.
