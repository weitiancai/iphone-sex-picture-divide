import Foundation
import PictureDivideCore

/// 不依赖 XCTest / swift-testing 的自检程序（Command Line Tools 环境下也能跑）。
///
/// 运行：swift run pdctl-selftest
@main
struct SelfTest {
    private static var failures = 0

    static func main() {
        expect(!ScanPolicy.standard.evaluate(RegionScores(nipples: 0.9)).isSensitive,
               "标准策略不应因单独胸部触发")
        expect(ScanPolicy.standard.evaluate(RegionScores(genitals: 0.8)).isSensitive,
               "标准策略应因生殖器触发")
        expect(ScanPolicy.strict.evaluate(RegionScores(nipples: 0.4)).isSensitive,
               "严格策略应因胸部触发")
        expect(!ScanPolicy.allowTopless.evaluate(RegionScores(nipples: 0.95)).isSensitive,
               "宽松策略不应因胸部触发")
        expect(!ScanPolicy.allowTopless.evaluate(RegionScores(buttocks: 0.9)).isSensitive,
               "宽松策略不应因臀部触发")
        expect(ScanPolicy.standard.evaluate(RegionScores(buttocks: 0.9)).isSensitive,
               "标准策略应因臀部触发")
        expect(abs(ScanPolicy.standard.evaluate(RegionScores(nipples: 0.3, genitals: 0.7)).score - 0.7) < 0.0001,
               "总分应取参与计分区域的最大值")

        do {
            let key = VaultCrypto.newKey()
            let plain = Data("私密照片内容".utf8)
            let sealed = try VaultCrypto.seal(plain, key: key)
            expect(sealed != plain, "密文应与明文不同")
            expect(try VaultCrypto.open(sealed, key: key) == plain, "解密应还原明文")
            var wrongKeyFailed = false
            do { _ = try VaultCrypto.open(sealed, key: VaultCrypto.newKey()) } catch { wrongKeyFailed = true }
            expect(wrongKeyFailed, "错误密钥应解密失败")
        } catch {
            fail("加密自检抛错：\(error)")
        }

        do {
            let dir = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("pd-selftest-\(UUID().uuidString)")
            let keyStore = KeychainKeyStore(service: "selftest.\(UUID().uuidString)",
                                            account: "vault",
                                            protection: .unlocked)
            let store = VaultStore(rootURL: dir, keyStore: keyStore)
            defer { try? FileManager.default.removeItem(at: dir) }
            let payload = Data("hello vault".utf8)
            let item = try store.add(data: payload, originalName: "IMG_0001.HEIC", assetIdentifier: "abc", kind: .image)
            expect(try store.items().count == 1, "保险箱应有 1 条记录")
            expect(try store.load(id: item.id) == payload, "读取内容应一致")
            try store.delete(id: item.id)
            expect(try store.items().count == 0, "删除后应无记录")
        } catch {
            fail("保险箱自检抛错：\(error)")
        }

        if failures == 0 {
            print("✅ 全部自检通过")
            exit(0)
        } else {
            print("❌ \(failures) 项自检失败")
            exit(1)
        }
    }

    private static func expect(_ condition: Bool, _ message: String) {
        if condition {
            print("  ✓ \(message)")
        } else {
            fail(message)
        }
    }

    private static func fail(_ message: String) {
        failures += 1
        print("  ✗ \(message)")
    }
}
