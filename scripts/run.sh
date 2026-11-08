#!/usr/bin/env bash
# Génère le projet, compile en Debug et relance l'app.
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate --quiet
xcodebuild -project Notch.xcodeproj -scheme Notch -configuration Debug \
  -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath build -quiet build

pkill -x Notch 2>/dev/null || true
pkill -x Encoche 2>/dev/null || true
open build/Build/Products/Debug/Encoche.app
