//
//  DeckSQLManager.swift
//  Deck
//
//  Deck Clipboard Manager - SQLite Database Management
//

import AppKit
import Foundation
import SQLite

enum Col {
    static let id = Expression<Int64>("id")
    static let uniqueId = Expression<String>("unique_id")
    static let type = Expression<String>("type")
    static let itemType = Expression<String>("item_type")
    static let data = Expression<Data>("data")
    static let previewData = Expression<Data?>("preview_data")
    static let ts = Expression<Int64>("timestamp")
    static let appPath = Expression<String>("app_path")
    static let appName = Expression<String>("app_name")
    static let searchText = Expression<String>("search_text")
    static let length = Expression<Int>("content_length")
    static let tagId = Expression<Int>("tag_id")
    static let blobPath = Expression<String?>("blob_path")
}

// MARK: - Search Cache Entry

/// 搜索缓存条目：存储解密且小写化后的搜索文本和应用名
private final class SearchCacheEntry: NSObject {
    let searchText: String
    let appName: String

    init(searchText: String, appName: String) {
        self.searchText = searchText
        self.appName = appName
    }
}

final class DeckSQLManager: NSObject {
    static let shared = DeckSQLManager()
    private static var isInitialized = false
    private nonisolated static let initLock = NSLock()

    // SQLite Connection is not thread-safe. Guard all DB access with a serial queue.
    private let dbQueue = DispatchQueue(label: "com.deck.sqlite.queue", qos: .userInitiated)
    private let dbQueueKey = DispatchSpecificKey<Void>()

    private var db: Connection?
    private var table: Table?
    private var securityScopedURL: URL?

    // Error tracking - 错误追踪
    private var consecutiveErrorCount = 0
    private var lastErrorTime: Date?
    private let errorThreshold = 3  // 连续 3 次错误后通知用户
    private var hasNotifiedUser = false

    // 搜索缓存：避免重复解密和 lowercased 转换
    // Key: row id, Value: 解密且小写化后的搜索文本
    private let searchTextCache: NSCache<NSNumber, SearchCacheEntry> = {
        let cache = NSCache<NSNumber, SearchCacheEntry>()
        cache.countLimit = 1000  // 限制最多缓存 1000 条，控制内存占用
        return cache
    }()

    override private init() {
        super.init()
        dbQueue.setSpecific(key: dbQueueKey, value: ())
    }
    
    private func syncOnDBQueue<T>(_ work: () throws -> T) rethrows -> T {
        if DispatchQueue.getSpecific(key: dbQueueKey) != nil {
            return try work()
        }
        return try dbQueue.sync(execute: work)
    }
    
    @discardableResult
    private func withDB<T>(_ work: () throws -> T) -> T? {
        // 在执行数据库操作前检查文件有效性，防止 try! 崩溃
        if !isDatabaseFileValid() {
            log.warn("Database file is invalid or missing, attempting to reinitialize...")
            handleDBError(NSError(domain: "DeckSQL", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Database file is invalid or missing"
            ]))
            // 尝试重新初始化数据库
            DispatchQueue.main.async { [weak self] in
                self?.reinitialize()
            }
            return nil
        }

