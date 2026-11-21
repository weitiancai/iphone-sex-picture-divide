import Foundation
import LocalAuthentication
import Photos
import SwiftUI
import UIKit
import PictureDivideCore

/// App 的全局状态：授权、扫描、复核队列、保险箱。
@MainActor
final class AppState: ObservableObject {
    // 授权
    @Published var authorization: PHAuthorizationStatus = PhotoLibrary.authorizationStatus()
    @Published var authorizationRequested = false

    // 扫描
    @Published var progress = ScanProgress()
    @Published var flagged: [FlaggedItem] = []
    @Published var policy: ScanPolicy = .standard
    @Published var quality: ModeratorDetector.Quality = .accurate
    @Published var engineOption: EngineOption = .moderator
    /// 自定义触发阈值（0.3 ~ 0.9）。调高 = 误报更少、漏报更多。
    @Published var threshold: Double = 0.5
    /// “疑似暴露”的下限（0 ~ 0.5）。
    @Published var suspectThreshold: Double = 0.15
    /// 是否把“疑似暴露”也当成需要处理的命中。
    @Published var includeSuspected: Bool = true
    /// 是否从上次断点继续扫。
    @Published var resumeEnabled: Bool = true
    /// 扫描被系统打断（息屏/切后台超时）时为真。
    @Published var scanInterrupted: Bool = false
    /// 上次扫描到的位置（仅展示）。
    @Published var cursorDate: Date?

    private var cursor = ScanCursor.load()
    @Published var scanRange: ScanRange = .last30Days
    /// 自定义区间的起始月 / 结束月。
    @Published var customStart: Date = Calendar.current.date(byAdding: .month, value: -3, to: Date()) ?? Date()
    @Published var customEnd: Date = Date()
    @Published var scanError: String?
    @Published var lastScanFinishedAt: Date?

    // 保险箱
    @Published var vaultItems: [VaultItem] = []
    @Published var vaultUnlocked = false
    @Published var vaultError: String?

    private var detector: ContentDetector?
    private var scanTask: Task<Void, Never>?

    private let keyStore = KeychainKeyStore(service: "com.picturedivide.vault",
                                             account: "vault-master-key",
                                             protection: .unlocked)
    private(set) lazy var vault = VaultStore(keyStore: keyStore)

    // MARK: - 初始化

    func bootstrap() async {
        authorization = PhotoLibrary.authorizationStatus()
        loadDetector()
        refreshVaultItems()

        // 命令行/自动化参数：
        //   --autoscan                     启动即扫描
        //   --engine <moderator|openNSFW|both>
        //   --threshold <0.3...0.9>
        //   --policy <standard|strict|allowTopless>
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "--engine"), index + 1 < args.count,
           let option = EngineOption(rawValue: args[index + 1]) {
            engineOption = option
        }
        if let index = args.firstIndex(of: "--threshold"), index + 1 < args.count,
           let value = Double(args[index + 1]) {
            threshold = value
        }
        if let index = args.firstIndex(of: "--policy"), index + 1 < args.count,
           let value = ScanPolicy(rawValue: args[index + 1]) {
            policy = value
        }
        loadDetector()
        NSLog("[PictureDivide] 当前配置：engine=%@ threshold=%.2f policy=%@ quality=%@",
              engineOption.rawValue, threshold, policy.rawValue, quality.rawValue)

