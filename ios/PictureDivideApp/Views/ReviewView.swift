import PictureDivideCore
import SwiftUI
import UIKit

/// 复核页：相册式网格 + 多选 + 批量操作。
struct ReviewView: View {
    @EnvironmentObject private var state: AppState

    /// 多选中的资源 id。
    @State private var selection: Set<String> = []
    @State private var selecting = false
    @State private var detail: FlaggedItem?
    /// 网格是否打码（默认打码，一键全显示）。
    @State private var blurred = true
    @State private var busy = false

    private var pending: [FlaggedItem] { state.flagged.filter { $0.state == .pending } }
    private var moved: [FlaggedItem] { state.flagged.filter { $0.state == .moved } }

    private let columns = [GridItem(.adaptive(minimum: 104, maximum: 160), spacing: 3)]

    var body: some View {
        NavigationStack {
            Group {
                if state.flagged.isEmpty {
                    ContentUnavailableView("还没有命中结果",
                                           systemImage: "checkmark.shield",
                                           description: Text("先去「扫描」跑一遍，命中的照片会出现在这里等你处理。"))
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 3) {
                            ForEach(pending) { item in
                                cell(item)
                            }
                        }
                        .padding(.horizontal, 1)

                        if !moved.isEmpty {
                            sectionHeader("已加入隐私相册（\(moved.count)）")
                            LazyVGrid(columns: columns, spacing: 3) {
                                ForEach(moved) { item in
                                    cell(item, dimmed: true)
                                }
                            }
                            .padding(.horizontal, 1)
                        }

                        if state.ignoredCount > 0 {
                            sectionHeader("已标记为不处理（\(state.ignoredCount)）—— 右上角菜单可以恢复")
                        }
                    }
                }
            }
            .navigationTitle(selecting ? "已选 \(selection.count) 张" : "复核")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Toggle("网格打码", isOn: $blurred)
                        Button("全选本页") {
                            selection = Set(pending.map(\.id))
                            selecting = true
                        }
                        if state.ignoredCount > 0 {
                            Button("恢复已标记为不处理的 \(state.ignoredCount) 张") {
                                state.restoreIgnored()
                            }
                        }
                        Button("取消选择") {
                            selection = []
                            selecting = false
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
            .sheet(item: $detail) { item in
                DetailSheet(item: item)
                    .environmentObject(state)
            }
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.top, 12)
            .padding(.horizontal, 12)
    }

    // MARK: - 网格单元

    @ViewBuilder
    private func cell(_ item: FlaggedItem, dimmed: Bool = false) -> some View {
        let isSelected = selection.contains(item.id)
        ZStack(alignment: .topTrailing) {
            GridThumbnail(item: item, blurred: blurred)
                .aspectRatio(1, contentMode: .fill)
                .clipped()
                .opacity(dimmed ? 0.45 : 1)
                .overlay(alignment: .bottomLeading) {
                    Text(item.tier.displayName)
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 4).padding(.vertical, 2)
                        .background(.black.opacity(0.55))
                        .foregroundStyle(tierColor(item.tier))
                        .padding(4)
                }
                .overlay {
                    if selecting && isSelected {
                        Color.accentColor.opacity(0.3)
                    }
                }
                .overlay(alignment: .topLeading) {
                    if selecting {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, isSelected ? Color.accentColor : Color.black.opacity(0.4))
                            .padding(6)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if selecting {
                        if isSelected { selection.remove(item.id) } else { selection.insert(item.id) }
                    } else {
                        detail = item
                    }
                }
                .onLongPressGesture {
                    if !selecting {
                        selecting = true
                        selection.insert(item.id)
                    }
                }
        }
    }

    // MARK: - 批量操作条

    private var batchBar: some View {
        VStack(spacing: 8) {
            if busy {
                ProgressView()
                    .padding(.vertical, 4)
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

                Button {
                    batchIgnore()
                } label: {
                    Label("不处理", systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)
                .disabled(busy)

                Menu {
                    Button("批量删除原图", role: .destructive) {
                        Task { await batchDeleteOriginals() }
                    }
                    Button("批量加入并删除原图", role: .destructive) {
                        Task { await batchAddAndDelete() }
                    }
                } label: {
                    Label("更多", systemImage: "ellipsis.circle")
                }
                .buttonStyle(.bordered)
                .disabled(busy)
            }
            Text("“加入隐私相册”只加密存副本，系统相册原图不动；删除才会动原图；“不处理”两张都不动，只是从列表里收走。")
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

    private func batchAddAndDelete() async {
        busy = true
        await state.addToPrivateAlbumAndDeleteOriginals(selectedItems())
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

/// 网格里的单张缩略图（异步加载 + 可选打码）。
private struct GridThumbnail: View {
    let item: FlaggedItem
    let blurred: Bool
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .blur(radius: blurred ? 10 : 0)
            } else {
                Rectangle().fill(.quaternary)
                    .overlay(ProgressView().scaleEffect(0.6))
            }
        }
        .task(id: item.id) {
            if let cached = item.thumbnail {
                image = cached
            } else if let loaded = await ThumbnailProvider.shared.thumbnail(for: item.id) {
                image = loaded
            }
        }
    }
}
