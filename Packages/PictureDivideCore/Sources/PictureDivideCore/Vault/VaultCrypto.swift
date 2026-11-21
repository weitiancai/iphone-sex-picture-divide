import CryptoKit
import Foundation

/// 保险箱文件的对称加密封装：ChaCha20-Poly1305（每次随机 nonce）。
public enum VaultCrypto {
    public static func seal(_ plaintext: Data, key: SymmetricKey) throws -> Data {
        let box = try ChaChaPoly.seal(plaintext, using: key)
        return box.combined
    }

    public static func open(_ ciphertext: Data, key: SymmetricKey) throws -> Data {
        let box = try ChaChaPoly.SealedBox(combined: ciphertext)
        return try ChaChaPoly.open(box, using: key)
    }

    /// 生成一个新的 256 位密钥。
    public static func newKey() -> SymmetricKey {
        SymmetricKey(size: .bits256)
    }
}
