//
//  OrbitBridgeXPC.swift
//  DeckOrbitBridgeService
//
//  XPC service for Orbit clipboard integration
//

import AppKit
import CryptoKit
import Foundation
import ImageIO
import Security
import SQLite

private enum OrbitBridgeDefaults {
    static let domain = "com.yuzeguitar.Deck"
    static let shared = UserDefaults(suiteName: domain) ?? .standard
}

private enum OrbitBridgeNotification {
    static let name = Notification.Name("DeckOrbitBridgeAction")
    static let actionKey = "action"
    static let deleteAction = "delete"
    static let idsKey = "uniqueIds"
}

@objc protocol OrbitBridgeXPC {
    func health(reply: @escaping (String) -> Void)
    func fetchRecentItems(limit: Int, reply: @escaping (Data?, String?) -> Void)
    func fetchItemPayload(_ uniqueId: String, reply: @escaping (Data?, String?) -> Void)
    func deleteItems(_ uniqueIds: [String], reply: @escaping (Bool, String?) -> Void)
    func copyItem(_ uniqueId: String, reply: @escaping (Bool, String?) -> Void)
}

private struct OrbitClipboardSummary: Codable {
    let uniqueId: String
    let itemType: String
    let pasteboardType: String
    let title: String
    let subtitle: String?
    let previewText: String?
    let previewImageData: Data?
    let timestamp: Int64
    let appName: String
    let appPath: String
    let filePaths: [String]?
    let urlString: String?
    let isTemporary: Bool
}

private struct OrbitClipboardPayload: Codable {
    let uniqueId: String
    let itemType: String
    let pasteboardType: String
    let text: String?
    let urlString: String?
    let filePaths: [String]?
    let imageData: Data?
}

private final class OrbitBridgeCrypto {
    private let keychainService = "com.deck.encryption"
    private let keychainAccount = "master-key"
    private var cachedKey: SymmetricKey?

    private var securityModeEnabled: Bool {
        OrbitBridgeDefaults.shared.bool(forKey: "securityModeEnabled")
    }

    func decryptData(_ data: Data) -> Data {
        guard securityModeEnabled else { return data }
        guard let key = loadKey() else { return data }
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: data)
            return try AES.GCM.open(sealedBox, using: key)
        } catch {
            return data
        }
    }

    func decryptString(_ string: String) -> String {
        guard securityModeEnabled else { return string }
        guard let data = Data(base64Encoded: string) else { return string }
        let decrypted = decryptData(data)
        return String(data: decrypted, encoding: .utf8) ?? string
    }

    private func loadKey() -> SymmetricKey? {
        if let cachedKey { return cachedKey }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let keyData = result as? Data else { return nil }

        let key = SymmetricKey(data: keyData)
        cachedKey = key
        return key
    }
}

private struct OrbitRow {
    let uniqueId: String
    let itemType: String
    let pasteboardType: String
    let data: Data
    let previewData: Data?
    let timestamp: Int64
    let appName: String
    let appPath: String
    let searchText: String
    let contentLength: Int
    let blobPath: String?
    let isTemporary: Bool
}

private final class OrbitBridgeStore {
    private struct StorageResolution {
        let path: String
        let securityScopedURL: URL?
    }

    private let db: Connection
    private let crypto = OrbitBridgeCrypto()
    private let storageDirectory: String
    private var securityScopedURL: URL?

    private let table = Table("ClipboardHistory")
    private let uniqueId = Expression<String>("unique_id")
    private let type = Expression<String>("type")
    private let itemType = Expression<String>("item_type")
    private let data = Expression<Data>("data")
    private let previewData = Expression<Data?>("preview_data")
    private let timestamp = Expression<Int64>("timestamp")
    private let appPath = Expression<String>("app_path")
    private let appName = Expression<String>("app_name")
    private let searchText = Expression<String>("search_text")
    private let contentLength = Expression<Int>("content_length")
    private let blobPath = Expression<String?>("blob_path")
    private let isTemporary = Expression<Bool>("is_temporary")

    init() throws {
        let storage = Self.resolveStorageDirectory()
        storageDirectory = storage.path
        securityScopedURL = storage.securityScopedURL
        let dbPath = (storage.path as NSString).appendingPathComponent("Deck.sqlite3")
        db = try Connection(dbPath)
        db.busyTimeout = 5.0
    }

    deinit {
        if let securityScopedURL {
            securityScopedURL.stopAccessingSecurityScopedResource()
        }
    }

    func fetchRecent(limit: Int) throws -> [OrbitRow] {
        let query = table.order(timestamp.desc).limit(limit)
        return try db.prepare(query).map { try row(from: $0) }
    }

    func fetchItem(uniqueId target: String) throws -> OrbitRow? {
        let query = table.filter(uniqueId == target).limit(1)
        guard let row = try db.pluck(query) else { return nil }
        return try self.row(from: row)
    }

