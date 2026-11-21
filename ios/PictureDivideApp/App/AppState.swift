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
    @Published var scanRange: ScanRange = .last30Days
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
    }

    private func loadDetector() {
        if detector == nil {
            do {
                let loaded = try ModeratorDetector.loadFromDisk()
                detector = loaded
                NSLog("[PictureDivide] 模型加载成功：%@", loaded.engine.rawValue)
            } catch {
                NSLog("[PictureDivide] 模型加载失败：%@", error.localizedDescription)
            }
        }
    }

    var engineDescription: String {
        guard let detector else { return "模型未加载" }
        switch detector.engine {
        case .moderator: return "内置模型 Moderator（离线）"
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
            let assets = Self.fetchAssets(range: range)
            await MainActor.run { self.progress.total = assets.count }

            var found: [FlaggedItem] = []
            for (index, asset) in assets.enumerated() {
                if Task.isCancelled { break }
                guard let cgImage = await PhotoLibrary.cgImage(for: asset) else { continue }
                do {
                    let result = try await detector.detect(image: cgImage, policy: policy)
                    if result.isSensitive {
                        let thumbnail = await PhotoLibrary.thumbnail(for: asset)
                        let preview = await PhotoLibrary.preview(for: asset)
                        found.append(FlaggedItem(id: asset.localIdentifier,
                                                 creationDate: asset.creationDate,
                                                 score: result.score,
                                                 regions: result.regions,
                                                 engine: result.engine,
                                                 thumbnail: thumbnail,
                                                 previewImage: preview))
                    }
                } catch {
                    await MainActor.run { self.scanError = error.localizedDescription }
                }
                let scanned = index + 1
                let current = found.count
                await MainActor.run {
                    self.progress.scanned = scanned
                    self.progress.found = current
                }
            }
            await MainActor.run {
                self.flagged.append(contentsOf: found)
                self.progress.isRunning = false
                self.progress.currentAsset = nil
                self.lastScanFinishedAt = Date()
            }
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        progress.isRunning = false
    }

    private nonisolated static func fetchAssets(range: ScanRange) -> [PHAsset] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        if let start = range.startDate {
            options.predicate = NSPredicate(format: "creationDate >= %@", start as NSDate)
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