        do {
            let result = try syncOnDBQueue(work)
            // 操作成功，重置错误计数
            consecutiveErrorCount = 0
            return result
        } catch {
            handleDBError(error)
            return nil
        }
    }

    /// 检查数据库文件是否存在且可访问
    /// 在数据库操作前调用，防止因文件被删除而导致 try! 崩溃
    private func isDatabaseFileValid() -> Bool {
        let basePath = getStoragePath()
        let dbPath = (basePath as NSString).appendingPathComponent("Deck.sqlite3")
        return FileManager.default.fileExists(atPath: dbPath) && FileManager.default.isReadableFile(atPath: dbPath)
    }

    /// 处理数据库错误并在必要时通知用户
    private func handleDBError(_ error: Error) {
        consecutiveErrorCount += 1
        lastErrorTime = Date()

        let errorMessage = error.localizedDescription
        log.error("DB operation failed (\(consecutiveErrorCount)/\(errorThreshold)): \(errorMessage)")

        // 检测严重错误类型
        let isCritical = errorMessage.contains("disk I/O error") ||
                         errorMessage.contains("database is locked") ||
                         errorMessage.contains("disk full") ||
                         errorMessage.contains("readonly") ||
                         errorMessage.contains("corrupt")

        // 连续错误达到阈值或遇到严重错误时通知用户
        if (consecutiveErrorCount >= errorThreshold || isCritical) && !hasNotifiedUser {
            hasNotifiedUser = true
            notifyUserOfDBError(errorMessage, isCritical: isCritical)
        }
    }

    /// 发送数据库错误通知
    private func notifyUserOfDBError(_ message: String, isCritical: Bool) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .databaseError,
                object: nil,
                userInfo: [
                    "message": message,
                    "isCritical": isCritical
                ]
            )
        }
    }

    /// 重置错误状态（用户处理后调用）
    func resetErrorState() {
        consecutiveErrorCount = 0
        hasNotifiedUser = false
        lastErrorTime = nil
    }

    /// 检查数据库健康状态
    func checkDatabaseHealth() -> (isHealthy: Bool, message: String) {
        guard let db = db else {
            return (false, "数据库连接未建立")
        }

        // 检查数据库是否可读写
        let canWrite = withDB {
            try db.scalar("SELECT 1") as? Int64 == 1
        } ?? false

        if !canWrite {
            return (false, "数据库无法正常访问")
        }

        // 检查最近是否有错误
        if consecutiveErrorCount > 0 {
            return (false, "最近有 \(consecutiveErrorCount) 次数据库操作失败")
        }

        return (true, "数据库运行正常")
    }
    
    func setup() {
        initializeDatabase()
    }
    
    func reinitialize() {
        securityScopedURL?.stopAccessingSecurityScopedResource()
        securityScopedURL = nil
        Self.isInitialized = false
        db = nil
        table = nil
        invalidateSearchCache()  // 清空搜索缓存
        initializeDatabase()
    }
    
    private func initializeDatabase() {
        Self.initLock.lock()
        defer { Self.initLock.unlock() }
        
        guard !Self.isInitialized else { return }
        
        let basePath = getStoragePath()
        let dbPath = (basePath as NSString).appendingPathComponent("Deck.sqlite3")
        
        var isDir = ObjCBool(false)
        if !FileManager.default.fileExists(atPath: basePath, isDirectory: &isDir) || !isDir.boolValue {
            do {
                try FileManager.default.createDirectory(atPath: basePath, withIntermediateDirectories: true)
            } catch {
                log.error("Failed to create database directory: \(error.localizedDescription)")
                return
            }
        }
        
        do {
            db = try Connection(dbPath)
            db?.busyTimeout = 5.0
            log.info("Database initialized at: \(dbPath)")
            Self.isInitialized = true
            registerCustomFunctions()
            createTable()
            applyMigrations()
        } catch {
            log.error("Database connection error: \(error.localizedDescription)")
        }
    }
    
    private func getStoragePath() -> String {
        var basePath: String
        
        if DeckUserDefaults.useCustomStorage {
            if let bookmarkData = DeckUserDefaults.storageBookmark {
                var isStale = false
                do {
                    let url = try URL(
                        resolvingBookmarkData: bookmarkData,
                        options: .withSecurityScope,
                        relativeTo: nil,
                        bookmarkDataIsStale: &isStale
                    )
                    
                    if url.startAccessingSecurityScopedResource() {
                        securityScopedURL = url
                        basePath = url.path
                        log.debug("Restored security-scoped access to \(url.path)")
                        
                        if isStale {
                            if let newBookmark = try? url.bookmarkData(
                                options: .withSecurityScope,
                                includingResourceValuesForKeys: nil,
                                relativeTo: nil
                            ) {
                                DeckUserDefaults.storageBookmark = newBookmark
                                log.debug("Refreshed stale bookmark")
                            }
                        }
                    } else {
                        basePath = defaultStoragePath()
                    }
                } catch {
                    log.error("Failed to resolve bookmark: \(error)")
                    basePath = defaultStoragePath()
                }
            } else if let customPath = DeckUserDefaults.customStoragePath {
                basePath = customPath
            } else {
                basePath = defaultStoragePath()
            }
        } else {
            securityScopedURL?.stopAccessingSecurityScopedResource()
            securityScopedURL = nil
            basePath = defaultStoragePath()
        }
        
        return (basePath as NSString).appendingPathComponent("Deck")
    }
    
    private func defaultStoragePath() -> String {
        NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true).first!
    }
    
    func getStorageDirectory() -> String {
        getStoragePath()
    }

    // MARK: - Custom SQL Functions

    /// 注册自定义 SQL 函数（如正则匹配）
    private func registerCustomFunctions() {
        guard let db = db else { return }

        // 注册 REGEXP 函数：regexp(pattern, text) -> Bool
        // 使用方式：WHERE search_text REGEXP 'pattern'
        db.createFunction("regexp", argumentCount: 2, deterministic: true) { args in
            guard args.count == 2,
                  let pattern = args[0] as? String,
                  let text = args[1] as? String else {
                return false
            }

            // 使用缓存的正则表达式
            guard let regex = RegexCache.shared.regex(for: pattern) else {
                return false
            }

            let range = NSRange(text.startIndex..., in: text)
            return regex.firstMatch(in: text, range: range) != nil
        }
        log.debug("Registered custom REGEXP function for SQLite")
    }

    /// 使用正则表达式搜索（在数据库层执行）
    func searchWithRegex(
        pattern: String,
        typeFilter: [String]? = nil,
        tagId: Int? = nil,
        limit: Int = 50
    ) async -> [Row] {
        guard !Task.isCancelled else { return [] }
        guard let db = db, let table = table else { return [] }

        // 安全模式下需要内存解密后再匹配正则
        if DeckUserDefaults.securityModeEnabled {
            return await searchWithRegexInMemory(
                pattern: pattern,
                typeFilter: typeFilter,
                tagId: tagId,
                limit: limit
            )
        }

        // 构建查询
        var query = table.filter(Expression<Bool>(literal: "regexp('\(pattern.replacingOccurrences(of: "'", with: "''"))', search_text)"))

        if let types = typeFilter, !types.isEmpty {
            let typeCondition = types.map { Col.itemType == $0 }.reduce(
                Expression<Bool>(value: false)
            ) { result, condition in
                result || condition
            }
            query = query.filter(typeCondition)
        }

        if let tagId = tagId, tagId != -1 {
            query = query.filter(Col.tagId == tagId)
        }

        query = query.order(Col.ts.desc).limit(limit)

        return withDB { Array(try db.prepare(query)) } ?? []
    }

    /// 安全模式下的正则搜索：在内存中解密后匹配
    /// 采用分批流式扫描，覆盖更多数据
    private func searchWithRegexInMemory(
        pattern: String,
        typeFilter: [String]?,
        tagId: Int?,
        limit: Int
    ) async -> [Row] {
        guard let db = db, let table = table else { return [] }
        guard let regex = RegexCache.shared.regex(for: pattern) else { return [] }

        var matchingRows: [Row] = []
        let batchSize = 500
        var offset = 0
        let maxScan = 5000  // 安全模式下最多扫描 5000 条

        while matchingRows.count < limit && offset < maxScan {
            // 支持任务取消
            guard !Task.isCancelled else { break }

            // 构建基础查询
            var query = table.order(Col.ts.desc).limit(batchSize, offset: offset)

            if let types = typeFilter, !types.isEmpty {
                let typeCondition = types.map { Col.itemType == $0 }.reduce(
                    Expression<Bool>(value: false)
                ) { result, condition in
                    result || condition
                }
                query = query.filter(typeCondition)
            }

            if let tagId = tagId, tagId != -1 {
                query = query.filter(Col.tagId == tagId)
            }

            guard let rows = withDB({ Array(try db.prepare(query)) }) else { break }

            // 没有更多数据
            if rows.isEmpty { break }

            for row in rows {
                guard matchingRows.count < limit else { break }
                guard !Task.isCancelled else { break }

                do {
                    let rawSearchText = try row.get(Col.searchText)
                    let searchText = decryptString(rawSearchText)

                    let range = NSRange(searchText.startIndex..., in: searchText)
                    if regex.firstMatch(in: searchText, range: range) != nil {
                        matchingRows.append(row)
                    }
                } catch {
                    continue
                }
            }

            // 本批次数据量不足，说明已到末尾
            if rows.count < batchSize { break }

            offset += batchSize

            // 批次间让出 CPU
            await Task.yield()
        }

        if offset >= maxScan && matchingRows.count < limit {
            log.info("Security mode regex search reached scan limit (\(maxScan) items), results may be incomplete")
        }

        return matchingRows
    }

    private func createTable() {
        guard let db = db else { return }

        let tab = Table("ClipboardHistory")

        do {
            try syncOnDBQueue {
                try db.run(tab.create(ifNotExists: true) { t in
                    t.column(Col.id, primaryKey: .autoincrement)
                    t.column(Col.uniqueId)
                    t.column(Col.type)
                    t.column(Col.itemType)
                    t.column(Col.data)
                    t.column(Col.previewData)
                    t.column(Col.ts)
                    t.column(Col.appPath)
                    t.column(Col.appName)
                    t.column(Col.searchText)
                    t.column(Col.length)
                    t.column(Col.tagId, defaultValue: -1)
                    t.column(Col.blobPath)
                })

                try db.run(tab.createIndex(Col.ts, ifNotExists: true))
                try db.run(tab.createIndex(Col.uniqueId, ifNotExists: true))
                try db.run(tab.createIndex(Col.tagId, ifNotExists: true))
                try db.run(tab.createIndex(Col.itemType, ifNotExists: true))

                table = tab

                // Create FTS5 virtual table for fast full-text search
                createFTS5Table()

                log.info("Database table created successfully")
            }
        } catch {
            log.error("DB queue failed during table creation: \(error.localizedDescription)")
        }
    }

    private func createFTS5Table() {
        guard let db = db else { return }

        do {
            try syncOnDBQueue {
                // Create FTS5 virtual table
                try db.run("""
                    CREATE VIRTUAL TABLE IF NOT EXISTS ClipboardHistory_fts USING fts5(
                        search_text,
                        app_name,
                        content='ClipboardHistory',
                        content_rowid='id'
                    )
                """)

                // Create triggers to keep FTS in sync
                try db.run("""
                    CREATE TRIGGER IF NOT EXISTS ClipboardHistory_ai AFTER INSERT ON ClipboardHistory BEGIN
                        INSERT INTO ClipboardHistory_fts(rowid, search_text, app_name)
                        VALUES (new.id, new.search_text, new.app_name);
                    END
                """)

                try db.run("""
                    CREATE TRIGGER IF NOT EXISTS ClipboardHistory_ad AFTER DELETE ON ClipboardHistory BEGIN
                        INSERT INTO ClipboardHistory_fts(ClipboardHistory_fts, rowid, search_text, app_name)
                        VALUES ('delete', old.id, old.search_text, old.app_name);
                    END
                """)

                try db.run("""
                    CREATE TRIGGER IF NOT EXISTS ClipboardHistory_au AFTER UPDATE ON ClipboardHistory BEGIN
                        INSERT INTO ClipboardHistory_fts(ClipboardHistory_fts, rowid, search_text, app_name)
                        VALUES ('delete', old.id, old.search_text, old.app_name);
                        INSERT INTO ClipboardHistory_fts(rowid, search_text, app_name)
                        VALUES (new.id, new.search_text, new.app_name);
                    END
                """)

                log.info("FTS5 table and triggers created successfully")
            }
        } catch {
            log.error("DB queue failed during FTS creation: \(error.localizedDescription)")
        }
    }

    /// Rebuild FTS index from existing data (call after migration or if FTS gets out of sync)
    func rebuildFTSIndex() {
        guard let db = db else { return }

        if withDB({
            try db.run("INSERT INTO ClipboardHistory_fts(ClipboardHistory_fts) VALUES ('rebuild')")
        }) != nil {
            // FTS 重建后清空搜索缓存，确保缓存与索引一致
            invalidateSearchCache()
            log.info("FTS5 index rebuilt successfully")
        }
    }
    
    // MARK: - Schema Versioning

    /// 当前数据库 Schema 版本
    /// 版本历史：
    /// - 0: 初始版本
    /// - 1: 添加 blob_path 列并完成大图迁移
    private static let currentSchemaVersion: Int32 = 1

    private func getSchemaVersion() -> Int32 {
        guard let db = db else { return 0 }
        return withDB {
            Int32(try db.scalar("PRAGMA user_version") as? Int64 ?? 0)
        } ?? 0
    }

    private func setSchemaVersion(_ version: Int32) {
        guard let db = db else { return }
        withDB {
            try db.run("PRAGMA user_version = \(version)")
        }
    }

    private func applyMigrations() {
        guard let db = db else { return }

        let currentVersion = getSchemaVersion()
        log.info("Current database schema version: \(currentVersion)")

        // Migration 0 -> 1: 添加 blob_path 列
        if currentVersion < 1 {
            withDB {
                let stmt = try db.prepare("PRAGMA table_info(ClipboardHistory)")
                var columns: [String] = []
                while let row = try stmt.failableNext() {
                    if let name = row[1] as? String {
                        columns.append(name)
                    }
                }
                if !columns.contains("blob_path") {
                    try db.run("ALTER TABLE ClipboardHistory ADD COLUMN blob_path TEXT")
                    log.info("Added blob_path column for large payload offloading")
                }
            }

            // 执行大图迁移
            migrateLargeImagesIfNeeded(targetVersion: 1)
        }

        // 未来的迁移可以继续添加:
        // if currentVersion < 2 { ... }
    }

    private func migrateLargeImagesIfNeeded(targetVersion: Int32) {
        // 在后台线程执行迁移
        Task(priority: .background) { [weak self] in
            guard let self else { return }
            await self.performLargeImageMigration()
            // 迁移完成后更新数据库版本
            self.setSchemaVersion(targetVersion)
            log.info("Database schema updated to version \(targetVersion)")
        }
    }

    private func performLargeImageMigration() async {
        guard let db = db, let table = table else { return }

        // 使用分页查询避免一次性加载全部数据
        let batchSize = 50
        var offset = 0
        var totalMigrated = 0

        while true {
            // 每次只查询一批需要迁移的图片
            let blobIsNil = Expression<Bool>("blob_path IS NULL")
            let filter = (Col.itemType == ClipItemType.image.rawValue) && blobIsNil
            let rows = await search(filter: filter, limit: batchSize, offset: offset)

            guard !rows.isEmpty else { break }

            var migratedInBatch = 0

            for row in rows {
                // 支持任务取消
                guard !Task.isCancelled else {
                    log.info("Large image migration cancelled after \(totalMigrated) items")
                    return
                }

                guard let item = rowToClipboardItem(row, isEncrypted: nil) else { continue }
                guard item.data.count > Const.largeBlobThreshold else { continue }

                let path = await BlobStorage.shared.storeAsync(data: item.data, uniqueId: item.uniqueId)

                guard let path else { continue }

                let storedData = item.previewData ?? Data()
                let encryptedData = encryptData(storedData)

                let query = table.filter(Col.id == item.id!)
                withDB {
                    try db.run(query.update(
                        Col.data <- encryptedData,
                        Col.blobPath <- path
                    ))
                }

                migratedInBatch += 1
                totalMigrated += 1
            }

            // 如果本批次没有符合条件的大图，继续下一批
            if migratedInBatch == 0 && rows.count < batchSize {
                break
            }

            offset += batchSize

            // 批次间让出 CPU，避免长时间阻塞后台线程
            await Task.yield()
        }

        log.info("Large image migration completed: \(totalMigrated) items migrated")
        vacuumDatabase()
    }

    private func vacuumDatabase() {
        guard let db = db else { return }
        if withDB({
            try db.run("VACUUM")
        }) != nil {
            log.info("Database vacuum completed after blob migration")
        }
    }
    
    deinit {
        securityScopedURL?.stopAccessingSecurityScopedResource()
    }
}

