//
//  SecurityService.swift
//  Deck
//
//  Deck Clipboard Manager - Touch ID Authentication & Data Encryption
//

import Foundation
import LocalAuthentication
import CryptoKit
import Security

final class SecurityService {
    static let shared = SecurityService()
    
    private let context = LAContext()
    private var isAuthenticated = false
    private var lastAuthTime: Date?
    private let authTimeout: TimeInterval = 300 // 5 minutes
    
    private init() {}
    
    // MARK: - Touch ID Authentication
    
    var canUseBiometrics: Bool {
        var error: NSError?
        let canEvaluate = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        return canEvaluate
    }
    
    var biometricType: String {
        switch context.biometryType {
        case .touchID:
            return "Touch ID"
        case .faceID:
            return "Face ID"
        case .opticID:
            return "Optic ID"
        case .none:
            return "生物识别"
        @unknown default:
            return "生物识别"
        }
    }
    
    func authenticate(reason: String = "验证身份以访问剪贴板历史") async -> Bool {
        // Check if still authenticated within timeout (unless authEveryTime is enabled)
        if !DeckUserDefaults.authEveryTime {
            if isAuthenticated, let lastAuth = lastAuthTime,
               Date().timeIntervalSince(lastAuth) < authTimeout {
                return true
            }
        }
        
        let context = LAContext()
        context.localizedCancelTitle = "取消"
        
        var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            return await evaluate(policy: .deviceOwnerAuthenticationWithBiometrics, reason: reason, context: context)
        }

        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            return await evaluate(policy: .deviceOwnerAuthentication, reason: reason, context: context)
        }

        log.warn("Authentication not available: \(error?.localizedDescription ?? "unknown")")
        return false
    }
    
    func resetAuthentication() {
        isAuthenticated = false
        lastAuthTime = nil
    }

    private func evaluate(policy: LAPolicy, reason: String, context: LAContext) async -> Bool {
        do {
            let success = try await context.evaluatePolicy(policy, localizedReason: reason)

            if success {
                isAuthenticated = true
                lastAuthTime = Date()
            }

            return success
        } catch {
            log.warn("Authentication failed: \(error.localizedDescription)")
            return false
        }
    }
    
    // MARK: - Encryption Key Management
    
    private let keychainService = "com.deck.encryption"
    private let keychainAccount = "master-key"
    
    func getOrCreateEncryptionKey() -> SymmetricKey? {
        // Try to get existing key from Keychain
        if let keyData = getKeyFromKeychain() {
            return SymmetricKey(data: keyData)
        }
        
        // Generate new key
        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        
        // Save to Keychain with biometric protection
        if saveKeyToKeychain(keyData) {
            return key
        }
        
        return nil
    }
    
    private func getKeyFromKeychain() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess {
            return result as? Data
        }
        
        return nil
    }
    
    private func saveKeyToKeychain(_ keyData: Data) -> Bool {
        // Delete existing key if any
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        
        // Save new key with simple accessibility (no biometric requirement for key storage)
        // Biometric auth is handled separately when opening the panel
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        if status == errSecSuccess {
            log.info("Encryption key saved to Keychain")
            return true
        } else {
            log.error("Failed to save key to Keychain: \(status)")
            // Fallback: try without accessibility attribute
            let fallbackQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: keychainService,
                kSecAttrAccount as String: keychainAccount,
                kSecValueData as String: keyData
            ]
            let fallbackStatus = SecItemAdd(fallbackQuery as CFDictionary, nil)
            if fallbackStatus == errSecSuccess {
                log.info("Encryption key saved to Keychain (fallback)")
                return true
            }
            log.error("Fallback also failed: \(fallbackStatus)")
            return false
        }
    }
    
    func deleteEncryptionKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
    }
    
    // MARK: - Data Encryption/Decryption
    
    func encrypt(_ data: Data) -> Data? {
        guard let key = getOrCreateEncryptionKey() else {
            log.error("No encryption key available")
            return nil
        }
        
        return encrypt(data, using: key)
    }
    
    func decrypt(_ encryptedData: Data) -> Data? {
        guard let key = getOrCreateEncryptionKey() else {
            log.error("No encryption key available")
            return nil
        }
        
        return decrypt(encryptedData, using: key)
    }

    func encrypt(_ data: Data, using key: SymmetricKey) -> Data? {
        do {
            let sealedBox = try AES.GCM.seal(data, using: key)
            return sealedBox.combined
        } catch {
            log.error("Encryption failed: \(error)")
            return nil
        }
    }

    func decrypt(_ encryptedData: Data, using key: SymmetricKey) -> Data? {
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
            return try AES.GCM.open(sealedBox, using: key)
        } catch {
            log.error("Decryption failed: \(error)")
            return nil
        }
    }
}
