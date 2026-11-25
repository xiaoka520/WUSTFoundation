import CryptoKit
import Foundation
import Security

enum DemoLoginFile {
    struct Credentials: Codable {
        let username: String
        let password: String
    }

    enum StoreError: Error {
        case missingFile
        case missingKey
        case invalidData
        case keychain(OSStatus)
    }

    private static var directory: URL {
        URL.applicationSupportDirectory.appending(path: "WUSTDemo", directoryHint: .isDirectory)
    }

    static var fileURL: URL { directory.appending(path: "login.enc") }

    static var exists: Bool { FileManager.default.fileExists(atPath: fileURL.path) }

    static func save(_ credentials: Credentials) throws {
        guard !credentials.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !credentials.password.isEmpty else { throw StoreError.invalidData }
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let key = try lookupKey() ?? createKey()
        let data = try JSONEncoder().encode(credentials)
        guard let encrypted = try AES.GCM.seal(data, using: key).combined else {
            throw StoreError.invalidData
        }
        try encrypted.write(to: fileURL, options: .atomic)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    static func load() throws -> Credentials {
        guard exists else { throw StoreError.missingFile }
        guard let key = try lookupKey() else { throw StoreError.missingKey }
        do {
            let encrypted = try Data(contentsOf: fileURL)
            let data = try AES.GCM.open(AES.GCM.SealedBox(combined: encrypted), using: key)
            let credentials = try JSONDecoder().decode(Credentials.self, from: data)
            guard !credentials.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !credentials.password.isEmpty else { throw StoreError.invalidData }
            return credentials
        } catch {
            throw StoreError.invalidData
        }
    }

    static func clear() throws {
        do { try FileManager.default.removeItem(at: fileURL) }
        catch CocoaError.fileNoSuchFile {}
    }

    private static var keyQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "WUSTFoundation.WUSTDemo.LoginFileKey",
         kSecAttrAccount as String: "v1",
         kSecAttrSynchronizable as String: false]
    }

    private static func lookupKey() throws -> SymmetricKey? {
        var query = keyQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw StoreError.keychain(status) }
        guard let bytes = item as? Data, bytes.count == 32 else { throw StoreError.invalidData }
        return SymmetricKey(data: bytes)
    }

    private static func createKey() throws -> SymmetricKey {
        let key = SymmetricKey(size: .bits256)
        var item = keyQuery
        item[kSecValueData as String] = key.withUnsafeBytes { Data($0) }
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        if status == errSecDuplicateItem, let existing = try lookupKey() { return existing }
        guard status == errSecSuccess else { throw StoreError.keychain(status) }
        return key
    }
}
