import Foundation

/// 五个区域的判定分数（Moderator 模型输出，sigmoid 后的 0...1 值）。
public struct RegionScores: Codable, Equatable, Hashable, Sendable {
    public var nipples: Double
    public var genitals: Double
    public var buttocks: Double
    public var nude: Double
    public var sexAct: Double

    public init(nipples: Double = 0, genitals: Double = 0, buttocks: Double = 0, nude: Double = 0, sexAct: Double = 0) {
        self.nipples = nipples
        self.genitals = genitals
        self.buttocks = buttocks
        self.nude = nude
        self.sexAct = sexAct
    }

    /// 命中的区域名（用于 UI 展示"暴露了哪些部位"）。
    public var detectedParts: [String] {
        var parts: [String] = []
        if nipples >= 0.5 { parts.append("胸部") }
        if genitals >= 0.5 { parts.append("生殖器") }
        if buttocks >= 0.5 { parts.append("臀部") }
        if nude >= 0.5 { parts.append("裸露") }
        if sexAct >= 0.5 { parts.append("性行为") }
        return parts
    }

    public static let zero = RegionScores()
}

/// 单张图片的检测结果。
public struct DetectionResult: Codable, Equatable, Sendable {
    public enum Engine: String, Codable, Sendable {
        /// 随 App 打包的 CoreML 模型（Moderator v1.0.0），区域级、无需任何 entitlement。
        case moderator
        /// Apple 系统框架 SensitiveContentAnalysis，需要 entitlement + 系统开关。
        case appleSensitive
    }

    /// 总分：按当前策略取参与计分的区域最大值。
    public var score: Double
    /// 各区域原始分数。
    public var regions: RegionScores
    /// 按策略判定是否敏感。
    public var isSensitive: Bool
    /// 使用哪个引擎得出。
    public var engine: Engine

    public init(score: Double, regions: RegionScores, isSensitive: Bool, engine: Engine) {
        self.score = score
        self.regions = regions
        self.isSensitive = isSensitive
        self.engine = engine
    }
}
