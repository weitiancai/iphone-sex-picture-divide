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
    /// 批量操作进度（0~1）。
    @Published var batchProgress: Double = 0
    /// 系统「已隐藏」相簿里的照片。
    @Published var hiddenPhotos: [PHAsset] = []
    /// 操作结果提示（系统弹窗）。
    @Published var toast: String?
    /// 提示里是否附带「打开系统照片」按钮（归类到相簿后引导用户去隐藏）。
    @Published var offerOpenPhotos = false
    /// 系统相簿名（命中照片归到这个相簿，用户随后可整册隐藏）。
    @Published var albumTitle: String = "隐私相册"
    /// 该相簿里的照片。
    @Published var albumAssets: [PHAsset] = []

    private var cursor = ScanCursor.load()
    /// 历史检测记录（跨重启保留，按 localIdentifier 去重）。
    private let detectionStore = DetectionStore.shared
    @Published var scanRange: ScanRange = .last30Days
    /// 增量模式：只扫上次之后新增的照片（配合游标）。
    @Published var incrementalOnly: Bool = true
    /// 并发数（越大越快，但更吃电/内存）。
    @Published var concurrency: Int = 4
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
        loadHistory()
        refreshHiddenPhotos()
        refreshAlbumAssets()

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
        // 自检：--ios27-test 报告本机是否具备“程序化隐藏”能力（只读探测，不改数据）。
        if args.contains("--ios27-test") {
            Task { @MainActor in
                NSLog("[ios27] 系统: %@", UIDevice.current.systemVersion)
                if #available(iOS 27.0, *) {
                    NSLog("[ios27] 公开 API 存在（isHidden / addKeyword / includeHiddenAssets）")
                    NSLog("[ios27] 本机可程序化隐藏 = %@（有则 true；免费个人账号为 false）",
                          PhotoLibrary.knownCanHideDirectly.map { $0 ? "YES" : "NO" } ?? "未探测")
                    NSLog("[ios27] 系统已隐藏 %d 张；相簿「%@」%d 张",
                          PhotoLibrary.hiddenAssets().count,
                          albumTitle,
                          PhotoLibrary.assets(inAlbumTitled: albumTitle).count)
                } else {
                    NSLog("[ios27] 当前系统没有公开 API（需要 iOS 27）")
                }
            }
        }

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

    /// 把新一轮扫描结果并入现有列表（按 localIdentifier 去重：已存在则更新，不新增）。
    private func mergeDetections(_ newItems: [FlaggedItem]) {
        var indexByID: [String: Int] = [:]
        for (i, item) in flagged.enumerated() { indexByID[item.id] = i }
        for item in newItems {
            if let idx = indexByID[item.id] {
                var merged = item
                merged.state = flagged[idx].state          // 保留已处理状态
                merged.timesDetected = max(flagged[idx].timesDetected, item.timesDetected)
                merged.previewImage = item.previewImage ?? flagged[idx].previewImage
                merged.thumbnail = item.thumbnail ?? flagged[idx].thumbnail
                flagged[idx] = merged
            } else {
                indexByID[item.id] = flagged.count
                flagged.append(item)
            }
        }
        flagged.sort { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
    }

    /// 从磁盘载入历史检测记录（去重后的）。
    private func loadHistory() {
        let records = detectionStore.load()
        let items: [FlaggedItem] = records
            .filter { $0.state == "pending" || $0.state == "moved" }
            .map { record in
                FlaggedItem(id: record.id,
                            creationDate: record.creationDate,
                            score: record.score,
                            regions: record.regions,
                            engine: DetectionResult.Engine(rawValue: record.engine) ?? .moderator,
                            tier: record.tier,
                            timesDetected: record.timesDetected,
                            thumbnail: detectionStore.thumbnail(for: record),
                            previewImage: nil,
                            state: record.state == "moved" ? .moved : .pending)
            }
            .sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
        flagged = items
        NSLog("[PictureDivide] 载入历史记录 %d 条", items.count)
    }

    /// 清空历史记录（设置页用）。
    func clearHistory() {
        detectionStore.removeAll()
        flagged.removeAll()
        cursor = ScanCursor()
        ScanCursor.clear()
        cursorDate = nil
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
            let useCursor = incrementalOnly && resumeEnabled ? cursor.lastDate : nil
            let assets = Self.fetchAssets(start: start, end: end, cursorDate: useCursor, skipHidden: true)
            if let useCursor {
                NSLog("[PictureDivide] 增量模式：只扫 %@ 之后新增的 %d 张", useCursor.formatted(), assets.count)
            } else {
                NSLog("[PictureDivide] 全量模式：待扫 %d 张", assets.count)
            }
            await MainActor.run { self.cursorDate = cursor.lastDate }
            await MainActor.run { self.progress.total = assets.count }

            var found: [FlaggedItem] = []
            let suspectThreshold = self.suspectThreshold
            let includeSuspected = self.includeSuspected
            let explicitThreshold = self.threshold
            let logScores = ProcessInfo.processInfo.arguments.contains("--log-scores")
            let detector = detector
            let limit = max(1, min(self.concurrency, 8))

            // 切后台 / 息屏时申请一段额外时间；被系统收回时中止并保存断点。
            BackgroundSupport.beginBackgroundTask { [weak self] in
                self?.scanTask?.cancel()
            }

            // 并发处理（CoreML 预测本身是线程安全的），大幅缩短 1 万张的扫描时间
            await withTaskGroup(of: FlaggedItem?.self) { group in
                var next = 0
                var running = 0
                var done = 0
                while next < assets.count || running > 0 {
                    while running < limit && next < assets.count {
                        let asset = assets[next]
                        next += 1
                        running += 1
                        group.addTask { [weak self] in
                            await Self.process(asset: asset,
                                              detector: detector,
                                              policy: policy,
                                              threshold: explicitThreshold,
                                              suspectThreshold: suspectThreshold,
                                              includeSuspected: includeSuspected,
                                              logScores: logScores)
                        }
                    }
                    if let item = await group.next() {
                        running -= 1
                        done += 1
                        if let item { found.append(item) }
                    }
                    if done % 50 == 0 {
                        await MainActor.run {
                            self.progress.scanned = done
                            self.progress.found = found.count
                        }
                    }
                }
            }

            BackgroundSupport.endBackgroundTask()
            let wasCancelled = Task.isCancelled
            await MainActor.run {
                self.mergeDetections(found)
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

    /// 处理单个资源：取图 → 检测 → 记录。返回命中的项（未命中返回 nil）。
    private nonisolated static func process(asset: PHAsset,
                                           detector: ContentDetector,
                                           policy: ScanPolicy,
                                           threshold: Double,
                                           suspectThreshold: Double,
                                           includeSuspected: Bool,
                                           logScores: Bool) async -> FlaggedItem? {
        guard let cgImage = await PhotoLibrary.cgImage(for: asset) else { return nil }
        do {
            let result = try await detector.detect(image: cgImage, policy: policy, threshold: threshold)
            let tier = TierPolicy.tier(score: result.score,
                                      regions: result.regions,
                                      explicitThreshold: threshold,
                                      suspectThreshold: suspectThreshold)
            let hit = result.isSensitive || (includeSuspected && tier == .suspected)
            guard hit else { return nil }
            if logScores {
                NSLog("[PictureDivide][score] %.3f %@", result.score, result.extra ?? "")
            }
            NSLog("[PictureDivide] 命中[%@]：score=%.3f %@", tier.rawValue, result.score,
                  result.extra ?? result.regions.detectedParts.joined(separator: "/"))
            let thumbnail = await PhotoLibrary.thumbnail(for: asset)
            let preview = await PhotoLibrary.preview(for: asset)
            let stored = await MainActor.run { () -> StoredDetection in
                DetectionStore.shared.upsert(id: asset.localIdentifier,
                                             creationDate: asset.creationDate,
                                             score: result.score,
                                             regions: result.regions,
                                             tier: tier,
                                             engine: result.engine.rawValue,
                                             thumbnail: thumbnail)
            }
            return FlaggedItem(id: asset.localIdentifier,
                                creationDate: asset.creationDate,
                                score: result.score,
                                regions: result.regions,
                                engine: result.engine,
                                tier: tier,
                                timesDetected: stored.timesDetected,
                                thumbnail: thumbnail,
                                previewImage: preview)
        } catch {
            NSLog("[PictureDivide] 单张检测失败：%@", error.localizedDescription)
            return nil
        }
    }

    /// 取待扫描的资源。
    /// - 增量：只取游标之后新增的
    /// - 跳过已隐藏：iOS 起系统默认不返回已隐藏资源，这里再显式过滤一次
    private nonisolated static func fetchAssets(start: Date?, end: Date?, cursorDate: Date?, skipHidden: Bool) -> [PHAsset] {
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
        result.enumerateObjects { asset, _, _ in
            // 增量：只取游标之后新增的
            if let cursorDate, let d = asset.creationDate, d <= cursorDate { return }
            // 跳过已隐藏的
            if skipHidden && PhotoLibrary.isHidden(asset) { return }
            assets.append(asset)
        }
        return assets
    }

    // MARK: - 复核操作

    /// ① 加入隐私相册。
    ///
    /// - iOS 27+：用**公开 API** 直接移进系统「已隐藏」相簿，并打上关键词标签。
    /// - iOS 26 及以下：公开 API 把照片归进**系统相簿**「隐私相册」，
    ///   用户在系统相册里对该相簿「全选 → 隐藏」即可（iOS 不允许 App 代劳隐藏）。
    func addToPrivateAlbum(_ item: FlaggedItem) async {
        guard let asset = Self.asset(for: item.id) else {
            toast = "找不到这张照片（可能已被删除）"
            return
        }
        do {
            // 先归入系统相簿（所有系统版本都支持，也是用户后续整册隐藏的抓手）
            try await PhotoLibrary.addToAlbum([asset], albumTitle: albumTitle)

            // iOS 27+ 用公开 API：直接设成「已隐藏」+ 打上「隐私」标签
            var hiddenDirectly = false
            var tagged = false
            if #available(iOS 27.0, *) {
                // 打标签总是可以的（实测有效）
                tagged = (try? await PhotoLibrary.addKeyword("隐私", to: asset)) ?? false
                // 直接隐藏需要 Sensitive Content Analysis entitlement；
                // 免费个人账号没有 → 系统会“接受但不生效”且很慢，所以只探测一次。
                if PhotoLibrary.knownCanHideDirectly != false {
                    _ = try? await PhotoLibrary.setHiddenPublic(true, for: asset)
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    hiddenDirectly = PhotoLibrary.isHidden(asset)
                    PhotoLibrary.knownCanHideDirectly = hiddenDirectly
                    if !hiddenDirectly {
                        NSLog("[PictureDivide] 本机不支持程序化隐藏（缺 entitlement），以后只用相簿方案")
                    }
                }
            }

            offerOpenPhotos = !hiddenDirectly
            toast = hiddenDirectly
                ? "已移入系统「已隐藏」相簿\(tagged ? "，并打了「隐私」标签" : "")"
                : "已归入系统相簿「\(albumTitle)」\(tagged ? "（并打了「隐私」标签）" : "")。\n在「照片 → 相簿 → \(albumTitle)」里全选后点「隐藏」，就会进入系统的「已隐藏」（Face ID 保护）。"
            mark(item.id, state: .moved)
            refreshAlbumAssets()
            refreshHiddenPhotos()
        refreshAlbumAssets()
        } catch {
            toast = "加入失败：\(error.localizedDescription)"
        }
    }

    /// 刷新系统相簿「隐私相册」里的照片。
    func refreshAlbumAssets() {
        albumAssets = PhotoLibrary.assets(inAlbumTitled: albumTitle)
    }

    /// 打开系统相册（引导用户整册隐藏）。
    func openSystemPhotos() {
        PhotoLibrary.openSystemPhotos()
    }

    /// ② 只删除系统相册里的原图（保险箱里已有副本时，会标记“原图已删除”）。
    func deleteOriginal(_ item: FlaggedItem) async {
        guard let asset = Self.asset(for: item.id) else {
            scanError = "找不到对应的相册资源（可能已被删除）。"
            return
        }
        do {
            try await PhotoLibrary.delete(asset: asset)
            toast = "已从系统相册删除"
            mark(item.id, state: .moved)
            refreshHiddenPhotos()
        refreshAlbumAssets()
        } catch {
            scanError = error.localizedDescription
        }
    }

    // MARK: - 系统「已隐藏」相簿

    /// 打开系统相册，配合引导文案把照片移进系统「已隐藏」。
    /// （系统不允许 App 代劳，只能一步步带着用户做。）
    func openSystemPhotosGuide() {
        guard let url = URL(string: "photos-redirect://") else { return }
        UIApplication.shared.open(url)
    }

    /// 检查某张是否已经被用户手动藏进系统「已隐藏」。
    func isHiddenInSystem(_ item: FlaggedItem) -> Bool {
        guard let asset = Self.asset(for: item.id) else { return false }
        return PhotoLibrary.isHidden(asset)
    }

    /// 取消隐藏（从「已隐藏」放回普通相册）。
    func unhide(_ item: FlaggedItem) async {
        guard let asset = Self.asset(for: item.id) else {
            toast = "找不到这张照片"
            return
        }
        do {
            try await PhotoLibrary.setHidden(false, for: asset)
            toast = "已移出「已隐藏」相簿"
            refreshHiddenPhotos()
        refreshAlbumAssets()
        } catch {
            toast = "操作失败：\(error.localizedDescription)"
        }
    }

    /// 刷新系统「已隐藏」列表。
    func refreshHiddenPhotos() {
        hiddenPhotos = PhotoLibrary.hiddenAssets()
    }

    /// 批量操作

    /// 批量加入隐私相册（归入系统相簿；iOS 27+ 顺带直接隐藏）。
    func addToPrivateAlbum(_ items: [FlaggedItem]) async {
        for (index, item) in items.enumerated() {
            await addToPrivateAlbum(item)
            batchProgress = Double(index + 1) / Double(max(items.count, 1))
        }
        batchProgress = 0
        refreshAlbumAssets()
        refreshHiddenPhotos()
        refreshAlbumAssets()
    }

    /// 批量删除系统相册原图。
    func deleteOriginals(_ items: [FlaggedItem]) async {
        for (index, item) in items.enumerated() {
            await deleteOriginal(item)
            batchProgress = Double(index + 1) / Double(max(items.count, 1))
        }
        batchProgress = 0
    }

    /// 批量标记为“不要处理”（误报/无需处理），原图一律不动。
    func markAsSafe(_ items: [FlaggedItem]) {
        for item in items {
            mark(item.id, state: .ignored)
        }
        NSLog("[PictureDivide] 批量标记为不处理：%d 张", items.count)
    }

    /// 把之前标记为“不处理”的全部恢复成待处理。
    func restoreIgnored() {
        var restored = 0
        for index in flagged.indices where flagged[index].state == .ignored {
            flagged[index].state = .pending
            detectionStore.setState(id: flagged[index].id, state: FlaggedItem.State.pending.rawValue)
            restored += 1
        }
        NSLog("[PictureDivide] 恢复不处理项：%d 张", restored)
    }

    /// 当前被标记为“不处理”的数量。
    var ignoredCount: Int {
        flagged.filter { $0.state == .ignored }.count
    }

    /// 批量加入隐私相册并删除原图。
    func addToPrivateAlbumAndDeleteOriginals(_ items: [FlaggedItem]) async {
        for (index, item) in items.enumerated() {
            await addToPrivateAlbumAndDeleteOriginal(item)
            batchProgress = Double(index + 1) / Double(max(items.count, 1))
        }
        batchProgress = 0
    }

    /// 加入隐私相册后再把系统相册里的原图删掉（顺序执行）。
    func addToPrivateAlbumAndDeleteOriginal(_ item: FlaggedItem) async {
        await addToPrivateAlbum(item)
        await deleteOriginal(item)
    }

    /// 存入保险箱（可选是否删除原图）。
    private func storeIntoVault(_ item: FlaggedItem, deleteOriginal: Bool) async throws {
        guard let asset = Self.asset(for: item.id) else {
            throw NSError(domain: "PictureDivide", code: 1, userInfo: [NSLocalizedDescriptionKey: "找不到对应的相册资源（可能已被删除）。"])
        }
        let raw = try await PhotoLibrary.imageData(for: asset)
        let clean = PhotoLibrary.stripMetadata(from: raw)
        _ = try vault.add(data: clean,
                          originalName: "IMG_\(item.id.suffix(8))",
                          assetIdentifier: item.id,
                          kind: .image,
                          originalDeleted: deleteOriginal ? true : nil)
        if deleteOriginal {
            try await PhotoLibrary.delete(asset: asset)
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
        detectionStore.setState(id: id, state: state.rawValue)
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
