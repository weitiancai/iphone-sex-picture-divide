import SwiftUI
import UIKit
import PictureDivideCore

struct VaultView: View {
    @EnvironmentObject private var state: AppState
    @State private var previewItem: VaultItem?

    var body: some View {
        NavigationStack {
            Group {
                if !state.vaultUnlocked {
                    VStack(spacing: 16) {
                        Image(systemName: "lock.shield")
                            .font(.system(size: 56))
                            .foregroundStyle(.secondary)
                        Text("保险箱已上锁")
                            .font(.title3)
                        Text("需要 Face ID / Touch ID 或设备密码才能打开。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button {
                            Task { await state.unlockVault() }
                        } label: {
                            Label("解锁", systemImage: "faceid")
                        }
                        .buttonStyle(.borderedProminent)
                        if let error = state.vaultError {
                            Text(error).font(.caption).foregroundStyle(.red)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if state.vaultItems.isEmpty {
                    ContentUnavailableView("保险箱是空的",
                                           systemImage: "tray",
                                           description: Text("在「复核」里把命中的照片移进来，就会加密存在这里。"))
                } else {
                    List {
                        ForEach(state.vaultItems) { item in
                            Button {
                                previewItem = item
                            } label: {
                                HStack {
                                    Image(systemName: item.kind == .image ? "photo" : "film")
                                    VStack(alignment: .leading) {
                                        Text(item.originalName)
                                            .font(.subheadline)
                                        Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(ByteCountFormatter.string(fromByteCount: Int64(item.originalByteCount), countStyle: .file))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .swipeActions {
                                Button(role: .destructive) {
                                    state.deleteFromVault(item)
                                } label: {
                                    Label("彻底删除", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("保险箱")
            .toolbar {
                if state.vaultUnlocked {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            state.lockVault()
                        } label: {
                            Image(systemName: "lock")
                        }
                    }
                }
            }
            .sheet(item: $previewItem) { item in
                VaultPreview(item: item)
                    .environmentObject(state)
            }
        }
    }
}

private struct VaultPreview: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    let item: VaultItem
    @State private var image: UIImage?

    var body: some View {
        NavigationStack {
            VStack {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    ProgressView()
                }
                Spacer()
                HStack {
                    Button(role: .destructive) {
                        state.deleteFromVault(item)
                        dismiss()
                    } label: {
                        Label("彻底删除", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                    Button {
                        Task {
                            await state.restore(item)
                            dismiss()
                        }
                    } label: {
                        Label("恢复到系统相册", systemImage: "arrow.uturn.backward.circle")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
            .navigationTitle(item.originalName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .task {
                if let data = state.imageData(for: item) {
                    image = UIImage(data: data)
                }
            }
        }
    }
}