// MARK: - Encryption Helpers

extension DeckSQLManager {
    private func encryptData(_ data: Data) -> Data {
        guard DeckUserDefaults.securityModeEnabled else { return data }
        return SecurityService.shared.encrypt(data) ?? data
    }
    
    private func decryptData(_ data: Data) -> Data {
        guard DeckUserDefaults.securityModeEnabled else { return data }
        return SecurityService.shared.decrypt(data) ?? data
    }
    
    private func encryptString(_ string: String) -> String {
        guard DeckUserDefaults.securityModeEnabled else { return string }
        guard let data = string.data(using: .utf8),
              let encrypted = SecurityService.shared.encrypt(data) else { return string }
        return encrypted.base64EncodedString()
    }
    
    private func decryptString(_ string: String) -> String {
        guard DeckUserDefaults.securityModeEnabled else { return string }
        guard let data = Data(base64Encoded: string),
              let decrypted = SecurityService.shared.decrypt(data),
              let result = String(data: decrypted, encoding: .utf8) else { return string }
        return result
    }

    // MARK: - Search Cache Helpers

    /// 获取缓存的搜索字符串，如果未缓存则解密并缓存
    /// 安全模式下禁用缓存，避免明文在内存中长时间暴露
    /// - Parameters:
    ///   - id: 行 ID
    ///   - rawSearchText: 原始搜索文本（可能已加密）
    ///   - appName: 应用名称
    ///   - isSecurityMode: 是否处于安全模式
    /// - Returns: 解密且小写化后的缓存条目
    private func getCachedSearchEntry(
        id: Int64,
        rawSearchText: String,
        appName: String,
        isSecurityMode: Bool
    ) -> SearchCacheEntry {
        // 安全模式下不使用缓存，避免明文在内存中长时间暴露
        // 每次请求都实时解密，虽然性能略低但更安全
        if isSecurityMode {
            let searchText = decryptString(rawSearchText)
            return SearchCacheEntry(
                searchText: searchText.lowercased(),
                appName: appName.lowercased()
            )
        }

        // 非安全模式下使用缓存优化性能
        let cacheKey = NSNumber(value: id)

        // 尝试从缓存获取
        if let cached = searchTextCache.object(forKey: cacheKey) {
            return cached
        }

        // 缓存未命中，小写化后存入缓存
        let entry = SearchCacheEntry(
            searchText: rawSearchText.lowercased(),
            appName: appName.lowercased()
        )

        searchTextCache.setObject(entry, forKey: cacheKey)
        return entry
    }

