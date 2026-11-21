import PictureDivideCore
import SwiftUI
import UIKit

/// 单张复核详情：大图（默认打码）+ 分档信息 + 处理动作。
///
/// 预览体验要点：
/// - 打码时用**小图**做模糊（420px，模糊开销小、滑动顺滑）
/// - 点"显示原图"才去取**原图**（ImageIO 缩放到 2400px，不整张解码 HEIC），加载中有指示
/// - 原图支持双指缩放 + 拖动
struct DetailSheet: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    let item: FlaggedItem

    @State private var reveal = false
    @State private var working = false
    @State private var showDeleteConfirm = false
    @State private var maskImage: UIImage?
    @State private var originalImage: UIImage?
    @State private var loadingOriginal = false

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                imageArea
                infoBar
                actions
                Text(explanation)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                Spacer(minLength: 0)
            }
            .padding(.top, 8)
            .navigationTitle(item.creationDate?.formatted(date: .abbreviated, time: .omitted) ?? "复核")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .task {
                // 打码底图：优先用已存的缩略图，否则现取一张中等分辨率的
                if let thumb = item.thumbnail {
                    maskImage = thumb
                } else {
                    maskImage = await ThumbnailProvider.shared.thumbnail(for: item.id)
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

    // MARK: - 图片区

    private var imageArea: some View {
        ZStack {
            Color.black.opacity(0.92)

            if reveal {
                if let originalImage {
                    Image(uiImage: originalImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(
                            SimultaneousGesture(
                                MagnificationGesture()
                                    .onChanged { value in scale = min(max(lastScale * value, 1), 5) }
                                    .onEnded { _ in lastScale = scale },
                                DragGesture()
                                    .onChanged { value in
                                        guard scale > 1 else { return }
                                        offset = CGSize(width: lastOffset.width + value.translation.width,
                                                        height: lastOffset.height + value.translation.height)
                                    }
                                    .onEnded { _ in lastOffset = offset }
                            )
                        )
                        .onTapGesture(count: 2) { resetZoom() }
                } else {
                    ProgressView()
                        .tint(.white)
                }
            } else if let maskImage {
                Image(uiImage: maskImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .blur(radius: 26)
            } else {
                ProgressView().tint(.white)
            }

            if loadingOriginal {
                VStack {
                    Spacer()
                    HStack(spacing: 6) {
                        ProgressView().tint(.white).scaleEffect(0.7)
                        Text("正在载入原图…").font(.caption).foregroundStyle(.white)
                    }
                    .padding(.bottom, 10)
                }
            }

            if reveal && scale > 1 {
                VStack {
                    HStack {
                        Spacer()
                        Text("双击复位 · 捏合缩放")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(8)
                    }
                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 340)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .contentShape(Rectangle())
        .onTapGesture {
            // 点图片也能切换打码（原图没载好时也能用）
            if reveal {
                reveal = false
                resetZoom()
            } else {
                Task { await showOriginal() }
            }
        }
    }

    private var infoBar: some View {
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
            if !item.detectedParts.isEmpty {
                Text(item.detectedParts.joined(separator: "·")).font(.caption).foregroundStyle(.secondary)
            }
        }
        .font(.footnote)
        .padding(.horizontal)
    }

    private var actions: some View {
        VStack(spacing: 9) {
            Button {
                if reveal {
                    reveal = false
                    resetZoom()
                } else {
                    Task { await showOriginal() }
                }
            } label: {
                Label(reveal ? "隐藏原图" : "显示原图", systemImage: reveal ? "eye.slash" : "eye")
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
    }

    private var explanation: String {
        """
        ① 加入隐私相册：加密副本存进本 App 的保险箱（ChaCha20-Poly1305，密钥在 Keychain），系统相册里的原图保持不动。
        ② 只删除原图：只删系统相册那一份。
        ③ 两者都做：加密存一份 + 删掉系统相册原图（iOS 保留 30 天「最近删除」，需你自己清空）。
        """
    }

    // MARK: - 原图加载

    private func showOriginal() async {
        if let originalImage {
            reveal = true
            return
        }
        loadingOriginal = true
        let image = await ThumbnailProvider.shared.original(for: item.id)
        loadingOriginal = false
        if let image {
            originalImage = image
            reveal = true
        } else {
            // 取不到就退回中等分辨率预览，至少不是空白
            if let fallback = await ThumbnailProvider.shared.preview(for: item.id) {
                originalImage = fallback
                reveal = true
            }
        }
    }

    private func resetZoom() {
        withAnimation(.easeOut(duration: 0.2)) {
            scale = 1
            lastScale = 1
            offset = .zero
            lastOffset = .zero
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
