#!/usr/bin/env bash
# 编译（模拟器，无需签名）。
set -euo pipefail
cd "$(dirname "$0")/.."

XG="$(command -v xcodegen || echo Tools/xcodegen/bin/xcodegen)"
"$XG" generate

xcodebuild \
  -project PictureDivide.xcodeproj \
  -scheme PictureDivide \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath ./DerivedData \
  build
