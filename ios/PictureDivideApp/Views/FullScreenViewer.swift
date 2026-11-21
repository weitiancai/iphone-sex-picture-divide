import SwiftUI
import UIKit

/// Photos 式全屏图片浏览器：左右翻页、双指缩放、底部固定操作栏。
///
/// 布局要点（避免之前的三个坑）：
/// - **翻页区与操作栏上下分离**（VStack，不是互相盖住的 ZStack），
///   这样底部的按钮不会被 TabView 吃掉点击。
/// - 操作栏**不套 `.tint(.white)`**（会把按钮主色也变成白底白字看不见）。
/// - 图片**默认清晰显示**（打码是可选项，不是默认），点开就是为了看图。
/// - 先快速取预览图，再在后台升级成原图；取不到会给出提示而不是一直转圈。
struct FullScreenViewer<Item: Identifiable & Hashable>: View {
    let items: [Item]
    let startID: Item.ID
    /// 是否默认打码（默认 false：点开就看清楚）
    var isBlurred: Bool = false
    let loadPreview: (Item) async -> UIImage?
    let loadOriginal: (Item) async -> UIImage?
    var titleFor: (Item) -> String = { _ in "" }
    var badgeFor: (Item) -> String?
    var badgeColorFor: (Item) -> Color = { _ in .secondary }
    /// 底部动作区
    var actions: (Item) -> AnyView

    @Environment(\.dismiss) private var dismiss
    @State private var currentID: Item.ID?
    @State private var images: [Item.ID: UIImage] = [:]
    @State private var failedIDs: Set<Item.ID> = []
    @State private var blurred = false
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                Color.black

                TabView(selection: Binding(get: { currentID }, set: { newValue in
                    if let newValue { currentID = newValue; resetZoom() }
                })) {
                    ForEach(items) { item in
                        zoomable(item)
                            .tag(Optional(item.id))
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                header
            }

            if let current = currentItem {
                controlBar(for: current)
            }
        }
        .background(Color.black)
        .onAppear {
            currentID = startID
            blurred = isBlurred
        }
        .onChange(of: startID) { _, newValue in currentID = newValue }
    }

    // MARK: - 顶部（关闭 + 标题 + 打码开关）

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.35))
            }
            .buttonStyle(.plain)

            Spacer()

            if let current = currentItem, !titleFor(current).isEmpty {
                Text(titleFor(current))
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(.black.opacity(0.4))
                    .clipShape(Capsule())
            }

            Spacer()

            Button {
                blurred.toggle()
            } label: {
                Image(systemName: blurred ? "eye.slash.fill" : "eye.fill")
                    .font(.title3)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.35))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    // MARK: - 底部操作栏（独立于翻页区，点击不会被吞）

    private func controlBar(for item: Item) -> some View {
        VStack(spacing: 10) {
            if let badge = badgeFor(item) {
                Text(badge)
                    .font(.caption)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(badgeColorFor(item).opacity(0.3))
                    .foregroundStyle(badgeColorFor(item))
            }
            actions(item)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
    }

    // MARK: - 图片

    @ViewBuilder
    private func zoomable(_ item: Item) -> some View {
        ZStack {
            if let image = images[item.id] {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(scale)
                    .offset(offset)
                    .blur(radius: blurred ? 16 : 0)
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
                    .onTapGesture { blurred.toggle() }
            } else if failedIDs.contains(item.id) {
                VStack(spacing: 8) {
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.largeTitle)
                        .foregroundStyle(.white.opacity(0.7))
                    Text("这张照片读不出来了（可能已被从相册删除）")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
            } else {
                ProgressView().tint(.white)
            }
        }
        .task(id: item.id) {
            guard images[item.id] == nil else { return }
            // 先拿预览图（快），再后台换成原图
            if let preview = await loadPreview(item) {
                images[item.id] = preview
            }
            if let original = await loadOriginal(item) {
                images[item.id] = original
            } else if images[item.id] == nil {
                failedIDs.insert(item.id)
            }
        }
    }

    private var currentItem: Item? {
        if let id = currentID { return items.first(where: { $0.id == id }) }
        return nil
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
