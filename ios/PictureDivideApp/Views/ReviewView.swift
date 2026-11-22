import PictureDivideCore
import SwiftUI
import UIKit

/// 复核页：Photos 式网格 + 全屏浏览 + 多选批量操作。
struct ReviewView: View {
    @EnvironmentObject private var state: AppState

    @State private var selection: Set<String> = []
    @State private var selecting = false
    @State private var viewing: FlaggedItem?
    @State private var blurred = false
    @State private var busy = false

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
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            grid(for: pending)

                            if !moved.isEmpty {
                                header("已加入隐私相册（\(moved.count)）")
                                grid(for: moved, dimmed: true)
                            }
                            if state.ignoredCount > 0 {
                                header("已标记为不处理（\(state.ignoredCount)）—— 右上角菜单可以恢复")
                            }
                        }
                    }
                }
            }
            .navigationTitle(selecting ? "已选 \(selection.count) 张" : "复核")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Toggle("图片打码", isOn: $blurred)
                        Button(selecting ? "退出多选" : "进入多选") {
                            selecting.toggle()
                            if !selecting { selection = [] }
                        }
                        if !pending.isEmpty {
                            Button("全选待处理（\(pending.count) 张）") {
                                selection = Set(pending.map(\.id))
                                selecting = true
                            }
                        }
                        if state.ignoredCount > 0 {
                            Button("恢复已标记为不处理的 \(state.ignoredCount) 张") {
                                state.restoreIgnored()
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if selecting && !selection.isEmpty {
                    batchBar
                }
            }
            .fullScreenCover(item: $viewing) { item in
                FullScreenViewer(items: pending.isEmpty ? [item] : pending,
                                 startID: item.id,
                                 isBlurred: blurred,
                                 loadPreview: { item in
                                     if let thumb = item.thumbnail { return thumb }
                                     return await ThumbnailProvider.shared.thumbnail(for: item.id)
                                 },
                                 loadOriginal: { item in
                                     await ThumbnailProvider.shared.original(for: item.id)
                                 },
                                 titleFor: { item in
                                     item.creationDate?.formatted(date: .abbreviated, time: .omitted) ?? ""
                                 },
                                 badgeFor: { $0.tier.displayName },
                                 badgeColorFor: { tierColor($0.tier) },
                                 actions: { current in
                                     AnyView(viewerActions(current))
                                 })
            }
        }
    }

    // MARK: - 网格

    private func grid(for items: [FlaggedItem], dimmed: Bool = false) -> some View {
        PhotoGridView(items: items,
                      columnCount: 3,
                      spacing: 2,
                      isBlurred: blurred,
                      selectedIDs: selection,
                      isSelecting: selecting,
                      badgeText: { $0.tier.displayName },
                      badgeColor: { tierColor($0.tier) },
                      loadImage: { item in
                          if let thumb = item.thumbnail { return thumb }
                          return await ThumbnailProvider.shared.thumbnail(for: item.id)
                      },
                      onTap: { item in
                          if selecting {
                              if selection.contains(item.id) { selection.remove(item.id) }
                              else { selection.insert(item.id) }
                          } else {
                              viewing = item
                          }
                      },
                      onLongPress: { item in
                          if !selecting {
                              selecting = true
                              selection.insert(item.id)
                          }
                      })
        .opacity(dimmed ? 0.45 : 1)
    }

    private func header(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
    }

    // MARK: - 全屏浏览器里的动作

    @ViewBuilder
    private func viewerActions(_ item: FlaggedItem) -> some View {
        HStack(spacing: 10) {
            Button {
                Task { await state.addToPrivateAlbum(item) }
            } label: {
                Label("加入隐私相册", systemImage: "lock.shield")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button(role: .destructive) {
                Task { await state.deleteOriginal(item) }
            } label: {
                Label("删除", systemImage: "trash")
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - 批量操作条

    private var batchBar: some View {
        VStack(spacing: 8) {
            if busy {
                ProgressView().padding(.vertical, 4)
            }
            HStack(spacing: 10) {
                Button {
                    Task { await batchAddToVault() }
                } label: {
                    Label("批量加入隐私相册", systemImage: "lock.shield")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(busy)

                Button(role: .destructive) {
                    Task { await batchDeleteOriginals() }
                } label: {
                    Label("批量删除", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .disabled(busy)

                Button {
                    batchIgnore()
                } label: {
                    Label("不处理", systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)
                .disabled(busy)
            }
            Text("加入隐私相册 = 移进系统相册的「已隐藏」（Face ID 保护）；删除 = 从系统相册移除；不处理 = 什么都不做。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }

    // MARK: - 批量动作

    private func selectedItems() -> [FlaggedItem] {
        pending.filter { selection.contains($0.id) }
    }

    private func batchAddToVault() async {
        busy = true
        await state.addToPrivateAlbum(selectedItems())
        busy = false
        selection = []
        selecting = false
    }

    private func batchDeleteOriginals() async {
        busy = true
        await state.deleteOriginals(selectedItems())
        busy = false
        selection = []
        selecting = false
    }

    /// 批量标记为“不要处理”：原图不动，只是从待处理列表里收走。
    private func batchIgnore() {
        state.markAsSafe(selectedItems())
        selection = []
        selecting = false
    }

    private func tierColor(_ tier: SensitivityTier) -> Color {
        switch tier {
        case .explicit: return .red
        case .suspected: return .orange
        case .safe: return .secondary
        }
    }
}
