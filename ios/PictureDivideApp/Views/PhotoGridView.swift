import SwiftUI
import UIKit

/// 通用图片网格组件（可复用）。
///
/// 关键点（之前踩过的坑）：
/// - **单元格尺寸一次性算准**（按容器宽度），不依赖图片是否加载完，
///   所以图片还没出来时也不会塌陷/错位/重叠。
/// - 加载中的占位是固定尺寸的 `Rectangle`，不是自适应内容。
/// - 图片一律 `.clipped()`，永远不会溢出到相邻格子。
struct PhotoGridView<Item: Identifiable & Hashable>: View {
    let items: [Item]
    /// 每行列数
    var columnCount: Int = 3
    /// 间距
    var spacing: CGFloat = 2
    /// 是否打码
    var isBlurred: Bool = true
    /// 选中的 id
    var selectedIDs: Set<Item.ID> = []
    /// 是否处于多选模式
    var isSelecting: Bool = false
    /// 左下角角标文字
    var badgeText: (Item) -> String?
    /// 角标颜色
    var badgeColor: (Item) -> Color = { _ in .secondary }
    /// 异步取图
    var loadImage: (Item) async -> UIImage?
    /// 点击
    var onTap: (Item) -> Void
    /// 长按
    var onLongPress: (Item) -> Void

    @State private var images: [Item.ID: UIImage] = [:]

    /// 容器宽度（默认屏幕宽度；调用方可以传别的值）。
    var containerWidth: CGFloat = UIScreen.main.bounds.width

    /// 单元格边长（正方形）：一次性算准，图片没加载也不会错位。
    private var cellSize: CGFloat {
        max(1, (containerWidth - spacing * CGFloat(columnCount - 1)) / CGFloat(columnCount))
    }

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(cellSize), spacing: spacing),
                                 count: columnCount),
                  spacing: spacing) {
            ForEach(items) { item in
                cellView(item, size: cellSize)
            }
        }
        .frame(width: containerWidth, alignment: .leading)
    }

    @ViewBuilder
    private func cellView(_ item: Item, size: CGFloat) -> some View {
        let isSelected = selectedIDs.contains(item.id)
        ZStack(alignment: .topLeading) {
            // 固定尺寸底板：保证加载前尺寸不变
            Rectangle()
                .fill(Color.secondary.opacity(0.12))
                .frame(width: size, height: size)
                .overlay {
                    if let image = images[item.id] {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .blur(radius: isBlurred ? 8 : 0)
                            .transition(.opacity)
                    } else {
                        ProgressView().scaleEffect(0.5)
                    }
                }
                .clipped()

            if let text = badgeText(item) {
                Text(text)
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 4).padding(.vertical, 2)
                    .background(.black.opacity(0.55))
                    .foregroundStyle(badgeColor(item))
                    .padding(4)
            }

            if isSelecting {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, isSelected ? Color.accentColor : Color.black.opacity(0.35))
                    .padding(6)
            } else if isSelected {
                Color.accentColor.opacity(0.25)
            }
        }
        .frame(width: size, height: size)
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture { onTap(item) }
        .onLongPressGesture { onLongPress(item) }
        .task(id: item.id) {
            if images[item.id] == nil, let image = await loadImage(item) {
                images[item.id] = image
            }
        }
    }
}
