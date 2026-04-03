import Foundation

#if canImport(Security)
import Security
#endif

public enum SecretStoreError: Error, LocalizedError, Equatable {
    case notAvailable
    case unexpectedStatus(Int)
    case invalidData

    public var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Keychain is not available on this platform."
        case let .unexpectedStatus(status):
            return "Keychain returned status \(status)."
        case .invalidData:
            return "Stored secret data is invalid."
        }
    }
}

public struct KeychainSecretStore: Sendable {
    private let service: String

    public init(service: String = "me.ian.zapi") {
        self.service = service
    }

    public func setSecret(_ value: String, for key: String) throws {
        #if canImport(Security)
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SecretStoreError.unexpectedStatus(Int(status))
        }
        #else
        throw SecretStoreError.notAvailable
        #endif
    }

    public func secret(for key: String) throws -> String? {
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw SecretStoreError.unexpectedStatus(Int(status))
        }

        guard
            let data = item as? Data,
            let value = String(data: data, encoding: .utf8)
        else {
            throw SecretStoreError.invalidData
        }

        return value
        #else
        throw SecretStoreError.notAvailable
        #endif
    }

    public func deleteSecret(for key: String) throws {
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecretStoreError.unexpectedStatus(Int(status))
        }
        #else
        throw SecretStoreError.notAvailable
        #endif
    }
}