    func deleteItem(uniqueId target: String) throws {
        let query = table.filter(uniqueId == target)
        _ = try db.run(query.delete())
    }

    func touchItem(uniqueId target: String) throws {
        let query = table.filter(uniqueId == target)
        _ = try db.run(query.update(timestamp <- Int64(Date().timeIntervalSince1970)))
    }

    func loadBlob(path: String) -> Data? {
        guard path.hasPrefix(storageDirectory) else { return nil }
        guard let raw = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        if path.hasSuffix(".enc") {
            return crypto.decryptData(raw)
        }
        return raw
    }

    private func row(from row: Row) throws -> OrbitRow {
        let rawData = try row.get(data)
        let rawPreview = try row.get(previewData)
        let rawSearchText = try row.get(searchText)
        let rawAppName = try row.get(appName)

        return OrbitRow(
            uniqueId: try row.get(uniqueId),
            itemType: try row.get(itemType),
            pasteboardType: try row.get(type),
            data: crypto.decryptData(rawData),
            previewData: rawPreview.map { crypto.decryptData($0) },
            timestamp: try row.get(timestamp),
            appName: crypto.decryptString(rawAppName),
            appPath: try row.get(appPath),
            searchText: crypto.decryptString(rawSearchText),
            contentLength: try row.get(contentLength),
            blobPath: try row.get(blobPath),
            isTemporary: try row.get(isTemporary)
        )
    }

    private static func resolveStorageDirectory() -> StorageResolution {
        let defaults = OrbitBridgeDefaults.shared
        let useCustom = defaults.bool(forKey: "useCustomStorage")
        var basePath: String
        var securityScopedURL: URL?

        if useCustom, let bookmarkData = defaults.data(forKey: "storageBookmark") {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                if url.startAccessingSecurityScopedResource() {
                    securityScopedURL = url
                }
                basePath = url.path
            } else {
                basePath = defaultStoragePath()
            }
        } else if useCustom, let customPath = defaults.string(forKey: "customStoragePath"), !customPath.isEmpty {
            basePath = customPath
        } else {
            basePath = defaultStoragePath()
        }

        let path = (basePath as NSString).appendingPathComponent("Deck")
        return StorageResolution(path: path, securityScopedURL: securityScopedURL)
    }

    private static func defaultStoragePath() -> String {
        NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true).first ?? NSTemporaryDirectory()
    }
}

private final class OrbitBridgeProvider: NSObject, OrbitBridgeXPC {
    private let encoder = JSONEncoder()

    func health(reply: @escaping (String) -> Void) {
        reply("ok")
    }

    func fetchRecentItems(limit: Int, reply: @escaping (Data?, String?) -> Void) {
        let clamped = max(1, min(limit, 50))
        do {
            let store = try OrbitBridgeStore()
            let rows = try store.fetchRecent(limit: clamped)
            let summaries = rows.map { makeSummary(from: $0, store: store) }
            let data = try encoder.encode(summaries)
            reply(data, nil)
        } catch {
            reply(nil, error.localizedDescription)
        }
    }

    func fetchItemPayload(_ uniqueId: String, reply: @escaping (Data?, String?) -> Void) {
        let trimmed = uniqueId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            reply(nil, "Empty uniqueId")
            return
        }