    /// 使缓存失效
    /// - Parameter ids: 要失效的行 ID 列表。如果为 nil，则清空所有缓存
    private func invalidateSearchCache(ids: [Int64]? = nil) {
        if let ids = ids {
            for id in ids {
                searchTextCache.removeObject(forKey: NSNumber(value: id))
            }
            log.debug("Invalidated search cache for \(ids.count) items")
        } else {
            searchTextCache.removeAllObjects()
            log.debug("Cleared all search cache")
        }
    }
}

// MARK: - Database Operations

extension DeckSQLManager {
    var totalCount: Int {
        guard let db = db, let table = table else { return 0 }
        return withDB { try db.scalar(table.count) } ?? 0
    }
    
    func insert(item: ClipboardItem) async -> Int64 {
        guard let db = db, let table = table else { return -1 }

        await delete(filter: Col.uniqueId == item.uniqueId)

        // Offload large image payloads to filesystem
        var dataToStore = item.data
        var blobPath = item.blobPath
        var previewData = item.previewData
        let isSecurityMode = DeckUserDefaults.securityModeEnabled

        if item.itemType == .image && item.data.count > Const.largeBlobThreshold {
            // Store large image to blob storage (auto-encrypts in security mode)
            if let path = BlobStorage.shared.store(data: item.data, uniqueId: item.uniqueId, encrypt: isSecurityMode) {
                blobPath = path

                // Pre-generate thumbnail for large images if not already present
                if previewData == nil || previewData!.isEmpty {
                    previewData = await ClipboardItem.generatePreviewThumbnailDataAsync(from: item.data, maxSize: 200)
                    log.debug("Pre-generated thumbnail for large image (\(item.data.count) bytes)")
                }

                dataToStore = previewData ?? Data()
            }
        } else if item.itemType == .image && item.data.count > 50 * 1024 && (previewData == nil || previewData!.isEmpty) {
            // For medium-sized images (50KB-512KB), also pre-generate thumbnail
            previewData = await ClipboardItem.generatePreviewThumbnailDataAsync(from: item.data, maxSize: 200)
            log.debug("Pre-generated thumbnail for medium image (\(item.data.count) bytes)")
        }

        // Encrypt sensitive data if security mode is enabled
        let encryptedData = encryptData(dataToStore)
        let encryptedPreviewData = previewData.map { encryptData($0) }
        let encryptedSearchText = encryptString(item.searchText)

        let insert = table.insert(
            Col.uniqueId <- item.uniqueId,
            Col.type <- item.pasteboardType.rawValue,
            Col.itemType <- item.itemType.rawValue,
            Col.data <- encryptedData,
            Col.previewData <- encryptedPreviewData,
            Col.ts <- item.timestamp,
            Col.appPath <- item.appPath,
            Col.appName <- item.appName,
            Col.searchText <- encryptedSearchText,
            Col.length <- item.contentLength,
            Col.tagId <- item.tagId,
            Col.blobPath <- blobPath
        )

        if let rowId: Int64 = withDB({ try db.run(insert) }) {
            log.debug("Inserted item with id: \(rowId)")
            return rowId
        }
        return -1
    }
    
