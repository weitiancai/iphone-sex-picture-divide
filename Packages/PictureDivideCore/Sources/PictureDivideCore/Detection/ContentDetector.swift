import CoreGraphics
import Foundation

/// 检测器统一协议：输入一张图，输出判定结果。
public protocol ContentDetector {
    var engine: DetectionResult.Engine { get }
    func detect(image: CGImage, policy: ScanPolicy) async throws -> DetectionResult
}

public enum DetectorError: LocalizedError {
    case modelNotFound
    case appleFrameworkUnavailable(reason: String)

    public var errorDescription: String? {
        switch self {
        case .modelNotFound:
            return "找不到检测模型 Moderator.mlmodelc（应放在 App bundle 或设置 PD_MODEL_PATH）。"
        case .appleFrameworkUnavailable(let reason):
            return reason
        }
    }
}
