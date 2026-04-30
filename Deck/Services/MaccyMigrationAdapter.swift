// Copyright © 2024–2026 Yuze Pan. 保留一切权利。

//
//  MaccyMigrationAdapter.swift
//  Deck
//
//  Deck Clipboard Manager - Maccy migration adapter
//

import AppKit
import Foundation
import SQLite3

struct ClipboardMigrationProgress: Equatable {
    let imported: Int
    let total: Int

    var fraction: Double {
        guard total > 0 else { return 0 }
        return Double(imported) / Double(total)
    }
}

protocol ClipboardMigrationAdapter {
    var displayName: String { get }
    func storageURL() -> URL?
    func scanItemCount() async throws -> Int
    func importItems(progress: @escaping (ClipboardMigrationProgress) -> Void) async throws -> Int
}

extension ClipboardMigrationAdapter {
    func insertBatchEnsuringDatabase(_ items: [ClipboardItem]) async -> Int {
        guard !items.isEmpty else { return 0 }
        DeckSQLManager.shared.setup()
        var inserted = await DeckSQLManager.shared.insertBatch(items).count
        if inserted == 0 {
            // Retry once in case the database was initializing.
            DeckSQLManager.shared.setup()
            inserted = await DeckSQLManager.shared.insertBatch(items).count
        }
        return inserted
    }
}

final class MaccyMigrationAdapter: ClipboardMigrationAdapter {
    var displayName: String { "Maccy" }

    private struct Schema {
        let itemTable: String
        let contentTable: String
        let contentItemColumn: String
    }

    private struct MaccyItemRow {
        let id: Int64
        let application: String?
        let timestamp: Int64
        let title: String?
    }

    private struct MaccyContentRow {
        let type: String
        let data: Data
    }

    private struct AppInfo {
        let path: String
        let name: String
    }

    private static let transientTypes: Set<String> = [
        NSPasteboard.PasteboardType.modified.rawValue,
        NSPasteboard.PasteboardType.fromMaccy.rawValue,
        NSPasteboard.PasteboardType.linkPresentationMetadata.rawValue,
        NSPasteboard.PasteboardType.customWebKitPasteboardData.rawValue,
        NSPasteboard.PasteboardType.source.rawValue,
        NSPasteboard.PasteboardType.customChromiumWebData.rawValue,
        NSPasteboard.PasteboardType.chromiumSourceUrl.rawValue,
        NSPasteboard.PasteboardType.chromiumSourceToken.rawValue,
        NSPasteboard.PasteboardType.notesRichText.rawValue
    ]

    private static let imageTypes: [NSPasteboard.PasteboardType] = [
        .png, .tiff, .jpeg, .heic, .heif, .gif, .webp, .bmp
    ]

    private static let richTextTypes: [NSPasteboard.PasteboardType] = [
        .rtfd, .flatRTFD, .rtf
    ]

    private static let htmlType = NSPasteboard.PasteboardType.html.rawValue
    private static let fileURLType = NSPasteboard.PasteboardType.fileURL.rawValue
    private static let stringType = NSPasteboard.PasteboardType.string.rawValue
    private static let universalClipboardType = NSPasteboard.PasteboardType.universalClipboard.rawValue