    func delete(filter: SQLite.Expression<Bool>) async {
        guard let db = db, let table = table else { return }

        let query = table.filter(filter)
        if let count: Int = withDB({ try db.run(query.delete()) }) {
            log.debug("Deleted \(count) items")
            // 无法确定具体删除了哪些 ID，清空所有缓存
            invalidateSearchCache()
        }
    }

    func deleteAll() {
        guard let db = db, let table = table else { return }
        _ = withDB { try db.run(table.delete()) }
        invalidateSearchCache()  // 清空所有搜索缓存
        log.info("Deleted all items from database")
    }

    func delete(id: Int64) async {
        guard let db = db, let table = table else { return }

        let query = table.filter(Col.id == id)
        if let count: Int = withDB({ try db.run(query.delete()) }) {
            log.debug("Deleted item with id \(id): \(count) rows")
            invalidateSearchCache(ids: [id])  // 只失效被删除的项
        }
    }

    func update(id: Int64, item: ClipboardItem) async {
        guard let db = db, let table = table else { return }

        // 与 insert 保持一致，安全模式下加密数据
        let encryptedData = encryptData(item.data)
        let encryptedPreviewData = item.previewData.map { encryptData($0) }
        let encryptedSearchText = encryptString(item.searchText)

        let query = table.filter(Col.id == id)
        let update = query.update(
            Col.type <- item.pasteboardType.rawValue,
            Col.itemType <- item.itemType.rawValue,
            Col.data <- encryptedData,
            Col.previewData <- encryptedPreviewData,
            Col.ts <- item.timestamp,
            Col.appPath <- item.appPath,
            Col.appName <- item.appName,
            Col.searchText <- encryptedSearchText,
            Col.length <- item.contentLength,
            Col.tagId <- item.tagId
        )

        if let count: Int = withDB({ try db.run(update) }) {
            log.debug("Updated \(count) items")
            invalidateSearchCache(ids: [id])  // 失效被更新的项（searchText 可能已变化）
        }
    }
    
    func updateItemTag(id: Int64, tagId: Int) async {
        guard let db = db, let table = table else { return }

        let query = table.filter(Col.id == id)
        let update = query.update(Col.tagId <- tagId)

        if let count: Int = withDB({ try db.run(update) }) {
            log.debug("Updated tag for \(count) items")
        }
    }

