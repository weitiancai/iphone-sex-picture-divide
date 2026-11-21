# 构建与分发指南（全部本机可完成，不上架、不审核）

## 0. 现在就能做什么

| 目标 | 需要什么 | 费用 |
|---|---|---|
| 在 Mac 上跑检测逻辑 | 已有 Xcode CLT 即可 | 0 |
| 装到自己的 iPhone 上用 | Xcode + **免费**个人 Apple ID | 0 |
| 通过 TestFlight 分发给自己/同事 | Xcode + **付费** Apple Developer Program（99 美元/年） | 99 美元/年 |

TestFlight 的**内部测试**不需要 App Store 审核；只有"外部测试"需要 Beta 审核，而且也只是 Beta 审核，不是上架。

---

## 1. 本机验证（不需要 Xcode）

```bash
# 逻辑自检（策略判定 + 加密 + 保险箱）
swift run --package-path Packages/PictureDivideCore pdctl-selftest

# 用内置模型检测一张图
swift run --package-path Packages/PictureDivideCore pdctl detect ~/Desktop/xxx.jpg --model ./Resources/Moderator.mlmodelc

# 扫描整个目录
swift run --package-path Packages/PictureDivideCore pdctl scan ~/Pictures --model ./Resources/Moderator.mlmodelc
```

> 模型是"已编译"的 CoreML 包（`Resources/Moderator.mlmodelc`），运行时用 `MLModel(contentsOf:)` 加载，不需要 Xcode 重新编译。

---

## 2. 装到自己 iPhone（完全免费）

1. 安装 Xcode（App Store，免费），然后：
   ```bash
   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
   xcodebuild -runFirstLaunch
   ```
2. 跑 `Scripts/bootstrap.sh`（会装 XcodeGen 并生成工程）。
3. Xcode 打开 `PictureDivide.xcodeproj`：
   - target `PictureDivide` → **Signing & Capabilities**
   - 勾选 *Automatically manage signing*，**Team 选你的个人 Apple ID**（免费账号也行）
   - 把 **Bundle Identifier** 改成唯一值，例如 `com.你的名字.picturedivide`
   - 删掉/忽略 `PictureDivideTests` target 也可以
4. iPhone 用数据线连上，Xcode 顶部设备选你的 iPhone，⌘R 运行。
5. 首次启动会请求相册权限 → 允许。

**免费个人签名的限制**：证书有效期 7 天，到期后重新 ⌘R 跑一次即可（数据不会丢，保险箱内容在 App 沙盒里；但**删掉 App = 密钥也删掉 = 保险箱内容不可恢复**，这是设计如此）。

---

## 3. 上 TestFlight（需要付费开发者账号）

1. 注册 Apple Developer Program（99 美元/年）：https://developer.apple.com/programs/whats-included/
2. Xcode → target → Signing & Capabilities：Team 选你的付费团队，Bundle ID 保持唯一。
3. 命令行打包上传（不需要 Xcode 的 Organizer GUI）：
   ```bash
   # 找到你的 Team ID
   xcrun devicectl list teams   # 或在 Xcode → Settings → Accounts 里看

   xcodebuild \
     -project PictureDivide.xcodeproj \
     -scheme PictureDivide \
     -configuration Release \
     -destination 'generic/platform=iOS' \
     -archivePath ./build/PictureDivide.xcarchive \
     -allowProvisioningUpdates \
     archive

   xcodebuild \
     -exportArchive \
     -archivePath ./build/PictureDivide.xcarchive \
     -exportOptionsPlist ExportOptions.plist \
     -allowProvisioningUpdates \
     exportPath ./build/ipa

   # 上传到 App Store Connect（内部测试不需要提交审核）
   xcrun altool --upload-app -f ./build/ipa/PictureDivide.ipa -t ios \
     --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
   ```
   `ExportOptions.plist`：
   ```xml
   <?xml version="1.0" encoding="UTF-8"?>
   <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
   <plist version="1.0"><dict>
     <key>method</key><string>app-store-connect</string>
     <key>teamID</key><string>YOUR_TEAM_ID</string>
     <key>destination</key><string>upload</string>
     <key>uploadSymbols</key><true/>
   </dict></plist>
   ```
4. App Store Connect → 我的 App → TestFlight → 内部测试 → 添加测试员（自己的 Apple ID）→ 打开 TestFlight App 安装。
   - 构建通常 5–30 分钟内可分发。

---

## 4. 想改用 Apple 官方 SensitiveContentAnalysis 框架？（可选）

这个框架**不要 entitlement 就静默失效**，实测行为是"永远检测不出"：

- 需要 entitlement `com.apple.developer.sensitivecontentanalysis.client` = `["analysis"]`
- 需要用户在 设置 → 隐私与安全性 → **敏感内容警告** 里打开开关
- 两条件缺一，`SCSensitivityAnalyzer().analysisPolicy == .disabled`

所以本项目**默认不依赖它**，用随包内置模型。要启用的话：

1. Xcode → target → Signing & Capabilities → + Capability → **Sensitive Content Analysis**
2. 或手动加 `ios/PictureDivideApp/Support/PictureDivide.sca.entitlements`：
   ```xml
   <?xml version="1.0" encoding="UTF-8"?>
   <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
   <plist version="1.0"><dict>
     <key>com.apple.developer.sensitivecontentanalysis.client</key>
     <array><string>analysis</string></array>
   </dict></plist>
   ```
   并在 `project.yml` 的 `settings.base.entitlements` 里指过去，然后重新 `xcodegen generate`。
   （免费个人账号很可能签不下来这个 entitlement，签不下来就别加。）

---

## 5. 上架 App Store 的话要注意（如果以后想上架）

- App Store 审核指南 1.2 与"色情内容"相关条款：App 内**不要明文展示露骨图片**。本项目默认缩略图打码、需手动"显示原图"，符合这个思路。
- Google Play 的性内容政策同理（仅 Android）。
- 内置模型许可：Moderator 是 Source-Available License（个人使用免费，规模化商用需商业授权），见 `Resources/Moderator.THIRD_PARTY_NOTICES.md`。
- `ITSAppUsesNonExemptEncryption = false` 已配置，避免每次上传都被问出口合规问卷。
