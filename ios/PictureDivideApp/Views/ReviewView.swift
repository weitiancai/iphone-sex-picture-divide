import SwiftUI
import UIKit

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
                            Section("已移入保险箱") {
                                ForEach(moved) { item in
                                    HStack {
                                        Image(systemName: "lock.fill")
                                        Text(item.creationDate?.formatted(date: .abbreviated, time: .omitted) ?? item.id)
                                        Spacer()
                                        Text("已隔离").foregroundStyle(.secondary)
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
                            await state.moveToVault(item)
                            working = false
                            dismiss()
                        }
                    } label: {
                        Label(working ? "处理中…" : "移入加密保险箱并删除原图", systemImage: "lock.shield")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(working)

                    Button {
                        state.markAsSafe(item)
                        dismiss()
                    } label: {
                        Label("这是误报（保持原样）", systemImage: "arrow.uturn.backward")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal)

                Text("移入保险箱后：照片会被加密存进 App 沙盒（ChaCha20-Poly1305，密钥在 Keychain），系统相册里的原图会被删除（iOS 会保留 30 天「最近删除」，需要你自己清空）。")
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
        }
    }
}
