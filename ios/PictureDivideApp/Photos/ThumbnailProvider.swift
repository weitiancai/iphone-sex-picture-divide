import Foundation
import Photos
import UIKit

/// 按 localIdentifier 异步取缩略图/大图，带内存缓存。
///
/// 历史记录里只存了缩略图文件名，大图需要现取；
/// 网格里也不可能一次把所有原图都塞进内存，所以统一走这里。
final class ThumbnailProvider {
    static let shared = ThumbnailProvider()

    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 300
    }

    /// 取小图（网格用）。
    func thumbnail(for id: String, size: CGSize = CGSize(width: 260, height: 260)) async -> UIImage? {
        let key = "t-\(id)-\(Int(size.width))" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let asset = Self.asset(for: id) else { return nil }
        let image = await PhotoLibrary.thumbnail(for: asset, size: size)
        if let image { cache.setObject(image, forKey: key) }
        return image
    }

    /// 取大图（详情用）。
    func preview(for id: String, size: CGSize = CGSize(width: 1200, height: 1200)) async -> UIImage? {
        let key = "p-\(id)-\(Int(size.width))" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let asset = Self.asset(for: id) else { return nil }
        let image = await PhotoLibrary.preview(for: asset, size: size)
        if let image { cache.setObject(image, forKey: key) }
        return image
    }

    /// 放进缓存（扫描时拿到的缩略图直接复用，不重复解码）。
    func preload(_ image: UIImage?, for id: String, size: CGSize = CGSize(width: 260, height: 260)) {
        guard let image else { return }
        cache.setObject(image, forKey: "t-\(id)-\(Int(size.width))" as NSString)
    }

    static func asset(for id: String) -> PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject
    }
}
