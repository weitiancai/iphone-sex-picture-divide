import Foundation
import ImageIO
import Photos
import UIKit
import UniformTypeIdentifiers

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
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: PhotoError.imageDataUnavailable)
                }
            }
        }
    }

    /// 生成缩略图（用于列表展示）。
    static func thumbnail(for asset: PHAsset, size: CGSize = CGSize(width: 240, height: 240)) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .opportunistic
            options.resizeMode = .fast
            PHImageManager.default().requestImage(for: asset, targetSize: size, contentMode: .aspectFill, options: options) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    /// 生成大一点的预览图。
    static func preview(for asset: PHAsset, size: CGSize = CGSize(width: 900, height: 900)) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .opportunistic
            options.resizeMode = .fast
            PHImageManager.default().requestImage(for: asset, targetSize: size, contentMode: .aspectFit, options: options) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    /// 资产对应的 CGImage（用于送检模型）。
    static func cgImage(for asset: PHAsset, size: CGSize = CGSize(width: 1024, height: 1024)) async -> CGImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            PHImageManager.default().requestImage(for: asset, targetSize: size, contentMode: .aspectFit, options: options) { image, _ in
                guard let image else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: image.cgImage)
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

        var errorDescription: String? {
            switch self {
            case .imageDataUnavailable: return "读取这张照片的数据失败（可能还在 iCloud 未下载）。"
            case .deleteFailed: return "从系统相册删除失败。"
            case .saveFailed: return "写回系统相册失败。"
            }
        }
    }
}