    func storageURL() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates: [URL] = [
            URL.applicationSupportDirectory.appending(path: "Maccy/Storage.sqlite"),
            home.appending(path: "Library/Containers/org.p0deje.Maccy/Data/Library/Application Support/Maccy/Storage.sqlite"),
            home.appending(path: "Library/Containers/com.p0deje.Maccy/Data/Library/Application Support/Maccy/Storage.sqlite")
        ]

        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            return url
        }

        return nil
    }

    func scanItemCount() async throws -> Int {
        guard let url = storageURL() else {
            throw MigrationError.sourceNotFound
        }

        let db = try openDatabase(path: url.path)
        defer { sqlite3_close(db) }

        let schema = try detectSchema(in: db)
        return try fetchCount(in: db, table: schema.itemTable)
    }

    func importItems(progress: @escaping (ClipboardMigrationProgress) -> Void) async throws -> Int {
        try await importItems(authenticationReason: nil, progress: progress)
    }

    func importItems(authenticationReason: String?, progress: @escaping (ClipboardMigrationProgress) -> Void) async throws -> Int {
        if DeckUserDefaults.securityModeEnabled {
            let reason = authenticationReason ?? "Authenticate to import Maccy data"
            let authenticated = await SecurityService.shared.authenticate(reason: reason)
            guard authenticated else {
                throw MigrationError.authenticationFailed
            }
        }

        guard let url = storageURL() else {
            throw MigrationError.sourceNotFound
        }

        let db = try openDatabase(path: url.path)
        defer { sqlite3_close(db) }

        let schema = try detectSchema(in: db)
        let total = try fetchCount(in: db, table: schema.itemTable)
        var imported = 0
        var lastProgressUpdate = 0
        var appCache: [String: AppInfo] = [:]
        var pendingItems: [ClipboardItem] = []
        let batchSize = 75

        let itemQuery = """
        SELECT Z_PK, ZAPPLICATION, ZLASTCOPIEDAT, ZFIRSTCOPIEDAT, ZTITLE
        FROM \(quote(schema.itemTable))
        ORDER BY Z_PK
        """

        let contentQuery = """
        SELECT ZTYPE, ZVALUE
        FROM \(quote(schema.contentTable))
        WHERE \(quote(schema.contentItemColumn)) = ?
        """

        let itemStatement = try prepareStatement(db, sql: itemQuery)
        defer { sqlite3_finalize(itemStatement) }

        let contentStatement = try prepareStatement(db, sql: contentQuery)
        defer { sqlite3_finalize(contentStatement) }

        while sqlite3_step(itemStatement) == SQLITE_ROW {
            if Task.isCancelled { break }

            let itemRow = parseItemRow(statement: itemStatement)
            let contents = fetchContents(statement: contentStatement, itemId: itemRow.id)

            if let clipboardItem = await buildClipboardItem(from: itemRow, contents: contents, appCache: &appCache) {
                pendingItems.append(clipboardItem)
            }

            if pendingItems.count >= batchSize {
                await flushBatch(
                    &pendingItems,
                    total: total,
                    imported: &imported,
                    progress: progress,
                    lastProgressUpdate: &lastProgressUpdate
                )
            }
        }

        if !pendingItems.isEmpty {
            await flushBatch(
                &pendingItems,
                total: total,
                imported: &imported,
                progress: progress,
                lastProgressUpdate: &lastProgressUpdate
            )
        }

        await DeckDataStore.shared.loadInitialData()
        return imported
    }
}

// MARK: - Data Mapping

private extension MaccyMigrationAdapter {
    private func buildClipboardItem(
        from item: MaccyItemRow,
        contents: [MaccyContentRow],
        appCache: inout [String: AppInfo]
    ) async -> ClipboardItem? {
        guard let resolved = resolveContent(from: contents, fallbackTitle: item.title) else { return nil }

        let appInfo = await resolveAppInfo(bundleIdentifier: item.application, cache: &appCache)
        let appName = appInfo.name.isEmpty ? (item.application ?? "") : appInfo.name

        return ClipboardItem(
            pasteboardType: resolved.pasteboardType,
            data: resolved.data,
            previewData: resolved.previewData,
            timestamp: item.timestamp,
            appPath: appInfo.path,
            appName: appName,
            searchText: resolved.searchText,
            contentLength: resolved.contentLength,
            tagId: -1,
            isTemporary: false
        )
    }

    private func resolveAppInfo(bundleIdentifier: String?, cache: inout [String: AppInfo]) async -> AppInfo {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else {
            return AppInfo(path: "", name: "")
        }

        if let cached = cache[bundleIdentifier] {
            return cached
        }

        let resolved = await MainActor.run { () -> AppInfo in
            guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
                return AppInfo(path: "", name: bundleIdentifier)
            }
            let path = appURL.path
            let name = Bundle(url: appURL)?.object(forInfoDictionaryKey: "CFBundleName") as? String
                ?? Bundle(url: appURL)?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? appURL.deletingPathExtension().lastPathComponent
            return AppInfo(path: path, name: name)
        }

