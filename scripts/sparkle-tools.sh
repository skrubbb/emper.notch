#!/bin/bash
# Fetch Sparkle's command-line tools (generate_keys, sign_update, generate_appcast) into .sparkle-tools.
# Pinned to the same Sparkle as Package.swift and checked against the GitHub release digest.
set -euo pipefail
cd "$(dirname "$0")/.."
VER="2.10.1"
SHA="1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27"
DIR=".sparkle-tools"
[ -x "$DIR/bin/sign_update" ] && { echo "$DIR/bin"; exit 0; }
TMP="$(mktemp -d)"
curl -fsSL --max-time 300 -o "$TMP/s.tar.xz" "https://github.com/sparkle-project/Sparkle/releases/download/$VER/Sparkle-$VER.tar.xz"
echo "$SHA  $TMP/s.tar.xz" | shasum -a 256 -c - >/dev/null
mkdir -p "$DIR"
tar -xJf "$TMP/s.tar.xz" -C "$DIR" bin
rm -rf "$TMP"
echo "$DIR/bin"
