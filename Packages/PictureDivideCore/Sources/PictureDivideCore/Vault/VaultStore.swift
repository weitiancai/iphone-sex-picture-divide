import CryptoKit
import Foundation

/// 保险箱里的一条记录（索引项，不含内容）。
public struct VaultItem: Codable, Identifiable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case image
        case video
    }

    public var id: UUID
    /// 原始文件名（仅作提示，已剥离 GPS 等元数据）。
    public var originalName: String
    /// 原始相册资源标识（用于恢复回系统相册时提示）。
    public var assetIdentifier: String?
    public var kind: Kind
    public var createdAt: Date
    /// 加密后字节数。
    public var encryptedByteCount: Int
    /// 原始字节数。
    public var originalByteCount: Int

    public init(id: UUID = UUID(),
                originalName: String,
                assetIdentifier: String? = nil,
                kind: Kind,
                createdAt: Date = Date(),
                encryptedByteCount: Int,
                originalByteCount: Int) {
        self.id = id
        self.originalName = originalName
        self.assetIdentifier = assetIdentifier
        self.kind = kind
        self.createdAt = createdAt
        self.encryptedByteCount = encryptedByteCount
        self.originalByteCount = originalByteCount
    }
}

/// 加密保险箱：文件用 ChaCha20-Poly1305 加密后落在 App 沙盒里，索引是一份明文 JSON。
public final class VaultStore {
    private let rootURL: URL
    private let blobsURL: URL
    private let indexURL: URL
    private let keyStore: KeychainKeyStore
    private let fileManager = FileManager.default

    public init(rootURL: URL? = nil, keyStore: KeychainKeyStore) {
        let base = rootURL ?? Self.defaultRootURL()
        self.rootURL = base
        self.blobsURL = base.appendingPathComponent("blobs", isDirectory: true)
        self.indexURL = base.appendingPathComponent("index.json")
        self.keyStore = keyStore
        try? fileManager.createDirectory(at: blobsURL, withIntermediateDirectories: true)
    }

    public static func defaultRootURL() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return support.appendingPathComponent("PictureDivideVault", isDirectory: true)
    }

    // MARK: - Items

    public func items() throws -> [VaultItem] {
        guard fileManager.fileExists(atPath: indexURL.path) else { return [] }
        let data = try Data(contentsOf: indexURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([VaultItem].self, from: data)
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// 存入一份内容（加密）。
    @discardableResult
    public func add(data: Data,
                    originalName: String,
                    assetIdentifier: String?,
                    kind: VaultItem.Kind) throws -> VaultItem {
        let key = SymmetricKey(data: try keyStore.loadOrCreateKey())
        let sealed = try VaultCrypto.seal(data, key: key)
        let id = UUID()
        let blobName = id.uuidString + ".blob"
        let blobURL = blobsURL.appendingPathComponent(blobName)
        try sealed.write(to: blobURL, options: [.atomic])
        try applyFileProtection(to: blobURL)

        let item = VaultItem(id: id,
                             originalName: originalName,
                             assetIdentifier: assetIdentifier,
                             kind: kind,
                             encryptedByteCount: sealed.count,
                             originalByteCount: data.count)
        var all = try items()
        all.append(item)
        try writeIndex(all)
        return item
    }

    /// 读取并解密。
    public func load(id: UUID) throws -> Data {
        let key = SymmetricKey(data: try keyStore.loadOrCreateKey())
        let blobURL = blobsURL.appendingPathComponent(id.uuidString + ".blob")
        let sealed = try Data(contentsOf: blobURL)
        return try VaultCrypto.open(sealed, key: key)
    }

    public func delete(id: UUID) throws {
        let blobURL = blobsURL.appendingPathComponent(id.uuidString + ".blob")
        try? fileManager.removeItem(at: blobURL)
        try writeIndex(try items().filter { $0.id != id })
    }

    /// 清空保险箱（内容 + 索引）。
    public func destroy() throws {
        try? fileManager.removeItem(at: blobsURL)
        try? fileManager.removeItem(at: indexURL)
        try fileManager.createDirectory(at: blobsURL, withIntermediateDirectories: true)
    }

    // MARK: - Private

    private func writeIndex(_ items: [VaultItem]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(items)
        try data.write(to: indexURL, options: [.atomic])
        try applyFileProtection(to: indexURL)
    }

    private func applyFileProtection(to url: URL) throws {
        #if os(iOS)
        try fileManager.setAttributes([.protectionKey: FileProtectionType.complete],
                                      ofItemAtPath: url.path)
        #endif
    }
}