        do {
            let store = try OrbitBridgeStore()
            guard let row = try store.fetchItem(uniqueId: trimmed) else {
                reply(nil, "Item not found")
                return
            }
            let payload = makePayload(from: row, store: store)
            let data = try encoder.encode(payload)
            reply(data, nil)
        } catch {
            reply(nil, error.localizedDescription)
        }
    }

    func deleteItems(_ uniqueIds: [String], reply: @escaping (Bool, String?) -> Void) {
        let ids = uniqueIds.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !ids.isEmpty else {
            reply(false, "Empty uniqueIds")
            return
        }

        do {
            let store = try OrbitBridgeStore()
            for id in ids {
                if let row = try store.fetchItem(uniqueId: id), let blobPath = row.blobPath {
                    _ = store.loadBlob(path: blobPath)
                    try? FileManager.default.removeItem(atPath: blobPath)
                }
                try store.deleteItem(uniqueId: id)
            }
            postDeleteNotification(ids)
            reply(true, nil)
        } catch {
            reply(false, error.localizedDescription)
        }
    }

    func copyItem(_ uniqueId: String, reply: @escaping (Bool, String?) -> Void) {
        let trimmed = uniqueId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            reply(false, "Empty uniqueId")
            return
        }

        do {
            let store = try OrbitBridgeStore()
            guard let row = try store.fetchItem(uniqueId: trimmed) else {
                reply(false, "Item not found")
                return
            }
            let success = copyToPasteboard(row, store: store)
            if success {
                try? store.touchItem(uniqueId: trimmed)
            }
            reply(success, success ? nil : "Pasteboard write failed")
        } catch {
            reply(false, error.localizedDescription)
        }
    }

    private func makeSummary(from row: OrbitRow, store: OrbitBridgeStore) -> OrbitClipboardSummary {
        let previewText = previewTextForRow(row)
        let title = summaryTitle(for: row, previewText: previewText)
        let subtitle = summarySubtitle(for: row)
        let filePaths = filePathsForRow(row, store: store)
        let urlString = row.itemType == "url" ? row.searchText : nil
        let previewImageData = previewImageForRow(row, store: store)

        return OrbitClipboardSummary(
            uniqueId: row.uniqueId,
            itemType: row.itemType,
            pasteboardType: row.pasteboardType,
            title: title,
            subtitle: subtitle,
            previewText: previewText,
            previewImageData: previewImageData,
            timestamp: row.timestamp,
            appName: row.appName,
            appPath: row.appPath,
            filePaths: filePaths,
            urlString: urlString,
            isTemporary: row.isTemporary
        )
    }

    private func makePayload(from row: OrbitRow, store: OrbitBridgeStore) -> OrbitClipboardPayload {
        let filePaths = filePathsForRow(row, store: store)
        let data = resolvedData(for: row, store: store)

        var text: String?
        var urlString: String?
        var imageData: Data?

        switch row.itemType {
        case "text", "richText", "code", "color":
            text = row.searchText
        case "url":
            urlString = row.searchText
        case "file":
            break
        case "image":
            if row.pasteboardType == NSPasteboard.PasteboardType.fileURL.rawValue {
                break
            }
            imageData = data
        default:
            text = row.searchText
        }

        return OrbitClipboardPayload(
            uniqueId: row.uniqueId,
            itemType: row.itemType,
            pasteboardType: row.pasteboardType,
            text: text,
            urlString: urlString,
            filePaths: filePaths,
            imageData: imageData
        )
    }

    private func previewTextForRow(_ row: OrbitRow) -> String? {
        guard row.itemType == "text" || row.itemType == "richText" || row.itemType == "code" else { return nil }
        let trimmed = row.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.count <= 120 { return trimmed }
        return String(trimmed.prefix(120)) + "..."
    }

    private func summaryTitle(for row: OrbitRow, previewText: String?) -> String {
        switch row.itemType {
        case "text", "richText", "code":
            return previewText ?? "Text"
        case "url":
            return row.searchText
        case "file":
            let files = filePathsForRow(row, store: nil)
            if let files, files.count == 1 {
                return URL(fileURLWithPath: files[0]).lastPathComponent
            }
            return "File"
        case "image":
            return "Image"
        case "color":
            return row.searchText
        default:
            return row.searchText
        }
    }

    private func summarySubtitle(for row: OrbitRow) -> String? {
        switch row.itemType {
        case "text", "richText", "code":
            return "\(row.contentLength) chars"
        case "file":
            let files = filePathsForRow(row, store: nil) ?? []
            if files.count > 1 {
                return "\(files.count) files"
            }
            return nil
        case "image":
            return nil
        default:
            return nil
        }
    }

    private func filePathsForRow(_ row: OrbitRow, store: OrbitBridgeStore?) -> [String]? {
        guard row.pasteboardType == NSPasteboard.PasteboardType.fileURL.rawValue else { return nil }
        if !row.data.isEmpty {
            return String(data: row.data, encoding: .utf8)?.split(separator: "\n").map { String($0) }
        }
        if let blobPath = row.blobPath, let data = store?.loadBlob(path: blobPath) {
            return String(data: data, encoding: .utf8)?.split(separator: "\n").map { String($0) }
        }
        return nil
    }

    private func previewImageForRow(_ row: OrbitRow, store: OrbitBridgeStore) -> Data? {
        guard row.itemType == "image" else { return nil }
        if let preview = row.previewData, !preview.isEmpty { return preview }

        if row.pasteboardType == NSPasteboard.PasteboardType.fileURL.rawValue,
           let filePath = filePathsForRow(row, store: store)?.first,
           let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)) {
            return generateThumbnail(from: data)
        }

        guard let data = resolvedData(for: row, store: store), !data.isEmpty else { return nil }
        if data.count > 5 * 1024 * 1024 { return nil }
        return generateThumbnail(from: data)
    }

    private func resolvedData(for row: OrbitRow, store: OrbitBridgeStore) -> Data? {
        if !row.data.isEmpty { return row.data }
        if let blobPath = row.blobPath {
            return store.loadBlob(path: blobPath)
        }
        return nil
    }

    private func generateThumbnail(from data: Data, maxSize: CGFloat = 200) -> Data? {
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSize
        ]

        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        return bitmapRep.representation(using: .png, properties: [:])
    }

    private func copyToPasteboard(_ row: OrbitRow, store: OrbitBridgeStore) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        let pasteboardType = NSPasteboard.PasteboardType(row.pasteboardType)

        switch row.itemType {
        case "text", "richText", "code", "color", "url":
            return pasteboard.setString(row.searchText, forType: .string)
        case "image":
            if pasteboardType == .fileURL {
                return writeFileURLs(from: row, store: store, pasteboard: pasteboard)
            }
            guard let data = resolvedData(for: row, store: store) else { return false }
            return pasteboard.setData(data, forType: pasteboardType)
        case "file":
            return writeFileURLs(from: row, store: store, pasteboard: pasteboard)
        default:
            return false
        }
    }

    private func writeFileURLs(from row: OrbitRow, store: OrbitBridgeStore, pasteboard: NSPasteboard) -> Bool {
        guard let filePaths = filePathsForRow(row, store: store), !filePaths.isEmpty else { return false }
        let urls = filePaths.filter { FileManager.default.fileExists(atPath: $0) }.map { URL(fileURLWithPath: $0) }
        guard !urls.isEmpty else { return false }

        let items = urls.map { url -> NSPasteboardItem in
            let item = NSPasteboardItem()
            item.setString(url.absoluteString, forType: .fileURL)
            return item
        }
        let success = pasteboard.writeObjects(items)
        let filenamesType = NSPasteboard.PasteboardType("NSFilenamesPboardType")
        _ = pasteboard.setPropertyList(urls.map(\.path), forType: filenamesType)
        return success
    }

    private func postDeleteNotification(_ ids: [String]) {
        DistributedNotificationCenter.default().post(
            name: OrbitBridgeNotification.name,
            object: nil,
            userInfo: [
                OrbitBridgeNotification.actionKey: OrbitBridgeNotification.deleteAction,
                OrbitBridgeNotification.idsKey: ids
            ]
        )
    }
}

