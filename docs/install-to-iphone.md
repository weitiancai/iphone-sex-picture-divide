# 从零把 App 装到自己 iPhone（完全免费，不需要上架 / 不需要 TestFlight）

> 总耗时：第一次约 40–70 分钟（大部分是下载 Xcode 15–20GB）。
> 前提：一台 Mac + 一根**数据线**（有些线只能充电，不能传数据）+ 一台 iPhone（iOS 17 或更高）。

---

## 第 0 步：安装 Xcode（必需，免费）

App Store 搜索 "Xcode" → 安装（Apple 官方，约 15–20GB）。

国内网络慢的话，两个替代方案：
- 用另一台网络正常的机器在 App Store 下载 Xcode，然后拷成压缩包传过来解压到 `/Applications`；
- 或 `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` 配好开发者目录即可。

装完后，在终端执行一次初始化：

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch      # 安装模拟器等组件
xcodebuild -version                  # 能打印版本号就 OK
```

## 第 1 步：安装 XcodeGen（生成 .xcodeproj 用）

本仓库不提交 `.xcodeproj`（它是生成的），需要 XcodeGen：

```bash
HOMEBREW_NO_AUTO_UPDATE=1 brew install xcodegen
# 或者直接用仓库里的脚本（会自动帮你装）：
# Scripts/bootstrap.sh
```

## 第 2 步：iPhone 端准备（两件事，最容易卡住）

1. **信任电脑**
   用数据线连上 Mac → **解锁 iPhone** → 弹出"要信任此电脑吗" → **信任** → 输入 iPhone 锁屏密码。
   （没弹窗：拔插一次数据线；或设置 → 通用 → VPN与设备管理 里看）

2. **打开开发者模式**（iOS 16+ 必做，否则装不上）
   iPhone：**设置 → 隐私与安全性 → 开发者模式** → 打开 → 按提示**重启手机** →
   重启后再次进入同一位置，点"开启"并输入锁屏密码。

3. 确认系统版本：**设置 → 通用 → 关于本机 → 软件版本** ≥ iOS 17.0（本项目最低要求）。

## 第 3 步：Xcode 登录 Apple ID

1. 打开 Xcode → **Settings**（⌘,）→ **Accounts** → 左下 **+** → **Apple ID** → 登录你的 Apple ID。
   （**免费个人 Apple ID 就够**，不用花钱）
2. 登录后，Target 的 Team 下拉框里才会出现 "你的名字 (Personal Team)"。

## 第 4 步：生成工程并配置签名

```bash
cd /Users/weimeng/.t3/projects/picture-divide
Scripts/bootstrap.sh          # 生成 PictureDivide.xcodeproj（会提示下一步）
open PictureDivide.xcodeproj
```

在 Xcode 里：

1. 左侧文件区最上面的**蓝色项目图标 PictureDivide** → 中间栏 **TARGETS** 选 **PictureDivide** →
   顶部标签页选 **Signing & Capabilities**。
2. 勾选 **Automatically manage signing**。
3. **Team**：选 `你的名字 (Personal Team)`。
4. **Bundle Identifier**：改成一个**唯一**的值，例如 `com.你的名字.picturedivide`
   （默认的 `com.picturedivide.app` 大概率已被别人占用，会报 "Failed to register"）。
5. Xcode 会自动在你的账号下注册 App ID 和证书，出现提示选同意即可。

> 本工程**默认没有 entitlements**（故意不加 `sensitivecontentanalysis.client`），
> 所以免费个人账号一定签得下来。

## 第 5 步：选设备 → 运行

1. Xcode 顶部工具栏中间的**设备下拉框** → 选你的 iPhone。
   - 手机没出现在列表里：菜单 **Window → Devices and Simulators**（⇧⌘2）→ 左下 **+** → 选你的手机 → 完成。
2. **⌘R**（运行）。
3. 首次会失败一次并提示 **"Untrusted Developer"**：
   iPhone → **设置 → 通用 → VPN与设备管理 → 开发者 App** → 点你的 Apple ID → **信任** → 回 Xcode 再按 **⌘R**。
4. App 跑起来后：
   - 首次进入 **扫描** 页 → 请求相册权限 → 选 **"完全访问"**（否则"移入保险箱后删原图"这类操作会受限）。
   - 保险箱解锁用 Face ID；未录入 Face ID 时会自动回退到设备密码。

## 第 6 步：日常使用与续签

- **证书 7 天有效**：过期后 Xcode 会报签名错误，重新 **⌘R** 一次即可（App 数据不丢；但**删除 App 会连密钥一起删掉，保险箱内容不可恢复**，这是安全设计）。
- 免费个人签名的额度：**最多 3 台设备**，每台 7 天。
- 换手机：直接重新 ⌘R。

---

## 常见问题

| 现象 | 处理 |
|---|---|
| Xcode 里看不到 iPhone | 换一根**能传数据**的线；保持手机解锁；点过"信任"；⇧⌘2 里手动 Add |
| `Failed to register bundle identifier` | Bundle ID 已被占用，换成带你名字的唯一 ID |
| `Unable to install` / "不受信任" | 设置 → 通用 → VPN与设备管理 → 信任开发者；并确认开发者模式已开 |
| `The certificate for this app is invalid` | 证书过期，重新 ⌘R |
| `xcodebuild: error: SDK "iPhoneOS" not found` | `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` |
| `Unable to find a destination` | 目标设备选一下；或用下面的命令行方式 |

## 不想用 Xcode 图形界面？命令行也行

```bash
# 编译并装到指定手机（先在 Xcode 里把设备插上并配好签名）
xcodebuild -project PictureDivide.xcodeproj \
  -scheme PictureDivide \
  -destination 'platform=iOS,name=你的iPhone名称' \
  -derivedDataPath ./DerivedData \
  -allowProvisioningUpdates \
  build

# 手动安装（Xcode 15+）
xcrun devicectl list devices                       # 拿 UDID
xcrun devicectl device install app \
  --device <UDID> \
  DerivedData/Build/Products/Debug-iphoneos/PictureDivide.app
```

## 想脱离 Mac 用？→ TestFlight（需要付费 99 美元/年）

内部测试**不需要 App Store 审核**，详见 [`build-and-testflight.md`](build-and-testflight.md#3-上-testflight需要付费开发者账号)。
