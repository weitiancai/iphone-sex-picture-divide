#!/usr/bin/env bash
# 在本机跑核心逻辑自检 + 用内置模型检测一张图片。
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> 编译核心包"
swift build --package-path Packages/PictureDivideCore

echo "==> 自检"
swift run --package-path Packages/PictureDivideCore pdctl-selftest

if [ $# -ge 1 ]; then
  echo "==> 检测 $1"
  swift run --package-path Packages/PictureDivideCore pdctl detect "$1" --model ./Resources/Moderator.mlmodelc
fi