        // 调试/自动化用：启动参数 --autoscan 会自动开扫，方便命令行验证。
        if args.contains("--autoscan") {
            if authorization == .notDetermined {
                await requestAccess()
            }
            if authorization == .authorized || authorization == .limited {
                NSLog("[PictureDivide] --autoscan 触发自动扫描")
                startScan()
            }
        }
    }

    /// 重新加载检测模型（切换扫描速度 / 引擎时调用）。
    func reloadDetector() {
        loadDetector()
    }

    private func loadDetector() {
        if let current = detector as? CompositeDetector,
           current.mode == engineOption,
           (current.moderatorQuality == quality) {
            return
        }
        do {
            let moderator = try? ModeratorDetector.loadFromDisk(quality: quality)
            let openNSFW = try? OpenNSFWDetector.loadFromDisk()
            let composite = CompositeDetector(mode: engineOption, moderator: moderator, openNSFW: openNSFW)
            detector = composite
            NSLog("[PictureDivide] 模型加载：%@（moderator=%@, open_nsfw=%@）",
                  engineOption.rawValue, moderator == nil ? "无" : "有", openNSFW == nil ? "无" : "有")
        } catch {
            NSLog("[PictureDivide] 模型加载失败：%@", error.localizedDescription)
        }
    }

    var engineDescription: String {
        guard let detector else { return "模型未加载" }
        switch detector.engine {
        case .moderator: return "内置模型 Moderator（离线，区域级）"
        case .openNSFW: return "内置模型 open_nsfw（离线，分类级）"
        case .appleSensitive: return "系统 SensitiveContentAnalysis"
        }
    }

    // MARK: - 授权

    func requestAccess() async {
        authorization = await PhotoLibrary.requestAuthorization()
        authorizationRequested = true
    }

    // MARK: - 扫描

    func startScan() {
        guard authorization == .authorized || authorization == .limited else { return }
        loadDetector()
        guard let detector else {
            scanError = "检测模型加载失败：找不到 Moderator.mlmodelc。"
            return
        }
        scanTask?.cancel()
        flagged.removeAll()
        scanError = nil
        progress = ScanProgress(isRunning: true)

        let range = scanRange
        let policy = self.policy

        scanTask = Task { [weak self] in
            guard let self else { return }
            let start = range == .custom ? ScanRange.monthStart(self.customStart) : range.startDate
            let end = range == .custom ? ScanRange.monthEnd(self.customEnd) : nil
            var assets = Self.fetchAssets(start: start, end: end)
            if resumeEnabled, let last = cursor.lastDate {
                let skipped = assets.count
                assets = assets.filter { asset in
                    guard let d = asset.creationDate else { return true }
                    return d >= last
                }
                NSLog("[PictureDivide] 断点续扫：跳过 %d 张，从 %@ 开始", skipped - assets.count, last.formatted())
            }
            await MainActor.run { self.cursorDate = cursor.lastDate }
            await MainActor.run { self.progress.total = assets.count }

            var found: [FlaggedItem] = []
            let suspectThreshold = self.suspectThreshold
            let includeSuspected = self.includeSuspected
            let explicitThreshold = self.threshold

            // 切后台 / 息屏时申请一段额外时间；被系统收回时中止并保存断点。
            BackgroundSupport.beginBackgroundTask { [weak self] in
                self?.scanTask?.cancel()
            }

            for (index, asset) in assets.enumerated() {
                if Task.isCancelled { break }
                guard let cgImage = await PhotoLibrary.cgImage(for: asset) else { continue }
                do {
                    let result = try await detector.detect(image: cgImage, policy: policy, threshold: threshold)
                    let tier = TierPolicy.tier(score: result.score,
                                              regions: result.regions,
                                              explicitThreshold: explicitThreshold,
                                              suspectThreshold: suspectThreshold)
                    let hit = result.isSensitive || (includeSuspected && tier == .suspected)
                    if hit {
                        NSLog("[PictureDivide] 命中[%@]：score=%.3f %@", tier.rawValue, result.score, result.extra ?? result.regions.detectedParts.joined(separator: "/"))
                        let thumbnail = await PhotoLibrary.thumbnail(for: asset)
                        let preview = await PhotoLibrary.preview(for: asset)
                        found.append(FlaggedItem(id: asset.localIdentifier,
                                                 creationDate: asset.creationDate,
                                                 score: result.score,
                                                 regions: result.regions,
                                                 engine: result.engine,
                                                 tier: tier,
                                                 thumbnail: thumbnail,
                                                 previewImage: preview))
                    }
                } catch {
                    await MainActor.run { self.scanError = error.localizedDescription }
                    NSLog("[PictureDivide] 单张检测失败：%@", error.localizedDescription)
                }
                let scanned = index + 1
                let current = found.count
                await MainActor.run {
                    self.progress.scanned = scanned
                    self.progress.found = current
                }
                if scanned % 10 == 0 {
                    cursor.lastDate = asset.creationDate
                    cursor.lastIdentifier = asset.localIdentifier
                    cursor.save()
                }
                if scanned % 25 == 0 {
                    NSLog("[PictureDivide] 扫描进度 %d/%d，命中 %d", scanned, assets.count, current)
                }
            }
            BackgroundSupport.endBackgroundTask()
            let wasCancelled = Task.isCancelled
            await MainActor.run {
                self.flagged.append(contentsOf: found)
                self.progress.isRunning = false
                self.progress.currentAsset = nil
                self.lastScanFinishedAt = Date()
                self.scanInterrupted = wasCancelled
                if wasCancelled {
                    self.cursorDate = self.cursor.lastDate
                }
            }
            NSLog("[PictureDivide] %@：共 %d 张，命中 %d 张", wasCancelled ? "扫描被打断（断点已保存）" : "扫描完成", assets.count, found.count)
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        progress.isRunning = false
        cursor.save()
        BackgroundSupport.endBackgroundTask()
    }

    /// 清空断点，下次从头扫。
    func resetCursor() {
        ScanCursor.clear()
        cursor = ScanCursor()
        cursorDate = nil
    }

    private nonisolated static func fetchAssets(start: Date?, end: Date?) -> [PHAsset] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        if let start, let end {
            options.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate <= %@",
                                            start as NSDate, end as NSDate)
        } else if let start {
            options.predicate = NSPredicate(format: "creationDate >= %@", start as NSDate)
        } else if let end {
            options.predicate = NSPredicate(format: "creationDate <= %@", end as NSDate)
        }
        let result = PHAsset.fetchAssets(with: .image, options: options)
        var assets: [PHAsset] = []
        assets.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in assets.append(asset) }
        return assets
    }

    // MARK: - 复核操作

    /// 把命中的照片移入加密保险箱，并从系统相册删除原图。
    func moveToVault(_ item: FlaggedItem) async {
        guard let asset = Self.asset(for: item.id) else {
            scanError = "找不到对应的相册资源（可能已被删除）。"
            return
        }
        do {
            let raw = try await PhotoLibrary.imageData(for: asset)
            let clean = PhotoLibrary.stripMetadata(from: raw)
            _ = try vault.add(data: clean,
                              originalName: "IMG_\(item.id.suffix(8))",
                              assetIdentifier: item.id,
                              kind: .image)
            try await PhotoLibrary.delete(asset: asset)
            mark(item.id, state: .moved)
            refreshVaultItems()
        } catch {
            scanError = error.localizedDescription
        }
    }

    /// 只标记为误报，不做任何改动。
    func markAsSafe(_ item: FlaggedItem) {
        mark(item.id, state: .ignored)
    }

    private func mark(_ id: String, state: FlaggedItem.State) {
        if let index = flagged.firstIndex(where: { $0.id == id }) {
            flagged[index].state = state
        }
    }

    private nonisolated static func asset(for localIdentifier: String) -> PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil).firstObject
    }

    // MARK: - 保险箱

    func refreshVaultItems() {
        vaultItems = (try? vault.items()) ?? []
    }

    func unlockVault() async {
        if await BiometricGate.authenticate(reason: "解锁隐私保险箱") {
            vaultUnlocked = true
            vaultError = nil
            refreshVaultItems()
        } else {
            vaultUnlocked = false
            vaultError = "身份验证未通过。"
        }
    }

    func lockVault() {
        vaultUnlocked = false
    }

    /// 从保险箱恢复到系统相册。
    func restore(_ item: VaultItem) async {
        do {
            let data = try vault.load(id: item.id)
            try await PhotoLibrary.save(imageData: data, filename: "Restored_\(item.id.uuidString).jpg")
            try vault.delete(id: item.id)
            refreshVaultItems()
        } catch {
            vaultError = error.localizedDescription
        }
    }

    func deleteFromVault(_ item: VaultItem) {
        try? vault.delete(id: item.id)
        refreshVaultItems()
    }

    /// 解密一张保险箱里的图用于预览。
    func imageData(for item: VaultItem) -> Data? {
        try? vault.load(id: item.id)
    }
}

/// Face ID / Touch ID 门禁。
enum BiometricGate {
    static func authenticate(reason: String) async -> Bool {
        await withCheckedContinuation { continuation in
            let context = LAContext()
            var error: NSError?
            guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
                continuation.resume(returning: false)
                return
            }
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
                continuation.resume(returning: success)
            }
        }
    }
}
