import SwiftUI
import PictureDivideCore

struct SettingsView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        NavigationStack {
            Form {
                Section("判定策略") {
                    Picker("策略", selection: $state.policy) {
                        ForEach(ScanPolicy.allCases, id: \.self) { policy in
                            Text(policy.displayName).tag(policy)
                        }
                    }
                    Text(state.policy.detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("检测引擎") {
                    LabeledContent("当前引擎", value: state.engineDescription)
                    LabeledContent("系统框架状态", value: AppleSensitiveDetector.policyDescription)
                    Text("本 App 默认使用随包内置的 CoreML 模型，不依赖系统开关，也不需要任何 Apple 授权；全部推理在本机完成，照片与结果都不上传。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("检测历史") {
                    LabeledContent("已记录", value: "\(state.flagged.count) 条")
                    Text("检测结果会存在本机（Application Support），重复扫描同一张只会累加次数，不会重复出现；闪退或重启 App 也不会丢。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("清空检测历史", role: .destructive) {
                        state.clearHistory()
                    }
                }

                Section("隐私相册（系统相簿）") {
                    TextField("相簿名称", text: $state.albumTitle)
                        .onChange(of: state.albumTitle) { _, _ in state.refreshAlbumAssets() }
                    LabeledContent("相簿内照片", value: "\(state.albumAssets.count) 张")
                    Text("命中的照片会归进系统相册里的这个相簿。到「照片 → 相簿 → 打开它 → 全选 → 隐藏」，就能整册移进系统的「已隐藏」（Face ID 保护）。iOS 27 起本 App 可以直接调用公开 API 设成已隐藏，不用手动操作。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("刷新相簿") {
                        state.refreshAlbumAssets()
                    }
                }

                Section("保险箱") {
                    LabeledContent("条目数", value: "\(state.vaultItems.count)")
                    Text("内容用 ChaCha20-Poly1305 加密，密钥存在 Keychain（仅本机、解锁后可用）。删除 App 会连同密钥一起消失，箱内内容无法恢复——这是设计如此。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("已知限制") {
                    Text("""
                    · 模型只针对真人照片，动漫/插画与打码内容基本识别不出。
                    · 误报与漏报都会有，关键内容请人工复核。
                    · 删除原图后 iOS 会保留 30 天「最近删除」，需要你在系统相册里清空才彻底消失。
                    · 系统「已隐藏」相簿没有对外 API，无法由 App 代劳；需要隐藏时可在系统相册长按 → 隐藏。
                    """)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }

                Section("关于") {
                    LabeledContent("模型", value: "Moderator v1.0.0（Desert Ant Labs，Source-Available License）")
                    Text("模型权重来自 desert-ant-labs/moderator，训练数据为公有领域/开放授权或自研生成。仅供个人使用；如要商用请先看它的许可。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("设置")
        }
    }
}
