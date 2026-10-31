// Copyright © 2024–2026 Yuze Pan. 保留一切权利。

//
//  UserDefaultsManager.swift
//  Deck
//
//  Deck Clipboard Manager
//

import Foundation
import SwiftUI

enum PrefKey: String {
    case historyRetentionDays
    case launchAtLogin
    case soundEnabled
    case showInMenuBar
    case pasteDirectly
    case customStoragePath
    case useCustomStorage
    case storageBookmark
    case databaseAutoBackupEnabled
    case userTags
    case tagDisplayOrder
    case appColorCache
    case globalHotKeys
    case appearance
    case ignoreSensitiveContent
    case securityModeEnabled
    case encryptionKey
    case stegoPassphraseLength
    case authEveryTime
    case hasLaunchedBefore
    case ignoredApps
    case enableLinkPreview
    case showDuringScreenShare
    case hideDockWhenPanelActive
    case keepPanelAboveOtherApps
    case deleteConfirmation
    // Smart URL Cleaner
    case cleanTrackingParams
    // Instant Calculation
    case instantCalculation
    // Smart Line Break Removal
    case smartLineBreakRemoval
    // Smart Pure Paste
    case smartPurePaste
    // Focus Mode / Pause
    case isPaused
    case pauseEndTime
    // Smart Window Title Detection
    case smartWindowTitleDetection
    // Context Aware
    case userAppTypePreferences
    // Vim Navigation
    case vimNavigationEnabled
    case vimStartInInsertMode
    case vimVerticalDirection
    // Script Safety
    case scriptTimeout
    case scriptMaxInputLength
    case authorizedNetworkPlugins  // 已授权网络权限的插件 ID 列表
    case authorizedNetworkPluginHashes  // 已授权网络权限的插件 hash 绑定
    // OCR
    case ocrRecognitionLevel
    case ocrUsesLanguageCorrection
    case ocrRecognitionLanguages
    case ocrMaxTextLength
    // LAN Sharing
    case lanSharingEnabled
    case lanSharingDeviceName
    case lanSharingDeviceIdentifier
    case lanSharingRememberedPeers
    case directConnectPortHints
    // Cursor Assistant
    case cursorAssistantEnabled
    case cursorAssistantTriggers
    case cursorAssistantTriggerKey  // 触发键：shift / option / control / command
    case cursorAssistantCustomShortcut  // 自定义触发键
    // AI Assistant
    case aiProviderType
    case aiOpenAIBaseURL
    case aiOpenAIModel
    case aiAnthropicBaseURL
    case aiAnthropicModel
    case aiOllamaBaseURL
    case aiOllamaModel
    case aiLocalAIClient
    case aiModelCatalogVersion
    case aiChatGPTModel
    case aiChatShortcut
    case aiMemoryEnabled
    case aiSessionContextEnabled
    // Double Modifier Hotkey
    case doubleOptionToToggle
    case doubleCommandToToggle
    // Typing Paste
    case typingPasteEnabled
    case typingPasteShortcut
    // Queue paste (paste next / link card), default ⌘⇧V for existing installs
    case queuePasteShortcut
    // Quick Paste (Panel 1-9)
    case quickPasteNumberModifier
    case queueQuickSelectAnchor
    // Search
    case searchMode  // exact, fuzzy, regex, mixed
    // iCloud Sync
    case iCloudSyncEnabled
    case iCloudEncryptionEnabled
    case iCloudLastSyncDate
    // Diagnostics Upload
    case diagnosticsUploadEnabled
    case diagnosticsLastUploadAt
    case diagnosticsClientId
    // Bank Card Detection
    case ignoreBankCardNumbers
    // Identity Number Detection
    case ignoreIdentityNumbers
    // Template Library
    case templateLibraries
    case templateItems
    /// 模版项元数据（payload 在 Application Support 文件中）
    case templateItemIndices
    /// 0 = 旧版整包存 UserDefaults；1 = 文件系统 payload
    case templateItemsStorageVersion
    case cursorAssistantTemplateBindings
    // Data maintenance
    case fileSearchTextBackfillVersion
    case autoScanRedundantBinaryOnLaunch
    case includeBinarySlimInOneClickMaintenance
    // CLI Bridge
    case cliBridgeEnabled
    case cliBridgePort
    // iOS Sync (Shortcuts)
    case iosSyncEnabled
    case iosSyncPortHints
    case iosSyncLastSuccessfulPort
    case iosSyncLastSyncAt
    case iosSyncOnboardingCompleted
    // Paste Queue HUD
    case pasteQueueHUDPositionX
    case pasteQueueHUDPositionY
    // Ambient Bar
    case showAmbientBar
    // Feedback survey card
    case feedbackSurveyCardPermanentlyHidden
    // Layout Mode
    case layoutMode
    // Vertical Panel Side
    case verticalPanelSide
    // Horizontal Panel Height (user-resizable)
    case horizontalPanelHeight
}

// MARK: - Ignored App Model

struct IgnoredAppInfo: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    let bundleIdentifier: String?
    let path: String
    
    init(name: String, bundleIdentifier: String? = nil, path: String) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.path = path
        self.id = bundleIdentifier ?? path
    }
}

