//
//  DeckSQLManager.swift
//  Deck
//
//  Deck Clipboard Manager - SQLite Database Management
//

import AppKit
import Foundation
import SQLite
import SQLite3
import Darwin

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

enum EmbeddingCol {
    static let id = Expression<Int64>("id")
    static let textHash = Expression<String>("text_hash")
    static let embedding = Expression<Data>("embedding")
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
    private let embeddingQueue = DispatchQueue(label: "com.deck.semantic.embedding", qos: .utility)

    private var db: Connection?
    private var table: Table?
    private var securityScopedURL: URL?
    private var ftsUsesTrigram = false
    private let ftsTrigramMinQueryLength = 3
    private let backupFileName = "Deck.sqlite3.bak"
    private let backupInterval: TimeInterval = 24 * 60 * 60
    private let vecTableBaseName = "ClipboardHistory_embedding_vec"
    private let vecExtensionFileNames = [
        "vec0",
        "vec0.dylib",
        "sqlite-vec",
        "sqlite-vec.dylib",
        "libsqlite_vec.dylib"
    ]
    private let vecNumberLocale = Locale(identifier: "en_US_POSIX")
    private var vecIndexEnabled = false
    private var vecReadyDimensions: Set<Int> = []
    private var vecLegacyTableCleaned = false
    private var vecBackfillInProgress = false
    private let vecBackfillStateQueue = DispatchQueue(label: "com.deck.vec.backfill.state")

    // Error tracking - 错误追踪
    private var consecutiveErrorCount = 0
    private var lastErrorTime: Date?
    private let errorThreshold = 3  // 连续 3 次错误后通知用户
    private var hasNotifiedUser = false
    private var recoveryInProgress = false

    // 搜索缓存：避免重复解密和 lowercased 转换
    // Key: row id, Value: 解密且小写化后的搜索文本
    private let searchTextCache: NSCache<NSNumber, SearchCacheEntry> = {
        let cache = NSCache<NSNumber, SearchCacheEntry>()
        cache.countLimit = 300  // 限制缓存条目，降低常驻内存
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
        let paths = databasePaths(for: basePath)
        let dbPath = paths.dbPath
        return FileManager.default.fileExists(atPath: dbPath) && FileManager.default.isReadableFile(atPath: dbPath)
    }

    /// 处理数据库错误并在必要时通知用户
    private func handleDBError(_ error: Error) {
        consecutiveErrorCount += 1
        lastErrorTime = Date()

        let details = extractDBErrorDetails(error)
        let errorMessage = details.message
        log.error("DB operation failed (\(consecutiveErrorCount)/\(errorThreshold)): \(errorMessage) (domain=\(details.domain), code=\(details.code))")
        if details.debug != details.message {
            log.debug("DB error detail: \(details.debug)")
        }

        // 检测严重错误类型
        let isCritical = errorMessage.contains("disk I/O error") ||
                         errorMessage.contains("database is locked") ||
                         errorMessage.contains("disk full") ||
                         errorMessage.contains("readonly") ||
                         errorMessage.contains("corrupt") ||
                         details.isCriticalSQLiteCode

        if details.isSQLiteDomain, details.code == SQLITE_OK {
            if !performIntegrityCheck() {
                attemptDBRecovery(reason: "SQLite error 0 with failed integrity check")
            } else if consecutiveErrorCount >= errorThreshold {
                consecutiveErrorCount = 0
            }
            return
        }

        if (consecutiveErrorCount >= errorThreshold || isCritical) && !hasNotifiedUser {
            if details.isSQLiteDomain, isCritical {
                attemptDBRecovery(reason: "Critical SQLite error")
            }
            hasNotifiedUser = true
            notifyUserOfDBError(errorMessage, isCritical: isCritical)
        }
    }

    private func attemptDBRecovery(reason: String) {
        guard !recoveryInProgress else { return }
        recoveryInProgress = true
        log.warn("Attempting database recovery: \(reason)")
        DispatchQueue.main.async { [weak self] in
            self?.reinitialize()
            self?.recoveryInProgress = false
        }
    }

    private struct DBErrorDetails {
        let message: String
        let debug: String
        let domain: String
        let code: Int32
        let isSQLiteDomain: Bool
        let isCriticalSQLiteCode: Bool
    }

