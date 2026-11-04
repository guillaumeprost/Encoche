#!/usr/bin/env bash
# Compile en Release, installe dans /Applications et lance l'app.
# Au premier lancement, elle s'ajoute aux éléments d'ouverture de session.
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate --quiet
xcodebuild -project Notch.xcodeproj -scheme Notch -configuration Release \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath build -quiet build

pkill -x Notch 2>/dev/null || true
sleep 0.5
rm -rf /Applications/Notch.app
cp -R build/Build/Products/Release/Notch.app /Applications/
open /Applications/Notch.app
echo "Notch installé dans /Applications"