struct RememberedLANPeer: Codable, Hashable, Identifiable {
    let id: String
    var deviceId: String?
    var legacyDisplayName: String?
    var displayName: String
    var isSecurityModeEnabled: Bool
    var isTrusted: Bool
    var lastSeenAt: Date?
    var lastConnectedAt: Date?
    var protocolVersion: Int?
    var minimumSupportedProtocolVersion: Int?
    var appVersion: String?
    var updatedAt: Date
}

enum HistoryRetention: Int, CaseIterable, Identifiable {
    case oneDay = 1
    case threeDays = 3
    case sevenDays = 7
    case fourteenDays = 14
    case thirtyDays = 30
    case ninetyDays = 90
    case oneYear = 365
    case forever = -1
    
    var id: Int { rawValue }
    
    var displayName: String {
        switch self {
        case .oneDay: return NSLocalizedString("1 天", comment: "1 day")
        case .threeDays: return NSLocalizedString("3 天", comment: "3 days")
        case .sevenDays: return NSLocalizedString("7 天", comment: "7 days")
        case .fourteenDays: return NSLocalizedString("14 天", comment: "14 days")
        case .thirtyDays: return NSLocalizedString("30 天", comment: "30 days")
        case .ninetyDays: return NSLocalizedString("90 天", comment: "90 days")
        case .oneYear: return NSLocalizedString("1 年", comment: "1 year")
        case .forever: return NSLocalizedString("永久保留", comment: "Forever")
        }
    }
}

enum AppearanceMode: Int, CaseIterable, Identifiable {
    case system = 0
    case light = 1
    case dark = 2
    
    var id: Int { rawValue }
    
    var displayName: String {
        switch self {
        case .system: return NSLocalizedString("跟随系统", comment: "Follow System")
        case .light: return NSLocalizedString("浅色", comment: "Light")
        case .dark: return NSLocalizedString("深色", comment: "Dark")
        }
    }
}

enum VimVerticalDirection: Int, CaseIterable, Identifiable {
    case jDownKUp = 0
    case jUpKDown = 1

    var id: Int { rawValue }
}

enum QuickPasteNumberModifier: String, CaseIterable, Identifiable {
    case command = "command"
    case option = "option"
    case control = "control"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .command: return "⌘"
        case .option: return "⌥"
        case .control: return "⌃"
        }
    }

    var displayName: String {
        switch self {
        case .command:
            return NSLocalizedString("Command ⌘", comment: "Quick paste number modifier: Command")
        case .option:
            return NSLocalizedString("Option ⌥", comment: "Quick paste number modifier: Option")
        case .control:
            return NSLocalizedString("Control ⌃", comment: "Quick paste number modifier: Control")
        }
    }
}

enum QueueQuickSelectAnchor: String, CaseIterable, Identifiable {
    case leftmost = "leftmost"
    case focused = "focused"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .leftmost:
            return NSLocalizedString("最左侧卡片", comment: "Queue quick select anchor: leftmost card")
        case .focused:
            return NSLocalizedString("当前聚焦卡片", comment: "Queue quick select anchor: focused card")
        }
    }
}

@propertyWrapper
struct UserDefault<T> {
    let key: String
    let defaultValue: T
    
