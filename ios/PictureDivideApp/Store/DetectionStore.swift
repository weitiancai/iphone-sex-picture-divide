import Foundation
import PictureDivideCore
import UIKit

/// 一条历史检测记录（可跨多次扫描、跨 App 重启保留）。
struct StoredDetection: Codable, Identifiable, Equatable {
    /// 相册资源 localIdentifier —— 去重的主键。
    var id: String
    var creationDate: Date?
    var score: Double
    var regions: RegionScores
    var tier: SensitivityTier
    var engine: String
    /// 第一次被检出的时间。
    var firstSeen: Date
    /// 最近一次被检出的时间。
    var lastSeen: Date
    /// 一共被检出过几次（多次扫描会累加）。
    var timesDetected: Int
    /// pending / moved / ignored
    var state: String
    /// 缩略图文件名（存磁盘，避免占内存）。
    var thumbnailFile: String?
}

/// 检测结果的持久化存储。
///
/// - 记录写在 `Application Support/PictureDivideDetections.json`
/// - 缩略图写在 `Application Support/PictureDivideThumbs/`
/// - 按 `localIdentifier` 去重：同一张照片被反复扫到只保留一条，累加 `timesDetected`
final class DetectionStore {
    /// 全局单例（并发扫描时多处写入）。
    static let shared = DetectionStore()

    private let fileURL: URL
    private let thumbsDir: URL
    private let queue = DispatchQueue(label: "com.picturedivide.detectionStore")
    private(set) var records: [String: StoredDetection] = [:]

    init(rootURL: URL? = nil) {
        let base = rootURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.fileURL = base.appendingPathComponent("PictureDivideDetections.json")
        self.thumbsDir = base.appendingPathComponent("PictureDivideThumbs", isDirectory: true)
        try? FileManager.default.createDirectory(at: thumbsDir, withIntermediateDirectories: true)
    }

    // MARK: - 读写

    func load() -> [StoredDetection] {
        queue.sync {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            guard let data = try? Data(contentsOf: fileURL),
                  let list = try? decoder.decode([StoredDetection].self, from: data) else {
                records = [:]
                return []
            }
            records = Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
            return list
        }
    }

    private func persist(_ list: [StoredDetection]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(list) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }

    // MARK: - 更新

    /// 写入/合并一条检测结果（去重）。
    @discardableResult
    func upsert(id: String,
                creationDate: Date?,
                score: Double,
                regions: RegionScores,
                tier: SensitivityTier,
                engine: String,
                thumbnail: UIImage?) -> StoredDetection {
        return queue.sync {
            let now = Date()
            var record = records[id]
            let isNew = record == nil
            if record == nil {
                record = StoredDetection(id: id,
                                         creationDate: creationDate,
                                         score: score,
                                         regions: regions,
                                         tier: tier,
                                         engine: engine,
                                         firstSeen: now,
                                         lastSeen: now,
                                         timesDetected: 1,
                                         state: "pending",
                                         thumbnailFile: nil)
            } else {
                record!.score = score
                record!.regions = regions
                record!.tier = tier
                record!.engine = engine
                record!.lastSeen = now
                record!.timesDetected += 1
                if record!.creationDate == nil { record!.creationDate = creationDate }
                // 已经处理过的（已移入保险箱 / 已标误报）不要被重置回 pending
            }
            if let thumbnail, let name = saveThumbnail(thumbnail, for: id) {
                record!.thumbnailFile = name
            }
            records[id] = record!
            persist(Array(records.values))
            if isNew { return record! }
            return record!
        }
    }

    /// 更新处理状态（pending / moved / ignored）。
    func setState(id: String, state: String) {
        queue.sync {
            guard var record = records[id] else { return }
            record.state = state
            records[id] = record
            persist(Array(records.values))
        }
    }

    /// 清空全部历史记录（连同缩略图）。
    func removeAll() {
        queue.sync {
            records = [:]
            try? FileManager.default.removeItem(at: fileURL)
            try? FileManager.default.removeItem(at: thumbsDir)
            try? FileManager.default.createDirectory(at: thumbsDir, withIntermediateDirectories: true)
        }
    }

    /// 彻底移除一条（保险箱里删掉后调用）。
    func remove(id: String) {
        queue.sync {
            guard let record = records.removeValue(forKey: id) else { return }
            if let file = record.thumbnailFile {
                try? FileManager.default.removeItem(at: thumbsDir.appendingPathComponent(file))
            }
            persist(Array(records.values))
        }
    }

    // MARK: - 缩略图

    private func saveThumbnail(_ image: UIImage, for id: String) -> String? {
        let name = id.replacingOccurrences(of: "/", with: "_") + ".jpg"
        let url = thumbsDir.appendingPathComponent(name)
        guard let data = image.jpegData(compressionQuality: 0.6) else { return nil }
        try? data.write(to: url, options: [.atomic])
        return name
    }

    func thumbnail(for record: StoredDetection) -> UIImage? {
        guard let file = record.thumbnailFile else { return nil }
        return UIImage(contentsOfFile: thumbsDir.appendingPathComponent(file).path)
    }
}
