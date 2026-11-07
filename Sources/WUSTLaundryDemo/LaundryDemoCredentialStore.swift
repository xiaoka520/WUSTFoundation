import Foundation
import Security
import WUSTFoundation

struct LaundryDemoCredentialStore {
    enum StoreError: Error { case keychain(OSStatus), invalidData }

    private let service = "WUSTFoundation.LaundrySmoke.Credential"

    func load() throws -> LaundryCredential? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw StoreError.keychain(status) }
        guard let data = item as? Data else { throw StoreError.invalidData }
        return try JSONDecoder().decode(LaundryCredential.self, from: data)
    }

    func save(_ credential: LaundryCredential) throws {
        let data = try JSONEncoder().encode(credential)
        let query = baseQuery
        let update = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw StoreError.keychain(addStatus) }
        } else if status != errSecSuccess {
            throw StoreError.keychain(status)
        }
    }

    func clear() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw StoreError.keychain(status) }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "default",
            kSecAttrSynchronizable as String: false,
        ]
    }
}
