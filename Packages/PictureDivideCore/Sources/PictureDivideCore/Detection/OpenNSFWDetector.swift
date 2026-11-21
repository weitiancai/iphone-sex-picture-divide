import CoreGraphics
import CoreML
import Foundation

/// Yahoo open_nsfw（Google MobileNetV2 迁移版）检测器。
///
/// - 输入 `data`：224×224 图像（模型内部做 BGR / 缩放 / 归一化）
/// - 输出 `prob`：字典，类别 → 概率（draw / hentai / neutral / porn / sexy）
///
/// 与 Moderator 的区别：它只给**分类概率**、没有部位细分，但训练数据更"老牌"，
/// 对明显的色情内容判得更保守 —— 误报通常更少，代价是会漏掉"性感/内衣"这类边界内容。
public final class OpenNSFWDetector: ContentDetector, @unchecked Sendable {
    public let engine: DetectionResult.Engine = .openNSFW

    private let model: MLModel
    private let side = 224

    public init(modelURL: URL) throws {
        self.model = try MLModel(contentsOf: modelURL)
    }

    public static func loadFromDisk(bundle: Bundle = .main) throws -> OpenNSFWDetector {
        let candidates: [URL?] = [
            ProcessInfo.processInfo.environment["PD_OPENNSFW_PATH"].map { URL(fileURLWithPath: $0) },
            bundle.url(forResource: "OpenNSFW", withExtension: "mlmodelc"),
            bundle.url(forResource: "OpenNSFW", withExtension: "mlpackage"),
            bundle.bundleURL.appendingPathComponent("OpenNSFW.mlmodelc", isDirectory: true),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Resources/OpenNSFW.mlpackage", isDirectory: true)
        ]
        for case let url? in candidates where FileManager.default.fileExists(atPath: url.path) {
            return try OpenNSFWDetector(modelURL: url)
        }
        throw DetectorError.modelNotFound
    }

    public func detect(image: CGImage, policy: ScanPolicy, threshold override: Double? = nil) async throws -> DetectionResult {
        let boxed = SendableImage(cgImage: image)
        let side = self.side
        let model = self.model

        let probabilities: [String: Double] = try await Task.detached(priority: .userInitiated) {
            guard let resized = Self.resize(boxed.cgImage, side: side) else { return [:] }
            guard let desc = model.modelDescription.inputDescriptionsByName["data"],
                  let constraint = desc.imageConstraint,
                  let feature = try? MLFeatureValue(cgImage: resized, constraint: constraint) else { return [:] }
            let output = try await model.prediction(from: SingleImageProvider(name: "data", feature: feature))
            guard let dict = output.featureValue(for: "prob")?.dictionaryValue else { return [:] }
            var result: [String: Double] = [:]
            for (key, value) in dict {
                if let number = value as? NSNumber {
                    result["\(key)"] = number.doubleValue
                }
            }
            return result
        }.value

        guard !probabilities.isEmpty else { throw DetectorError.modelNotFound }

        let porn = probabilities["porn"] ?? 0
        let hentai = probabilities["hentai"] ?? 0
        let sexy = probabilities["sexy"] ?? 0
        let explicit = min(1, porn + hentai)

        // 映射到我们的区域结构：它没有部位细分，全部归到"裸露"。
        var regions = RegionScores.zero
        regions.nude = explicit
        let evaluation = policy.evaluate(regions, thresholdOverride: override)
        return DetectionResult(score: evaluation.score,
                               regions: regions,
                               isSensitive: evaluation.isSensitive,
                               engine: .openNSFW,
                               extra: "porn=\(String(format: "%.2f", porn)) hentai=\(String(format: "%.2f", hentai)) sexy=\(String(format: "%.2f", sexy))")
    }

    private static func resize(_ image: CGImage, side: Int) -> CGImage? {
        guard let ctx = CGContext(data: nil,
                                  width: side,
                                  height: side,
                                  bitsPerComponent: 8,
                                  bytesPerRow: side * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        return ctx.makeImage()
    }
}

/// 图像型输入的 MLFeatureProvider。
final class SingleImageProvider: NSObject, MLFeatureProvider {
    private let name: String
    private let feature: MLFeatureValue

    init(name: String, feature: MLFeatureValue) {
        self.name = name
        self.feature = feature
        super.init()
    }

    var featureNames: Set<String> { [name] }

    func featureValue(for featureName: String) -> MLFeatureValue? {
        featureName == name ? feature : nil
    }
}
