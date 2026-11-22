import Photos
import SwiftUI
import UIKit

/// 「已隐藏」指引页。
///
/// 重要：**本 App 不展示任何隐藏照片**（用户要求）。
/// 这里只做两件事：
/// 1. 说明流程：命中照片被归进系统相簿「隐私相册」→ 你去系统相册整册隐藏
/// 2. 一键跳转系统「照片」App，由你自己查看和管理
struct PrivacyAlbumView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("整册隐藏到系统「已隐藏」", systemImage: "eye.slash")
                            .font(.headline)
                        Text("""
                        ① 在「复核」里对命中的照片点「加入隐私相册」——照片会被归进系统相册的「\(state.albumTitle)」相簿（并打上「隐私」标签）。
                        ② 点下面的按钮打开系统「照片」
                        ③ 切到「相簿」→ 打开「\(state.albumTitle)」→ 点「全选」→ 分享/更多 → 「隐藏」
                        ④ 这批照片就进了 Photos → 精选集 → 更多项目 → 已隐藏（Face ID 保护）

                        本 App **不会**显示这些照片的内容，只负责帮你分类。
                        """)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button {
                            state.openSystemPhotos()
                        } label: {
                            Label("打开系统照片", systemImage: "photo.on.rectangle.angled")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.4))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 12)

                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("系统「已隐藏」里的照片", value: "\(state.hiddenPhotos.count) 张")
                        LabeledContent("相簿「\(state.albumTitle)」里的照片", value: "\(state.albumAssets.count) 张")
                        Text("（这里只显示数量，不显示照片本身）")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)

                    if state.albumAssets.count > 0 {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("还没隐藏？一键去系统相册处理：")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Button {
                                state.openSystemPhotos()
                            } label: {
                                Label("打开「照片」→ 相簿 → \(state.albumTitle)", systemImage: "arrow.up.forward.app")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.horizontal, 14)
                    }
                }
                .padding(.vertical, 12)
            }
            .navigationTitle("已隐藏")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        state.refreshHiddenPhotos()
                        state.refreshAlbumAssets()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .task {
                state.refreshHiddenPhotos()
                state.refreshAlbumAssets()
            }
        }
    }
}
