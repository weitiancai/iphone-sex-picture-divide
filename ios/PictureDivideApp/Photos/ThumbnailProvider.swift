import Foundation
import Photos
import PictureDivideCore
import UIKit

/// 按 localIdentifier 异步取缩略图/预览图/原图，带内存缓存。
///
/// 历史记录里只存了缩略图文件名，大图需要现取；
/// 网格里也不可能一次把所有原图都塞进内存，所以统一走这里。
final class ThumbnailProvider {
    static let shared = ThumbnailProvider()

    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 240
        cache.totalCostLimit = 120 * 1024 * 1024
    }

    /// 取网格小图。
    func thumbnail(for id: String, size: CGSize = CGSize(width: 420, height: 420)) async -> UIImage? {
        let key = "t-\(id)-\(Int(size.width))" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let asset = Self.asset(for: id) else { return nil }
        let image = await PhotoLibrary.thumbnail(for: asset, size: size)
        if let image { store(image, forKey: key) }
        return image
    }

    /// 取中等分辨率预览图。
    func preview(for id: String, size: CGSize = CGSize(width: 1200, height: 1200)) async -> UIImage? {
        let key = "p-\(id)-\(Int(size.width))" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let asset = Self.asset(for: id) else { return nil }
        let image = await PhotoLibrary.preview(for: asset, size: size)
        if let image { store(image, forKey: key) }
        return image
    }

    /// 取**原图**（最长边缩到 2400px，兼顾清晰度和内存）。
    func original(for id: String) async -> UIImage? {
        let key = "o-\(id)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let asset = Self.asset(for: id) else { return nil }
        let image = await PhotoLibrary.originalImage(for: asset)
        if let image { store(image, forKey: key) }
        return image
    }

    /// 放进缓存（扫描时拿到的缩略图直接复用，不重复解码）。
    func preload(_ image: UIImage?, for id: String, size: CGSize = CGSize(width: 420, height: 420)) {
        guard let image else { return }
        store(image, forKey: "t-\(id)-\(Int(size.width))" as NSString)
    }

    private func store(_ image: UIImage, forKey key: NSString) {
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        cache.setObject(image, forKey: key, cost: cost)
    }

    static func asset(for id: String) -> PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject
    }
}
