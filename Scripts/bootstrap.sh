#!/usr/bin/env bash
# 一键准备：检查 Xcode → 装 XcodeGen（需要时）→ 生成 Xcode 工程。
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> 检查 Xcode"
if ! xcodebuild -version >/dev/null 2>&1; then
  echo "❌ 没找到 Xcode。请先从 App Store 安装 Xcode（免费），然后："
  echo "   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
  echo "   xcodebuild -runFirstLaunch"
  exit 1
fi
xcodebuild -version | head -2

echo "==> 检查 XcodeGen"
XG="$(command -v xcodegen || true)"
if [ -z "$XG" ]; then
  if command -v brew >/dev/null 2>&1; then
    echo "通过 Homebrew 安装 XcodeGen…"
    brew install xcodegen
    XG="$(command -v xcodegen)"
  else
    echo "没有 Homebrew，改为直接下载二进制…"
    mkdir -p Tools
    URL="https://github.com/yonaskolb/XcodeGen/releases/download/2.48.0/xcodegen.zip"
    curl -sL -o /tmp/xcodegen.zip "$URL"
    unzip -o -q /tmp/xcodegen.zip -d Tools
    XG="Tools/xcodegen/bin/xcodegen"
  fi
fi
echo "XcodeGen: $("$XG" --version)"

echo "==> 生成 Xcode 工程"
"$XG" generate

cat <<'MSG'

✅ 工程已生成：PictureDivide.xcodeproj

接下来（免费路线，装到自己手机上）：
  1. 用 Xcode 打开 PictureDivide.xcodeproj
  2. 选中 PictureDivide target → Signing & Capabilities
  3. 勾选 "Automatically manage signing"，Team 选你的个人 Apple ID
     （免费账号即可，证书 7 天有效，到期重跑一次就行）
  4. Bundle ID 改成你自己的唯一值，例如 com.yourname.picturedivide
  5. 连上 iPhone → 选你的设备 → ⌘R 运行
  6. 首次运行会要求相册权限，点允许

想用 TestFlight（需要付费 99 美元/年的 Apple Developer Program，
但不需要 App Store 审核，内部测试直接可用）：
  详见 docs/build-and-testflight.md
MSG
