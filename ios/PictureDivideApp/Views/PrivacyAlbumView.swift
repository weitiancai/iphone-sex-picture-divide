import Photos
import SwiftUI
import UIKit

/// 「隐私相册」页：管理我们归到系统相簿里的照片。
///
/// 工作方式：
/// - App 把命中的照片归进**系统相簿**「隐私相册」（Photos 里能直接看到）
/// - 点顶部按钮打开系统相册 → 打开「隐私相册」→ 全选 → 隐藏，就进了系统的「已隐藏」
/// - iOS 27+ App 能直接把它设成「已隐藏」（公开 API），这里会显示状态
struct PrivacyAlbumView: View {
    @EnvironmentObject private var state: AppState
    @State private var hiddenIDs: Set<String> = []

    private let columns = [GridItem(.adaptive(minimum: 104, maximum: 160), spacing: 3)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    guideCard

                    if state.albumAssets.isEmpty {
                        Text("相簿「\(state.albumTitle)」里还没有照片。在「复核」里点「加入隐私相册」就会归进来。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                    } else {
                        LazyVGrid(columns: columns, spacing: 3) {
                            ForEach(state.albumAssets, id: \.localIdentifier) { asset in
                                cell(asset)
                            }
                        }
                        .padding(.horizontal, 1)
                    }
                }
                .padding(.vertical, 8)
            }
            .navigationTitle("隐私相册")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        state.refreshAlbumAssets()
                        refreshHiddenFlags()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .task {
                state.refreshAlbumAssets()
                refreshHiddenFlags()
            }
        }
    }

    private var guideCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("整册隐藏到系统「已隐藏」", systemImage: "eye.slash")
                .font(.headline)
            Text("""
            ① 点下面的按钮打开系统「照片」
            ② 切到「相簿」→ 打开「\(state.albumTitle)」
            ③ 点「全选」→ 分享/更多 → 「隐藏」
            完成后这批照片就在 Photos → 精选集 → 更多项目 → 已隐藏（Face ID 保护）里了。
            """)
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                state.openSystemPhotos()
            } label: {
                Label("打开系统照片", systemImage: "photo.on.rectangle.angled")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 12)
    }

    private func cell(_ asset: PHAsset) -> some View {
        ZStack(alignment: .topTrailing) {
            AlbumCell(asset: asset)
                .aspectRatio(1, contentMode: .fill)
                .clipped()
                .overlay(alignment: .bottomLeading) {
                    if hiddenIDs.contains(asset.localIdentifier) {
                        Label("已隐藏", systemImage: "eye.slash.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 4).padding(.vertical, 2)
                            .background(.black.opacity(0.55))
                            .foregroundStyle(.green)
                            .padding(4)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    Menu {
                        Button("移出该相簿", role: .destructive) {
                            Task { await removeFromAlbum(asset) }
                        }
                        Button("从系统相册删除", role: .destructive) {
                            Task { await deleteAsset(asset) }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .black.opacity(0.35))
                            .padding(6)
                    }
                }
        }
    }

    private func refreshHiddenFlags() {
        var set: Set<String> = []
        for asset in state.albumAssets where PhotoLibrary.isHidden(asset) {
            set.insert(asset.localIdentifier)
        }
        hiddenIDs = set
    }

    private func removeFromAlbum(_ asset: PHAsset) async {
        guard let collection = PhotoLibrary.album(named: state.albumTitle) else { return }
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges({
                guard let request = PHAssetCollectionChangeRequest(for: collection) else { return }
                request.removeAssets([asset] as NSArray)
            }, completionHandler: { _, _ in continuation.resume(returning: ()) })
        }
        state.refreshAlbumAssets()
        refreshHiddenFlags()
    }

    private func deleteAsset(_ asset: PHAsset) async {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.deleteAssets([asset] as NSArray)
            }, completionHandler: { _, _ in continuation.resume(returning: ()) })
        }
        state.refreshAlbumAssets()
        refreshHiddenFlags()
    }
}

/// 相簿里单张照片的小图。
private struct AlbumCell: View {
    let asset: PHAsset
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ProgressView().scaleEffect(0.5)
            }
        }
        .task {
            image = await PhotoLibrary.thumbnail(for: asset, size: CGSize(width: 420, height: 420))
        }
    }
}