private final class OrbitBridgeListener: NSObject, NSXPCListenerDelegate {
    private static let orbitBundleId = "com.yuzeguitar.Orbit"
    private let requirement: SecRequirement?

    override init() {
        requirement = Self.makeRequirement(bundleId: Self.orbitBundleId, teamId: Self.fetchTeamIdentifierForSelf())
        super.init()
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard isTrustedOrbitConnection(connection) else {
            connection.invalidate()
            return false
        }

        connection.exportedInterface = NSXPCInterface(with: OrbitBridgeXPC.self)
        connection.exportedObject = OrbitBridgeProvider()
        connection.resume()
        return true
    }

    private func isTrustedOrbitConnection(_ connection: NSXPCConnection) -> Bool {
        guard let code = Self.secCode(for: connection) else { return false }
        guard let requirement else { return false }
        let status = SecCodeCheckValidity(code, SecCSFlags(), requirement)
        return status == errSecSuccess
    }

    private static func secCode(for connection: NSXPCConnection) -> SecCode? {
        let pid = connection.processIdentifier
        let attributes = [kSecGuestAttributePid: NSNumber(value: pid)] as CFDictionary

        var code: SecCode?
        let status = SecCodeCopyGuestWithAttributes(nil, attributes, SecCSFlags(), &code)
        guard status == errSecSuccess else { return nil }
        return code
    }

    private static func makeRequirement(bundleId: String, teamId: String?) -> SecRequirement? {
        let requirementString: String
        if let teamId, !teamId.isEmpty {
            requirementString = "anchor apple generic and certificate leaf[subject.OU] = \"\(teamId)\" and identifier \"\(bundleId)\""
        } else {
            requirementString = "anchor apple generic and identifier \"\(bundleId)\""
        }

        var requirement: SecRequirement?
        let status = SecRequirementCreateWithString(requirementString as CFString, SecCSFlags(), &requirement)
        guard status == errSecSuccess else { return nil }
        return requirement
    }

    private static func fetchTeamIdentifierForSelf() -> String? {
        var code: SecCode?
        let status = SecCodeCopySelf([], &code)
        guard status == errSecSuccess, let code else { return nil }

        var staticCode: SecStaticCode?
        let staticStatus = SecCodeCopyStaticCode(code, SecCSFlags(), &staticCode)
        guard staticStatus == errSecSuccess, let staticCode else { return nil }

        var info: CFDictionary?
        let infoStatus = SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
        guard infoStatus == errSecSuccess, let infoDict = info as? [String: Any] else { return nil }
        return infoDict[kSecCodeInfoTeamIdentifier as String] as? String
    }
}

@main
final class OrbitBridgeServiceMain {
    static func main() {
        let listener = NSXPCListener.service()
        listener.delegate = OrbitBridgeListener()
        listener.resume()
        RunLoop.current.run()
    }
}
