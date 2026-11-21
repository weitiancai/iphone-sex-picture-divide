import Foundation
import Photos
import UIKit
import PictureDivideCore

/// 一张被判定为敏感的相册资源。
struct FlaggedItem: Identifiable, Hashable {
    /// 相册资源的 localIdentifier（稳定，删掉重建后可能变化）。
    var id: String
    var creationDate: Date?
    var score: Double
    var regions: RegionScores
    var engine: DetectionResult.Engine
    /// 敏感程度分档（明确色情 / 疑似暴露）。
    var tier: SensitivityTier = .explicit
    /// 一共被检出过几次（多次扫描会累加，用于去重展示）。
    var timesDetected: Int = 1
    /// 列表里显示的小图（已默认打码）。
    var thumbnail: UIImage?
    var previewImage: UIImage?
    enum State: String, Hashable {
        case pending      // 还没处理
        case moved        // 已移入保险箱
        case ignored      // 用户标记为误报
    }
    var state: State = .pending

    var detectedParts: [String] { regions.detectedParts }
}

enum ScanRange: String, CaseIterable, Identifiable {
    case last7Days
    case last30Days
    case lastYear
    case all
    /// 自定义：从某月到某月。
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .last7Days: return "最近 7 天"
        case .last30Days: return "最近 30 天"
        case .lastYear: return "最近一年"
        case .all: return "全部照片"
        case .custom: return "自定义月份区间"
        }
    }

    var startDate: Date? {
        let calendar = Calendar.current
        switch self {
        case .last7Days: return calendar.date(byAdding: .day, value: -7, to: Date())
        case .last30Days: return calendar.date(byAdding: .day, value: -30, to: Date())
        case .lastYear: return calendar.date(byAdding: .year, value: -1, to: Date())
        case .all, .custom: return nil
        }
    }

    /// 自定义区间：起始月第一天 00:00。
    static func monthStart(_ date: Date) -> Date {
        let calendar = Calendar.current
        let comps = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: comps) ?? date
    }

    /// 自定义区间：结束月最后一天 23:59:59。
    static func monthEnd(_ date: Date) -> Date {
        let calendar = Calendar.current
        let start = monthStart(date)
        guard let lastDay = calendar.range(of: .day, in: .month, for: start)?.last,
              let day = calendar.date(byAdding: .day, value: lastDay - 1, to: start) else { return date }
        let comps = calendar.dateComponents([.year, .month, .day], from: day)
        return calendar.date(byAdding: .hour, value: 23, to: calendar.date(from: comps) ?? day) ?? date
    }
}

struct ScanProgress {
    var scanned: Int = 0
    var total: Int = 0
    var found: Int = 0
    var currentAsset: String?
    var isRunning: Bool = false

    var fraction: Double {
        total > 0 ? min(1, Double(scanned) / Double(total)) : 0
    }
}
