import Foundation
import Security

public enum UnionPasswordEncoderError: Error {
    case invalidPublicKeyData
    case publicKeyImportFailed
    case unsupportedAlgorithm
    case passwordTooLong
    case encryptionFailed
}

struct UnionPasswordEncoder {
    private let publicKeyBase64 =
        "MIGJAoGBALXusWbgaZIOgL69H+pIKdPR8yFvKqvnm2xHo8GNzuX9IsLnrFGcq1kZjs4Dbc8onqggHioLne0wf4+3BBNurrZwKG9a1E5pEAW6nqWvBK2lNnzXJLWib9tRIMyVtkMWBL0hnGt9g6b48ktDkY6piKdvk8MzqlogmRST1OsRF+exAgMBAAE="

    // MARK: 转十六进制
    private func hexString(from data: Data) -> String {
        var result: String = ""
        for byte in data {
            if String(byte, radix: 16).count == 1 {
                result.append("0")
            }
            result.append(String(byte, radix: 16))
        }
        return result
    }
    // MARK: 转UTF-8
    private func passwordData(from password: String) -> Data {
        var result: String = ""
        for scalar in password.unicodeScalars.reversed() {
            result.append(String(scalar))
        }
        return Data(result.utf8)
    }

    private func makePublicKey() throws -> SecKey {
        guard let keyData = Data(base64Encoded: publicKeyBase64) else {
            throw UnionPasswordEncoderError.invalidPublicKeyData
        }

        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
        ]
        
        guard let publicKey = SecKeyCreateWithData(
            keyData as CFData,
            attributes as CFDictionary,
            nil
        ) else {
            throw UnionPasswordEncoderError.publicKeyImportFailed
        }
        
        return publicKey
    }
    
    func encode(password: String) throws -> String {
        let publicKey = try makePublicKey()
        let plainData = passwordData(from: password)
        let algorithm: SecKeyAlgorithm = .rsaEncryptionRaw
        guard SecKeyIsAlgorithmSupported(publicKey, .encrypt, algorithm) else {
            throw UnionPasswordEncoderError.unsupportedAlgorithm
        }
        
        let blockSize = SecKeyGetBlockSize(publicKey)
        
        guard plainData.count <= blockSize else {
            throw UnionPasswordEncoderError.passwordTooLong
        }
        
        var paddedData = Data(
            repeating: 0,
            count: (blockSize-plainData.count)
        )
        paddedData.append(plainData)
        
        guard let encryptedData = SecKeyCreateEncryptedData(
            publicKey,
            algorithm,
            paddedData as CFData,
            nil
        ) else {
            throw UnionPasswordEncoderError.encryptionFailed
        }
        
        return hexString(from: encryptedData as Data)
    }
}
