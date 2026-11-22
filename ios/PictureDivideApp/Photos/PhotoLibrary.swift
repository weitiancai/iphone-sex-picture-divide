import Foundation
import ImageIO
import Photos
import UIKit
import UniformTypeIdentifiers

/// 防止 `withCheckedContinuation` 被 resume 多次（会触发 Swift 运行时 trap：SWIFT CHECKED CONTINUATION MISUSE）。
///
/// `PHImageRequestOptions.deliveryMode = .opportunistic` 会回调两次（先低清后高清），
/// 所有 PhotoKit 请求都必须用这个兜底。
final class OneShot<T, F: Error> {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, F>?

    init(_ continuation: CheckedContinuation<T, F>) {
        self.continuation = continuation
    }

    func resume(returning value: T) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
    }

    func resume(throwing error: F) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(throwing: error)
    }
}

/// 相册读取 + 资源搬运（删除 / 恢复）。
enum PhotoLibrary {
    static func authorizationStatus() -> PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    static func requestAuthorization() async -> PHAuthorizationStatus {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                continuation.resume(returning: status)
            }
        }
    }

    /// 读取资源的原始图片数据（尽量保留原始编码，便于后续解密写回）。
    static func imageData(for asset: PHAsset) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.version = .current
            options.deliveryMode = .highQualityFormat
            let shot = OneShot(continuation)
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                if let data {
                    shot.resume(returning: data)
                } else {
                    shot.resume(throwing: PhotoError.imageDataUnavailable)
                }
            }        }
    }

    /// 生成缩略图（用于网格展示）。
    /// 用 `.exact` + `.highQualityFormat`，避免 `.fast` 带来的模糊。
    static func thumbnail(for asset: PHAsset, size: CGSize = CGSize(width: 420, height: 420)) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .exact
            let shot = OneShot(continuation)
            PHImageManager.default().requestImage(for: asset, targetSize: size, contentMode: .aspectFill, options: options) { image, _ in
                shot.resume(returning: image)
            }
        }
    }

    /// 生成预览图（中等分辨率，用于详情页背景/缩略）。
    static func preview(for asset: PHAsset, size: CGSize = CGSize(width: 1200, height: 1200)) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .exact
            let shot = OneShot(continuation)
            PHImageManager.default().requestImage(for: asset, targetSize: size, contentMode: .aspectFit, options: options) { image, _ in
                shot.resume(returning: image)
            }
        }
    }

    /// 取**原图**（按需缩放到 maxPixel 长边，避免解码十几 MB 的 HEIC）。
    /// 用 ImageIO 的 thumbnail 接口，只解一次缩略，不整张解码。
    static func originalImage(for asset: PHAsset, maxPixel: CGFloat = 2400) async -> UIImage? {
        guard let data = try? await imageData(for: asset),
              data.count <= 80 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    /// 资产对应的 CGImage（用于送检模型）。
    static func cgImage(for asset: PHAsset, size: CGSize = CGSize(width: 1024, height: 1024)) async -> CGImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            let shot = OneShot(continuation)
            PHImageManager.default().requestImage(for: asset, targetSize: size, contentMode: .aspectFit, options: options) { image, _ in
                guard let image else {
                    shot.resume(returning: nil)
                    return
                }
                shot.resume(returning: image.cgImage)
            }
        }
    }

    /// 删除相册里的原始资源（会进"最近删除"，30 天后彻底消失）。
    static func delete(asset: PHAsset) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.deleteAssets([asset] as NSArray)
            }) { success, error in
                if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: error ?? PhotoError.deleteFailed)
                }
            }
        }
    }

    /// 把一张图片写回系统相册。
    static func save(imageData: Data, filename: String) async throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try imageData.write(to: tempURL, options: [.atomic])
        defer { try? FileManager.default.removeItem(at: tempURL) }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetCreationRequest.creationRequestForAssetFromImage(atFileURL: tempURL)
                request?.creationDate = Date()
            }) { success, error in
                if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: error ?? PhotoError.saveFailed)
                }
            }
        }
    }



    // MARK: - 系统相簿（分类） + 关键词标签 + 隐藏
    //
    // iOS 27 起 PhotoKit 公开了：
    //   PHAssetChangeRequest.hidden   → 直接把资源移进系统「已隐藏」相簿
    //   PHAssetChangeRequest.addKeyword(_:) → 打关键词标签
    //   PHAsset.extendedMetadata.keywords → 读标签
    // iOS 26 及以下没有这些公开 API，只能退而求其次：
    //   把资源归进一个**系统相簿**（公开 API，任何系统版本都支持），
    //   由用户在系统相册里对该相簿「全选 → 隐藏」。

    /// 找到（或创建）指定标题的系统相簿。
    static func album(named title: String) -> PHAssetCollection? {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "title = %@", title)
        return PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: options).firstObject
    }

    /// 把资源加入指定相簿（相簿不存在则创建）。
    static func addToAlbum(_ assets: [PHAsset], albumTitle: String) async throws {
        guard !assets.isEmpty else { return }
        var collection = album(named: albumTitle)

        if collection == nil {
            // 先创建
            var placeholder: PHObjectPlaceholder?
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                PHPhotoLibrary.shared().performChanges({
                    let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: albumTitle)
                    placeholder = request.placeholderForCreatedAssetCollection
                }, completionHandler: { success, error in
                    if success { continuation.resume(returning: ()) }
                    else { continuation.resume(throwing: error ?? PhotoError.changeFailed) }
                })
            }
            guard let id = placeholder?.localIdentifier,
                  let created = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil).firstObject else {
                throw PhotoError.changeFailed
            }
            collection = created
        }

        guard let collection else { throw PhotoError.changeFailed }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                guard let request = PHAssetCollectionChangeRequest(for: collection) else { return }
                request.addAssets(assets as NSArray)
            }, completionHandler: { success, error in
                if success { continuation.resume(returning: ()) }
                else { continuation.resume(throwing: error ?? PhotoError.changeFailed) }
            })
        }
    }

    /// 相簿里的资源。
    static func assets(inAlbumTitled title: String) -> [PHAsset] {
        guard let collection = album(named: title) else { return [] }
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        var result: [PHAsset] = []
        PHAsset.fetchAssets(in: collection, options: options).enumerateObjects { asset, _, _ in
            result.append(asset)
        }
        return result
    }

    /// iOS 27+：直接设为「已隐藏」。iOS 26 及以下返回 false。
    @discardableResult
    static func setHiddenPublic(_ hidden: Bool, for asset: PHAsset) async throws -> Bool {
        if #available(iOS 27.0, *) {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                PHPhotoLibrary.shared().performChanges({
                    let request = PHAssetChangeRequest(for: asset)
                    request.isHidden = hidden
                }, completionHandler: { success, error in
                    if success { continuation.resume(returning: ()) }
                    else { continuation.resume(throwing: error ?? PhotoError.changeFailed) }
                })
            }
            return true
        }
        return false
    }

    /// iOS 27+：给资源打关键词标签。
    @discardableResult
    static func addKeyword(_ keyword: String, to asset: PHAsset) async throws -> Bool {
        if #available(iOS 27.0, *) {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                PHPhotoLibrary.shared().performChanges({
                    let request = PHAssetChangeRequest(for: asset)
                    request.addKeyword(keyword)
                }, completionHandler: { success, error in
                    if success { continuation.resume(returning: ()) }
                    else { continuation.resume(throwing: error ?? PhotoError.changeFailed) }
                })
            }
            return true
        }
        return false
    }

    /// 读资源的关键词（iOS 27+）。
    static func keywords(of asset: PHAsset) -> [String] {
        if #available(iOS 27.0, *) {
            return asset.extendedMetadata.keywords
        }
        return []
    }

    /// 打开系统相册 App（用于引导用户「全选 → 隐藏」）。
    static func openSystemPhotos() {
        guard let url = URL(string: "photos-redirect://") else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - 系统「已隐藏」相簿
    //
    // PhotoKit 的**公开 API 没有**把资源移进「已隐藏」的能力（头文件里连 hidden 都没有）。
    // 但 iOS 运行时里存在私有入口：
    //   PHAssetChangeRequest.setHidden: / isHidden
    //   PHAsset.isHidden
    // 这里用 KVC 调用（KVC 会正确处理 BOOL 的装箱），并在调用前检查 selector 是否存在，
    // 不存在就返回错误而不是崩溃。
    // ⚠️ 私有 API：不能上架 App Store，仅供自用。

    /// 把资源移进系统「已隐藏」（或取消隐藏）。
    static func setHidden(_ hidden: Bool, for asset: PHAsset) async throws {
        let selector = NSSelectorFromString("setHidden:")
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetChangeRequest(for: asset)
                guard request.responds(to: selector) else {
                    continuation.resume(throwing: PhotoError.hiddenNotSupported)
                    return
                }
                request.setValue(NSNumber(value: hidden), forKey: "hidden")
            }) { success, error in
                if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: error ?? PhotoError.changeFailed)
                }
            }
        }
    }

    /// 判断某个资源当前是否在「已隐藏」里。
    static func isHidden(_ asset: PHAsset) -> Bool {
        guard asset.responds(to: NSSelectorFromString("isHidden")) else { return false }
        return (asset.value(forKey: "hidden") as? NSNumber)?.boolValue ?? false
    }

    /// 列出系统「已隐藏」里的照片。
    static func hiddenAssets() -> [PHAsset] {
        let result = PHAsset.fetchAssets(with: .image, options: nil)
        var hidden: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in
            if isHidden(asset) { hidden.append(asset) }
        }
        return hidden
    }

    /// 重新编码一张图，剥掉 EXIF/GPS 等元数据（保险箱里只保留画面本身）。
    static func stripMetadata(from data: Data) -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return data
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            return data
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return data }
        return output as Data
    }

    enum PhotoError: LocalizedError {
        case imageDataUnavailable
        case deleteFailed
        case saveFailed
        case changeFailed
        case hiddenNotSupported

        var errorDescription: String? {
            switch self {
            case .imageDataUnavailable: return "读取这张照片的数据失败（可能还在 iCloud 未下载）。"
            case .deleteFailed: return "从系统相册删除失败。"
            case .saveFailed: return "写回系统相册失败。"
            case .changeFailed: return "修改系统相册失败。"
            case .hiddenNotSupported: return "当前 iOS 版本不支持程序化移入「已隐藏」相簿。"
            }
        }
    }
}
