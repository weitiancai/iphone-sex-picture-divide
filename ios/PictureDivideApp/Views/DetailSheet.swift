import PictureDivideCore
import SwiftUI
import UIKit

/// 单张复核详情：大图（默认打码）+ 分档信息 + 三个处理动作。
struct DetailSheet: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    let item: FlaggedItem

    @State private var reveal = false
    @State private var working = false
    @State private var showDeleteConfirm = false
    @State private var loaded: UIImage?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                ZStack {
                    if let image = loaded ?? item.previewImage {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .blur(radius: reveal ? 0 : 26)
                            .onTapGesture { reveal.toggle() }
                    } else {
                        Rectangle()
                            .fill(.quaternary)
                            .overlay(ProgressView())
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(maxHeight: 340)
                .background(.black.opacity(0.92))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                HStack {
                    Text(String(format: "总分 %.3f", item.score))
                    Spacer()
                    Text(item.tier.displayName)
                        .font(.caption)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(tierColor(item.tier).opacity(0.25))
                        .foregroundStyle(tierColor(item.tier))
                    if item.timesDetected > 1 {
                        Text("×\(item.timesDetected)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .font(.footnote)

                VStack(spacing: 10) {
                    Button {
                        reveal.toggle()
                    } label: {
                        Label(reveal ? "隐藏原图" : "显示原图（点图片也行）", systemImage: reveal ? "eye.slash" : "eye")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        working = true
                        Task {
                            await state.addToPrivateAlbum(item)
                            working = false
                            dismiss()
                        }
                    } label: {
                        Label(working ? "处理中…" : "① 加入隐私相册（保留原图）", systemImage: "lock.shield")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(working)

                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("② 只删除系统相册原图", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(working)

                    Button {
                        working = true
                        Task {
                            await state.addToPrivateAlbumAndDeleteOriginal(item)
                            working = false
                            dismiss()
                        }
                    } label: {
                        Label("③ 加入隐私相册并删除原图", systemImage: "arrow.up.bin")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(working)

                    Button {
                        state.markAsSafe(item)
                        dismiss()
                    } label: {
                        Label("这是误报（什么都不做）", systemImage: "arrow.uturn.backward")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal)

                Text("""
                ① 加入隐私相册：加密副本存进本 App 的保险箱（ChaCha20-Poly1305，密钥在 Keychain），系统相册里的原图保持不动。
                ② 只删除原图：只删系统相册那一份。
                ③ 两者都做：加密存一份 + 删掉系统相册原图（iOS 保留 30 天「最近删除」，需你自己清空）。
                """)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                Spacer()
            }
            .padding(.top)
            .navigationTitle(item.creationDate?.formatted(date: .abbreviated, time: .omitted) ?? "复核")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .task {
                // 历史记录里没存大图，这里现取（之前“显示原图”没反应就是因为图是空的）。
                if loaded == nil && item.previewImage == nil {
                    loaded = await ThumbnailProvider.shared.preview(for: item.id)
                } else {
                    loaded = item.previewImage
                }
            }
            .confirmationDialog("确定删除系统相册里的原图？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("删除原图", role: .destructive) {
                    working = true
                    Task {
                        await state.deleteOriginal(item)
                        working = false
                        dismiss()
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("这只会删掉系统相册里的那份照片，不会动保险箱里的加密副本。iOS 会在「最近删除」里保留 30 天。")
            }
        }
    }

    private func tierColor(_ tier: SensitivityTier) -> Color {
        switch tier {
        case .explicit: return .red
        case .suspected: return .orange
        case .safe: return .secondary
        }
    }
}
