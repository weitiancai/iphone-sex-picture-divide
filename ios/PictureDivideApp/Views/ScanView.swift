import Photos
import SwiftUI
import UIKit
import PictureDivideCore

struct ScanView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    switch state.authorization {
                    case .authorized, .limited:
                        Label("已获得相册访问权限", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    case .denied, .restricted:
                        VStack(alignment: .leading, spacing: 8) {
                            Label("没有相册权限", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("需要在「设置 → PictureDivide → 照片」里允许访问，系统才会允许本 App 扫描与搬运照片。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Button("打开系统设置") {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            }
                        }
                    case .notDetermined:
                        Button("请求相册访问权限") {
                            Task { await state.requestAccess() }
                        }
                    @unknown default:
                        Text("未知状态")
                    }
                } header: {
                    Text("权限")
                }

                Section {
                    Picker("扫描范围", selection: $state.scanRange) {
                        ForEach(ScanRange.allCases) { range in
                            Text(range.title).tag(range)
                        }
                    }
                    if state.scanRange == .custom {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("从")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            MonthPicker(date: $state.customStart)
                                .frame(height: 120)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("到")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            MonthPicker(date: $state.customEnd)
                                .frame(height: 120)
                        }
                        Text("实际扫描：\(state.customStart.formatted(.dateTime.year().month())) — \(state.customEnd.formatted(.dateTime.year().month()))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if state.customStart > state.customEnd {
                            Text("⚠️ 起始月晚于结束月，将扫不到东西。")
                                .font(.footnote)
                                .foregroundStyle(.orange)
                        }
                    }
                    Picker("判定策略", selection: $state.policy) {
                        ForEach(ScanPolicy.allCases, id: \.self) { policy in
                            Text(policy.displayName).tag(policy)
                        }
                    }
                    Text(state.policy.detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Picker("扫描速度", selection: $state.quality) {
                        Text("快速").tag(ModeratorDetector.Quality.fast)
                        Text("均衡").tag(ModeratorDetector.Quality.balanced)
                        Text("精确").tag(ModeratorDetector.Quality.accurate)
                    }
                    Picker("检测引擎", selection: $state.engineOption) {
                        ForEach(EngineOption.allCases, id: \.self) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    Text(state.engineOption.detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading) {
                        HStack {
                            Text("触发阈值")
                            Spacer()
                            Text(String(format: "%.2f", state.threshold))
                                .font(.body.monospacedDigit())
                        }
                        Slider(value: $state.threshold, in: 0.30...0.90, step: 0.05)
                    }
                    Text("阈值调高 → 误报更少、漏报更多。默认 0.50；如果你老是被误报打扰，调到 0.65~0.70。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading) {
                        HStack {
                            Text("疑似暴露下限")
                            Spacer()
                            Text(String(format: "%.2f", state.suspectThreshold))
                                .font(.body.monospacedDigit())
                        }
                        Slider(value: $state.suspectThreshold, in: 0.05...0.50, step: 0.05)
                    }
                    Toggle("把「疑似暴露」也标记出来", isOn: $state.includeSuspected)
                    Text("""
                    明确色情 = 露点 / 生殖器 / 性行为（高置信）。
                    疑似暴露 = 没露点但裸露明显（内衣、网袜、局部胸臀），例如刚才那张网袜图约 0.21。
                    关掉这个开关就只报“明确色情”。
                    """)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Text(state.quality == .fast
                         ? "快速：每张只算 1 次，最快，但可能漏掉边缘内容。"
                         : state.quality == .balanced
                           ? "均衡：每张算 5 次（整图 + 4 个裁剪块）。"
                           : "精确：每张算 9 次（整图 + 4 个裁剪块 + 镜像），召回最高，也最慢。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("参数")
                } footer: {
                    Text("照片数量多时扫描会花点时间；全程在设备本地完成，照片不会上传。")
                }

                Section {
                    if state.progress.isRunning {
                        ProgressView(value: state.progress.fraction) {
                            Text("已扫描 \(state.progress.scanned) / \(state.progress.total)")
                        }
                        Button(role: .destructive) {
                            state.cancelScan()
                        } label: {
                            Label("停止扫描", systemImage: "stop.circle")
                        }
                    } else {
                        Button {
                            state.startScan()
                        } label: {
                            Label("开始扫描", systemImage: "play.circle.fill")
                        }
                        .disabled(state.authorization != .authorized && state.authorization != .limited)
                    }
                    Toggle("断点续扫（被系统打断后接着扫）", isOn: $state.resumeEnabled)
                    if let cursor = state.cursorDate {
                        HStack {
                            Text("上次扫到")
                            Spacer()
                            Text(cursor.formatted(date: .abbreviated, time: .omitted))
                                .foregroundStyle(.secondary)
                        }
                        Button("清除断点，从头开始") {
                            state.resetCursor()
                        }
                        .font(.footnote)
                    }
                    if state.scanInterrupted {
                        Label("上次扫描被系统打断（息屏/切后台），已保存断点。", systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text("扫描")
                } footer: {
                    Text("切到其他 App 或息屏时会尽量继续（系统给一小段后台时间）；被打断也没关系，下次自动从断点继续。")
                    if let error = state.scanError {
                        Text(error).foregroundStyle(.red)
                    } else if let finished = state.lastScanFinishedAt {
                        Text("上次完成：\(finished.formatted(date: .abbreviated, time: .shortened))，命中 \(state.flagged.count) 张。")
                    }
                }
            }
            .navigationTitle("扫描")
            .onChange(of: state.quality) { _, _ in
                state.reloadDetector()
            }
            .onChange(of: state.engineOption) { _, _ in
                state.reloadDetector()
            }
        }
    }
}