    private func extractDBErrorDetails(_ error: Error) -> DBErrorDetails {
        let nsError = error as NSError
        let domain = nsError.domain
        let code = Int32(nsError.code)
        let message = nsError.localizedDescription
        let debug = String(reflecting: error)
        let isSQLiteDomain = domain.lowercased().contains("sqlite")
        let criticalCodes: Set<Int32> = [
            SQLITE_IOERR,
            SQLITE_CORRUPT,
            SQLITE_NOTADB,
            SQLITE_READONLY,
            SQLITE_CANTOPEN,
            SQLITE_FULL
        ]
        let isCriticalSQLiteCode = isSQLiteDomain && criticalCodes.contains(code)
        return DBErrorDetails(
            message: message,
            debug: debug,
            domain: domain,
            code: code,
            isSQLiteDomain: isSQLiteDomain,
            isCriticalSQLiteCode: isCriticalSQLiteCode
        )
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

        // 轻量完整性检查（用于用户主动诊断）
        if !performIntegrityCheck() {
            return (false, "数据库完整性检查未通过")
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
        let paths = databasePaths(for: basePath)
        let dbPath = paths.dbPath
        let backupPath = paths.backupPath
        
        var isDir = ObjCBool(false)
        if !FileManager.default.fileExists(atPath: basePath, isDirectory: &isDir) || !isDir.boolValue {
            do {
                try FileManager.default.createDirectory(atPath: basePath, withIntermediateDirectories: true)
            } catch {
                log.error("Failed to create database directory: \(error.localizedDescription)")
                return
            }
        }
        
        if !FileManager.default.fileExists(atPath: dbPath) &&
            FileManager.default.fileExists(atPath: backupPath) {
            if restoreDatabaseFromBackup(dbPath: dbPath, backupPath: backupPath) {
                log.info("Restored database from backup at startup")
            }
        }

        do {
            try openDatabase(at: dbPath)

            if !performIntegrityCheck() {
                log.warn("Database integrity check failed, attempting to restore from backup")
                db = nil
                if restoreDatabaseFromBackup(dbPath: dbPath, backupPath: backupPath) {
                    try openDatabase(at: dbPath)
                    if !performIntegrityCheck() {
                        handleDBError(NSError(domain: "DeckSQL", code: -2, userInfo: [
                            NSLocalizedDescriptionKey: "Database integrity check failed after restore"
                        ]))
                    }
                } else {
                    handleDBError(NSError(domain: "DeckSQL", code: -3, userInfo: [
                        NSLocalizedDescriptionKey: "Database integrity check failed and no backup available"
                    ]))
                }
            }

            log.info("Database initialized at: \(dbPath)")
            Self.isInitialized = true
            registerCustomFunctions()
            createTable()
            applyMigrations()
            Task { @MainActor in
                DeckSQLManager.shared.ensureFTSTrigramIfAvailable()
            }
            Task {
                DeckSQLManager.shared.backupDatabaseIfNeeded(dbPath: dbPath, backupPath: backupPath)
            }
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

    private func databasePaths(for basePath: String) -> (dbPath: String, backupPath: String) {
        let dbPath = (basePath as NSString).appendingPathComponent("Deck.sqlite3")
        let backupPath = (basePath as NSString).appendingPathComponent(backupFileName)
        return (dbPath, backupPath)
    }

    private func openDatabase(at dbPath: String) throws {
        vecIndexEnabled = false
        vecReadyDimensions.removeAll()
        vecLegacyTableCleaned = false
        db = try Connection(dbPath)
        db?.busyTimeout = 5.0
        if let db = db {
            // Use a modest mmap size to reduce read overhead without inflating heap usage.
            do {
                try db.run("PRAGMA mmap_size = 134217728") // 128MB
            } catch {
                log.debug("Failed to set mmap_size: \(error.localizedDescription)")
            }
        }
        initializeSQLiteVecOnConnection()
        loadSQLiteVecExtensionIfAvailable()
    }

    private typealias SQLiteEnableLoadExtensionFn = @convention(c) (OpaquePointer?, Int32) -> Int32
    private typealias SQLiteLoadExtensionFn = @convention(c) (
        OpaquePointer?,
        UnsafePointer<Int8>?,
        UnsafePointer<Int8>?,
        UnsafeMutablePointer<UnsafeMutablePointer<Int8>?>?
    ) -> Int32
    private func resolveSQLiteLoadExtensionAPI() -> (enable: SQLiteEnableLoadExtensionFn, load: SQLiteLoadExtensionFn)? {
        let handle = UnsafeMutableRawPointer(bitPattern: -2)
        guard let enablePtr = dlsym(handle, "sqlite3_enable_load_extension"),
              let loadPtr = dlsym(handle, "sqlite3_load_extension") else {
            return nil
        }
        let enable = unsafeBitCast(enablePtr, to: SQLiteEnableLoadExtensionFn.self)
        let load = unsafeBitCast(loadPtr, to: SQLiteLoadExtensionFn.self)
        return (enable, load)
    }

    private func initializeSQLiteVecOnConnection() {
        guard let db = db else { return }
        guard !DeckUserDefaults.securityModeEnabled else { return }

        var error: UnsafeMutablePointer<Int8>?
        // sqlite-vec is compiled with SQLITE_CORE, so pApi can be nil.
        let rc = sqlite3_vec_init(db.handle, &error, nil)
        if rc == SQLITE_OK {
            vecIndexEnabled = true
            log.info("sqlite-vec initialized via sqlite3_vec_init (static)")
            cleanupLegacyVecTableIfNeeded()
            scheduleVecIndexBackfillIfNeeded()
            return
        }

        let message = error.map { String(cString: $0) } ?? "unknown error"
        if let error { sqlite3_free(error) }
        vecIndexEnabled = false
        log.debug("sqlite-vec init failed (rc=\(rc)): \(message)")
    }

    private func loadSQLiteVecExtensionIfAvailable() {
        guard let db = db else { return }
        guard !DeckUserDefaults.securityModeEnabled else { return }
        if vecIndexEnabled {
            cleanupLegacyVecTableIfNeeded()
            scheduleVecIndexBackfillIfNeeded()
            return
        }

        let candidates = vecExtensionCandidateURLs()
        guard let url = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            log.debug("sqlite-vec extension not found, vector index disabled")
            return
        }

        guard let api = resolveSQLiteLoadExtensionAPI() else {
            log.debug("SQLite load_extension API not available, vector index disabled")
            return
        }

        syncOnDBQueue {
            var error: UnsafeMutablePointer<Int8>?
            let rc: Int32 = url.path.withCString { path in
                _ = api.enable(db.handle, 1)
                defer { _ = api.enable(db.handle, 0) }
                return api.load(db.handle, path, nil, &error)
            }

            if rc == SQLITE_OK {
                vecIndexEnabled = true
                log.info("Loaded sqlite-vec extension at: \(url.path)")
            } else {
                let message = error.map { String(cString: $0) } ?? "unknown error"
                if let error { sqlite3_free(error) }
                log.debug("Failed to load sqlite-vec extension: \(message)")
            }
        }

        if vecIndexEnabled {
            cleanupLegacyVecTableIfNeeded()
            scheduleVecIndexBackfillIfNeeded()
        }
    }

    private func vecExtensionCandidateURLs() -> [URL] {
        var searchPaths: [URL] = []
        let bundle = Bundle.main
        if let url = bundle.resourceURL {
            searchPaths.append(url)
        }
        if let url = bundle.privateFrameworksURL {
            searchPaths.append(url)
        }
        if let url = bundle.builtInPlugInsURL {
            searchPaths.append(url)
        }
        if let url = bundle.executableURL?.deletingLastPathComponent() {
            searchPaths.append(url)
        }

        var result: [URL] = []
        for dir in searchPaths {
            for name in vecExtensionFileNames {
                result.append(dir.appendingPathComponent(name))
            }
        }
        return result
    }

    private func vecTableName(for dimension: Int) -> String {
        "\(vecTableBaseName)_\(dimension)"
    }

    private func vecTriggerName(for dimension: Int) -> String {
        "\(vecTableBaseName)_ad_\(dimension)"
    }

    private func listVecTables() -> [String] {
        guard let db = db else { return [] }
        return (try? syncOnDBQueue {
            let sql = """
                SELECT name FROM sqlite_master
                WHERE type='table' AND name LIKE ?
            """
            let pattern = "\(vecTableBaseName)%"
            let stmt = try db.prepare(sql).bind(pattern)
            var names: [String] = []
            while let row = try stmt.failableNext() {
                if let name = row[0] as? String {
                    names.append(name)
                }
            }
            return names
        }) ?? []
    }

    private func cleanupLegacyVecTableIfNeeded() {
        guard let db = db else { return }
        guard !vecLegacyTableCleaned else { return }
        vecLegacyTableCleaned = true
        syncOnDBQueue {
            do {
                let legacyName = vecTableBaseName
                let sql = "SELECT name FROM sqlite_master WHERE type='table' AND name=? LIMIT 1"
                let exists = (try? db.scalar(sql, legacyName) as? String) != nil
                guard exists else { return }
                try db.run("DROP TABLE IF EXISTS \(legacyName)")
                try db.run("DROP TRIGGER IF EXISTS \(legacyName)_ad")
                log.info("Dropped legacy vec table \(legacyName)")
            } catch {
                log.debug("Failed to clean legacy vec table: \(error.localizedDescription)")
            }
        }
    }

    private func dropVecTables() {
        guard let db = db else { return }
        let tables = listVecTables()
        guard !tables.isEmpty else { return }
        syncOnDBQueue {
            for name in tables {
                do {
                    try db.run("DROP TABLE IF EXISTS \(name)")
                    if let dimension = vecDimension(from: name) {
                        let triggerName = vecTriggerName(for: dimension)
                        try db.run("DROP TRIGGER IF EXISTS \(triggerName)")
                    }
                } catch {
                    log.debug("Failed to drop vec table \(name): \(error.localizedDescription)")
                }
            }
        }
        vecReadyDimensions.removeAll()
    }

    private func vecDimension(from tableName: String) -> Int? {
        let prefix = "\(vecTableBaseName)_"
        guard tableName.hasPrefix(prefix) else { return nil }
        return Int(tableName.dropFirst(prefix.count))
    }

    private func ensureVecTable(dimension: Int) {
        guard vecIndexEnabled, dimension > 0 else { return }
        guard let db = db else { return }
        if vecReadyDimensions.contains(dimension) { return }
        let tableName = vecTableName(for: dimension)
        let triggerName = vecTriggerName(for: dimension)

        syncOnDBQueue {
            do {
                let sql = """
                    CREATE VIRTUAL TABLE IF NOT EXISTS \(tableName) USING vec0(
                        embedding float[\(dimension)]
                    )
                """
                try db.run(sql)
                try db.run("""
                    CREATE TRIGGER IF NOT EXISTS \(triggerName)
                    AFTER DELETE ON ClipboardHistory_embedding BEGIN
                        DELETE FROM \(tableName) WHERE rowid = old.id;
                    END
                """)
                vecReadyDimensions.insert(dimension)
            } catch {
                log.debug("Failed to create vec table: \(error.localizedDescription)")
            }
        }
    }

    private func scheduleVecIndexBackfillIfNeeded() {
        guard vecIndexEnabled else { return }
        let shouldStart = vecBackfillStateQueue.sync {
            if vecBackfillInProgress {
                return false
            }
            vecBackfillInProgress = true
            return true
        }
        guard shouldStart else { return }
        Task(priority: .background) { [weak self] in
            defer {
                self?.vecBackfillStateQueue.sync {
                    self?.vecBackfillInProgress = false
                }
            }
            await self?.backfillVecIndexIfNeeded()
        }
    }

    private func backfillVecIndexIfNeeded() async {
        guard let db = db, vecIndexEnabled else { return }

        let batchSize = 100
        let maxItems = DeckUserDefaults.securityModeEnabled ? 300 : 1000
        var processed = 0
        var offset = 0
        while processed < maxItems {
            guard !Task.isCancelled else { break }

            let rows: [(id: Int64, data: Data)] = syncOnDBQueue {
                do {
                    let sql = """
                        SELECT e.id, e.embedding
                        FROM ClipboardHistory_embedding e
                        ORDER BY e.id ASC
                        LIMIT ? OFFSET ?
                    """
                    let stmt = try db.prepare(sql).bind(batchSize, offset)
                    var result: [(Int64, Data)] = []
                    while let row = try stmt.failableNext() {
                        let idValue = row[0]
                        let dataValue = row[1]
                        let id: Int64
                        if let id64 = idValue as? Int64 {
                            id = id64
                        } else if let idInt = idValue as? Int {
                            id = Int64(idInt)
                        } else {
                            continue
                        }
                        guard let data = bindingToData(dataValue) else { continue }
                        result.append((id, data))
                    }
                    return result
                } catch {
                    return []
                }
            }

            guard !rows.isEmpty else { break }

            for row in rows {
                guard !Task.isCancelled else { break }
                let raw = DeckUserDefaults.securityModeEnabled ? decryptData(row.data) : row.data
                guard let vector = decodeEmbedding(raw) else { continue }
                updateVecIndex(id: row.id, vector: vector)
                processed += 1
            }

            offset += rows.count
            await Task.yield()
        }

        if processed > 0 {
            log.info("Vec index backfill completed: \(processed) items processed")
        }
    }

    private func performIntegrityCheck() -> Bool {
        guard let db = db else { return false }
        let result: String? = syncOnDBQueue {
            (try? db.scalar("PRAGMA quick_check(1)") as? String) ?? nil
        }
        if result == "ok" {
            return true
        }
        log.warn("Database integrity check returned: \(result ?? "unknown")")
        return false
    }

    private func backupDatabaseIfNeeded(
        dbPath: String,
        backupPath: String,
        force: Bool = false,
        synchronous: Bool = false
    ) {
        guard FileManager.default.fileExists(atPath: dbPath) else { return }

        if !force, let attrs = try? FileManager.default.attributesOfItem(atPath: backupPath),
           let modDate = attrs[.modificationDate] as? Date,
           Date().timeIntervalSince(modDate) < backupInterval {
            return
        }

        if let db = db {
            syncOnDBQueue {
                do {
                    try db.run("PRAGMA wal_checkpoint(TRUNCATE)")
                } catch {
                    log.debug("Failed to checkpoint WAL before backup: \(error.localizedDescription)")
                }
            }
        }

        let dbURL = URL(fileURLWithPath: dbPath)
        let backupURL = URL(fileURLWithPath: backupPath)
        let tempURL = URL(fileURLWithPath: backupPath + ".tmp")

        let copyBlock = {
            do {
                if FileManager.default.fileExists(atPath: tempURL.path) {
                    try FileManager.default.removeItem(at: tempURL)
                }
                try FileManager.default.copyItem(at: dbURL, to: tempURL)
                if FileManager.default.fileExists(atPath: backupURL.path) {
                    _ = try FileManager.default.replaceItemAt(backupURL, withItemAt: tempURL)
                } else {
                    try FileManager.default.moveItem(at: tempURL, to: backupURL)
                }
                log.info("Database backup updated")
            } catch {
                log.warn("Failed to backup database: \(error.localizedDescription)")
                if FileManager.default.fileExists(atPath: tempURL.path) {
                    try? FileManager.default.removeItem(at: tempURL)
                }
            }
        }

        if synchronous {
            copyBlock()
        } else {
            DispatchQueue.global(qos: .utility).async(execute: copyBlock)
        }
    }

    private func restoreDatabaseFromBackup(dbPath: String, backupPath: String) -> Bool {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: backupPath) else { return false }

        let dbURL = URL(fileURLWithPath: dbPath)
        let backupURL = URL(fileURLWithPath: backupPath)
        let tempURL = URL(fileURLWithPath: dbPath + ".restore")

        do {
            if fileManager.fileExists(atPath: tempURL.path) {
                try fileManager.removeItem(at: tempURL)
            }
            try fileManager.copyItem(at: backupURL, to: tempURL)
            if fileManager.fileExists(atPath: dbURL.path) {
                _ = try fileManager.replaceItemAt(dbURL, withItemAt: tempURL)
            } else {
                try fileManager.moveItem(at: tempURL, to: dbURL)
            }
            cleanupSQLiteSidecarFiles(for: dbPath)
            log.info("Database restored from backup")
            return true
        } catch {
            log.error("Failed to restore database from backup: \(error.localizedDescription)")
            if fileManager.fileExists(atPath: tempURL.path) {
                try? fileManager.removeItem(at: tempURL)
            }
            return false
        }
    }

    private func cleanupSQLiteSidecarFiles(for dbPath: String) {
        let fileManager = FileManager.default
        let walPath = dbPath + "-wal"
        let shmPath = dbPath + "-shm"
        if fileManager.fileExists(atPath: walPath) {
            try? fileManager.removeItem(atPath: walPath)
        }
        if fileManager.fileExists(atPath: shmPath) {
            try? fileManager.removeItem(atPath: shmPath)
        }
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
                createEmbeddingTable()

                log.info("Database table created successfully")
            }
        } catch {
            log.error("DB queue failed during table creation: \(error.localizedDescription)")
        }
    }

    private func createFTS5Table(forceRecreate: Bool = false, preferTrigram: Bool = true) {
        guard let db = db else { return }

        syncOnDBQueue {
            if forceRecreate {
                do {
                    try db.run("DROP TRIGGER IF EXISTS ClipboardHistory_ai")
                    try db.run("DROP TRIGGER IF EXISTS ClipboardHistory_ad")
                    try db.run("DROP TRIGGER IF EXISTS ClipboardHistory_au")
                    try db.run("DROP TABLE IF EXISTS ClipboardHistory_fts")
                } catch {
                    log.warn("Failed to drop existing FTS5 table/triggers: \(error.localizedDescription)")
                }
            }

            let defaultSQL = """
                CREATE VIRTUAL TABLE IF NOT EXISTS ClipboardHistory_fts USING fts5(
                    search_text,
                    app_name,
                    content='ClipboardHistory',
                    content_rowid='id'
                )
            """

            let trigramSQL = """
                CREATE VIRTUAL TABLE IF NOT EXISTS ClipboardHistory_fts USING fts5(
                    search_text,
                    app_name,
                    content='ClipboardHistory',
                    content_rowid='id',
                    tokenize='trigram'
                )
            """

            var createdWithTrigram = false
            if preferTrigram {
                do {
                    try db.run(trigramSQL)
                    createdWithTrigram = true
                } catch {
                    log.warn("FTS5 trigram tokenizer unavailable, falling back to default: \(error.localizedDescription)")
                    do {
                        try db.run(defaultSQL)
                    } catch {
                        log.error("Failed to create FTS5 table: \(error.localizedDescription)")
                        return
                    }
                }
            } else {
                do {
                    try db.run(defaultSQL)
                } catch {
                    log.error("Failed to create FTS5 table: \(error.localizedDescription)")
                    return
                }
            }

            // Create triggers to keep FTS in sync
            do {
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
            } catch {
                log.error("Failed to create FTS5 triggers: \(error.localizedDescription)")
            }

            ftsUsesTrigram = createdWithTrigram
        }

        updateFTSTokenizerState()
        log.info("FTS5 table and triggers created successfully (trigram=\(ftsUsesTrigram))")
    }

    private func createEmbeddingTable() {
        guard let db = db else { return }

        do {
            try syncOnDBQueue {
                let tab = Table("ClipboardHistory_embedding")
                try db.run(tab.create(ifNotExists: true) { t in
                    t.column(EmbeddingCol.id, primaryKey: true)
                    t.column(EmbeddingCol.textHash)
                    t.column(EmbeddingCol.embedding)
                })

                try db.run("""
                    CREATE TRIGGER IF NOT EXISTS ClipboardHistory_embedding_ad AFTER DELETE ON ClipboardHistory BEGIN
                        DELETE FROM ClipboardHistory_embedding WHERE id = old.id;
                    END
                """)

                log.info("Embedding table and triggers created successfully")
            }
        } catch {
            log.error("DB queue failed during embedding table creation: \(error.localizedDescription)")
        }
    }

    private func updateFTSTokenizerState() {
        guard let db = db else { return }

        let sql = "SELECT sql FROM sqlite_master WHERE type='table' AND name='ClipboardHistory_fts' LIMIT 1"
        let ftsSQL: String? = syncOnDBQueue {
            (try? db.scalar(sql) as? String) ?? nil
        }

        let normalized = ftsSQL?.lowercased() ?? ""
        let compact = normalized.components(separatedBy: .whitespacesAndNewlines).joined()
        ftsUsesTrigram = compact.contains("tokenize='trigram'") || compact.contains("tokenize=\"trigram\"")
        log.debug("FTS5 tokenizer detected: \(ftsUsesTrigram ? "trigram" : "default")")
    }

    private func isFTSTrigramAvailable() -> Bool {
        guard let db = db else { return false }

        let testTable = "ClipboardHistory_fts_trigram_check"
        var available = false

        syncOnDBQueue {
            do {
                try db.run("CREATE VIRTUAL TABLE IF NOT EXISTS \(testTable) USING fts5(content, tokenize='trigram')")
                available = true
            } catch {
                log.debug("FTS5 trigram tokenizer not available: \(error.localizedDescription)")
            }

            do {
                try db.run("DROP TABLE IF EXISTS \(testTable)")
            } catch {
                log.debug("Failed to drop trigram test table: \(error.localizedDescription)")
            }
        }

        return available
    }

    private func ensureFTSTrigramIfAvailable() {
        dbQueue.async { [weak self] in
            guard let self else { return }
            self.updateFTSTokenizerState()
            guard !self.ftsUsesTrigram else { return }
            guard self.isFTSTrigramAvailable() else { return }

            log.info("FTS5 trigram tokenizer available, rebuilding FTS table for CJK support")
            self.createFTS5Table(forceRecreate: true, preferTrigram: true)
            self.rebuildFTSIndex()
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
    /// - 2: 添加语义向量缓存表
    private static let currentSchemaVersion: Int32 = 2

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

        if currentVersion < Self.currentSchemaVersion {
            let basePath = getStoragePath()
            let paths = databasePaths(for: basePath)
            backupDatabaseIfNeeded(
                dbPath: paths.dbPath,
                backupPath: paths.backupPath,
                force: true,
                synchronous: true
            )
        }

        let needsLargeImageMigration = currentVersion < 1
        let needsEmbeddingMigration = currentVersion < 2

        // Migration 0 -> 1: 添加 blob_path 列
        if needsLargeImageMigration {
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

            if needsEmbeddingMigration {
                createEmbeddingTable()
            }

            // 执行大图迁移，完成后再进行语义缓存回填
            let postMigration: (() async -> Void)?
            if needsEmbeddingMigration {
                postMigration = { [weak self] in
                    await self?.performSemanticEmbeddingBackfill()
                }
            } else {
                postMigration = nil
            }
            migrateLargeImagesIfNeeded(
                finalVersion: Self.currentSchemaVersion,
                postMigration: postMigration
            )
            return
        }

        // Migration 1 -> 2: 添加语义向量缓存表
        if needsEmbeddingMigration {
            createEmbeddingTable()
            backfillSemanticEmbeddingsIfNeeded(targetVersion: Self.currentSchemaVersion)
        }

        // 未来的迁移可以继续添加:
        // if currentVersion < 3 { ... }
    }

    private func migrateLargeImagesIfNeeded(
        finalVersion: Int32,
        postMigration: (() async -> Void)? = nil
    ) {
        // 在后台线程执行迁移
        Task(priority: .background) { [weak self] in
            guard let self else { return }
            await self.performLargeImageMigration()
            if let postMigration {
                await postMigration()
            }
            // 迁移完成后更新数据库版本
            self.setSchemaVersion(finalVersion)
            log.info("Database schema updated to version \(finalVersion)")
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

    private func backfillSemanticEmbeddingsIfNeeded(targetVersion: Int32) {
        Task(priority: .background) { [weak self] in
            guard let self else { return }
            await self.performSemanticEmbeddingBackfill()
            self.setSchemaVersion(targetVersion)
            log.info("Database schema updated to version \(targetVersion)")
        }
    }

    private func performSemanticEmbeddingBackfill() async {
        guard let db = db else { return }

        let batchSize = 100
        let maxItems = DeckUserDefaults.securityModeEnabled ? 300 : 1000
        var processed = 0

        while processed < maxItems {
            guard !Task.isCancelled else { break }

            let rows: [(id: Int64, searchText: String)] = withDB {
                let sql = """
                    SELECT ch.id, ch.search_text
                    FROM ClipboardHistory ch
                    LEFT JOIN ClipboardHistory_embedding e ON ch.id = e.id
                    WHERE e.id IS NULL
                    ORDER BY ch.id ASC
                    LIMIT ?
                """
                let stmt = try db.prepare(sql).bind(batchSize)
                var result: [(Int64, String)] = []
                while let row = try stmt.failableNext() {
                    if let id = row[0] as? Int64, let text = row[1] as? String {
                        result.append((id, text))
                    }
                }
                return result
            } ?? []

            guard !rows.isEmpty else { break }

            for row in rows {
                guard !Task.isCancelled else { break }
                let rawText = decryptString(row.searchText)
                let normalized = SemanticSearchService.normalizedSemanticText(rawText)
                guard !normalized.isEmpty else { continue }

                let textHash = SemanticSearchService.semanticTextHash(normalizedText: normalized)
                guard let vector = SemanticSearchService.shared.vector(for: normalized, cacheKey: "i:\(row.id)-\(textHash)") else {
                    continue
                }
                storeSemanticEmbedding(id: row.id, textHash: textHash, vector: vector)
                processed += 1
            }

            await Task.yield()
        }

        if processed > 0 {
            log.info("Semantic embedding backfill completed: \(processed) items processed")
        }
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

    // MARK: - Semantic Embedding Helpers

    private func semanticTextHash(_ text: String) -> String {
        SemanticSearchService.semanticTextHash(text)
    }

    private func bindingToData(_ binding: Binding?) -> Data? {
        if let blob = binding as? Blob {
            return Data(blob.bytes)
        }
        return nil
    }

    private func bindingToInt64(_ binding: Binding?) -> Int64? {
        if let value = binding as? Int64 {
            return value
        }
        if let value = binding as? Int {
            return Int64(value)
        }
        if let value = binding as? NSNumber {
            return value.int64Value
        }
        return nil
    }

    private func bindingToDouble(_ binding: Binding?) -> Double? {
        if let value = binding as? Double {
            return value
        }
        if let value = binding as? Int64 {
            return Double(value)
        }
        if let value = binding as? Int {
            return Double(value)
        }
        if let value = binding as? NSNumber {
            return value.doubleValue
        }
        return nil
    }

    private func encodeEmbedding(_ vector: [Float]) -> Data {
        vector.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    private func decodeEmbedding(_ data: Data) -> [Float]? {
        guard data.count % MemoryLayout<Float>.size == 0 else { return nil }
        return data.withUnsafeBytes { rawBuffer in
            let buffer = rawBuffer.bindMemory(to: Float.self)
            return Array(buffer)
        }
    }

    private func normalizeVector(_ vector: [Float]) -> [Float] {
        guard !vector.isEmpty else { return vector }
        var sum: Double = 0
        for value in vector {
            sum += Double(value) * Double(value)
        }
        let norm = sqrt(sum)
        guard norm.isFinite, norm > 0 else { return vector }
        let scale = Float(1.0 / norm)
        var normalized = vector
        for index in normalized.indices {
            normalized[index] *= scale
        }
        return normalized
    }

    private func vectorToJSONString(_ vector: [Float]) -> String {
        var parts: [String] = []
        parts.reserveCapacity(vector.count)
        for value in vector {
            parts.append(String(format: "%.6f", locale: vecNumberLocale, value))
        }
        return "[\(parts.joined(separator: ","))]"
    }

    private func updateVecIndex(id: Int64, vector: [Float]) {
        guard vecIndexEnabled, !DeckUserDefaults.securityModeEnabled else { return }
        guard let db = db else { return }
        guard !vector.isEmpty else { return }
        let normalized = normalizeVector(vector)
        ensureVecTable(dimension: normalized.count)
        guard vecReadyDimensions.contains(normalized.count) else { return }
        let tableName = vecTableName(for: normalized.count)
        let payload = vectorToJSONString(normalized)
        withDB {
            try db.run("DELETE FROM \(tableName) WHERE rowid = ?", id)
            try db.run(
                "INSERT INTO \(tableName)(rowid, embedding) VALUES (?, ?)",
                id,
                payload
            )
        }
    }

    private func storeSemanticEmbedding(id: Int64, textHash: String, vector: [Float]) {
        guard let db = db else { return }

        let encoded = encodeEmbedding(vector)
        let storedData = DeckUserDefaults.securityModeEnabled ? encryptData(encoded) : encoded
        let tab = Table("ClipboardHistory_embedding")

        withDB {
            let insert = tab.insert(or: .replace,
                                    EmbeddingCol.id <- id,
                                    EmbeddingCol.textHash <- textHash,
                                    EmbeddingCol.embedding <- storedData)
            try db.run(insert)
        }

        updateVecIndex(id: id, vector: vector)
    }

    func scheduleSemanticEmbeddingUpdate(id: Int64, searchText: String) {
        embeddingQueue.async { [weak self] in
            guard let self else { return }
            let normalized = SemanticSearchService.normalizedSemanticText(searchText)
            guard !normalized.isEmpty else { return }
            let textHash = SemanticSearchService.semanticTextHash(normalizedText: normalized)
            guard let vector = SemanticSearchService.shared.vector(for: normalized, cacheKey: "i:\(id)-\(textHash)") else {
                return
            }
            self.storeSemanticEmbedding(id: id, textHash: textHash, vector: vector)
        }
    }

    func scheduleSemanticEmbeddingStore(id: Int64, textHash: String, vector: [Float]) {
        embeddingQueue.async { [weak self] in
            self?.storeSemanticEmbedding(id: id, textHash: textHash, vector: vector)
        }
    }

    func fetchSemanticEmbeddings(for items: [ClipboardItem]) async -> [Int64: [Float]] {
        guard let db = db else { return [:] }

        let ids = items.compactMap { $0.id }
        guard !ids.isEmpty else { return [:] }

        var expectedHashes: [Int64: String] = [:]
        expectedHashes.reserveCapacity(ids.count)
        for item in items {
            if let id = item.id {
                let normalized = SemanticSearchService.normalizedSemanticText(item.searchText)
                guard !normalized.isEmpty else { continue }
                expectedHashes[id] = SemanticSearchService.semanticTextHash(normalizedText: normalized)
            }
        }

        let tab = Table("ClipboardHistory_embedding")
        let query = tab.select(EmbeddingCol.id, EmbeddingCol.textHash, EmbeddingCol.embedding)
            .filter(ids.contains(EmbeddingCol.id))

        return withDB {
            var result: [Int64: [Float]] = [:]
            let rows = Array(try db.prepare(query))
            for row in rows {
                let id = try row.get(EmbeddingCol.id)
                let storedHash = try row.get(EmbeddingCol.textHash)
                guard let expectedHash = expectedHashes[id], expectedHash == storedHash else { continue }
                let rawData = try row.get(EmbeddingCol.embedding)
                let decodedData = DeckUserDefaults.securityModeEnabled ? decryptData(rawData) : rawData
                guard let vector = decodeEmbedding(decodedData) else { continue }
                result[id] = vector
            }
            return result
        } ?? [:]
    }

    var isVecSearchAvailable: Bool {
        vecIndexEnabled && !DeckUserDefaults.securityModeEnabled
    }

    func searchVecIds(queryVector: [Float], limit: Int) async -> [Int64] {
        let candidates = await searchVecCandidates(queryVector: queryVector, limit: limit)
        return candidates.map { $0.id }
    }

    func searchVecCandidates(queryVector: [Float], limit: Int) async -> [(id: Int64, distance: Double)] {
        guard !Task.isCancelled else { return [] }
        guard isVecSearchAvailable else { return [] }
        guard !queryVector.isEmpty else { return [] }

        let normalized = normalizeVector(queryVector)
        guard !normalized.isEmpty else { return [] }
        ensureVecTable(dimension: normalized.count)
        guard vecReadyDimensions.contains(normalized.count) else { return [] }
        guard let db = db else { return [] }

        let tableName = vecTableName(for: normalized.count)
        let payload = vectorToJSONString(normalized)
        return withDB {
            let sql = """
                SELECT rowid, distance FROM \(tableName)
                WHERE embedding MATCH ?
                ORDER BY distance
                LIMIT ?
            """
            let stmt = try db.prepare(sql).bind(payload, limit)
            var rows: [(Int64, Double)] = []
            while let row = try stmt.failableNext() {
                guard let id = bindingToInt64(row[0]),
                      let distance = bindingToDouble(row[1]) else {
                    continue
                }
                rows.append((id, distance))
            }
            return rows
        } ?? []
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

    func clearSearchCache() {
        invalidateSearchCache()
    }

    func shrinkMemory() {
        guard let db = db else { return }
        _ = withDB { try db.run("PRAGMA shrink_memory") }
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
            scheduleSemanticEmbeddingUpdate(id: rowId, searchText: item.searchText)
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
        _ = withDB { try db.run("DELETE FROM ClipboardHistory_embedding") }
        dropVecTables()
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
        var dataToStore = item.data
        if item.blobPath != nil {
            dataToStore = item.previewData ?? item.data
        } else if !item.hasFullData, let fullData = item.loadFullData() {
            dataToStore = fullData
        }

        let encryptedData = encryptData(dataToStore)
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
            scheduleSemanticEmbeddingUpdate(id: id, searchText: item.searchText)
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
            scheduleSemanticEmbeddingUpdate(id: id, searchText: searchText)
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

    private func buildFTSQuery(from keyword: String, useTrigram: Bool) -> String {
        let terms = keyword
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .filter { !useTrigram || $0.count >= ftsTrigramMinQueryLength }
            .map { term -> String in
                let escaped = term
                    .replacingOccurrences(of: "\"", with: "\"\"")
                    .replacingOccurrences(of: "*", with: "")
                if useTrigram {
                    return "\"\(escaped)\""
                }
                return "\"\(escaped)\"*"
            }

        return terms.joined(separator: " OR ")
    }

    private func runFTSQuery(_ ftsQuery: String, limit: Int) -> [Int64] {
        guard let db = db else { return [] }

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

    private func escapeForLike(_ keyword: String) -> String {
        var escaped = keyword
        escaped = escaped.replacingOccurrences(of: "\\", with: "\\\\")
        escaped = escaped.replacingOccurrences(of: "%", with: "\\%")
        escaped = escaped.replacingOccurrences(of: "_", with: "\\_")
        return escaped
    }

    private func searchWithSQLLike(keyword: String, limit: Int) -> [Int64] {
        guard let db = db else { return [] }

        let escaped = escapeForLike(keyword)
        let pattern = "%\(escaped)%"

        return withDB {
            let sql = """
                SELECT id FROM ClipboardHistory
                WHERE search_text LIKE ? ESCAPE '\\'
                   OR app_name LIKE ? ESCAPE '\\'
                ORDER BY timestamp DESC
                LIMIT ?
            """
            let stmt = try db.prepare(sql).bind(pattern, pattern, limit)
            var ids: [Int64] = []
            while let row = try stmt.failableNext() {
                if let id = row[0] as? Int64 {
                    ids.append(id)
                }
            }
            return ids
        } ?? []
    }

    /// Fast full-text search using FTS5
    /// Returns row IDs matching the search term
    func searchFTS(keyword: String, limit: Int = 50) async -> [Int64] {
        guard !Task.isCancelled else { return [] }
        guard db != nil, !keyword.isEmpty else { return [] }

        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)

        // 安全模式下 FTS 索引存储的是加密内容，无法直接匹配
        // 需要使用内存解密搜索
        if DeckUserDefaults.securityModeEnabled {
            return await searchWithLike(keyword: trimmed, limit: limit)
        }

        if ftsUsesTrigram {
            let ftsQuery = buildFTSQuery(from: trimmed, useTrigram: true)
            guard !ftsQuery.isEmpty else {
                return searchWithSQLLike(keyword: trimmed, limit: limit)
            }
            return runFTSQuery(ftsQuery, limit: limit)
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

        // FTS5 默认分词器对 CJK 支持不好，保留内存搜索兜底
        if containsCJK {
            let sqlIds = searchWithSQLLike(keyword: trimmed, limit: limit)
            if !sqlIds.isEmpty {
                return sqlIds
            }
            return await searchWithLike(keyword: trimmed, limit: limit)
        }

        let ftsQuery = buildFTSQuery(from: trimmed, useTrigram: false)
        guard !ftsQuery.isEmpty else { return [] }
        return runFTSQuery(ftsQuery, limit: limit)
    }

    /// In-memory fallback search (security mode or CJK without trigram support)
    /// 安全模式/无 trigram 时使用内存搜索，避免 FTS5 无法匹配
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
    
    func fetchAll(limit: Int = 10000, offset: Int = 0, loadFullData: Bool = false) -> [ClipboardItem] {
        guard let db = db, let table = table else { return [] }
        
        let query = table.order(Col.ts.desc).limit(limit, offset: offset)
        
        let rows = withDB { Array(try db.prepare(query)) } ?? []
        return rows.compactMap { rowToClipboardItem($0, loadFullData: loadFullData) }
    }
    
    func fetch(id: Int64) async -> Row? {
        guard let db = db, let table = table else { return nil }

        let query = table.filter(Col.id == id)

        return withDB { try db.pluck(query) } ?? nil
    }

    /// Fetch raw data payload for a single item (used for lazy loading).
    func fetchData(for id: Int64, isEncrypted: Bool? = nil) -> Data? {
        guard let db = db, let table = table else { return nil }

        let query = table.select(Col.data).filter(Col.id == id).limit(1)

        return withDB { () -> Data? in
            guard let row = try db.pluck(query) else { return nil }
            let rawData = try row.get(Col.data)
            let shouldDecrypt = isEncrypted ?? DeckUserDefaults.securityModeEnabled
            return shouldDecrypt ? decryptData(rawData) : rawData
        } ?? nil
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
    
    func rowToClipboardItem(_ row: Row, isEncrypted: Bool? = nil, loadFullData: Bool = true) -> ClipboardItem? {
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
            let storedItemType = try row.get(Col.itemType)
            
            // Decrypt data if security mode is enabled
            let shouldDecrypt = isEncrypted ?? DeckUserDefaults.securityModeEnabled
            let data = shouldDecrypt ? decryptData(rawData) : rawData
            let previewData = rawPreviewData.map { shouldDecrypt ? decryptData($0) : $0 }
            let searchText = shouldDecrypt ? decryptString(rawSearchText) : rawSearchText

            var inlineData = data
            var dataIsFull = true

            if blobPath != nil {
                dataIsFull = false
            } else if !loadFullData,
                      let itemType = ClipItemType(rawValue: storedItemType),
                      itemType == .image,
                      let preview = previewData,
                      !preview.isEmpty {
                inlineData = preview
                dataIsFull = false
            }
            
            let item = ClipboardItem(
                pasteboardType: PasteboardType(type),
                data: inlineData,
                previewData: previewData,
                timestamp: timestamp,
                appPath: appPath,
                appName: appName,
                searchText: searchText,
                contentLength: length,
                tagId: tagId,
                id: id,
                uniqueId: storedUniqueId,
                blobPath: blobPath,
                dataIsFull: dataIsFull
            )

            if !dataIsFull, blobPath == nil {
                item.setDeferredDataLoader { [weak self] in
                    self?.fetchData(for: id, isEncrypted: shouldDecrypt)
                }
            }

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

        // 迁移语义向量缓存表的加密状态
        await migrateEmbeddingEncryption(encrypt: encrypt)

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

    private func migrateEmbeddingEncryption(encrypt: Bool) async {
        guard let db = db else { return }

        let tab = Table("ClipboardHistory_embedding")
        let batchSize = 200
        var offset = 0

        while true {
            guard !Task.isCancelled else { break }

            let rows: [Row] = withDB {
                let query = tab.select(EmbeddingCol.id, EmbeddingCol.embedding)
                    .order(EmbeddingCol.id.asc)
                    .limit(batchSize, offset: offset)
                return Array(try db.prepare(query))
            } ?? []

            guard !rows.isEmpty else { break }

            for row in rows {
                do {
                    let id = try row.get(EmbeddingCol.id)
                    let rawEmbedding = try row.get(EmbeddingCol.embedding)

                    let newEmbedding: Data
                    if encrypt {
                        newEmbedding = SecurityService.shared.encrypt(rawEmbedding) ?? rawEmbedding
                    } else {
                        newEmbedding = SecurityService.shared.decrypt(rawEmbedding) ?? rawEmbedding
                    }

                    let updateQuery = tab.filter(EmbeddingCol.id == id)
                    withDB {
                        try db.run(updateQuery.update(EmbeddingCol.embedding <- newEmbedding))
                    }
                } catch {
                    continue
                }
            }

            if rows.count < batchSize { break }
            offset += batchSize
            await Task.yield()
        }

        if encrypt {
            dropVecTables()
        } else {
            loadSQLiteVecExtensionIfAvailable()
            if vecIndexEnabled {
                scheduleVecIndexBackfillIfNeeded()
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
