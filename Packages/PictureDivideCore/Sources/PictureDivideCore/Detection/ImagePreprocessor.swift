import CoreGraphics
import CoreML
import Foundation

/// 把 CGImage 预处理成 Moderator 模型需要的输入张量。
///
/// 模型签名（Moderator v1.0.0）：
///   输入 `image`：MultiArray Float16 `[1, 384, 384, 3]`，NHWC，RGB 通道，值域 0...255，归一化在图内完成。
///   输出 `scores`：MultiArray Float16 `[1, 5]` = [nipples, genitals, buttocks, nude, sex_act]。
public enum ImagePreprocessor {
    public static let side = 384
    public static let channelCount = 3

    /// 居中裁成正方形（保持比例），再缩放到模型输入尺寸。
    ///
    /// ⚠️ 之前直接把图拉伸成正方形，竖图会被压扁，模型看到的"人体比例"失真 → 漏判。
    public static func centerCropSquare(_ image: CGImage) -> CGImage? {
        let w = CGFloat(image.width), h = CGFloat(image.height)
        guard w > 0, h > 0 else { return nil }
        let side = min(w, h)
        let rect = CGRect(x: (w - side) / 2, y: (h - side) / 2, width: side, height: side)
        return image.cropping(to: rect)
    }

    /// CGImage → 模型的输入张量。
    public static func makeInput(from image: CGImage) throws -> MLMultiArray {
        let w = side, h = side
        let square = centerCropSquare(image) ?? image
        guard let ctx = CGContext(data: nil,
                                  width: w,
                                  height: h,
                                  bitsPerComponent: 8,
                                  bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw PreprocessorError.contextCreationFailed
        }
        ctx.draw(square, in: CGRect(x: 0, y: 0, width: w, height: h))

        guard let rendered = ctx.makeImage(),
              let provider = rendered.dataProvider,
              let data = provider.data else {
            throw PreprocessorError.renderFailed
        }
        let bgra = [UInt8](data as Data)

        let array = try MLMultiArray(shape: [1, h, w, channelCount] as [NSNumber], dataType: .float16)
        let ptr = array.dataPointer.bindMemory(to: Float16.self, capacity: w * h * channelCount)
        for i in 0..<(h * w) {
            ptr[i * 3] = Float16(bgra[i * 4 + 2])      // R
            ptr[i * 3 + 1] = Float16(bgra[i * 4 + 1])  // G
            ptr[i * 3 + 2] = Float16(bgra[i * 4])      // B
        }
        return array
    }

    /// 生成"裁剪块"：把原图按给定矩形裁剪并缩放到模型输入尺寸。
    /// 用于多裁剪策略（center / tiles / mirrors），提升召回率。
    public static func crop(_ image: CGImage, normalizedRect: CGRect) -> CGImage? {
        let w = CGFloat(image.width), h = CGFloat(image.height)
        let rect = CGRect(x: normalizedRect.origin.x * w,
                          y: normalizedRect.origin.y * h,
                          width: normalizedRect.width * w,
                          height: normalizedRect.height * h)
        guard rect.width >= 1, rect.height >= 1,
              let cropped = image.cropping(to: rect) else { return nil }
        return cropped
    }

    /// 水平镜像一张图（多裁剪策略里用来覆盖镜像姿势）。
    public static func mirrored(_ image: CGImage) -> CGImage? {
        let w = image.width, h = image.height
        guard let ctx = CGContext(data: nil,
                                  width: w,
                                  height: h,
                                  bitsPerComponent: 8,
                                  bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.translateBy(x: CGFloat(w), y: 0)
        ctx.scaleBy(x: -1, y: 1)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    public enum PreprocessorError: Error {
        case contextCreationFailed
        case renderFailed
    }
}

/// MLFeatureProvider 的轻量实现（兼容 iOS 17 到 iOS 26 的 CoreML API 变化）。
final class SingleFeatureProvider: NSObject, MLFeatureProvider {
    private let name: String
    private let value: MLFeatureValue

    init(name: String, multiArray: MLMultiArray) {
        self.name = name
        self.value = MLFeatureValue(multiArray: multiArray)
        super.init()
    }

    var featureNames: Set<String> { [name] }

    func featureValue(for featureName: String) -> MLFeatureValue? {
        featureName == name ? value : nil
    }
}
