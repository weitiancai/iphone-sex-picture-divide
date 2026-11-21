# 竞品与选型（2026-11 调研，数据来自 Apple/Google 官方接口）

## 一、iOS 上做"自动识别露骨内容 + 私密空间"的产品

| App | id | 平台 | 下载价 | 内购 | 关键事实 |
|---|---|---|---|---|---|
| **NuDefndr** | 6745149292 | iPhone/iPad，**iOS 18+** | 免费 | Pro 订阅约 $3–5/月 或买断 ~$90 | 直接调 Apple `SensitiveContentAnalysis`；ChaCha20-Poly1305 保险箱；旅行模式/诱饵箱/自毁 PIN；开源透明仓库；**免费版只有每周 2 次扫描 + 最近 7 天，没有 Vault** |
| **Velum: Hide Private Photos** | 6822656401 | iPhone/iPad，iOS 16.4+ | 免费 | Pro 一次性买断（非订阅），GPL-3.0 | 扫描照片/截图/视频 → 命中可移进**系统「已隐藏」相簿**（不复制）或移进自有 vault（移出 Photos，不再上 iCloud）；飞行模式可用 |
| **留光相册管家** | 6777389561 | iPhone/iPad，iOS 17+ | 免费 | — | 中文界面；本地检测疑似裸露/不雅 + OCR 敏感文字（身份证/银行卡/密码）；加密隐私相册（Face ID 或独立 6 位密码） |
| **UnseeAI** | 6755056363 | 仅 iPhone，iOS 16+ | 免费 | 有内购 | AES-256-GCM；相册内自动打码 |
| **Cacti** | 1503660093 | 仅 iPhone，iOS 13+ | 免费 | 有内购 | 2020 老牌，★4.5；自研 ML 模型"建议私密照" |
| **Punge** | 6450322655 | iPhone/iPad + Android | 免费 | Photo+Video $24.99–29.99 等 | 图+视频双端都有 |
| **Private Gallery** | 6792702821 | iPhone/iPad + Android | 免费 | PRO $7.99/月 | 端侧模型；AES-256 |
| **PrivaSee** | 6758581552 | iPhone/iPad，**iOS 18.4+** | 免费 | $0.29–9.99 | 走 Apple 端侧分析 |
| **Vault: Privacy Guardian** | 6751948680 | iPhone/iPad | 免费 | Token 包 $59.99–179.99 | Demo 只给数量不给内容 |
| **Nude App** | 1281405417 | 仅 iPhone | **$9.99 / ¥68 买断** | 无 | 2017 元老，2019 后基本不更新，★1.0 |
| **Sensitivity** | — | iPhone/iPad/Mac | 免费 | 视频扫描一次性 | 照片扫描免费；Android 版仍在社区测试 |
| **SafePic by Norton Labs** | 1462789873 | iPhone/iPad | 免费 | 有内购 | Gen Digital 大厂；**中国区已下架** |
| **Keepsafe** | 510873505 | iPhone/iPad + Android | 免费 | $4.99–12.99/月、$23.99/年 | 主流 vault，★4.7/38.7万评；**无自动检测**、非 zero-knowledge |
| **Private Photo Vault - Pic Safe** | 417571834 | iPhone + Android | 免费 | 有内购 | ★4.9；手动 vault |
| **PV私密相册管家** | 867586326 | iPhone/iPad | 免费 | 有内购 | ★4.9 / **18.7万评分**；免费：假密码、Face ID、无限隐藏；**无自动检测** |

### Android 侧（做 NSFW 检测的）
- **Cover - Photo Lock**（com.baloota.galleryprotector）：50万+下载，★4.1；**最早做"自动露骨检测 + 内容拦截"**；免费 + 广告 + IAP $4.99–99.99
- **SafePix - NSFW Photo Scanner**（com.nubestour.safepix）：ONNX 模型，纯离线
- **Punge**（com.markatlarge.scrub）、**Private Gallery**（com.privategallery.private_gallery）
- **系统级**：Google Photos 内置"敏感内容警告"（端侧自动模糊，可开关）；三星 Secure Folder + AltZLife（端侧 AI 主动建议把私密内容移入 Secure Folder，专利 US12482290B2）

---

## 二、关键结论（决定了这个项目怎么做）

1. **"免费且能自动把照片移进隐私空间"的 iOS App 基本不存在**：
   免费额度普遍只给"最近 7 天 + 每周 2 次扫描"，核心的自动隔离/加密保险箱都在付费墙后。
   → 本项目走另一条路：**自己写，零依赖**。

2. **Apple 官方框架有硬性前置条件，且失败是静默的**：
   - entitlement `com.apple.developer.sensitivecontentanalysis.client` = `["analysis"]`
   - 用户手动打开 设置 → 隐私与安全性 → 敏感内容警告
   - 缺任一条件 → `analysisPolicy == .disabled` → **永远返回"一切正常"**
   → 所以自带模型是唯一可靠方案。

3. **区域级细分是空白点**：主流产品只给"是否敏感"，不给"露了哪里"。
   Moderator 模型给出五个区域分数（nipples/genitals/buttocks/nude/sexAct），
   可以据此做"允许胸部 / 禁止裸露"这类分级策略。

4. **跨端很少**：只有 Punge 和 Private Gallery 做了双端，其余都是单端。

5. **iOS 没有"移入系统已隐藏相簿"的公开 API**：
   要么用户手动长按隐藏，要么 App 自己实现加密容器。

---

## 三、值得抄的竞品设计

- **NuDefndr**：旅行模式（关 Face ID 只认 PIN）、诱饵保险箱、自毁 PIN、密钥可导出/迁移、审计日志
- **Velum**：命中后给出两个出口（系统隐藏相簿 / 自有 vault），并检查"哪张照片在图库里存了多份"
- **Cover**：不只扫相册，还能拦下"别人发给你"的图
- **Punge**：图 + 视频双端一致
