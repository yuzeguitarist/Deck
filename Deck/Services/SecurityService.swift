// Copyright © 2024–2026 Yuze Pan. 保留一切权利。

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

    // MARK: - Encryption Key Cache
    /// Cache the resolved encryption key in memory to avoid hitting Keychain on every encrypt/decrypt.
    /// Keep the TTL short to limit how long key material lives in RAM.
    private let encryptionKeyCacheTTL: TimeInterval = 60
    private let encryptionKeyLock = NSLock()
    private var cachedEncryptionKey: SymmetricKey?
    private var cachedEncryptionKeyLastAccess: Date?
    
    private init() {}
    
    // MARK: - Touch ID Authentication
    
    var canUseBiometrics: Bool {
        var error: NSError?
        let canEvaluate = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        return canEvaluate
    }
    
    var biometricType: String {
        var error: NSError?
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        switch context.biometryType {
        case .touchID:
            return "Touch ID"
        case .faceID:
            return "Face ID"
        case .opticID:
            return "Optic ID"
        case .none:
            return NSLocalizedString("生物识别", comment: "Biometrics")
        @unknown default:
            return NSLocalizedString("生物识别", comment: "Biometrics")
        }
    }
    
    func authenticate(reason: String = NSLocalizedString("验证身份以访问剪贴板历史", comment: "Authenticate to access clipboard history")) async -> Bool {
        // Check if still authenticated within timeout (unless authEveryTime is enabled)
        if !DeckUserDefaults.authEveryTime {
            if isAuthenticated, let lastAuth = lastAuthTime,
               Date().timeIntervalSince(lastAuth) < authTimeout {
                return true
            }
        }
        
        let context = LAContext()
        context.localizedCancelTitle = NSLocalizedString("取消", comment: "Cancel")
        
        var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            return await evaluate(policy: .deviceOwnerAuthenticationWithBiometrics, reason: reason, context: context)
        }

        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            return await evaluate(policy: .deviceOwnerAuthentication, reason: reason, context: context)
        }

        await log.warn("Authentication not available: \(error?.localizedDescription ?? "unknown")")
        return false
    }
    
    func resetAuthentication() {
        isAuthenticated = false
        lastAuthTime = nil
        // Reduce lifetime of key material in memory when user is no longer authenticated.
        clearCachedEncryptionKey()
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
            await log.warn("Authentication failed: \(error.localizedDescription)")
            return false
        }
    }
    
    // MARK: - Encryption Key Management
    
    private let keychainService = "com.deck.encryption"
    private let keychainAccount = "master-key"
    
    private enum KeychainLoadResult {
        case success(Data)
        case notFound
        case failure(OSStatus)
    }

    // MARK: - In-Memory Key Cache
    private func cachedKeyIfValid(now: Date = Date()) -> SymmetricKey? {
        encryptionKeyLock.lock()
        defer { encryptionKeyLock.unlock() }
        guard let key = cachedEncryptionKey,
              let lastAccess = cachedEncryptionKeyLastAccess,
              now.timeIntervalSince(lastAccess) < encryptionKeyCacheTTL else {
            return nil
        }
        // Touch access time so bursts of encrypt/decrypt keep the key warm.
        cachedEncryptionKeyLastAccess = now
        return key
    }

    private func cacheKey(_ key: SymmetricKey, now: Date = Date()) {
        encryptionKeyLock.lock()
        cachedEncryptionKey = key
        cachedEncryptionKeyLastAccess = now
        encryptionKeyLock.unlock()
    }

    private func clearCachedEncryptionKey() {
        encryptionKeyLock.lock()
        cachedEncryptionKey = nil
        cachedEncryptionKeyLastAccess = nil
        encryptionKeyLock.unlock()
    }
    
    func getOrCreateEncryptionKey() -> SymmetricKey? {
        // Fast path: return cached key (avoids Keychain round-trips during heavy encrypt/decrypt bursts).
        if let cached = cachedKeyIfValid() {
            return cached
        }

        // Try to get existing key from Keychain
        switch getKeyFromKeychain() {
        case .success(let keyData):
            let key = SymmetricKey(data: keyData)
            cacheKey(key)
            return key
        case .failure(let status):
            log.error("Failed to read encryption key from Keychain: \(status)")
            return nil
        case .notFound:
            break
        }
        
        // Generate new key
        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        
        // Save to Keychain with biometric protection
        if saveKeyToKeychain(keyData) {
            cacheKey(key)
            return key
        }
        
        return nil
    }
    
    private func getKeyFromKeychain() -> KeychainLoadResult {
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
            guard let data = result as? Data else {
                return .failure(errSecInternalError)
            }
            return .success(data)
        }
        
        if status == errSecItemNotFound {
            return .notFound
        }
        
        return .failure(status)
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
        clearCachedEncryptionKey()
    }
    
    // MARK: - Data Encryption/Decryption
    
    private func encryptInternal(_ data: Data) -> Data? {
        guard let key = getOrCreateEncryptionKey() else {
            log.error("No encryption key available")
            return nil
        }
        
        return encrypt(data, using: key)
    }

    func encrypt(_ data: Data) -> Data? {
        encryptInternal(data)
    }

    /// Async overload to support call sites that already use `await SecurityService.shared.encrypt(...)`.
    /// Implementation is still synchronous, but this avoids Swift Concurrency warnings.
    func encrypt(_ data: Data) async -> Data? {
        encryptInternal(data)
    }
    
    private func decryptInternal(_ encryptedData: Data) -> Data? {
        guard let key = getOrCreateEncryptionKey() else {
            log.error("No encryption key available")
            return nil
        }
        
        return decrypt(encryptedData, using: key)
    }

    func decrypt(_ encryptedData: Data) -> Data? {
        decryptInternal(encryptedData)
    }

    /// Async overload to support call sites that already use `await SecurityService.shared.decrypt(...)`.
    /// Implementation is still synchronous, but this avoids Swift Concurrency warnings.
    func decrypt(_ encryptedData: Data) async -> Data? {
        decryptInternal(encryptedData)
    }

    func decryptSilently(_ encryptedData: Data) -> Data? {
        guard let key = getOrCreateEncryptionKey() else {
            return nil
        }
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
            return try AES.GCM.open(sealedBox, using: key)
        } catch {
            return nil
        }
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
