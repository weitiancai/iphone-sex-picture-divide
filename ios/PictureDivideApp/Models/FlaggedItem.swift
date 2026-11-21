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

    var id: String { rawValue }

    var title: String {
        switch self {
        case .last7Days: return "最近 7 天"
        case .last30Days: return "最近 30 天"
        case .lastYear: return "最近一年"
        case .all: return "全部照片"
        }
    }

    var startDate: Date? {
        let calendar = Calendar.current
        switch self {
        case .last7Days: return calendar.date(byAdding: .day, value: -7, to: Date())
        case .last30Days: return calendar.date(byAdding: .day, value: -30, to: Date())
        case .lastYear: return calendar.date(byAdding: .year, value: -1, to: Date())
        case .all: return nil
        }
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
