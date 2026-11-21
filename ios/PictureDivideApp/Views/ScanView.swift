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
                } header: {
                    Text("扫描")
                } footer: {
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
        }
    }
}
