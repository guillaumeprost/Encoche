#!/usr/bin/env bash
# Compile une version universelle (Apple Silicon et Intel) et la zippe dans dist/,
# prête à être jointe à une Release GitHub.
#
# L'app est signée avec le certificat local (voir create-signing-cert.sh) : une identité
# stable d'une version à l'autre, pour que macOS garde les autorisations après une mise à jour.
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate --quiet
xcodebuild -project Notch.xcodeproj -scheme Notch -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath build/release \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO -quiet build

app=build/release/Build/Products/Release/Encoche.app
version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$app/Contents/Info.plist")
codesign --verify --deep --strict "$app"

mkdir -p dist
zip="dist/Encoche-$version.zip"
rm -f "$zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$zip"
echo "Version $version prête : $zip ($(du -h "$zip" | cut -f1))"
