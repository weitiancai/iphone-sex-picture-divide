#!/usr/bin/env bash
# 改 Bundle ID（必须全球唯一，否则 Xcode 报 "Failed to register bundle identifier"）。
#
# 用法：Scripts/set-bundle-id.sh com.yourname.picturedivide
set -euo pipefail
cd "$(dirname "$0")/.."

NEW="${1:-}"
if [ -z "$NEW" ]; then
  echo "用法：$0 <新的 bundle id>，例如 com.yourname.picturedivide"
  exit 1
fi
if ! [[ "$NEW" =~ ^[A-Za-z0-9.-]+$ ]]; then
  echo "❌ bundle id 只能包含字母、数字、点和连字符"
  exit 1
fi

python3 - "$NEW" <<'PY'
import re, sys
new = sys.argv[1]
p = 'project.yml'
s = open(p).read()
s2 = re.sub(r'(?m)^(\s*PRODUCT_BUNDLE_IDENTIFIER:\s*).*$', r'\g<1>' + new, s)
if s2 == s:
    sys.exit('❌ 没在 project.yml 里找到 PRODUCT_BUNDLE_IDENTIFIER')
open(p, 'w').write(s2)
print(f'✅ Bundle ID 已改为 {new}')
PY

XG="$(command -v xcodegen || echo Tools/xcodegen/bin/xcodegen)"
"$XG" generate
echo "✅ 工程已重新生成。请在 Xcode 里重新打开工程（关闭旧窗口再打开），然后在 Signing & Capabilities 里选 Team。"
