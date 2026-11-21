import Foundation

/// 判定策略：不同人对"什么算敏感"的容忍度不同。
public enum ScanPolicy: String, Codable, CaseIterable, Sendable {
    /// 标准：裸露 / 性行为 / 生殖器 / 臀部 命中即算敏感；单独的胸部不触发。
    case standard
    /// 严格：胸部也算，外加更低的阈值，误报率更高。
    case strict
    /// 宽松（allow-topless）：只保留裸露 / 性行为 / 生殖器，胸部与臀部都不触发。
    case allowTopless

    public var displayName: String {
        switch self {
        case .standard: return "标准"
        case .strict: return "严格"
        case .allowTopless: return "宽松（允许胸部/臀部裸露）"
        }
    }

    public var detail: String {
        switch self {
        case .standard:
            return "裸露、性行为、生殖器、臀部会被标记；单独的胸部不触发。"
        case .strict:
            return "胸部也会被标记，且阈值更低，误报率更高。"
        case .allowTopless:
            return "只标记裸露、性行为、生殖器；胸部与臀部裸露不触发。"
        }
    }

    /// 触发阈值。
    public var threshold: Double {
        switch self {
        case .standard, .allowTopless: return 0.5
        case .strict: return 0.35
        }
    }

    /// 该策略下参与计分的区域分数。
    func participatingScores(_ regions: RegionScores) -> [Double] {
        switch self {
        case .standard:
            return [regions.nude, regions.sexAct, regions.genitals, regions.buttocks]
        case .strict:
            return [regions.nude, regions.sexAct, regions.genitals, regions.buttocks, regions.nipples]
        case .allowTopless:
            return [regions.nude, regions.sexAct, regions.genitals]
        }
    }

    /// 依据策略计算总分与是否敏感。
    public func evaluate(_ regions: RegionScores) -> (score: Double, isSensitive: Bool) {
        let scores = participatingScores(regions)
        let score = scores.max() ?? 0
        return (score, score >= threshold)
    }
}
