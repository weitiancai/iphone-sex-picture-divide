import CoreGraphics
import Foundation

public enum DetectorError: LocalizedError {
    case modelNotFound
    case appleFrameworkUnavailable(reason: String)

    public var errorDescription: String? {
        switch self {
        case .modelNotFound:
            return "找不到检测模型（应放在 App bundle 或设置对应的环境变量）。"
        case .appleFrameworkUnavailable(let reason):
            return reason
        }
    }
}

/// 检测器统一协议：输入一张图，输出判定结果。
public protocol ContentDetector {
    var engine: DetectionResult.Engine { get }
    func detect(image: CGImage, policy: ScanPolicy, threshold override: Double?) async throws -> DetectionResult
}

extension ContentDetector {
    /// 不带自定义阈值的便捷调用。
    public func detect(image: CGImage, policy: ScanPolicy) async throws -> DetectionResult {
        try await detect(image: image, policy: policy, threshold: nil)
    }
}

/// 用哪个（些）模型来判。
public enum EngineOption: String, CaseIterable, Codable, Sendable {
    /// 只用 Moderator（区域级，召回高，误报也高一些）。
    case moderator
    /// 只用 Yahoo open_nsfw（分类级，误报少，但会漏"性感/内衣"边界内容）。
    case openNSFW
    /// 双模型投票：**两个模型都判定敏感才算敏感**（误报最少，召回最低）。
    case both

    public var displayName: String {
        switch self {
        case .moderator: return "Moderator（区域级）"
        case .openNSFW: return "open_nsfw（分类级）"
        case .both: return "双模型投票（都命中才算）"
        }
    }

    public var detail: String {
        switch self {
        case .moderator:
            return "能分出胸部/生殖器/臀部/裸露/性行为。召回高，误报相对多。"
        case .openNSFW:
            return "只看是不是色情内容（porn/hentai）。判得更保守，误报少，但会漏掉内衣、性感这类边界内容。"
        case .both:
            return "两个模型都说是才标记。误报最少，适合图库很大、不想被打扰。"
        }
    }
}

/// 组合检测器：按选项跑一个或两个模型。
public final class CompositeDetector: ContentDetector, @unchecked Sendable {
    public let engine: DetectionResult.Engine
    public let mode: EngineOption

    private let moderator: ModeratorDetector?
    private let openNSFW: OpenNSFWDetector?

    /// 便于上层判断是否需要重建。
    public var moderatorQuality: ModeratorDetector.Quality? { moderator?.quality }

    public init(mode: EngineOption, moderator: ModeratorDetector?, openNSFW: OpenNSFWDetector?) {
        self.mode = mode
        self.moderator = moderator
        self.openNSFW = openNSFW
        switch mode {
        case .moderator: engine = .moderator
        case .openNSFW: engine = .openNSFW
        case .both: engine = .moderator
        }
    }

    public func detect(image: CGImage, policy: ScanPolicy, threshold override: Double?) async throws -> DetectionResult {
        switch mode {
        case .moderator:
            guard let moderator else { throw DetectorError.modelNotFound }
            return try await moderator.detect(image: image, policy: policy, threshold: override)

        case .openNSFW:
            guard let openNSFW else { throw DetectorError.modelNotFound }
            return try await openNSFW.detect(image: image, policy: policy, threshold: override)

        case .both:
            guard let moderator, let openNSFW else { throw DetectorError.modelNotFound }
            let m = try await moderator.detect(image: image, policy: policy, threshold: override)
            let o = try await openNSFW.detect(image: image, policy: policy, threshold: override)
            // AND 逻辑：两个模型都说是敏感，才算敏感。
            let both = m.isSensitive && o.isSensitive
            NSLog("[PictureDivide][dual] moderator=%.3f openNSFW=%.3f", m.score, o.score)
            return DetectionResult(score: min(m.score, o.score),
                                   regions: m.regions,
                                   isSensitive: both,
                                   engine: .moderator,
                                   extra: "moderator=\(String(format: "%.2f", m.score)) / open_nsfw=\(String(format: "%.2f", o.score))\(o.extra.map { " " + $0 } ?? "")")
        }
    }
}
