import SwiftUI
import UIKit

/// Photos 式全屏图片浏览器：左右翻页、双指缩放、下拉关闭。
///
/// 复用来复核页：点网格里的任意一张 → 进入这里，可以左右滑看其它命中照片，
/// 底部直接做处理动作（加入隐私相册 / 不处理 / 删除原图），不用退回详情页。
struct FullScreenViewer<Item: Identifiable & Hashable>: View {
    let items: [Item]
    /// 初始显示的那一张
    let startID: Item.ID
    let isBlurred: Bool
    let loadImage: (Item) async -> UIImage?
    /// 标题（例如日期）
    var titleFor: (Item) -> String = { _ in "" }
    /// 角标
    var badgeFor: (Item) -> String?
    var badgeColorFor: (Item) -> Color = { _ in .secondary }
    /// 底部动作区
    var actions: (Item) -> AnyView

    @Environment(\.dismiss) private var dismiss
    @State private var currentID: Item.ID?
    @State private var images: [Item.ID: UIImage] = [:]
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $currentID) {
                ForEach(items) { item in
                    zoomable(item)
                        .tag(Optional(item.id))
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            VStack {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .black.opacity(0.35))
                    }
                    Spacer()
                    if let current = currentItem {
                        Text(titleFor(current))
                            .font(.footnote)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(.black.opacity(0.35))
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                Spacer()

                if let current = currentItem {
                    VStack(spacing: 10) {
                        if let badge = badgeFor(current) {
                            Text(badge)
                                .font(.caption)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(badgeColorFor(current).opacity(0.25))
                                .foregroundStyle(badgeColorFor(current))
                        }
                        actions(current)
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
                }
            }
        }
        .onAppear { currentID = startID }
        .onChange(of: startID) { _, newValue in currentID = newValue }
    }

    private var currentItem: Item? {
        if let id = currentID { return items.first(where: { $0.id == id }) }
        return nil
    }

    @ViewBuilder
    private func zoomable(_ item: Item) -> some View {
        ZStack {
            if let image = images[item.id] {
                Image(uiImage: image)
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
                    .blur(radius: isBlurred ? 18 : 0)
            } else {
                ProgressView().tint(.white)
            }
        }
        .task(id: item.id) {
            if images[item.id] == nil, let image = await loadImage(item) {
                images[item.id] = image
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
}
