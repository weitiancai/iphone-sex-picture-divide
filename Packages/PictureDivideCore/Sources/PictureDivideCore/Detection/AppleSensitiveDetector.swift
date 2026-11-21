import CoreGraphics
import Foundation
#if canImport(SensitiveContentAnalysis)
import SensitiveContentAnalysis
#endif

/// Apple 系统框架 SensitiveContentAnalysis 的封装。
///
/// ⚠️ 重要事实（已在 SDK 源码与真机行为上验证）：
///   1. 必须带 `com.apple.developer.sensitivecontentanalysis.client`（值为 `analysis`）entitlement，
///      否则框架**静默返回"一切正常"**（不会报错，只是永远检测不出）。
///   2. 用户必须在 系统设置 → 隐私与安全性 → 敏感内容警告 里打开开关，
///      否则 `analysisPolicy == .disabled`，同样静默失效。
///   3. 该框架只能给"是否敏感"和（iOS 18+）大致类型，没有区域级分数。
///
/// 因此本 App 默认使用自带模型（Moderator），只有当 entitlement 确实可用时才会选这个引擎。
public final class AppleSensitiveDetector: ContentDetector, @unchecked Sendable {
    public let engine: DetectionResult.Engine = .appleSensitive

    #if canImport(SensitiveContentAnalysis)
    private let analyzer = SCSensitivityAnalyzer()
    #endif

    /// 系统当前是否允许做敏感内容分析。
    public static var isAvailable: Bool {
        #if canImport(SensitiveContentAnalysis)
        return SCSensitivityAnalyzer().analysisPolicy != .disabled
        #else
        return false
        #endif
    }

    /// 当前系统策略的说明文案。
    public static var policyDescription: String {
        #if canImport(SensitiveContentAnalysis)
        switch SCSensitivityAnalyzer().analysisPolicy {
        case .disabled:
            return "系统敏感内容分析未启用（缺少 entitlement，或未在「设置 → 隐私与安全性 → 敏感内容警告」打开）。"
        case .simpleInterventions:
            return "系统敏感内容分析可用（简单干预模式）。"
        case .descriptiveInterventions:
            return "系统敏感内容分析可用（描述性干预模式，Screen Time 通信安全已开启）。"
        @unknown default:
            return "系统敏感内容分析状态未知。"
        }
        #else
        return "当前平台不支持 SensitiveContentAnalysis。"
        #endif
    }

    public func detect(image: CGImage, policy: ScanPolicy, threshold override: Double? = nil) async throws -> DetectionResult {
        #if canImport(SensitiveContentAnalysis)
        guard analyzer.analysisPolicy != .disabled else {
            throw DetectorError.appleFrameworkUnavailable(reason: Self.policyDescription)
        }
        let sensitive = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            analyzer.analyzeImage(image) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: result?.isSensitive ?? false)
                }
            }
        }
        let regions = RegionScores()
        return DetectionResult(score: sensitive ? 1 : 0,
                               regions: regions,
                               isSensitive: sensitive,
                               engine: .appleSensitive)
        #else
        throw DetectorError.appleFrameworkUnavailable(reason: "当前平台不支持 SensitiveContentAnalysis。")
        #endif
    }
}
