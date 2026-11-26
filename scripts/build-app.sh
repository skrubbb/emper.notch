#!/bin/bash
# Build Emper.app with SwiftPM (Command Line Tools are enough, Xcode not required).
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
BIN="$(swift build -c release --show-bin-path)"
APP="build/Emper.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Emper" "$APP/Contents/MacOS/Emper"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/Emper.icns "$APP/Contents/Resources/Emper.icns"
cp Resources/logo/emper-symbol.png "$APP/Contents/Resources/emper-symbol.png"
# MediaRemote helper (system-wide now playing); loaded by /usr/bin/perl, see SystemMedia.swift.
clang -fobjc-arc -framework Foundation -dynamiclib -O2 -mmacosx-version-min=14.0 \
  Helpers/MediaRemoteBridge.m -o "$APP/Contents/Resources/libEmperMR.dylib"
# Sparkle (in-app updates): embed the framework, then sign inner parts before the app (inside out).
mkdir -p "$APP/Contents/Frameworks"
ditto "$BIN/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
SP="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
for x in "$SP/XPCServices/Installer.xpc" "$SP/XPCServices/Downloader.xpc" "$SP/Autoupdate" "$SP/Updater.app"; do
  [ -e "$x" ] && codesign --force --sign - --preserve-metadata=entitlements "$x"
done
codesign --force --sign - "$APP/Contents/Frameworks/Sparkle.framework"
# Ad-hoc signature, local use only. Round 28: the designated requirement names the bundle id instead of
# the default cdhash, so the Accessibility permission survives a rebuild (a cdhash changes every build).
codesign --force --sign - -r='designated => identifier "com.skrubbb.emper"' "$APP"

echo "Built $(pwd)/$APP"
