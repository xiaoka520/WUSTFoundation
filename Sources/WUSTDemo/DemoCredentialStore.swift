import Foundation
import Security
import WUSTFoundation

actor DemoCredentialStore: UnionCredentialStore {
    enum StoreError: Error { case keychain(OSStatus), invalidData }
    private let service = "WUSTFoundation.WUSTDemo.UnionCredential"

    func loadCredential(for username: String) throws -> UnionCredential? {
        var query = baseQuery(username)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw StoreError.keychain(status) }
        guard let data = item as? Data,
              let tgt = String(data: data, encoding: .utf8), !tgt.isEmpty else {
            throw StoreError.invalidData
        }
        return UnionCredential(tgt: tgt)
    }

    func saveCredential(_ credential: UnionCredential, for username: String) throws {
        let data = Data(credential.tgt.utf8)
        let query = baseQuery(username)
        let update = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw StoreError.keychain(addStatus) }
        } else if status != errSecSuccess { throw StoreError.keychain(status) }
    }

    func clearCredential(for username: String) throws {
        let status = SecItemDelete(baseQuery(username) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw StoreError.keychain(status)
        }
    }

    private func baseQuery(_ username: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: username,
         kSecAttrSynchronizable as String: false]
    }
}
