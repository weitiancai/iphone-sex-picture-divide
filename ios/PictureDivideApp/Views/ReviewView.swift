import SwiftUI
import UIKit
import PictureDivideCore

struct ReviewView: View {
    @EnvironmentObject private var state: AppState
    @State private var selected: FlaggedItem?

    private var pending: [FlaggedItem] { state.flagged.filter { $0.state == .pending } }
    private var moved: [FlaggedItem] { state.flagged.filter { $0.state == .moved } }

    var body: some View {
        NavigationStack {
            Group {
                if state.flagged.isEmpty {
                    ContentUnavailableView("还没有命中结果",
                                           systemImage: "checkmark.shield",
                                           description: Text("先去「扫描」跑一遍，命中的照片会出现在这里等你处理。"))
                } else {
                    List {
                        Section {
                            ForEach(pending) { item in
                                Button {
                                    selected = item
                                } label: {
                                    row(for: item)
                                }
                                .buttonStyle(.plain)
                            }
                        } header: {
                            Text("待处理 \(pending.count) 张")
                        } footer: {
                            Text("缩略图默认打码。点开可以看大图，再决定「移入保险箱」还是「这是误报」。")
                        }

                        if !moved.isEmpty {
                            Section("已加入隐私相册") {
                                ForEach(moved) { item in
                                    HStack {
                                        Image(systemName: "lock.fill")
                                        Text(item.creationDate?.formatted(date: .abbreviated, time: .omitted) ?? item.id)
                                        Spacer()
                                        Text("已加入隐私相册").foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("复核")
            .sheet(item: $selected) { item in
                DetailSheet(item: item)
                    .environmentObject(state)
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

    private func row(for item: FlaggedItem) -> some View {
        HStack(spacing: 12) {
            ZStack {
                if let thumb = item.thumbnail {
                    Image(uiImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 56, height: 56)
                        .clipped()
                        .blur(radius: 10)
                } else {
                    Rectangle().fill(.quaternary).frame(width: 56, height: 56)
                }
                Image(systemName: "lock.fill")
                    .foregroundStyle(.white)
                    .shadow(radius: 2)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(item.creationDate?.formatted(date: .abbreviated, time: .omitted) ?? "未知日期")
                    .font(.headline)
                HStack(spacing: 6) {
                    Text(String(format: "%.2f", item.score))
                        .font(.caption.monospacedDigit())
                    Text(item.tier.displayName)
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(tierColor(item.tier).opacity(0.25))
                        .foregroundStyle(tierColor(item.tier))
                    if item.timesDetected > 1 {
                        Text("×\(item.timesDetected)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    if !item.detectedParts.isEmpty {
                        Text(item.detectedParts.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

private struct DetailSheet: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    let item: FlaggedItem
    @State private var reveal = false
    @State private var working = false
    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                ZStack {
                    if let image = item.previewImage {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .blur(radius: reveal ? 0 : 26)
                    } else {
                        Rectangle().fill(.quaternary).frame(height: 240)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(maxHeight: 320)
                .background(.black.opacity(0.92))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                HStack {
                    Text(String(format: "总分 %.3f", item.score))
                    Spacer()
                    Text(item.detectedParts.isEmpty ? "未识别到具体部位" : item.detectedParts.joined(separator: " · "))
                        .foregroundStyle(.secondary)
                }
                .font(.footnote)

                VStack(spacing: 10) {
                    Button {
                        reveal.toggle()
                    } label: {
                        Label(reveal ? "隐藏" : "显示原图", systemImage: reveal ? "eye.slash" : "eye")
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
                ① 加入隐私相册：加密副本存进本 App 的保险箱（ChaCha20-Poly1305，密钥在 Keychain），**系统相册里的原图保持不动**。
                ② 只删除原图：只删系统相册那一份，保险箱里已有副本的话会标注“原图已删除”。
                ③ 两者都做：加密存一份 + 删掉系统相册原图（iOS 会保留 30 天“最近删除”，需你自己清空）。
                """)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                Spacer()
            }
            .padding(.top)
            .navigationTitle("复核")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
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
}
