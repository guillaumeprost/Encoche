#!/usr/bin/env bash
# Lance les tests unitaires (logique d'Encoche, sans interface).
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate --quiet
xcodebuild -project Notch.xcodeproj -scheme Notch -configuration Debug \
  -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath build test
