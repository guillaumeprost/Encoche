#!/usr/bin/env bash
# Compile Encoche en Release, l'installe dans /Applications et la relance.
# Au premier lancement, elle s'ajoute aux éléments d'ouverture de session.
#
# Prérequis (vérifiés ci-dessous) : Xcode 26 ou plus récent, XcodeGen, et le certificat
# de signature local créé une fois par ./scripts/create-signing-cert.sh.
set -euo pipefail
cd "$(dirname "$0")/.."

fail() {
  echo "✗ $1" >&2
  exit 1
}

xcodebuild -version >/dev/null 2>&1 || fail "Xcode est introuvable : installe Xcode 26 ou plus récent, puis lance-le une fois."
command -v xcodegen >/dev/null || fail "XcodeGen est introuvable : brew install xcodegen"
security find-certificate -c "Notch Local Signing" >/dev/null 2>&1 \
  || fail "Certificat de signature absent : lance d'abord ./scripts/create-signing-cert.sh"

arch=$(uname -m)
app=build/Build/Products/Release/Encoche.app

echo "→ Compilation en Release ($arch)…"
xcodegen generate --quiet
xcodebuild -project Notch.xcodeproj -scheme Notch -configuration Release \
  -destination "platform=macOS,arch=$arch" -derivedDataPath build -quiet build
codesign --verify --strict "$app" || fail "La signature de l'app compilée est invalide."

echo "→ Installation dans /Applications…"
# Ferme l'app en cours (et l'ancienne « Notch ») et attend qu'elle ait quitté, 5 s au plus.
pkill -x Encoche 2>/dev/null || true
pkill -x Notch 2>/dev/null || true
for _ in {1..50}; do
  pgrep -x Encoche >/dev/null || pgrep -x Notch >/dev/null || break
  sleep 0.1
done
rm -rf /Applications/Notch.app /Applications/Encoche.app
ditto "$app" /Applications/Encoche.app

open /Applications/Encoche.app
version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" /Applications/Encoche.app/Contents/Info.plist)
echo "✓ Encoche $version installé dans /Applications et lancé"