    /// 更新项目的 searchText（用于 OCR 结果）
    /// 注意：FTS 索引会通过 ClipboardHistory_au 触发器自动更新
    func updateSearchText(id: Int64, searchText: String) async {
        guard let db = db, let table = table else {
            log.error("OCR DB: Database not initialized")
            return
        }

        log.info("OCR DB: Updating searchText for item \(id), text length: \(searchText.count)")

        // 根据安全模式决定是否加密
        let textToStore = encryptString(searchText)

        let query = table.filter(Col.id == id)
        let update = query.update(Col.searchText <- textToStore)

        if let count: Int = withDB({ try db.run(update) }) {
            log.info("OCR DB: Successfully updated searchText for \(count) items (FTS auto-synced via trigger)")
            invalidateSearchCache(ids: [id])
        } else {
            log.error("OCR DB: Failed to update searchText for item \(id)")
        }
    }

    func search(
        filter: SQLite.Expression<Bool>? = nil,
        order: [Expressible]? = nil,
        limit: Int? = nil,
        offset: Int? = nil
    ) async -> [Row] {
        guard !Task.isCancelled else { return [] }
        guard let db = db, let table = table else { return [] }

        let ord = order ?? [Col.ts.desc]

        var query = table.order(ord)
        if let f = filter { query = query.filter(f) }
        if let l = limit { query = query.limit(l, offset: offset ?? 0) }

        return withDB { Array(try db.prepare(query)) } ?? []
    }

    /// Fast full-text search using FTS5
    /// Returns row IDs matching the search term
    func searchFTS(keyword: String, limit: Int = 50) async -> [Int64] {
        guard !Task.isCancelled else { return [] }
        guard let db = db, !keyword.isEmpty else { return [] }

        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)

        // 安全模式下 FTS 索引存储的是加密内容，无法直接匹配
        // 需要使用内存解密搜索
        if DeckUserDefaults.securityModeEnabled {
            return await searchWithLike(keyword: trimmed, limit: limit)
        }

        // 检测是否包含 CJK 字符（中日韩）
        let containsCJK = trimmed.unicodeScalars.contains { scalar in
            // CJK Unified Ideographs and extensions
            (0x4E00...0x9FFF).contains(scalar.value) ||   // CJK Unified
            (0x3400...0x4DBF).contains(scalar.value) ||   // CJK Extension A
            (0x20000...0x2A6DF).contains(scalar.value) || // CJK Extension B
            (0x3000...0x303F).contains(scalar.value) ||   // CJK Symbols
            (0x3040...0x309F).contains(scalar.value) ||   // Hiragana
            (0x30A0...0x30FF).contains(scalar.value) ||   // Katakana
            (0xAC00...0xD7AF).contains(scalar.value)      // Korean Hangul
        }

        // 对于包含 CJK 的搜索词，使用 LIKE 查询（FTS5 默认分词器对 CJK 支持不好）
        if containsCJK {
            return await searchWithLike(keyword: trimmed, limit: limit)
        }

        // 将搜索词按空格分割，每个词独立搜索（OR 逻辑）
        // 这样 "hello world" 会匹配包含 "hello" 或 "world" 的内容
        let terms = trimmed
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .map { term -> String in
                // 转义特殊字符
                let escaped = term
                    .replacingOccurrences(of: "\"", with: "\"\"")
                    .replacingOccurrences(of: "*", with: "")
                // 使用前缀匹配
                return "\"\(escaped)\"*"
            }

        guard !terms.isEmpty else { return [] }

        // 用 OR 连接多个词，更宽松的匹配
        let ftsQuery = terms.joined(separator: " OR ")