        cache[bundleIdentifier] = resolved
        return resolved
    }

    private struct ResolvedContent {
        let pasteboardType: NSPasteboard.PasteboardType
        let data: Data
        let previewData: Data?
        let searchText: String
        let contentLength: Int
    }

    private func resolveContent(from contents: [MaccyContentRow], fallbackTitle: String?) -> ResolvedContent? {
        let filtered = contents.filter { !Self.transientTypes.contains($0.type) }
        guard !filtered.isEmpty else { return nil }

        let grouped = Dictionary(grouping: filtered, by: { $0.type })

        let isUniversalClipboard = grouped[Self.universalClipboardType] != nil
        let hasUniversalTextPayload = [
            Self.htmlType,
            NSPasteboard.PasteboardType.tiff.rawValue,
            NSPasteboard.PasteboardType.png.rawValue,
            NSPasteboard.PasteboardType.jpeg.rawValue,
            NSPasteboard.PasteboardType.rtf.rawValue,
            Self.stringType,
            NSPasteboard.PasteboardType.heic.rawValue
        ].contains { grouped[$0] != nil }

        let allowFileURLs = !(isUniversalClipboard && hasUniversalTextPayload)

        func firstData(for type: String) -> Data? {
            grouped[type]?.first(where: { !$0.data.isEmpty })?.data
        }

        for type in Self.imageTypes {
            if let data = firstData(for: type.rawValue) {
                let previewData = ClipboardItem.generatePreviewThumbnailData(from: data, maxSize: 200)
                return ResolvedContent(
                    pasteboardType: type,
                    data: data,
                    previewData: previewData,
                    searchText: "",
                    contentLength: data.count
                )
            }
        }

        if allowFileURLs {
            let fileURLData = grouped[Self.fileURLType]?.compactMap { $0.data } ?? []
            let filePaths = filePathsFromData(fileURLData)
            if !filePaths.isEmpty, let data = filePaths.joined(separator: "\n").data(using: .utf8) {
                return ResolvedContent(
                    pasteboardType: .fileURL,
                    data: data,
                    previewData: nil,
                    searchText: ClipboardItem.searchTextForFilePaths(filePaths),
                    contentLength: data.count
                )
            }
        }

        for type in Self.richTextTypes {
            if let data = firstData(for: type.rawValue),
               let attributed = NSAttributedString(with: data, type: type) {
                let text = attributed.string
                guard !normalizedPlainText(text).isEmpty else { continue }
                let previewData = previewData(from: attributed, type: type)
                return ResolvedContent(
                    pasteboardType: type,
                    data: data,
                    previewData: previewData,
                    searchText: text,
                    contentLength: attributed.length
                )
            }
        }

        if let htmlData = firstData(for: Self.htmlType),
           let attributed = NSAttributedString(html: htmlData, documentAttributes: nil) {
            let text = attributed.string
            if !normalizedPlainText(text).isEmpty {
                if let rtfData = attributed.toData(with: .rtf) {
                    let previewData = previewData(from: attributed, type: .rtf)
                    return ResolvedContent(
                        pasteboardType: .rtf,
                        data: rtfData,
                        previewData: previewData,
                        searchText: text,
                        contentLength: attributed.length
                    )
                }
                if let data = text.data(using: .utf8) {
                    let attr = NSAttributedString(string: text)
                    let previewData = previewData(from: attr, type: .string)
                    return ResolvedContent(
                        pasteboardType: .string,
                        data: data,
                        previewData: previewData,
                        searchText: text,
                        contentLength: attr.length
                    )
                }
            }
        }

        if let textData = firstData(for: Self.stringType),
           let text = String(data: textData, encoding: .utf8) {
            let normalized = normalizedPlainText(text)
            guard !normalized.isEmpty else { return nil }
            let attr = NSAttributedString(string: text)
            let previewData = previewData(from: attr, type: .string)
            return ResolvedContent(
                pasteboardType: .string,
                data: textData,
                previewData: previewData,
                searchText: text,
                contentLength: attr.length
            )
        }

        if let title = fallbackTitle {
            let normalized = normalizedPlainText(title)
            if !normalized.isEmpty, let data = title.data(using: .utf8) {
                let attr = NSAttributedString(string: title)
                let previewData = previewData(from: attr, type: .string)
                return ResolvedContent(
                    pasteboardType: .string,
                    data: data,
                    previewData: previewData,
                    searchText: title,
                    contentLength: attr.length
                )
            }
        }

        return nil
    }

    private func previewData(from attributed: NSAttributedString, type: NSPasteboard.PasteboardType) -> Data? {
        let previewAttr = attributed.length > 250
            ? attributed.attributedSubstring(from: NSRange(location: 0, length: 250))
            : attributed
        return previewAttr.toData(with: type)
    }

    private func normalizedPlainText(_ text: String) -> String {
        let stripped = text
            .replacingOccurrences(of: "\u{FFFC}", with: "")
            .replacingOccurrences(of: "\u{200B}", with: "")
            .replacingOccurrences(of: "\u{FEFF}", with: "")
        return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func filePathsFromData(_ dataList: [Data]) -> [String] {
        var paths: [String] = []
        for data in dataList {
            if let url = URL(dataRepresentation: data, relativeTo: nil, isAbsolute: true) {
                if !url.path.isEmpty {
                    paths.append(url.path)
                }
                continue
            }

            if let raw = String(data: data, encoding: .utf8) {
                let candidates = raw.components(separatedBy: "\n").filter { !$0.isEmpty }
                for candidate in candidates {
                    if let url = URL(string: candidate), url.isFileURL {
                        paths.append(url.path)
                    } else {
                        paths.append(candidate)
                    }
                }
            }
        }
        return Array(Set(paths)).sorted()
    }

    private func flushBatch(
        _ items: inout [ClipboardItem],
        total: Int,
        imported: inout Int,
        progress: @escaping (ClipboardMigrationProgress) -> Void,
        lastProgressUpdate: inout Int
    ) async {
        guard !items.isEmpty else { return }
        let inserted = await insertBatchEnsuringDatabase(items)
        items.removeAll(keepingCapacity: true)

        if inserted > 0 {
            imported += inserted
            if imported - lastProgressUpdate >= 25 || imported >= total {
                progress(ClipboardMigrationProgress(imported: imported, total: total))
                lastProgressUpdate = imported
            }
        }

        await Task.yield()
    }
}

