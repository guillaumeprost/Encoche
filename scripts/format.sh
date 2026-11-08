#!/usr/bin/env bash
# Met en forme le code Swift (règles dans .swift-format).
# `./scripts/format.sh --check` : vérifie seulement, sans rien modifier (utilisé par la CI).
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ "${1:-}" == "--check" ]]; then
  xcrun swift-format lint --strict --recursive --parallel Notch NotchTests
else
  xcrun swift-format format --in-place --recursive --parallel Notch NotchTests
fi
