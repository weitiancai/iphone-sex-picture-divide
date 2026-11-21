import CoreGraphics
import CoreML
import Foundation

/// CoreGraphics 的 CGImage 本身不可标记 Sendable，但它一旦创建就不再被修改，跨线程传递是安全的。
struct SendableImage: @unchecked Sendable {
    let cgImage: CGImage
}

/// 基于随 App 打包的 Moderator CoreML 模型的检测器。
///
/// 完全离线、无网络、不需要任何 Apple entitlement，是本 App 的主力引擎。
///
/// 模型签名（Moderator v1.0.0）：
///   输入 `image`：Float16 `[1, 384, 384, 3]`，NHWC，RGB，值域 0...255（归一化在图内完成）
///   输出 `scores`：Float16 `[1, 5]` = [nipples, genitals, buttocks, nude, sex_act]
public final class ModeratorDetector: ContentDetector, @unchecked Sendable {
    public enum Quality: String, Codable, Sendable {
        /// 单张整图，最快。
        case fast
        /// 整图 + 4 个多尺度裁剪块。
        case balanced
        /// 整图 + 4 个裁剪块 + 它们的镜像（召回最高，也最慢）。
        case accurate

        var crops: [CGRect] {
            switch self {
            case .fast:
                return [CGRect(x: 0, y: 0, width: 1, height: 1)]
            case .balanced, .accurate:
                let s: CGFloat = 0.6
                return [
                    CGRect(x: 0, y: 0, width: s, height: s),
                    CGRect(x: 1 - s, y: 0, width: s, height: s),
                    CGRect(x: 0, y: 1 - s, width: s, height: s),
                    CGRect(x: 1 - s, y: 1 - s, width: s, height: s)
                ]
            }
        }

        var useMirrors: Bool { self == .accurate }
    }

    public let engine: DetectionResult.Engine = .moderator

    public let model: MLModel
    public let quality: Quality

    public init(modelURL: URL, quality: Quality = .accurate) throws {
        self.model = try MLModel(contentsOf: modelURL)
        self.quality = quality
    }

    /// 从 App bundle / 环境变量 / 本地目录里寻找模型。
    public static func loadFromDisk(bundle: Bundle = .main, quality: Quality = .accurate) throws -> ModeratorDetector {
        let candidates: [URL?] = [
            ProcessInfo.processInfo.environment["PD_MODEL_PATH"].map { URL(fileURLWithPath: $0) },
            bundle.url(forResource: "Moderator", withExtension: "mlmodelc"),
            bundle.url(forResource: "Moderator", withExtension: "mlpackage"),
            bundle.bundleURL.appendingPathComponent("Moderator.mlmodelc", isDirectory: true),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Resources/Moderator.mlmodelc", isDirectory: true)
        ]
        for case let url? in candidates where FileManager.default.fileExists(atPath: url.path) {
            return try ModeratorDetector(modelURL: url, quality: quality)
        }
        throw DetectorError.modelNotFound
    }

    public func detect(image: CGImage, policy: ScanPolicy, threshold override: Double? = nil) async throws -> DetectionResult {
        let boxed = SendableImage(cgImage: image)
        let crops = quality.crops
        let useMirrors = quality.useMirrors

        // CoreML 推理很重，放到后台线程，别卡住 UI。
        let regions: RegionScores = try await Task.detached(priority: .userInitiated) { [model] in
            var best = RegionScores.zero
            for rect in crops {
                let piece = (rect.width >= 1 && rect.height >= 1)
                    ? (ImagePreprocessor.crop(boxed.cgImage, normalizedRect: rect) ?? boxed.cgImage)
                    : boxed.cgImage
                try await Self.score(piece, model: model, into: &best)
                if useMirrors, let mirrored = ImagePreprocessor.mirrored(piece) {
                    try await Self.score(mirrored, model: model, into: &best)
                }
            }
            return best
        }.value

        let evaluation = policy.evaluate(regions, thresholdOverride: override)
        return DetectionResult(score: evaluation.score,
                               regions: regions,
                               isSensitive: evaluation.isSensitive,
                               engine: .moderator)
    }

    private static func score(_ image: CGImage, model: MLModel, into best: inout RegionScores) async throws {
        let input = try ImagePreprocessor.makeInput(from: image)
        let output = try await model.prediction(from: SingleFeatureProvider(name: "image", multiArray: input))
        guard let scores = output.featureValue(for: "scores")?.multiArrayValue else { return }
        let p = scores.dataPointer.bindMemory(to: Float16.self, capacity: 5)
        let values = (0..<5).map { Double(p[$0]) }
        best.nipples = max(best.nipples, values[0])
        best.genitals = max(best.genitals, values[1])
        best.buttocks = max(best.buttocks, values[2])
        best.nude = max(best.nude, values[3])
        best.sexAct = max(best.sexAct, values[4])
    }
}