// MARK: - SQLite Helpers

private extension MaccyMigrationAdapter {
    private func openDatabase(path: String) throws -> OpaquePointer {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(path, &db, flags, nil) != SQLITE_OK {
            let message = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            throw MigrationError.openFailed(message)
        }
        guard let db else {
            throw MigrationError.openFailed("Failed to open database (nil handle)")
        }
        sqlite3_busy_timeout(db, 1500)
        return db
    }

    private func prepareStatement(_ db: OpaquePointer, sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) != SQLITE_OK {
            let message = String(cString: sqlite3_errmsg(db))
            throw MigrationError.queryFailed(message)
        }
        guard let statement else {
            throw MigrationError.queryFailed("Failed to prepare statement")
        }
        return statement
    }

    private func fetchTableNames(in db: OpaquePointer) throws -> [String] {
        let statement = try prepareStatement(db, sql: "SELECT name FROM sqlite_master WHERE type='table'")
        defer { sqlite3_finalize(statement) }

        var names: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let name = sqlite3_column_text(statement, 0) {
                let table = String(cString: name)
                if !table.hasPrefix("sqlite_") {
                    names.append(table)
                }
            }
        }
        return names
    }

    private func fetchColumns(in db: OpaquePointer, table: String) throws -> [String] {
        let statement = try prepareStatement(db, sql: "PRAGMA table_info(\(quote(table)))")
        defer { sqlite3_finalize(statement) }

        var columns: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let name = sqlite3_column_text(statement, 1) {
                columns.append(String(cString: name))
            }
        }
        return columns
    }

    private func detectSchema(in db: OpaquePointer) throws -> Schema {
        let tables = try fetchTableNames(in: db)
        var itemCandidates: [(String, Set<String>)] = []
        var contentCandidates: [(String, Set<String>)] = []

        for table in tables {
            let columnSet = Set(try fetchColumns(in: db, table: table))
            if columnSet.contains("ZAPPLICATION") && columnSet.contains("ZLASTCOPIEDAT") && columnSet.contains("ZTITLE") {
                itemCandidates.append((table, columnSet))
            }
            if columnSet.contains("ZTYPE") && columnSet.contains("ZVALUE") {
                contentCandidates.append((table, columnSet))
            }
        }

        guard let itemTable = selectTable(from: itemCandidates, preferred: "HISTORYITEM") else {
            throw MigrationError.schemaUnsupported
        }
        guard let contentTable = selectTable(from: contentCandidates, preferred: "HISTORYITEMCONTENT") else {
            throw MigrationError.schemaUnsupported
        }

        let contentColumns = Set(try fetchColumns(in: db, table: contentTable))
        let linkColumn = selectLinkColumn(from: contentColumns)

        return Schema(itemTable: itemTable, contentTable: contentTable, contentItemColumn: linkColumn)
    }

    private func selectTable(from candidates: [(String, Set<String>)], preferred: String) -> String? {
        if let preferred = candidates.first(where: { $0.0.uppercased().contains(preferred) }) {
            return preferred.0
        }
        return candidates.first?.0
    }

    private func selectLinkColumn(from columns: Set<String>) -> String {
        if columns.contains("ZITEM") { return "ZITEM" }
        if columns.contains("ZHISTORYITEM") { return "ZHISTORYITEM" }
        if let fallback = columns.first(where: { $0.uppercased().hasSuffix("ITEM") && $0 != "ZITEMS" }) {
            return fallback
        }
        return "ZITEM"
    }

    private func fetchCount(in db: OpaquePointer, table: String) throws -> Int {
        let statement = try prepareStatement(db, sql: "SELECT COUNT(*) FROM \(quote(table))")
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw MigrationError.queryFailed("count failed")
        }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func parseItemRow(statement: OpaquePointer) -> MaccyItemRow {
        let id = sqlite3_column_int64(statement, 0)
        let application = sqlite3_column_text(statement, 1).flatMap { String(cString: $0) }
        let lastCopied = sqlite3_column_double(statement, 2)
        let firstCopied = sqlite3_column_double(statement, 3)
        let title = sqlite3_column_text(statement, 4).flatMap { String(cString: $0) }

        let timestamp = resolveTimestamp(lastCopied: lastCopied, firstCopied: firstCopied)
        return MaccyItemRow(id: id, application: application, timestamp: timestamp, title: title)
    }

    private func resolveTimestamp(lastCopied: Double, firstCopied: Double) -> Int64 {
        let referenceInterval = lastCopied > 0 ? lastCopied : firstCopied
        if referenceInterval <= 0 {
            return Int64(Date().timeIntervalSince1970)
        }
        let date: Date
        if referenceInterval > 1_000_000_000 {
            date = Date(timeIntervalSince1970: referenceInterval)
        } else {
            date = Date(timeIntervalSinceReferenceDate: referenceInterval)
        }
        return Int64(date.timeIntervalSince1970)
    }

    private func fetchContents(statement: OpaquePointer, itemId: Int64) -> [MaccyContentRow] {
        sqlite3_reset(statement)
        sqlite3_clear_bindings(statement)
        sqlite3_bind_int64(statement, 1, itemId)

        var contents: [MaccyContentRow] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let typeText = sqlite3_column_text(statement, 0) else { continue }
            let type = String(cString: typeText)
            guard sqlite3_column_type(statement, 1) != SQLITE_NULL else { continue }
            guard let blob = sqlite3_column_blob(statement, 1) else { continue }
            let length = Int(sqlite3_column_bytes(statement, 1))
            let data = Data(bytes: blob, count: length)
            if !data.isEmpty {
                contents.append(MaccyContentRow(type: type, data: data))
            }
        }
        return contents
    }

    private func quote(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}

// MARK: - Errors

enum MigrationError: LocalizedError {
    case sourceNotFound
    case authenticationFailed
    case openFailed(String)
    case schemaUnsupported
    case queryFailed(String)

    var errorDescription: String? {
        switch self {
        case .sourceNotFound:
            return "Source database not found"
        case .authenticationFailed:
            return "Authentication failed"
        case .openFailed(let message):
            return "Unable to open source database: \(message)"
        case .schemaUnsupported:
            return "Unsupported database schema"
        case .queryFailed(let message):
            return "Failed to read source data: \(message)"
        }
    }
}
