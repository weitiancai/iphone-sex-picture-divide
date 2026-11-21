import Foundation
import Testing
@testable import PictureDivideCore

@Test func standardPolicyIgnoresNipplesAlone() {
    let result = ScanPolicy.standard.evaluate(RegionScores(nipples: 0.9))
    #expect(!result.isSensitive)
}

@Test func standardPolicyTriggersOnGenitals() {
    let result = ScanPolicy.standard.evaluate(RegionScores(genitals: 0.8))
    #expect(result.isSensitive)
}

@Test func strictPolicyTriggersOnNipples() {
    let result = ScanPolicy.strict.evaluate(RegionScores(nipples: 0.4))
    #expect(result.isSensitive)
}

@Test func allowToplessIgnoresNipples() {
    let result = ScanPolicy.allowTopless.evaluate(RegionScores(nipples: 0.95))
    #expect(!result.isSensitive)
}

@Test func scoreIsMaxOfParticipatingRegions() {
    let regions = RegionScores(nipples: 0.3, genitals: 0.7, buttocks: 0.2, nude: 0.1, sexAct: 0.05)
    let result = ScanPolicy.standard.evaluate(regions)
    #expect(abs(result.score - 0.7) < 0.0001)
}

@Test func vaultCryptoRoundTrip() throws {
    let key = VaultCrypto.newKey()
    let plain = Data("私密照片内容".utf8)
    let sealed = try VaultCrypto.seal(plain, key: key)
    #expect(sealed != plain)
    let opened = try VaultCrypto.open(sealed, key: key)
    #expect(opened == plain)
}

@Test func vaultCryptoRejectsWrongKey() throws {
    let sealed = try VaultCrypto.seal(Data("x".utf8), key: VaultCrypto.newKey())
    #expect(throws: (any Error).self) {
        try VaultCrypto.open(sealed, key: VaultCrypto.newKey())
    }
}

@Test func vaultStoreAddLoadDelete() throws {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("pd-test-\(UUID().uuidString)")
    let keyStore = KeychainKeyStore(service: "test.\(UUID().uuidString)",
                                    account: "vault",
                                    protection: .unlocked)
    let store = VaultStore(rootURL: dir, keyStore: keyStore)
    defer { try? FileManager.default.removeItem(at: dir) }

    let payload = Data("hello vault".utf8)
    let item = try store.add(data: payload, originalName: "IMG_0001.HEIC", assetIdentifier: "abc", kind: .image)
    #expect(try store.items().count == 1)
    #expect(try store.load(id: item.id) == payload)
    try store.delete(id: item.id)
    #expect(try store.items().count == 0)
}

@Test func appleDetectorReportsPolicyState() {
    // 不做断言，只保证不崩；真机上用于展示系统状态。
    _ = AppleSensitiveDetector.isAvailable
    _ = AppleSensitiveDetector.policyDescription
}
