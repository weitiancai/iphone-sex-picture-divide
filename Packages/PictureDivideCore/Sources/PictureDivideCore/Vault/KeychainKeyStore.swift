import Foundation
import LocalAuthentication
import Security

/// 保险箱密钥的存放位置。
///
/// - iOS：密钥保存在 Keychain，`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`，可选叠加生物识别保护。
/// - macOS（命令行工具）：退化为"仅本机可访问"，不强制生物识别，方便本地跑测试。
public final class KeychainKeyStore {
    public enum Protection: String {
        /// 只要求设备已解锁（App 层用 LocalAuthentication 做 Face ID 门禁）。
        case unlocked
        /// 读取密钥本身就需要生物识别（当前设备 enrolled 的生物识别变更后密钥自动失效）。
        case biometry
    }

    private let service: String
    private let account: String
    private let protection: Protection

    public init(service: String = "com.picturedivide.vault",
                account: String = "vault-master-key",
                protection: Protection = .unlocked) {
        self.service = service
        self.account = account
        self.protection = protection
    }

    /// 读取密钥；不存在则创建。
    public func loadOrCreateKey() throws -> Data {
        if let existing = try readKeyData() { return existing }
        let keyData = VaultCrypto.newKey().withUnsafeBytes { Data($0) }
        try storeKeyData(keyData)
        return keyData
    }

    public func deleteKey() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandled(status)
        }
    }

    // MARK: - Private

    private func readKeyData() throws -> Data? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        if protection == .biometry {
            // 需要 Face ID / Touch ID 才能取出密钥。
            let context = LAContextFactory.makeContext(reason: "解锁隐私保险箱")
            query[kSecUseAuthenticationContext as String] = context
        }
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { return nil }
            return data
        case errSecItemNotFound:
            return nil
        case errSecUserCanceled, errSecAuthFailed:
            throw KeychainError.authenticationFailed
        default:
            throw KeychainError.unhandled(status)
        }
    }

    private func storeKeyData(_ data: Data) throws {
        var attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]
        if protection == .biometry {
            var error: Unmanaged<CFError>?
            guard let access = SecAccessControlCreateWithFlags(nil,
                                                             kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                                                             .biometryCurrentSet,
                                                             &error) else {
                throw KeychainError.unhandled(OSStatus(-1))
            }
            attributes[kSecAttrAccessControl as String] = access
        } else {
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        }
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecDuplicateItem {
            throw KeychainError.duplicateItem
        }
        guard status == errSecSuccess else {
            throw KeychainError.unhandled(status)
        }
    }

    public enum KeychainError: LocalizedError {
        case unhandled(OSStatus)
        case duplicateItem
        case authenticationFailed

        public var errorDescription: String? {
            switch self {
            case .unhandled(let status):
                return "Keychain 操作失败（status \(status)）。"
            case .duplicateItem:
                return "Keychain 中已存在同名密钥。"
            case .authenticationFailed:
                return "身份验证失败或已被取消。"
            }
        }
    }
}

/// 便于在非 App 环境（测试）里替换 LAContext。
enum LAContextFactory {
    static func makeContext(reason: String) -> LAContext {
        let context = LAContext()
        context.localizedReason = reason
        return context
    }
}