    var wrappedValue: T {
        get { UserDefaults.standard.object(forKey: key) as? T ?? defaultValue }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

/// Process-local benchmark isolation. Inert unless the worktree active file or
/// `DECK_MEMOPT_STORAGE` is present. Never writes preferences.
enum MemOptIsolation {
    struct Active: Sendable {
        var storage: String
        var scenario: String
        var fixture: String
        var output: String
        var run: String
    }

    nonisolated static let activeFileURL = URL(
        fileURLWithPath: "/Users/jerry/Desktop/开发/Deck/Deck-memopt-50/tmp/memopt/active.json"
    )

    nonisolated private static let cachedActive: Active? = loadActive()

    nonisolated static var active: Active? { cachedActive }

    nonisolated private static func loadActive() -> Active? {
        if let data = try? Data(contentsOf: activeFileURL),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let storage = object["storage"] as? String,
           !storage.isEmpty {
            return Active(
                storage: storage,
                scenario: object["scenario"] as? String ?? "suite",
                fixture: object["fixture"] as? String ?? "",
                output: object["output"] as? String ?? "",
                run: object["run"] as? String ?? "1"
            )
        }
        if let value = ProcessInfo.processInfo.environment["DECK_MEMOPT_STORAGE"], !value.isEmpty {
            return Active(
                storage: value,
                scenario: ProcessInfo.processInfo.environment["DECK_MEMOPT_SCENARIO"] ?? "suite",
                fixture: ProcessInfo.processInfo.environment["DECK_MEMOPT_FIXTURE"] ?? "",
                output: ProcessInfo.processInfo.environment["DECK_MEMOPT_OUTPUT"] ?? "",
                run: ProcessInfo.processInfo.environment["DECK_MEMOPT_RUN"] ?? "1"
            )
        }
        return nil
    }

    nonisolated static var storageRoot: String? {
        guard let storage = active?.storage, !storage.isEmpty else { return nil }
        return storage
    }

    nonisolated static var isActive: Bool { storageRoot != nil }
}

struct DeckUserDefaults {
    @UserDefault(key: PrefKey.historyRetentionDays.rawValue, defaultValue: 30)
    static var historyRetentionDays: Int
    
    @UserDefault(key: PrefKey.launchAtLogin.rawValue, defaultValue: false)
    static var launchAtLogin: Bool
    
    @UserDefault(key: PrefKey.soundEnabled.rawValue, defaultValue: true)
    static var soundEnabled: Bool
    
    @UserDefault(key: PrefKey.showInMenuBar.rawValue, defaultValue: true)
    static var showInMenuBar: Bool
    
    @UserDefault(key: PrefKey.pasteDirectly.rawValue, defaultValue: true)
    static var pasteDirectly: Bool
    
    @UserDefault(key: PrefKey.useCustomStorage.rawValue, defaultValue: false)
    nonisolated(unsafe) static var useCustomStorage: Bool

    nonisolated static var databaseAutoBackupEnabled: Bool {
        get {
            if MemOptIsolation.isActive { return false }
            return UserDefaults.standard.object(forKey: PrefKey.databaseAutoBackupEnabled.rawValue) as? Bool ?? true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: PrefKey.databaseAutoBackupEnabled.rawValue)
        }
    }
    
    @UserDefault(key: PrefKey.appearance.rawValue, defaultValue: 0)
    static var appearance: Int
    
    @UserDefault(key: PrefKey.ignoreSensitiveContent.rawValue, defaultValue: true)
    static var ignoreSensitiveContent: Bool
    
    nonisolated static var securityModeEnabled: Bool {
        get {
            if MemOptIsolation.isActive { return false }
            return UserDefaults.standard.object(forKey: PrefKey.securityModeEnabled.rawValue) as? Bool ?? false
        }
        set {
            UserDefaults.standard.set(newValue, forKey: PrefKey.securityModeEnabled.rawValue)
        }
    }

    @UserDefault(key: PrefKey.stegoPassphraseLength.rawValue, defaultValue: 0)
    static var stegoPassphraseLength: Int
    
    @UserDefault(key: PrefKey.authEveryTime.rawValue, defaultValue: false)
    static var authEveryTime: Bool
    
    @UserDefault(key: PrefKey.hasLaunchedBefore.rawValue, defaultValue: false)
    static var hasLaunchedBefore: Bool
    
    @UserDefault(key: PrefKey.enableLinkPreview.rawValue, defaultValue: true)
    static var enableLinkPreview: Bool
    
    @UserDefault(key: PrefKey.showDuringScreenShare.rawValue, defaultValue: true)
    static var showDuringScreenShare: Bool

    @UserDefault(key: PrefKey.hideDockWhenPanelActive.rawValue, defaultValue: false)
    static var hideDockWhenPanelActive: Bool

    @UserDefault(key: PrefKey.keepPanelAboveOtherApps.rawValue, defaultValue: true)
    static var keepPanelAboveOtherApps: Bool
    
    @UserDefault(key: PrefKey.deleteConfirmation.rawValue, defaultValue: false)
    static var deleteConfirmation: Bool

    @UserDefault(key: PrefKey.showAmbientBar.rawValue, defaultValue: true)
    static var showAmbientBar: Bool

    @UserDefault(key: PrefKey.feedbackSurveyCardPermanentlyHidden.rawValue, defaultValue: false)
    static var feedbackSurveyCardPermanentlyHidden: Bool

    // MARK: - Layout Mode
    @UserDefault(key: PrefKey.layoutMode.rawValue, defaultValue: LayoutMode.horizontal.rawValue)
    static var layoutMode: Int

    @UserDefault(key: PrefKey.verticalPanelSide.rawValue, defaultValue: VerticalPanelSide.right.rawValue)
    static var verticalPanelSide: Int

    @UserDefault(key: PrefKey.cleanTrackingParams.rawValue, defaultValue: true)
    static var cleanTrackingParams: Bool

    @UserDefault(key: PrefKey.instantCalculation.rawValue, defaultValue: true)
    static var instantCalculation: Bool

    @UserDefault(key: PrefKey.smartLineBreakRemoval.rawValue, defaultValue: true)
    static var smartLineBreakRemoval: Bool

    @UserDefault(key: PrefKey.smartPurePaste.rawValue, defaultValue: true)
    static var smartPurePaste: Bool

    @UserDefault(key: PrefKey.isPaused.rawValue, defaultValue: false)
    static var isPaused: Bool

    @UserDefault(key: PrefKey.smartWindowTitleDetection.rawValue, defaultValue: true)
    static var smartWindowTitleDetection: Bool

    @UserDefault(key: PrefKey.fileSearchTextBackfillVersion.rawValue, defaultValue: 0)
    static var fileSearchTextBackfillVersion: Int

    @UserDefault(key: PrefKey.autoScanRedundantBinaryOnLaunch.rawValue, defaultValue: false)
    static var autoScanRedundantBinaryOnLaunch: Bool

    @UserDefault(key: PrefKey.includeBinarySlimInOneClickMaintenance.rawValue, defaultValue: false)
    static var includeBinarySlimInOneClickMaintenance: Bool

    static var pauseEndTime: Date? {
        get {
            guard let timestamp = UserDefaults.standard.object(forKey: PrefKey.pauseEndTime.rawValue) as? Double else {
                return nil
            }
            return Date(timeIntervalSince1970: timestamp)
        }
        set {
            if let date = newValue {
                UserDefaults.standard.set(date.timeIntervalSince1970, forKey: PrefKey.pauseEndTime.rawValue)
            } else {
                UserDefaults.standard.removeObject(forKey: PrefKey.pauseEndTime.rawValue)
            }
        }
    }

    static var ignoredApps: [IgnoredAppInfo] {
        get {
            guard let data = UserDefaults.standard.data(forKey: PrefKey.ignoredApps.rawValue),
                  let apps = try? JSONDecoder().decode([IgnoredAppInfo].self, from: data) else {
                // Default ignored apps (password managers)
                return [
                    IgnoredAppInfo(
                        name: NSLocalizedString("密码", comment: "Default ignored app name: Passwords"),
                        bundleIdentifier: "com.apple.Passwords",
                        path: "/System/Applications/Passwords.app"
                    ),
                    IgnoredAppInfo(
                        name: NSLocalizedString("钥匙串访问", comment: "Default ignored app name: Keychain Access"),
                        bundleIdentifier: "com.apple.keychainaccess",
                        path: "/System/Applications/Utilities/Keychain Access.app"
                    )
                ]
            }
            return apps
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: PrefKey.ignoredApps.rawValue)
            }
        }
    }
    
    nonisolated static var customStoragePath: String? {
        get { UserDefaults.standard.string(forKey: PrefKey.customStoragePath.rawValue) }
        set { UserDefaults.standard.set(newValue, forKey: PrefKey.customStoragePath.rawValue) }
    }
    
    nonisolated static var storageBookmark: Data? {
        get { UserDefaults.standard.data(forKey: PrefKey.storageBookmark.rawValue) }
        set { UserDefaults.standard.set(newValue, forKey: PrefKey.storageBookmark.rawValue) }
    }
    
    static var userTags: [DeckTag] {
        get {
            guard let data = UserDefaults.standard.data(forKey: PrefKey.userTags.rawValue),
                  let tags = try? JSONDecoder().decode([DeckTag].self, from: data) else {
                return []
            }
            return tags
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: PrefKey.userTags.rawValue)
            }
        }
    }

    /// 标签显示顺序（包含系统标签与用户标签的 id）
    @UserDefault(key: PrefKey.tagDisplayOrder.rawValue, defaultValue: [])
    static var tagDisplayOrder: [Int]
    
    static var appColorCache: [String: String] {
        get {
            UserDefaults.standard.dictionary(forKey: PrefKey.appColorCache.rawValue) as? [String: String] ?? [:]
        }
        set {
            UserDefaults.standard.set(newValue, forKey: PrefKey.appColorCache.rawValue)
        }
    }
    
    static var globalHotKeys: [HotKeyInfo] {
        get {
            guard let data = UserDefaults.standard.data(forKey: PrefKey.globalHotKeys.rawValue),
                  let keys = try? JSONDecoder().decode([HotKeyInfo].self, from: data) else {
                return []
            }
            return keys
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: PrefKey.globalHotKeys.rawValue)
            }
        }
    }

    /// 用户自定义的应用类型偏好（覆盖内置配置）
    static var userAppTypePreferences: [String: [String]] {
        get {
            guard let data = UserDefaults.standard.data(forKey: PrefKey.userAppTypePreferences.rawValue),
                  let prefs = try? JSONDecoder().decode([String: [String]].self, from: data) else {
                return [:]
            }
            return prefs
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: PrefKey.userAppTypePreferences.rawValue)
            }
        }
    }

    // MARK: - Vim Navigation
    
    @UserDefault(key: PrefKey.vimNavigationEnabled.rawValue, defaultValue: false)
    static var vimNavigationEnabled: Bool

    @UserDefault(key: PrefKey.vimStartInInsertMode.rawValue, defaultValue: false)
    static var vimStartInInsertMode: Bool

    @UserDefault(
        key: PrefKey.vimVerticalDirection.rawValue,
        defaultValue: VimVerticalDirection.jDownKUp.rawValue
    )
    private static var vimVerticalDirectionRawValue: Int

    static var vimVerticalDirection: VimVerticalDirection {
        get { VimVerticalDirection(rawValue: vimVerticalDirectionRawValue) ?? .jDownKUp }
        set { vimVerticalDirectionRawValue = newValue.rawValue }
    }

    // MARK: - Script Safety

    @UserDefault(key: PrefKey.scriptTimeout.rawValue, defaultValue: 5)
    nonisolated(unsafe) static var scriptTimeout: Int  // 秒

    @UserDefault(key: PrefKey.scriptMaxInputLength.rawValue, defaultValue: 100000)
    nonisolated(unsafe) static var scriptMaxInputLength: Int

    /// 已授权网络权限的插件 ID 列表
    nonisolated(unsafe) static var authorizedNetworkPlugins: [String] {
        get {
            UserDefaults.standard.stringArray(forKey: PrefKey.authorizedNetworkPlugins.rawValue) ?? []
        }
        set {
            UserDefaults.standard.set(newValue, forKey: PrefKey.authorizedNetworkPlugins.rawValue)
        }
    }

    /// 已授权网络权限的插件 hash 绑定
    nonisolated(unsafe) static var authorizedNetworkPluginHashes: [String: String] {
        get {
            guard let data = UserDefaults.standard.data(forKey: PrefKey.authorizedNetworkPluginHashes.rawValue),
                  let mapping = try? JSONDecoder().decode([String: String].self, from: data) else {
                return [:]
            }
            return mapping
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: PrefKey.authorizedNetworkPluginHashes.rawValue)
            }
        }
    }

    nonisolated static func isNetworkPluginAuthorized(pluginId: String, scriptHash: String?) -> Bool {
        guard let scriptHash = scriptHash?.trimmingCharacters(in: .whitespacesAndNewlines),
              !scriptHash.isEmpty else {
            return false
        }

        let hashes = authorizedNetworkPluginHashes
        if let stored = hashes[pluginId] {
            if stored == scriptHash {
                return true
            }

            // 用户已授权过同插件 ID，脚本变更后自动更新 hash 绑定。
            var updated = hashes
            updated[pluginId] = scriptHash
            authorizedNetworkPluginHashes = updated
            return true
        }

        // One-time legacy migration: only when hash-bound entry does not exist.
        if authorizedNetworkPlugins.contains(pluginId) {
            var updated = hashes
            updated[pluginId] = scriptHash
            authorizedNetworkPluginHashes = updated

            var legacy = authorizedNetworkPlugins
            legacy.removeAll { $0 == pluginId }
            authorizedNetworkPlugins = legacy
            return true
        }

        return false
    }

    nonisolated static func authorizeNetworkPlugin(pluginId: String, scriptHash: String?) {
        guard let scriptHash = scriptHash?.trimmingCharacters(in: .whitespacesAndNewlines),
              !scriptHash.isEmpty else { return }

        var hashes = authorizedNetworkPluginHashes
        hashes[pluginId] = scriptHash
        authorizedNetworkPluginHashes = hashes

        // Cleanup legacy list once hash-bound authorization is stored.
        var legacy = authorizedNetworkPlugins
        legacy.removeAll { $0 == pluginId }
        authorizedNetworkPlugins = legacy
    }

    nonisolated static func revokeNetworkPlugin(pluginId: String) {
        var hashes = authorizedNetworkPluginHashes
        hashes.removeValue(forKey: pluginId)
        authorizedNetworkPluginHashes = hashes

        var legacy = authorizedNetworkPlugins
        legacy.removeAll { $0 == pluginId }
        authorizedNetworkPlugins = legacy
    }

    // MARK: - OCR

    @UserDefault(key: PrefKey.ocrRecognitionLevel.rawValue, defaultValue: "accurate")
    nonisolated(unsafe)
    static var ocrRecognitionLevel: String

    @UserDefault(key: PrefKey.ocrUsesLanguageCorrection.rawValue, defaultValue: true)
    nonisolated(unsafe)
    static var ocrUsesLanguageCorrection: Bool

    nonisolated(unsafe) static var ocrRecognitionLanguages: [String] {
        get {
            let defaultLanguages = ["zh-Hans", "zh-Hant", "en-US", "ja-JP", "ko-KR"]
            return UserDefaults.standard.stringArray(forKey: PrefKey.ocrRecognitionLanguages.rawValue) ?? defaultLanguages
        }
        set {
            UserDefaults.standard.set(newValue, forKey: PrefKey.ocrRecognitionLanguages.rawValue)
        }
    }

    @UserDefault(key: PrefKey.ocrMaxTextLength.rawValue, defaultValue: 10000)
    nonisolated(unsafe)
    static var ocrMaxTextLength: Int

    // MARK: - LAN Sharing

    @UserDefault(key: PrefKey.lanSharingEnabled.rawValue, defaultValue: false)
    static var lanSharingEnabled: Bool

    static var lanSharingDeviceName: String {
        get {
            UserDefaults.standard.string(forKey: PrefKey.lanSharingDeviceName.rawValue) ?? Host.current().localizedName ?? "Mac"
        }
        set {
            UserDefaults.standard.set(newValue, forKey: PrefKey.lanSharingDeviceName.rawValue)
        }
    }

    static var lanSharingDeviceIdentifier: String {
        get {
            if let existing = UserDefaults.standard.string(forKey: PrefKey.lanSharingDeviceIdentifier.rawValue),
               !existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return existing
            }

            let generated = UUID().uuidString
            UserDefaults.standard.set(generated, forKey: PrefKey.lanSharingDeviceIdentifier.rawValue)
            return generated
        }
        set {
            UserDefaults.standard.set(newValue, forKey: PrefKey.lanSharingDeviceIdentifier.rawValue)
        }
    }

    static var lanSharingRememberedPeers: [RememberedLANPeer] {
        get {
            guard let data = UserDefaults.standard.data(forKey: PrefKey.lanSharingRememberedPeers.rawValue),
                  let peers = try? JSONDecoder().decode([RememberedLANPeer].self, from: data) else {
                return []
            }
            return peers
        }
        set {
            if newValue.isEmpty {
                UserDefaults.standard.removeObject(forKey: PrefKey.lanSharingRememberedPeers.rawValue)
                return
            }

            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: PrefKey.lanSharingRememberedPeers.rawValue)
            }
        }
    }

    static var directConnectPortHints: [String: Int] {
        get {
            let raw = UserDefaults.standard.dictionary(forKey: PrefKey.directConnectPortHints.rawValue) ?? [:]
            return raw.reduce(into: [String: Int]()) { partialResult, entry in
                if let value = entry.value as? Int {
                    partialResult[entry.key] = value
                }
            }
        }
        set {
            if newValue.isEmpty {
                UserDefaults.standard.removeObject(forKey: PrefKey.directConnectPortHints.rawValue)
                return
            }
            UserDefaults.standard.set(newValue, forKey: PrefKey.directConnectPortHints.rawValue)
        }
    }

    // MARK: - Cursor Assistant

    @UserDefault(key: PrefKey.cursorAssistantEnabled.rawValue, defaultValue: false)
    static var cursorAssistantEnabled: Bool

    /// 触发键：shift / option / control / command（默认 shift）
    @UserDefault(key: PrefKey.cursorAssistantTriggerKey.rawValue, defaultValue: "shift")
    static var cursorAssistantTriggerKey: String

    /// 自定义触发键（例如 ⌘K），为空表示未设置
    static var cursorAssistantCustomShortcut: KeyboardShortcut {
        get {
            guard let data = UserDefaults.standard.data(forKey: PrefKey.cursorAssistantCustomShortcut.rawValue),
                  let shortcut = try? JSONDecoder().decode(KeyboardShortcut.self, from: data) else {
                return .empty
            }
            return shortcut
        }
        set {
            if newValue.isEmpty {
                UserDefaults.standard.removeObject(forKey: PrefKey.cursorAssistantCustomShortcut.rawValue)
                return
            }
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: PrefKey.cursorAssistantCustomShortcut.rawValue)
            }
        }
    }

    /// 自定义触发词映射: [触发词: [类型rawValue]]
    static var cursorAssistantTriggers: [String: [String]] {
        get {
            guard let data = UserDefaults.standard.data(forKey: PrefKey.cursorAssistantTriggers.rawValue),
                  let triggers = try? JSONDecoder().decode([String: [String]].self, from: data) else {
                return [:]
            }
            return triggers
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: PrefKey.cursorAssistantTriggers.rawValue)
            }
        }
    }

    /// 触发词与模版库的绑定: [触发词: 库UUID字符串]
    static var cursorAssistantTemplateBindings: [String: String] {
        get {
            guard let data = UserDefaults.standard.data(forKey: PrefKey.cursorAssistantTemplateBindings.rawValue),
                  let bindings = try? JSONDecoder().decode([String: String].self, from: data) else {
                return [:]
            }
            return bindings
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: PrefKey.cursorAssistantTemplateBindings.rawValue)
            }
        }
    }

    // MARK: - AI Assistant

    @UserDefault(key: PrefKey.aiProviderType.rawValue, defaultValue: "openai_api")
    static var aiProviderType: String

    @UserDefault(key: PrefKey.aiOpenAIBaseURL.rawValue, defaultValue: "https://api.openai.com/v1")
    static var aiOpenAIBaseURL: String

    @UserDefault(key: PrefKey.aiOpenAIModel.rawValue, defaultValue: "")
    static var aiOpenAIModel: String

    @UserDefault(key: PrefKey.aiAnthropicBaseURL.rawValue, defaultValue: "https://api.anthropic.com/v1")
    static var aiAnthropicBaseURL: String

    @UserDefault(key: PrefKey.aiAnthropicModel.rawValue, defaultValue: "")
    static var aiAnthropicModel: String

    @UserDefault(key: PrefKey.aiOllamaBaseURL.rawValue, defaultValue: "http://localhost:11434")
    static var aiOllamaBaseURL: String

    @UserDefault(key: PrefKey.aiOllamaModel.rawValue, defaultValue: "")
    static var aiOllamaModel: String

    @UserDefault(key: PrefKey.aiLocalAIClient.rawValue, defaultValue: "ollama")
    static var aiLocalAIClient: String

    @UserDefault(key: PrefKey.aiModelCatalogVersion.rawValue, defaultValue: 0)
    static var aiModelCatalogVersion: Int

    @UserDefault(key: PrefKey.aiChatGPTModel.rawValue, defaultValue: "gpt-6.1-terra")
    static var aiChatGPTModel: String

    @UserDefault(key: PrefKey.aiMemoryEnabled.rawValue, defaultValue: true)
    static var aiMemoryEnabled: Bool

    @UserDefault(key: PrefKey.aiSessionContextEnabled.rawValue, defaultValue: true)
    static var aiSessionContextEnabled: Bool

    static var aiChatShortcut: KeyboardShortcut {
        get {
            guard let data = UserDefaults.standard.data(forKey: PrefKey.aiChatShortcut.rawValue),
                  let shortcut = try? JSONDecoder().decode(KeyboardShortcut.self, from: data) else {
                var shortcut = KeyboardShortcut()
                shortcut.modifiers = [.option, .shift]
                shortcut.keyCode = KeyCode.space
                shortcut.displayKey = "Space"
                return shortcut
            }
            return shortcut
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            UserDefaults.standard.set(data, forKey: PrefKey.aiChatShortcut.rawValue)
        }
    }

    // MARK: - Template Library

    /// 模版库列表
    static var templateLibraries: [TemplateLibrary] {
        get {
            guard let data = UserDefaults.standard.data(forKey: PrefKey.templateLibraries.rawValue),
                  let libraries = try? JSONDecoder().decode([TemplateLibrary].self, from: data) else {
                return []
            }
            return libraries
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: PrefKey.templateLibraries.rawValue)
            }
        }
    }

    /// 模版项元数据索引（不含大体积 data / previewData）
    static var templateItemIndices: [TemplateItemIndex] {
        get {
            guard let data = UserDefaults.standard.data(forKey: PrefKey.templateItemIndices.rawValue),
                  let items = try? JSONDecoder().decode([TemplateItemIndex].self, from: data) else {
                return []
            }
            return items
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: PrefKey.templateItemIndices.rawValue)
            }
        }
    }

    /// 模版项存储格式版本（迁移用；未写入 key 时视为 0 = 可能仍有旧版 UserDefaults 大包）
    static var templateItemsStorageVersion: Int {
        get {
            guard UserDefaults.standard.object(forKey: PrefKey.templateItemsStorageVersion.rawValue) != nil else {
                return 0
            }
            return UserDefaults.standard.integer(forKey: PrefKey.templateItemsStorageVersion.rawValue)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: PrefKey.templateItemsStorageVersion.rawValue)
        }
    }

    /// 已废弃：旧版整包 JSON；仅迁移逻辑读取，新代码请用 `templateItemIndices` + `TemplatePayloadStore`
    static var legacyTemplateItemsBlob: Data? {
        UserDefaults.standard.data(forKey: PrefKey.templateItems.rawValue)
    }

    static func clearLegacyTemplateItemsBlob() {
        UserDefaults.standard.removeObject(forKey: PrefKey.templateItems.rawValue)
    }

    // MARK: - Modifier Hotkey

    @UserDefault(key: PrefKey.doubleOptionToToggle.rawValue, defaultValue: false)
    static var doubleOptionToToggle: Bool

    @UserDefault(key: PrefKey.doubleCommandToToggle.rawValue, defaultValue: false)
    static var doubleCommandToToggle: Bool

    @UserDefault(key: PrefKey.typingPasteEnabled.rawValue, defaultValue: true)
    static var typingPasteEnabled: Bool

    static var typingPasteShortcut: KeyboardShortcut {
        get {
            guard let data = UserDefaults.standard.data(forKey: PrefKey.typingPasteShortcut.rawValue),
                  let shortcut = try? JSONDecoder().decode(KeyboardShortcut.self, from: data),
                  !shortcut.isEmpty else {
                return .defaultTypingPaste
            }
            return shortcut
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: PrefKey.typingPasteShortcut.rawValue)
            }
        }
    }

    static var hasQueuePasteShortcutPreference: Bool {
        UserDefaults.standard.object(forKey: PrefKey.queuePasteShortcut.rawValue) != nil
    }

    /// 队列「依次粘贴」/ 链接卡片粘贴快捷键。未设置时沿用 ⌘⇧V；设置为空表示关闭。
    static var queuePasteShortcut: KeyboardShortcut {
        get {
            guard let data = UserDefaults.standard.data(forKey: PrefKey.queuePasteShortcut.rawValue) else {
                return .defaultQueuePaste
            }
            return (try? JSONDecoder().decode(KeyboardShortcut.self, from: data)) ?? .defaultQueuePaste
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: PrefKey.queuePasteShortcut.rawValue)
            }
        }
    }

    static var quickPasteNumberModifier: QuickPasteNumberModifier {
        get {
            guard let rawValue = UserDefaults.standard.string(forKey: PrefKey.quickPasteNumberModifier.rawValue),
                  let modifier = QuickPasteNumberModifier(rawValue: rawValue) else {
                return .command
            }
            return modifier
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: PrefKey.quickPasteNumberModifier.rawValue)
        }
    }

    static var queueQuickSelectAnchor: QueueQuickSelectAnchor {
        get {
            guard let rawValue = UserDefaults.standard.string(forKey: PrefKey.queueQuickSelectAnchor.rawValue),
                  let anchor = QueueQuickSelectAnchor(rawValue: rawValue) else {
                return .leftmost
            }
            return anchor
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: PrefKey.queueQuickSelectAnchor.rawValue)
        }
    }

    // MARK: - Search

    /// 搜索模式：exact, fuzzy, regex, mixed, semantic（默认 mixed）
    static var searchMode: SearchMode {
        get {
            guard let rawValue = UserDefaults.standard.string(forKey: PrefKey.searchMode.rawValue),
                  let mode = SearchMode(rawValue: rawValue) else {
                return .mixed
            }
            return mode
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: PrefKey.searchMode.rawValue)
        }
    }

    // MARK: - iCloud Sync

    @UserDefault(key: PrefKey.iCloudSyncEnabled.rawValue, defaultValue: false)
    static var iCloudSyncEnabled: Bool

    @UserDefault(key: PrefKey.iCloudEncryptionEnabled.rawValue, defaultValue: true)
    static var iCloudEncryptionEnabled: Bool

    static var iCloudLastSyncDate: Date? {
        get {
            guard let timestamp = UserDefaults.standard.object(forKey: PrefKey.iCloudLastSyncDate.rawValue) as? Double else {
                return nil
            }
            return Date(timeIntervalSince1970: timestamp)
        }
        set {
            if let date = newValue {
                UserDefaults.standard.set(date.timeIntervalSince1970, forKey: PrefKey.iCloudLastSyncDate.rawValue)
            } else {
                UserDefaults.standard.removeObject(forKey: PrefKey.iCloudLastSyncDate.rawValue)
            }
        }
    }

    // MARK: - Diagnostics Upload

    @UserDefault(key: PrefKey.diagnosticsUploadEnabled.rawValue, defaultValue: false)
    nonisolated(unsafe) static var diagnosticsUploadEnabled: Bool

    static var diagnosticsLastUploadAt: Date? {
        get {
            guard let timestamp = UserDefaults.standard.object(forKey: PrefKey.diagnosticsLastUploadAt.rawValue) as? Double else {
                return nil
            }
            return Date(timeIntervalSince1970: timestamp)
        }
        set {
            if let date = newValue {
                UserDefaults.standard.set(date.timeIntervalSince1970, forKey: PrefKey.diagnosticsLastUploadAt.rawValue)
            } else {
                UserDefaults.standard.removeObject(forKey: PrefKey.diagnosticsLastUploadAt.rawValue)
            }
        }
    }

    static var diagnosticsClientId: String {
        get { UserDefaults.standard.string(forKey: PrefKey.diagnosticsClientId.rawValue) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: PrefKey.diagnosticsClientId.rawValue) }
    }

    // MARK: - Bank Card Detection

    /// 忽略银行卡号（使用 Luhn 算法检测）
    @UserDefault(key: PrefKey.ignoreBankCardNumbers.rawValue, defaultValue: true)
    static var ignoreBankCardNumbers: Bool

    /// 忽略身份证/证件号（基于多国格式校验）
    @UserDefault(key: PrefKey.ignoreIdentityNumbers.rawValue, defaultValue: true)
    static var ignoreIdentityNumbers: Bool

    // MARK: - CLI Bridge

    @UserDefault(key: PrefKey.cliBridgeEnabled.rawValue, defaultValue: false)
    static var cliBridgeEnabled: Bool

    @UserDefault(key: PrefKey.cliBridgePort.rawValue, defaultValue: 19999)
    static var cliBridgePort: Int

    // MARK: - iOS Sync (Shortcuts)

    @UserDefault(key: PrefKey.iosSyncEnabled.rawValue, defaultValue: false)
    static var iosSyncEnabled: Bool

    /// 逗号分隔端口列表缓存（非敏感，用于 UI 与模板提示）
    @UserDefault(key: PrefKey.iosSyncPortHints.rawValue, defaultValue: "")
    static var iosSyncPortHints: String

    @UserDefault(key: PrefKey.iosSyncLastSuccessfulPort.rawValue, defaultValue: 0)
    static var iosSyncLastSuccessfulPort: Int

    static var iosSyncLastSyncAt: Date? {
        get {
            guard let ts = UserDefaults.standard.object(forKey: PrefKey.iosSyncLastSyncAt.rawValue) as? Double else { return nil }
            return Date(timeIntervalSince1970: ts)
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue.timeIntervalSince1970, forKey: PrefKey.iosSyncLastSyncAt.rawValue)
            } else {
                UserDefaults.standard.removeObject(forKey: PrefKey.iosSyncLastSyncAt.rawValue)
            }
        }
    }

    @UserDefault(key: PrefKey.iosSyncOnboardingCompleted.rawValue, defaultValue: false)
    static var iosSyncOnboardingCompleted: Bool

    // MARK: - Paste Queue HUD Position
    @UserDefault(key: PrefKey.pasteQueueHUDPositionX.rawValue, defaultValue: -1)
    static var pasteQueueHUDPositionX: Double

    @UserDefault(key: PrefKey.pasteQueueHUDPositionY.rawValue, defaultValue: -1)
    static var pasteQueueHUDPositionY: Double

    // MARK: - Horizontal Panel Height
    @UserDefault(key: PrefKey.horizontalPanelHeight.rawValue, defaultValue: Double(Const.windowHeight))
    static var horizontalPanelHeight: Double
}
