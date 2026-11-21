<img src="assets/icon.svg" width="64" height="64" alt="">

# picture-divide

把手机相册里的**露骨/私密照片**自动挑出来，和普通照片分开，经你确认后移进**加密保险箱**（需要 Face ID / 设备密码才能打开）。

- 全程**在设备本地**完成，照片与检测结果**不上传**、不联网
- 检测用**随包内置的 CoreML 模型**（Moderator v1.0.0），能分出**胸部 / 生殖器 / 臀部 / 裸露 / 性行为**五个区域
- 移动到保险箱时：剥掉 EXIF/GPS 元数据 → ChaCha20-Poly1305 加密 → 存进 App 沙盒 → 删除系统相册原图
- 不上架也能用：装到自己 iPhone（免费 Apple ID）或走 TestFlight（付费开发者账号，内部测试免审核）

> 图标和思路参考了市面上已有的同类产品（NuDefndr / Velum / Cover 等），
> 选型对比见 [`docs/competitive-landscape.md`](docs/competitive-landscape.md)。

---

## 目录结构

```
Packages/PictureDivideCore/     核心逻辑（Swift Package，本机可编译可测）
  Sources/PictureDivideCore/
    Detection/                    检测引擎（Moderator CoreML / Apple 框架）
    Vault/                        加密保险箱（ChaCha20-Poly1305 + Keychain）
  Sources/PDCtl/                  命令行工具：本机跑检测
  Sources/PDSelfTest/             不依赖 XCTest 的自检程序
ios/PictureDivideApp/           iOS App（SwiftUI + PhotoKit）
Resources/Moderator.mlmodelc/   已编译的 CoreML 模型（9.7MB）
Scripts/                         bootstrap / build / check
docs/                            构建分发指南 + 竞品选型
```

---

## 快速开始

### 1）先在本机验证（不用 Xcode）

```bash
# 逻辑自检
swift run --package-path Packages/PictureDivideCore pdctl-selftest

# 用内置模型检测一张图
swift run --package-path Packages/PictureDivideCore pdctl detect ~/Desktop/1.jpg \
  --model ./Resources/Moderator.mlmodelc

# 扫描整个目录
swift run --package-path Packages/PictureDivideCore pdctl scan ~/Pictures \
  --model ./Resources/Moderator.mlmodelc
```

输出示例：

```
IMG_2317.jpg  score=0.842  sensitive=是  部位=生殖器/裸露  [0.71/0.84/0.62/0.79/0.55]
```

### 2）装到自己 iPhone（免费）

见 [`docs/build-and-testflight.md`](docs/build-and-testflight.md#2-装到自己-iphone完全免费)：

```bash
brew install xcodegen          # 或用 Scripts/bootstrap.sh 自动装
Scripts/bootstrap.sh           # 生成 PictureDivide.xcodeproj
open PictureDivide.xcodeproj   # 选自己的 iPhone，⌘R
```

Team 选**个人 Apple ID** 即可（免费，证书 7 天有效，到期重跑一次）。

### 3）走 TestFlight（需 99 美元/年开发者账号，内部测试免审核）

见 [`docs/build-and-testflight.md`](docs/build-and-testflight.md#3-上-testflight需要付费开发者账号)。

---

## 三个必须知道的事实（都在本机实测过）

1. **Apple 的 `SensitiveContentAnalysis` 没有 entitlement 会"静默失效"**——
   不报错、不提示，就是永远检测不出任何东西（`analysisPolicy == .disabled`）。
   本机跑 SDK 源码确认过：还必须用户手动打开 设置 → 隐私与安全性 → 敏感内容警告。
   ⇒ 所以本项目**默认用自带模型**，不依赖系统开关。
2. **iOS 没有把照片移进系统「已隐藏」相簿的公开 API** ⇒ 保险箱是 App 自己的加密容器；
   想用系统隐藏相簿，只能在系统相册长按 → 隐藏（App 里写了引导）。
3. **删除原图后 iOS 会保留 30 天「最近删除」** ⇒ 保险箱流程结束时明确提示，
   需要你自己去系统相册清空。

---

## 判定策略

| 策略 | 触发区域 | 阈值 |
|---|---|---|
| 标准（默认） | 裸露 / 性行为 / 生殖器 / 臀部 | 0.5 |
| 严格 | 以上 + 胸部 | 0.35 |
| 宽松 | 裸露 / 性行为 / 生殖器 | 0.5 |

误报可以一键标记"这是误报"，不会动原图。

---

## 已知限制

- 模型只针对**真人照片**，动漫/插画与打码内容基本识别不出。
- 会有误报和漏报，命中结果一定要人工复核。
- 删掉 App = 密钥一起消失 = 保险箱内容不可恢复（安全设计）。
- 模型许可：Desert Ant Labs Source-Available License，个人使用免费，
  规模化商用需商业授权（见 `Resources/Moderator.THIRD_PARTY_NOTICES.md`）。