        return withDB {
            let sql = """
                SELECT rowid FROM ClipboardHistory_fts
                WHERE ClipboardHistory_fts MATCH ?
                ORDER BY rank
                LIMIT ?
            """
            let stmt = try db.prepare(sql).bind(ftsQuery, limit)
            var ids: [Int64] = []
            while let row = try stmt.failableNext() {
                if let id = row[0] as? Int64 {
                    ids.append(id)
                }
            }
            return ids
        } ?? []
    }

    /// LIKE-based search for CJK characters
    /// 对于中文搜索，使用内存搜索更可靠（SQL LIKE 可能有编码问题）
    /// 使用缓存避免重复解密和 lowercased 转换，显著提升频繁搜索性能
    /// 采用分批流式扫描，覆盖全量数据
    private func searchWithLike(keyword: String, limit: Int) async -> [Int64] {
        guard let db = db, let table = table else { return [] }

        var matchingIds: [Int64] = []
        let lowercasedKeyword = keyword.lowercased()
        let isSecurityMode = DeckUserDefaults.securityModeEnabled

        // 分批扫描参数
        let batchSize = 500
        var offset = 0
        // 安全模式下最多扫描 5000 条（解密开销大），普通模式扫描全量
        let maxScan = isSecurityMode ? 5000 : Int.max

        while matchingIds.count < limit && offset < maxScan {
            // 支持任务取消
            guard !Task.isCancelled else { break }

            let query = table.select(Col.id, Col.searchText, Col.appName)
                .order(Col.ts.desc)
                .limit(batchSize, offset: offset)

            guard let rows = withDB({ Array(try db.prepare(query)) }) else { break }

            // 没有更多数据
            if rows.isEmpty { break }

            for row in rows {
                // 早停：已找到足够的匹配项
                guard matchingIds.count < limit else { break }

                // 支持任务取消
                guard !Task.isCancelled else { break }

                do {
                    let id = try row.get(Col.id)
                    let rawSearchText = try row.get(Col.searchText)
                    let appName = try row.get(Col.appName)

                    // 使用缓存获取解密且小写化后的搜索文本
                    // 热路径优化：避免重复解密和 lowercased 转换
                    let cached = getCachedSearchEntry(
                        id: id,
                        rawSearchText: rawSearchText,
                        appName: appName,
                        isSecurityMode: isSecurityMode
                    )

                    // 匹配搜索文本或应用名称（都已预先小写化）
                    if cached.searchText.contains(lowercasedKeyword) ||
                       cached.appName.contains(lowercasedKeyword) {
                        matchingIds.append(id)
                    }
                } catch {
                    continue
                }
            }

            // 本批次数据量不足，说明已到末尾
            if rows.count < batchSize { break }

            offset += batchSize

            // 批次间让出 CPU，避免长时间阻塞
            await Task.yield()
        }

        // 安全模式下如果达到扫描上限且未找到足够结果，记录日志提示
        if isSecurityMode && offset >= maxScan && matchingIds.count < limit {
            log.info("Security mode search reached scan limit (\(maxScan) items), results may be incomplete")
        }

        return matchingIds
    }

    /// Search using FTS5 and return full ClipboardItem objects
    func searchWithFTS(
        keyword: String,
        typeFilter: [String]? = nil,
        tagId: Int? = nil,
        limit: Int = 50
    ) async -> [Row] {
        guard !Task.isCancelled else { return [] }
        guard let db = db, let table = table else { return [] }

        // Get matching IDs from FTS
        let matchingIds = await searchFTS(keyword: keyword, limit: limit * 2)
        guard !matchingIds.isEmpty else { return [] }

        // Build query with additional filters
        var query = table.filter(matchingIds.contains(Col.id))

        if let types = typeFilter, !types.isEmpty {
            let typeCondition = types.map { Col.itemType == $0 }.reduce(
                Expression<Bool>(value: false)
            ) { result, condition in
                result || condition
            }
            query = query.filter(typeCondition)
        }

        if let tagId = tagId, tagId != -1 {
            query = query.filter(Col.tagId == tagId)
        }

        query = query.order(Col.ts.desc).limit(limit)

        return withDB { Array(try db.prepare(query)) } ?? []
    }
    
    func fetchAll(limit: Int = 10000, offset: Int = 0) -> [ClipboardItem] {
        guard let db = db, let table = table else { return [] }
        
        let query = table.order(Col.ts.desc).limit(limit, offset: offset)
        
        let rows = withDB { Array(try db.prepare(query)) } ?? []
        return rows.compactMap { rowToClipboardItem($0) }
    }
    
    func fetch(id: Int64) async -> Row? {
        guard let db = db, let table = table else { return nil }

        let query = table.filter(Col.id == id)

        return withDB { try db.pluck(query) } ?? nil
    }

    /// 批量获取多个 ID 的记录，使用单次 SQL 查询
    func fetchBatch(ids: [Int64]) async -> [Row] {
        guard let db = db, let table = table, !ids.isEmpty else { return [] }

        // 使用 WHERE id IN (...) 查询
        let query = table.filter(ids.contains(Col.id))

        return withDB { Array(try db.prepare(query)) } ?? []
    }

    func count(typeFilter: [String]? = nil) async -> Int {
        guard let db = db, let table = table else { return 0 }
        
        var query = table
        if let types = typeFilter, !types.isEmpty {
            let typeCondition = types.map { Col.itemType == $0 }.reduce(
                Expression<Bool>(value: false)
            ) { result, condition in
                result || condition
            }
            query = query.filter(typeCondition)
        }
        
        return withDB { try db.scalar(query.count) } ?? 0
    }
    
    func rowToClipboardItem(_ row: Row, isEncrypted: Bool? = nil) -> ClipboardItem? {
        do {
            let type = try row.get(Col.type)
            let rawData = try row.get(Col.data)
            let timestamp = try row.get(Col.ts)
            let id = try row.get(Col.id)
            let appName = try row.get(Col.appName)
            let appPath = try row.get(Col.appPath)
            let rawPreviewData = try row.get(Col.previewData)
            let rawSearchText = try row.get(Col.searchText)
            let length = try row.get(Col.length)
            let tagId = try row.get(Col.tagId)
            let blobPath = try row.get(Col.blobPath)
            let storedUniqueId = try row.get(Col.uniqueId)
            
            // Decrypt data if security mode is enabled
            let shouldDecrypt = isEncrypted ?? DeckUserDefaults.securityModeEnabled
            let data = shouldDecrypt ? decryptData(rawData) : rawData
            let previewData = rawPreviewData.map { shouldDecrypt ? decryptData($0) : $0 }
            let searchText = shouldDecrypt ? decryptString(rawSearchText) : rawSearchText
            
            let item = ClipboardItem(
                pasteboardType: PasteboardType(type),
                data: data,
                previewData: previewData,
                timestamp: timestamp,
                appPath: appPath,
                appName: appName,
                searchText: searchText,
                contentLength: length,
                tagId: tagId,
                id: id,
                uniqueId: storedUniqueId,
                blobPath: blobPath
            )
            return item
        } catch {
            log.error("Failed to convert row to ClipboardItem: \(error)")
            return nil
        }
    }
    
    // MARK: - Encryption Migration

    /// Re-encrypt or decrypt all existing data when security mode changes
    /// - Parameter encrypt: true to encrypt, false to decrypt
    /// - Returns: true if migration succeeded, false if failed
    func migrateEncryption(encrypt: Bool) async -> Bool {
        guard let db = db, let table = table else {
            log.error("Database not initialized for encryption migration")
            return false
        }

        log.info("Starting encryption migration: encrypt=\(encrypt)")

        // 使用分批处理避免一次性加载全表到内存
        let batchSize = 100
        var offset = 0
        var totalProcessed = 0
        var hasError = false

        while !hasError {
            // 分批查询，只获取 id 和需要迁移的字段
            let batchResult: (rows: [Row], count: Int)? = withDB {
                let query = table
                    .select(Col.id, Col.data, Col.previewData, Col.searchText)
                    .order(Col.id.asc)
                    .limit(batchSize, offset: offset)
                let rows = Array(try db.prepare(query))
                return (rows, rows.count)
            }

            guard let batch = batchResult else {
                hasError = true
                break
            }

            // 没有更多数据，退出循环
            if batch.rows.isEmpty {
                break
            }

            // 处理当前批次
            let batchSuccess = withDB {
                for row in batch.rows {
                    let id = try row.get(Col.id)
                    let rawData = try row.get(Col.data)
                    let rawPreviewData = try row.get(Col.previewData)
                    let rawSearchText = try row.get(Col.searchText)

                    let newData: Data
                    let newPreviewData: Data?
                    let newSearchText: String

                    if encrypt {
                        // Encrypting: data is currently unencrypted
                        newData = SecurityService.shared.encrypt(rawData) ?? rawData
                        newPreviewData = rawPreviewData.flatMap { SecurityService.shared.encrypt($0) }
                        if let stringData = rawSearchText.data(using: .utf8),
                           let encrypted = SecurityService.shared.encrypt(stringData) {
                            newSearchText = encrypted.base64EncodedString()
                        } else {
                            newSearchText = rawSearchText
                        }
                    } else {
                        // Decrypting: data is currently encrypted
                        newData = SecurityService.shared.decrypt(rawData) ?? rawData
                        newPreviewData = rawPreviewData.flatMap { SecurityService.shared.decrypt($0) }
                        if let decoded = Data(base64Encoded: rawSearchText),
                           let decrypted = SecurityService.shared.decrypt(decoded),
                           let str = String(data: decrypted, encoding: .utf8) {
                            newSearchText = str
                        } else {
                            newSearchText = rawSearchText
                        }
                    }

                    // Update the row
                    let query = table.filter(Col.id == id)
                    let update = query.update(
                        Col.data <- newData,
                        Col.previewData <- newPreviewData,
                        Col.searchText <- newSearchText
                    )
                    try db.run(update)
                }
                return true
            }

            if batchSuccess != true {
                hasError = true
                break
            }

            totalProcessed += batch.count
            offset += batchSize

            // 批次间让出 CPU，避免长时间阻塞
            await Task.yield()
        }

        if hasError {
            log.error("Encryption migration failed after processing \(totalProcessed) items")
            return false
        }

        log.info("Encryption migration completed: \(totalProcessed) items processed")

        // 迁移 blob 文件的加密状态
        await BlobStorage.shared.migrateEncryption(encrypt: encrypt)

        // 更新数据库中的 blob_path（加密后缀变化）
        await updateBlobPathsAfterMigration(encrypt: encrypt)

        // 加密状态变化后，缓存的解密文本全部失效
        invalidateSearchCache()
        return true
    }

    /// 更新数据库中的 blob_path 字段（加密迁移后路径后缀变化）
    private func updateBlobPathsAfterMigration(encrypt: Bool) async {
        guard let db = db, let table = table else { return }

        // 查找所有有 blob_path 的记录
        let query = table.select(Col.id, Col.blobPath)
            .filter(Col.blobPath != nil)

        guard let rows = withDB({ Array(try db.prepare(query)) }) else { return }

        for row in rows {
            do {
                let id = try row.get(Col.id)
                guard let oldPath = try row.get(Col.blobPath) else { continue }

                let newPath: String
                if encrypt {
                    // 添加 .enc 后缀
                    newPath = oldPath.hasSuffix(".enc") ? oldPath : "\(oldPath).enc"
                } else {
                    // 移除 .enc 后缀
                    newPath = oldPath.hasSuffix(".enc") ? String(oldPath.dropLast(4)) : oldPath
                }

                if newPath != oldPath {
                    let updateQuery = table.filter(Col.id == id)
                    withDB {
                        try db.run(updateQuery.update(Col.blobPath <- newPath))
                    }
                }
            } catch {
                continue
            }
        }
    }

    // MARK: - Storage Migration

    /// Update blob paths in a database file (used during storage migration)
    static func updateBlobPaths(inDatabaseAt dbPath: String, oldBlobsPath: String, newBlobsPath: String) {
        guard let db = try? Connection(dbPath) else {
            log.error("Failed to open database for blob path migration: \(dbPath)")
            return
        }

        do {
            let sql = """
                UPDATE ClipboardHistory
                SET blob_path = REPLACE(blob_path, ?, ?)
                WHERE blob_path IS NOT NULL AND blob_path LIKE ?
            """
            try db.run(sql, oldBlobsPath, newBlobsPath, oldBlobsPath + "%")
            log.info("Blob paths updated in migrated database")
        } catch {
            log.error("Failed to update blob paths: \(error)")
        }
    }

    /// Checkpoint WAL to ensure all transactions are written to the main database file
    /// - Parameter dbPath: Path to the SQLite database
    /// - Returns: true if checkpoint succeeded, false otherwise
    static func checkpointWAL(at dbPath: String) -> Bool {
        guard let db = try? Connection(dbPath) else {
            log.error("Failed to open database for WAL checkpoint: \(dbPath)")
            return false
        }

        do {
            try db.execute("PRAGMA wal_checkpoint(TRUNCATE)")
            log.info("WAL checkpoint completed for \(dbPath)")
            return true
        } catch {
            log.warn("Failed to checkpoint WAL: \(error)")
            return false
        }
    }
}
