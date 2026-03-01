// Copyright © 2024–2026 Yuze Pan. 保留一切权利。

//
//  DeckSQLManager.swift
//  Deck
//
//  Deck Clipboard Manager - SQLite Database Management
//
//  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  职责边界 (Responsibility Boundaries)
//  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//
//  DeckSQLManager 是 Deck 应用的核心数据持久化层，负责：
//
//  1. **数据库生命周期管理**
//     - 数据库初始化、连接管理、完整性检查
//     - 自动备份/恢复机制（24小时周期）
//     - Schema 迁移和版本控制
//     - 数据库文件损坏时的自动恢复
//
//  2. **剪贴板数据 CRUD**
//     - 插入、查询、更新、删除剪贴板历史记录
//     - 支持文本、图片、文件、URL、颜色等多种类型
//     - 大数据（>512KB）自动分离存储到 BlobStorage
//
//  3. **多维度搜索引擎**
//     - FTS5 全文搜索（支持 trigram 分词）
//     - 正则表达式搜索（安全模式下内存解密后匹配）
//     - 语义向量搜索（基于 sqlite-vec 扩展）
//     - 应用名、标签、类型等结构化过滤
//
//  4. **安全模式集成**
//     - 敏感数据加密存储（data、search_text、app_name、embedding）
//     - 安全模式下禁用向量索引（防止明文泄露）
//     - 搜索时自动解密并缓存（NSCache 限制 300 条）
//
//  5. **性能优化**
//     - 搜索缓存（避免重复解密）
//     - 正则表达式缓存（RegexCache）
//     - 分批流式处理（backfill、迁移）
//     - mmap 优化（128MB）
//
//  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  线程模型 (Threading Model)
//  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//
//  **核心原则：SQLite 连接非线程安全，所有数据库操作必须在 dbQueue 上串行执行**
//
//  1. **dbQueue (DispatchQueue)**
//     - Label: "com.deck.sqlite.queue"
//     - QoS: .userInitiated
//     - 所有读写操作必须通过 `withDB` / `withDBAsync` / `syncOnDBQueue` / `asyncOnDBQueue`
//
//  2. **函数线程约束**
//
//     **必须在 dbQueue 上调用（内部不切队列）：**
//     - `createTable()`, `createFTS5Table()`, `createEmbeddingTable()`
//     - `registerCustomFunctions()` - 注册 REGEXP 函数
//     - `performIntegrityCheck()` - 完整性检查
//     - `ensureVecTable(dimension:)` - 创建向量表
//     - `cleanupLegacyVecTableIfNeeded()` - 清理旧表
//
//     **内部自动切到 dbQueue（可从任意线程调用）：**
//     - `insert(_:)`, `update(_:)`, `delete(_:)` - CRUD 操作
//     - `search(...)`, `searchWithRegex(...)` - 搜索接口
//     - `getRecentItems(...)`, `getItemById(...)` - 查询接口
//     - `storeSemanticEmbedding(...)`, `updateVecIndex(...)` - 向量索引
//     - `backupDatabaseIfNeeded(...)` - 备份操作
//
//     **异步后台任务（Task.priority: .background）：**
//     - `backfillVecIndexIfNeeded()` - 向量索引回填
//     - `performSemanticEmbeddingBackfill()` - 语义嵌入回填
//     - `performLargeImageMigration()` - 大图迁移
//     - `backfillFileSearchTextIfNeeded()` - 文件搜索文本回填
//
//  3. **队列检测机制**
//     - `dbQueueKey: DispatchSpecificKey<Void>` - 检测当前是否在 dbQueue
//     - `syncOnDBQueue` / `asyncOnDBQueue` - 避免重复 dispatch 导致死锁
//
//  4. **embeddingQueue (DispatchQueue)**
//     - Label: "com.deck.semantic.embedding"
//     - QoS: .utility
//     - 用于语义向量计算（与 dbQueue 解耦，避免阻塞数据库操作）
//
//  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  安全模式语义 (Security Mode Semantics)
//  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//
//  **触发条件：** `DeckUserDefaults.securityModeEnabled == true`
//
//  1. **加密列（存储时加密，读取时解密）**
//     - `data` (Col.data) - 剪贴板内容主体
//     - `search_text` (Col.searchText) - 用于全文搜索的文本
//     - `app_name` (Col.appName) - 来源应用名称
//     - `custom_title` (Col.customTitle) - 用户自定义标题
//     - `embedding` (ClipboardHistory_embedding.embedding) - 语义向量
//
//  2. **不可检索列（FTS5 / 向量索引失效）**
//     - **FTS5 全文搜索：** 加密后的 search_text 无法被 FTS5 索引
//       - Fallback: `searchWithRegexInMemory()` - 分批解密后内存匹配
//       - 限制：最多扫描 5000 条，返回前 N 条匹配
//
//     - **向量索引：** 完全禁用（`vecIndexEnabled = false`）
//       - 原因：加密后的向量无法进行相似度计算
//       - Fallback: 语义搜索降级为普通文本搜索
//
//  3. **搜索缓存策略**
//     - `searchTextCache: NSCache<NSNumber, SearchCacheEntry>`
//       - Key: row.id
//       - Value: 解密后的 searchText + appName + customTitle（已 lowercased）
//       - Limit: 300 条（降低常驻内存）
//     - 缓存失效：`reinitialize()` / `invalidateSearchCache()`
//
//  4. **性能权衡**
//     - 安全模式下搜索性能显著下降（需解密）
//     - 向量索引回填限制：300 条（非安全模式 1000 条）
//     - 正则搜索扫描限制：5000 条（分批 500 条）
//
//  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  存储策略 (Storage Strategy)
//  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//
//  1. **存储路径**
//     - 默认路径：`~/Library/Application Support/Deck/Deck.sqlite3`
//     - 自定义路径：支持用户选择（需 security-scoped bookmark）
//     - 备份路径：`Deck.sqlite3.bak`（同目录）
//
//  2. **大数据分离存储（blobPath 机制）**
//     - **触发条件：** `data.count > Const.largeBlobThreshold` (512KB)
//     - **存储流程：**
//       1. 调用 `BlobStorage.shared.storeAsync(data, uniqueId)` 存储到文件系统
//       2. 数据库 `data` 列存储 `previewData`（缩略图/前 N 字节）
//       3. `blob_path` 列存储文件路径（相对路径）
//     - **读取流程：**
//       1. 检查 `blob_path` 是否为 nil
//       2. 若非 nil，调用 `BlobStorage.shared.loadAsync(path)` 加载完整数据
//       3. 若 nil，直接使用 `data` 列
//     - **迁移：** `performLargeImageMigration()` - 分批迁移历史大图
//
//  3. **备份与恢复**
//     - **自动备份：**
//       - 触发：`backupDatabaseIfNeeded()` - 启动时 + 24 小时周期
//       - 方法：`FileManager.copyItem()` - 文件级拷贝
//       - 条件：距上次备份超过 `backupInterval` (24h)
//
//     - **自动恢复：**
//       - 触发时机：
//         1. 启动时主数据库不存在但备份存在
//         2. 完整性检查失败（`performIntegrityCheck()` 返回 false）
//       - 方法：`restoreDatabaseFromBackup()` - 删除损坏文件，拷贝备份
//
//  4. **迁移顺序约束（Schema Migration）**
//     - **版本控制：** `getSchemaVersion()` / `setSchemaVersion()`
//     - **迁移顺序（必须严格按序执行）：**
//
//       ```
//       Version 1 → 2: 添加 tagId 列
//       Version 2 → 3: 添加 blobPath 列
//       Version 3 → 4: 创建 FTS5 表
//       Version 4 → 5: 创建 Embedding 表
//       Version 5 → 6: 大图迁移（异步后台）
//       Version 6 → 7: 语义嵌入回填（异步后台）
//       ```
//
//     - **异步迁移处理：**
//       - Version 5 → 6: `migrateLargeImagesIfNeeded()` - 后台任务
//       - Version 6 → 7: `backfillSemanticEmbeddingsIfNeeded()` - 后台任务
//       - 迁移完成后才更新 schema_version（防止中断导致重复迁移）
//
//     - **迁移失败处理：**
//       - 完整性检查失败 → 尝试从备份恢复
//       - 备份恢复失败 → 发送 `.databaseError` 通知
//       - 连续 3 次错误 → 触发 `attemptDBRecovery()`
//
//  5. **向量索引表（sqlite-vec）**
//     - **表命名规则：** `ClipboardHistory_embedding_vec_{dimension}`
//       - 示例：`ClipboardHistory_embedding_vec_384`（MiniLM）
//       - 示例：`ClipboardHistory_embedding_vec_1024`（Nomic Embed）
//
//     - **动态创建：** `ensureVecTable(dimension:)` - 按需创建
//     - **触发器：** `ClipboardHistory_embedding_vec_ad_{dimension}` - 级联删除
//     - **回填：** `backfillVecIndexIfNeeded()` - 启动时后台回填
//     - **清理：** `cleanupLegacyVecTableIfNeeded()` - 删除旧版无维度后缀的表
//
//  6. **错误恢复机制**
//     - **错误追踪：**
//       - `consecutiveErrorCount` - 连续错误计数
//       - `errorThreshold = 3` - 触发通知阈值
//       - `hasNotifiedUser` - 防止重复通知
//
//     - **关键错误码（触发自动恢复）：**
//       - `SQLITE_IOERR` - 磁盘 I/O 错误
//       - `SQLITE_CORRUPT` - 数据库损坏
//       - `SQLITE_NOTADB` - 文件不是数据库
//       - `SQLITE_READONLY` - 只读错误
//       - `SQLITE_CANTOPEN` - 无法打开
//       - `SQLITE_FULL` - 磁盘已满
//
//     - **恢复流程：**
//       1. `handleDBError()` - 检测错误类型
//       2. `attemptDBRecovery()` - 触发恢复
//       3. `reinitialize()` - 重新初始化数据库
//       4. 从备份恢复（如果可用）
//       5. 发送 `.databaseError` 通知给 UI
//
//  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//

import AppKit
import Foundation
@preconcurrency import SQLite
import SQLite3
import Darwin
import Accelerate

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
    static let customTitle = Expression<String?>("custom_title")
    static let sourceAnchor = Expression<String?>("source_anchor")
    static let searchText = Expression<String>("search_text")
    static let length = Expression<Int>("content_length")
    static let tagId = Expression<Int>("tag_id")
    static let blobPath = Expression<String?>("blob_path")
    static let isTemporary = Expression<Bool>("is_temporary")
    static let isEncrypted = Expression<Bool>("is_encrypted")
}

// MARK: - Maintenance helpers (storage cleanup / rollback snapshot)

extension DeckSQLManager {
    private struct UnsafeRowBatch: @unchecked Sendable {
        let rows: [Row]
    }

    struct PageInfo: Sendable {
        let pageCount: Int64
        let freelistCount: Int64
        let pageSize: Int64

        var freelistBytes: Int64 { freelistCount * pageSize }
    }

    struct BlobRecord: Sendable {
        let id: Int64
        let blobPath: String
    }

    /// Fetch ids matching a filter with minimal IO (select only `id`).
    func fetchIds(filter: Expression<Bool>, limit: Int? = nil) async -> [Int64] {
        await withDBAsyncBackground {
            guard let db = self.db, let table = self.table else { return [] }
            do {
                var query = table.select(Col.id).filter(filter)
                if let limit { query = query.limit(limit) }
                return try db.prepare(query).map { row in row[Col.id] }
            } catch {
                return []
            }
        } ?? []
    }

    /// Fetch `(id, blobPath)` pairs for all rows with a blob path.
    func fetchBlobRecords() async -> [BlobRecord] {
        await withDBAsyncBackground {
            guard let db = self.db, let table = self.table else { return [] }
            do {
                let query = table.select(Col.id, Col.blobPath)
                    .filter(Col.blobPath != nil)
                    .order(Col.id.asc)

                var out: [BlobRecord] = []
                out.reserveCapacity(512)
                for row in try db.prepare(query) {
                    if let blobPath = row[Col.blobPath] {
                        out.append(BlobRecord(id: row[Col.id], blobPath: blobPath))
                    }
                }
                return out
            } catch {
                return []
            }
        } ?? []
    }

    /// Fetch blob paths for a given id list.
    func fetchBlobPaths(ids: [Int64]) async -> [String] {
        guard !ids.isEmpty else { return [] }
        let chunks = ids.chunked(into: 500)
        var out: [String] = []
        out.reserveCapacity(min(ids.count, 1024))

        for chunk in chunks {
            let paths: [String] = await withDBAsyncBackground {
                guard let db = self.db, let table = self.table else { return [] }
                do {
                    let query = table.select(Col.blobPath)
                        .filter(chunk.contains(Col.id) && Col.blobPath != nil)
                    var local: [String] = []
                    for row in try db.prepare(query) {
                        if let p = row[Col.blobPath] { local.append(p) }
                    }
                    return local
                } catch {
                    return []
                }
            } ?? []
            out.append(contentsOf: paths)
            await Task.yield()
        }

        return out
    }

    /// Fetch uniqueIds for a given id list.
    func fetchUniqueIds(ids: [Int64]) async -> [String] {
        guard !ids.isEmpty else { return [] }
        let chunks = ids.chunked(into: 500)
        var out: [String] = []
        out.reserveCapacity(min(ids.count, 1024))

        for chunk in chunks {
            let uids: [String] = await withDBAsyncBackground {
                guard let db = self.db, let table = self.table else { return [] }
                do {
                    let query = table.select(Col.uniqueId)
                        .filter(chunk.contains(Col.id))
                    return try db.prepare(query).map { row in row[Col.uniqueId] }
                } catch {
                    return []
                }
            } ?? []
            out.append(contentsOf: uids)
            await Task.yield()
        }

        return out
    }

    /// Delete rows in safe batches (avoids overly large `IN (...)` queries).
    /// - Returns: total deleted rows as reported by SQLite.
    func deleteBatch(ids: [Int64]) async -> Int {
        guard !ids.isEmpty else { return 0 }

        let chunks = ids.chunked(into: 500)
        let deleted: Int = await withDBAsyncBackground {
            guard let db = self.db, let table = self.table else { return 0 }
            do {
                var total = 0
                try db.transaction {
                    for chunk in chunks {
                        let query = table.filter(chunk.contains(Col.id))
                        total += try db.run(query.delete())
                    }
                }
                // Invalidate once (hot path: avoid repeated cache clears/log spam).
                self.invalidateSearchCache()
                return total
            } catch {
                return 0
            }
        } ?? 0

        return deleted
    }

    /// Export a rollback snapshot database containing the specified ids.
    ///
    /// This creates a small SQLite file with two tables:
    /// - ClipboardHistory
    /// - ClipboardHistory_embedding
    ///
    /// The schema is created via `CREATE TABLE AS SELECT ... WHERE 0` so it stays lightweight.
    func exportSnapshotDatabase(ids: [Int64], to snapshotDBPath: String) async throws {
        guard !ids.isEmpty else { return }

        let ok = await withDBAsyncBackground {
            guard let db = self.db else { return false }
            do {
                let escaped = snapshotDBPath.replacingOccurrences(of: "'", with: "''")

                // Create / replace snapshot db.
                try db.execute("ATTACH DATABASE '\(escaped)' AS snap")
                defer { try? db.execute("DETACH DATABASE snap") }

                try db.execute("DROP TABLE IF EXISTS snap.ClipboardHistory")
                try db.execute("DROP TABLE IF EXISTS snap.ClipboardHistory_embedding")

                try db.execute("CREATE TABLE snap.ClipboardHistory AS SELECT * FROM ClipboardHistory WHERE 0")
                try db.execute("CREATE TABLE snap.ClipboardHistory_embedding AS SELECT * FROM ClipboardHistory_embedding WHERE 0")

                let chunks = ids.chunked(into: 500)
                for chunk in chunks {
                    let idList = chunk.map(String.init).joined(separator: ",")
                    try db.execute("INSERT INTO snap.ClipboardHistory SELECT * FROM ClipboardHistory WHERE id IN (\(idList))")
                    try db.execute("INSERT INTO snap.ClipboardHistory_embedding SELECT * FROM ClipboardHistory_embedding WHERE id IN (\(idList))")
                }

                return true
            } catch {
                return false
            }
        } ?? false

        if !ok {
            throw NSError(domain: "DeckSQLManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to export snapshot database"])
        }
    }

    /// Restore rows from a snapshot database created by `exportSnapshotDatabase`.
    /// - Returns: number of rows in the snapshot table (not necessarily all inserted if conflicts exist).
    func restoreSnapshotDatabase(from snapshotDBPath: String) async throws -> Int {
        let result: (ok: Bool, count: Int) = await withDBAsyncBackground {
            guard let db = self.db else { return (false, 0) }
            do {
                let escaped = snapshotDBPath.replacingOccurrences(of: "'", with: "''")
                try db.execute("ATTACH DATABASE '\(escaped)' AS snap")
                defer { try? db.execute("DETACH DATABASE snap") }

                let total = (try db.scalar("SELECT COUNT(*) FROM snap.ClipboardHistory") as? Int64) ?? 0

                let cols = "id, unique_id, type, item_type, data, preview_data, timestamp, app_path, app_name, custom_title, source_anchor, search_text, content_length, tag_id, blob_path, is_temporary, is_encrypted"
                try db.execute("INSERT OR IGNORE INTO ClipboardHistory (\(cols)) SELECT \(cols) FROM snap.ClipboardHistory")

                // Embeddings are best-effort.
                try? db.execute("INSERT OR IGNORE INTO ClipboardHistory_embedding (id, text_hash, embedding) SELECT id, text_hash, embedding FROM snap.ClipboardHistory_embedding")

                self.invalidateSearchCache()
                return (true, Int(total))
            } catch {
                return (false, 0)
            }
        } ?? (false, 0)

        guard result.ok else {
            throw NSError(domain: "DeckSQLManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to restore snapshot database"])
        }
        return result.count
    }

    /// Gather current DB page statistics.
    func fetchPageInfo() async -> PageInfo {
        await withDBAsyncBackground {
            guard let db = self.db else { return PageInfo(pageCount: 0, freelistCount: 0, pageSize: 4096) }
            do {
                let pageCount = (try db.scalar("PRAGMA page_count") as? Int64) ?? 0
                let freelistCount = (try db.scalar("PRAGMA freelist_count") as? Int64) ?? 0
                let pageSize = (try db.scalar("PRAGMA page_size") as? Int64) ?? 4096
                return PageInfo(pageCount: pageCount, freelistCount: freelistCount, pageSize: pageSize)
            } catch {
                return PageInfo(pageCount: 0, freelistCount: 0, pageSize: 4096)
            }
        } ?? PageInfo(pageCount: 0, freelistCount: 0, pageSize: 4096)
    }

    /// Perform a WAL checkpoint (TRUNCATE).
    func walCheckpointTruncate() async -> Bool {
        await withDBAsyncBackground {
            guard let db = self.db else { return false }
            do {
                try db.execute("PRAGMA wal_checkpoint(TRUNCATE)")
                return true
            } catch {
                return false
            }
        } ?? false
    }

    /// Run SQLite `PRAGMA optimize`.
    func pragmaOptimize() async -> Bool {
        await withDBAsyncBackground {
            guard let db = self.db else { return false }
            do {
                try db.execute("PRAGMA optimize")
                return true
            } catch {
                return false
            }
        } ?? false
    }

    /// Run SQLite `PRAGMA quick_check` and return the first result row (usually "ok").
    func pragmaQuickCheck() async -> String? {
        await withDBAsyncBackground {
            guard let db = self.db else { return nil }
            do {
                return try db.scalar("PRAGMA quick_check") as? String
            } catch {
                return nil
            }
        } ?? nil
    }

    /// Run a VACUUM right now on the background queue.
    func vacuumNow(reason: String) async -> Bool {
        await withDBAsyncBackground {
            guard let db = self.db else { return false }
            do {
                log.info("Running VACUUM (maintenance): \(reason)")
                try db.execute("PRAGMA wal_checkpoint(TRUNCATE)")
                try db.execute("VACUUM")
                return true
            } catch {
                return false
            }
        } ?? false
    }

    /// Fetch all blob paths currently referenced by the database.
    func fetchAllBlobPaths() async -> [String] {
        await withDBAsyncBackground {
            guard let db = self.db, let table = self.table else { return [] }
            do {
                let query = table.select(Col.blobPath).filter(Col.blobPath != nil)
                var out: [String] = []
                out.reserveCapacity(1024)
                for row in try db.prepare(query) {
                    if let p = row[Col.blobPath] { out.append(p) }
                }
                return out
            } catch {
                return []
            }
        } ?? []
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0, !self.isEmpty else { return [] }
        var result: [[Element]] = []
        result.reserveCapacity((count + size - 1) / size)
        var i = 0
        while i < count {
            let end = Swift.min(i + size, count)
            result.append(Array(self[i..<end]))
            i = end
        }
        return result
    }
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
    let customTitle: String

    init(searchText: String, appName: String, customTitle: String) {
        self.searchText = searchText
        self.appName = appName
        self.customTitle = customTitle
    }
}

final class DeckSQLManager: NSObject, @unchecked Sendable {
    static let shared = DeckSQLManager()
    private static var isInitialized = false
    private nonisolated static let initLock = NSLock()

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Thread Safety (线程安全)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    
    /// 数据库操作队列：SQLite 连接非线程安全，所有 DB 操作必须串行执行。
    ///
    /// 这里拆分为 *交互* 与 *后台维护* 两个队列，但它们都 target 到同一个串行 `dbSerialQueue`：
    /// - 好处：
    ///   - 用户触发的搜索/写入依然用 `.userInitiated` 保证响应
    ///   - 后台 backfill / vacuum / migration 等用 `.utility`，避免抢占 CPU/能耗飙升
    ///   - 仍然保证 SQLite 单连接串行访问（不会并发触碰 Connection）
    // Keep the serial queue user-initiated so panel-open queries are not downgraded.
    private let dbSerialQueue = DispatchQueue(label: "com.deck.sqlite.queue.serial", qos: .userInitiated)
    private lazy var dbQueue: DispatchQueue = {
        DispatchQueue(label: "com.deck.sqlite.queue.interactive", qos: .userInitiated, target: dbSerialQueue)
    }()
    private lazy var dbBackgroundQueue: DispatchQueue = {
        DispatchQueue(label: "com.deck.sqlite.queue.background", qos: .utility, target: dbSerialQueue)
    }()
    
    /// 队列检测 Key：用于判断当前代码是否已在 dbQueue 上执行
    /// - 作用：防止重复 dispatch 导致死锁（如在 dbQueue 上再次 sync 到 dbQueue）
    /// - 使用：`DispatchQueue.getSpecific(key: dbQueueKey)` 检测
    private let dbQueueKey = DispatchSpecificKey<Void>()
    
    /// 语义向量计算队列：与 dbQueue 解耦，避免阻塞数据库操作
    /// - Label: "com.deck.semantic.embedding"
    /// - QoS: .utility - 后台任务，不影响用户交互
    /// - 用途：向量编码、相似度计算等 CPU 密集型任务
    private let embeddingQueue = DispatchQueue(label: "com.deck.semantic.embedding", qos: .utility)

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Database Core (数据库核心)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    
    /// SQLite 数据库连接（非线程安全，必须在 dbQueue 上访问）
    private var db: Connection?
    
    /// ClipboardHistory 主表引用
    private var table: Table?

    /// 当前打开的数据库文件路径缓存
    /// - 目的：避免在热路径（每次查询/写入）里反复解析 security-scoped bookmark / 读取 UserDefaults
    /// - 注意：路径变化时会在 `openDatabase`/`reinitialize` 过程中刷新
    private var currentDBPath: String?
    private let dbPathLock = NSLock()

    /// 数据库文件有效性检查节流（避免每次 DB 操作都触发 fileExists/readable 的系统调用）
    private var lastDBFileCheckAt: TimeInterval = 0
    private var lastDBFileCheckResult: Bool = true
    private let dbFileCheckThrottle: TimeInterval = 0.5

    /// 是否可用 UPSERT(unique_id) + RETURNING（取决于 SQLite 版本与 unique index 是否就绪）
    /// - 第一次失败后会自动降级为 delete+insert，避免每次都走异常路径
    private var supportsUniqueIdUpsert: Bool = true

    /// 列表模式下 Data 列投影阈值（与 `rowToClipboardItem(loadFullData: false)` 保持一致）
    private static let listInlineBytesForNonImage = 32 * 1024
    private static let listInlineBytesForFile = 256 * 1024
    private static let listInlineBytesForImageWithoutPreview = 256 * 1024

    /// 列表模式下的 `data` 投影表达式：
    /// - 对于大 payload：返回空 BLOB（X''），避免把大 blob materialize 到 Swift Data
    /// - 对于 image：优先只取 preview_data
    private lazy var listModeProjectedDataExpr: Expression<Data> = {
        Expression<Data>(literal: """
            CASE
                WHEN blob_path IS NOT NULL THEN X''
                WHEN item_type = 'image' AND preview_data IS NOT NULL AND length(preview_data) > 0 THEN X''
                WHEN item_type = 'file' AND content_length > \(Self.listInlineBytesForFile) THEN X''
                WHEN item_type != 'file' AND item_type != 'image' AND content_length > \(Self.listInlineBytesForNonImage) THEN X''
                WHEN item_type = 'image' AND (preview_data IS NULL OR length(preview_data) = 0) AND content_length > \(Self.listInlineBytesForImageWithoutPreview) THEN X''
                ELSE data
            END AS data
            """)
    }()
    
    /// 自定义存储路径的 security-scoped URL（需要在 deinit 时释放）
    private var securityScopedURL: URL?
    /// 保护 security-scoped access 的并发访问
    private let securityScopeLock = NSLock()
    /// 当前是否已成功 startAccessingSecurityScopedResource()
    private var securityScopedAccessActive = false
    
    /// FTS5 是否使用 trigram 分词（支持中文等 CJK 语言）
    private var ftsUsesTrigram = false
    
    /// trigram 分词最小查询长度（少于此长度不触发 FTS5 搜索）
    private let ftsTrigramMinQueryLength = 3
    
    /// 备份文件名
    private let backupFileName = "Deck.sqlite3.bak"
    
    /// 自动备份间隔（24 小时）
    private let backupInterval: TimeInterval = 24 * 60 * 60
    
    /// 初始化失败时间（用于重试退避）
    private var lastInitFailureAt: Date?
    /// 初始化重试退避时间
    private let initRetryBackoff: TimeInterval = 60

    /// Startup integrity check interval (default: 24 hours).
    private let integrityCheckInterval: TimeInterval = 24 * 60 * 60
    private let integrityCheckLastRunKey = "com.deck.sqlite.integrityCheck.lastRun"
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Vector Index (向量索引 - sqlite-vec)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    
    /// 向量表基础名称（实际表名会加上维度后缀，如 _384, _1024）
    private let vecTableBaseName = "ClipboardHistory_embedding_vec"
    
    /// sqlite-vec 扩展文件候选名称（按优先级搜索）
    private let vecExtensionFileNames = [
        "vec0",
        "vec0.dylib",
        "sqlite-vec",
        "sqlite-vec.dylib",
        "libsqlite_vec.dylib"
    ]
    
    /// 向量数值解析使用的 Locale（确保小数点格式一致）
    private let vecNumberLocale = Locale(identifier: "en_US_POSIX")
    
    /// 向量索引是否启用（安全模式下强制禁用）
    private var vecIndexEnabled = false
    
    /// 已创建的向量表维度集合（如 [384, 1024]）
    private var vecReadyDimensions: Set<Int> = []
    
    /// 是否已清理旧版向量表（无维度后缀的表）
    private var vecLegacyTableCleaned = false
    
    /// 向量索引回填是否正在进行（防止重复启动）
    private var vecBackfillInProgress = false
    
    /// 向量回填状态队列（保护 vecBackfillInProgress 的并发访问）
    private let vecBackfillStateQueue = DispatchQueue(label: "com.deck.vec.backfill.state")
    
    /// 已记录缺失维度警告的集合（避免重复日志）
    private var vecMissingDimensionLogged: Set<Int> = []

    /// 已判定不可用的向量维度（当前会话内熔断，避免重复 rebuild 风暴）
    private var vecBrokenDimensions: Set<Int> = []

    /// 已记录不可用维度警告的集合（避免重复日志）
    private var vecBrokenDimensionLogged: Set<Int> = []

    /// 当前维度对应的活跃 vec 表名（支持恢复后切换到新表名）
    private var vecActiveTableNames: [Int: String] = [:]

    /// 正在进行恢复回填的维度集合（防止重复恢复任务）
    private var vecRecoveryInProgressDimensions: Set<Int> = []

    /// 恢复表序号（用于生成唯一表名）
    private var vecRecoverySequence: Int64 = 0

    /// 持久化活跃 vec 表映射（跨重启保持恢复后的读写目标）
    private let vecActiveTablesDefaultsKey = "com.deck.vec.activeTables.v2"

    /// 无法立即清理的旧 vec 表（避免每次恢复都重复尝试）
    private var vecCleanupDeferredTables: Set<String> = []

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Error Tracking (错误追踪与恢复)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    
    /// 连续错误计数（成功操作后重置为 0）
    private var consecutiveErrorCount = 0
    
    /// 最后一次错误发生时间
    private var lastErrorTime: Date?
    
    /// 错误阈值：连续错误达到此值时通知用户
    private let errorThreshold = 3
    
    /// 是否已通知用户（防止重复弹窗）
    private var hasNotifiedUser = false
    /// 是否已提示过加密失败（避免频繁弹窗）
    private var hasNotifiedEncryptionFailure = false
    
    /// 数据库恢复是否正在进行（防止并发恢复）
    private var recoveryInProgress = false
    
    /// 错误状态锁（保护错误计数与通知状态）
    private let errorStateQueue = DispatchQueue(label: "com.deck.sqlite.error.state")
    private let errorStateQueueKey = DispatchSpecificKey<Void>()

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Search Cache (搜索缓存 - 安全模式优化)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    
    /// 搜索缓存：避免重复解密和 lowercased 转换（安全模式下会在失焦时清空）
    /// - Key: row.id (NSNumber)
    /// - Value: SearchCacheEntry (解密且小写化后的 searchText + appName + customTitle)
    /// - Limit: 300 条（平衡性能与内存占用）
    /// - 失效时机：`reinitialize()` / `invalidateSearchCache()`
    private let searchTextCache: NSCache<NSNumber, SearchCacheEntry> = {
        let cache = NSCache<NSNumber, SearchCacheEntry>()
        cache.countLimit = 300  // 限制缓存条目，降低常驻内存
        return cache
    }()

    /// Backfill cache for legacy rows with empty unique_id values.
    /// Keeps a stable generated UUID per row until the DB update succeeds.
    private var pendingUniqueIdBackfill: [Int64: String] = [:]

    /// 单例初始化（设置队列检测机制）
    /// - Note: 设置 `dbQueueKey` 用于检测当前是否在 dbQueue 上执行
    override private init() {
        super.init()
        // 两个队列 target 到同一串行队列，因此三者都设置 specific key，保证死锁检测可靠。
        dbSerialQueue.setSpecific(key: dbQueueKey, value: ())
        dbQueue.setSpecific(key: dbQueueKey, value: ())
        dbBackgroundQueue.setSpecific(key: dbQueueKey, value: ())
        errorStateQueue.setSpecific(key: errorStateQueueKey, value: ())

        // Security mode keeps some plaintext in memory caches (lowercased search strings). Clear them when inactive.
        NotificationCenter.default.addObserver(self, selector: #selector(handleSensitiveCacheInvalidation), name: NSApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleSensitiveCacheInvalidation), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
    }

    @objc private func handleSensitiveCacheInvalidation() {
        guard DeckUserDefaults.securityModeEnabled else { return }
        invalidateSearchCache()
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Thread Safety Wrappers (线程安全包装)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    
    /// 在 dbQueue 上同步执行代码块（防止死锁）
    /// - Parameter work: 需要执行的代码块
    /// - Returns: 代码块的返回值
    /// - Note: 如果当前已在 dbQueue 上，直接执行；否则 sync 到 dbQueue
    /// - Warning: 仅用于内部数据库操作，外部调用应使用 `withDB` / `withDBAsync`
    private func syncOnDBQueue<T>(_ work: () throws -> T) rethrows -> T {
        if DispatchQueue.getSpecific(key: dbQueueKey) != nil {
            return try work()
        }
        return try dbQueue.sync(execute: work)
    }

    /// 在 dbQueue 上异步执行代码块（防止死锁）
    /// - Parameter work: 需要执行的代码块
    /// - Returns: 代码块的返回值
    /// - Note: 如果当前已在 dbQueue 上，直接执行；否则异步切换到 dbQueue
    /// - Warning: 仅用于内部数据库操作，外部调用应使用 `withDB` / `withDBAsync`
    private func asyncOnDBQueue<T>(_ work: @escaping () throws -> T) async throws -> T {
        if DispatchQueue.getSpecific(key: dbQueueKey) != nil {
            return try work()
        }
        return try await withCheckedThrowingContinuation { continuation in
            dbQueue.async {
                do {
                    continuation.resume(returning: try work())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// 在后台维护队列上同步执行代码块（防止死锁）
    /// - Note: 该队列 QoS 更低，适合 migration/backfill/vacuum 等“非交互”工作。
    private func syncOnDBBackgroundQueue<T>(_ work: () throws -> T) rethrows -> T {
        if DispatchQueue.getSpecific(key: dbQueueKey) != nil {
            return try work()
        }
        return try dbBackgroundQueue.sync(flags: .enforceQoS, execute: work)
    }

    /// 在后台维护队列上异步执行代码块（防止死锁）
    private func asyncOnDBBackgroundQueue<T>(_ work: @escaping () throws -> T) async throws -> T {
        if DispatchQueue.getSpecific(key: dbQueueKey) != nil {
            return try work()
        }
        return try await withCheckedThrowingContinuation { continuation in
            dbBackgroundQueue.async(qos: .utility, flags: .enforceQoS) {
                do {
                    continuation.resume(returning: try work())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// 在错误状态队列上同步执行（避免 NSLock 在 async 上下文报错）
    private func syncOnErrorStateQueue<T>(_ work: () -> T) -> T {
        if DispatchQueue.getSpecific(key: errorStateQueueKey) != nil {
            return work()
        }
        return errorStateQueue.sync(execute: work)
    }

    /// 在 dbQueue 上执行数据库操作（带错误处理和文件有效性检查）
    /// - Parameter work: 数据库操作代码块
    /// - Returns: 操作结果，失败时返回 nil
    /// - Note: 自动处理错误、重置错误计数、触发恢复机制
    /// - Warning: 操作失败时会调用 `handleDBError()`，可能触发数据库恢复
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
            syncOnErrorStateQueue {
                consecutiveErrorCount = 0
            }
            return result
        } catch {
            handleDBError(error)
            return nil
        }
    }

    /// 在 dbQueue 上异步执行数据库操作（带错误处理和文件有效性检查）
    /// - Parameter work: 数据库操作代码块
    /// - Returns: 操作结果，失败时返回 nil
    /// - Note: 自动处理错误、重置错误计数、触发恢复机制
    /// - Warning: 操作失败时会调用 `handleDBError()`，可能触发数据库恢复
    @discardableResult
    private func withDBAsync<T>(_ work: @escaping () throws -> T) async -> T? {
        // 在执行数据库操作前检查文件有效性，防止 try! 崩溃
        if !isDatabaseFileValid() {
            await log.warn("Database file is invalid or missing, attempting to reinitialize...")
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
            let result = try await asyncOnDBQueue(work)
            // 操作成功，重置错误计数
            syncOnErrorStateQueue {
                consecutiveErrorCount = 0
            }
            return result
        } catch {
            handleDBError(error)
            return nil
        }
    }

    /// 在后台维护队列上异步执行数据库操作（带错误处理与文件有效性检查）。
    ///
    /// 适用场景：migrations / backfills / VACUUM / 大批量重算等。
    /// 这样可以避免这些任务在 `.userInitiated` 下和用户交互抢 CPU，显著降低能耗与卡顿风险。
    @discardableResult
    private func withDBAsyncBackground<T>(_ work: @escaping () throws -> T) async -> T? {
        if !isDatabaseFileValid() {
            await log.warn("Database file is invalid or missing, attempting to reinitialize...")
            handleDBError(NSError(domain: "DeckSQL", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Database file is invalid or missing"
            ]))
            DispatchQueue.main.async { [weak self] in
                self?.reinitialize()
            }
            return nil
        }

        do {
            let result = try await asyncOnDBBackgroundQueue(work)
            syncOnErrorStateQueue {
                consecutiveErrorCount = 0
            }
            return result
        } catch {
            handleDBError(error)
            return nil
        }
    }

    /// 检查数据库文件是否存在且可访问
    /// 在数据库操作前调用，防止因文件被删除而导致 try! 崩溃
    private func isDatabaseFileValid() -> Bool {
        let now = Date().timeIntervalSince1970

        // Throttle the expensive filesystem checks on hot paths (search/pagination).
        dbPathLock.lock()
        let cachedPath = currentDBPath
        let lastAt = lastDBFileCheckAt
        let lastResult = lastDBFileCheckResult
        dbPathLock.unlock()

        if now - lastAt < dbFileCheckThrottle {
            return lastResult
        }

        let dbPath: String
        if let cachedPath {
            dbPath = cachedPath
        } else {
            // Fallback: resolve once, then cache.
            let basePath = getStoragePath()
            dbPath = databasePaths(for: basePath).dbPath
            dbPathLock.lock()
            currentDBPath = dbPath
            dbPathLock.unlock()
        }

        let fm = FileManager.default
        let ok = fm.fileExists(atPath: dbPath) && fm.isReadableFile(atPath: dbPath)

        dbPathLock.lock()
        lastDBFileCheckAt = now
        lastDBFileCheckResult = ok
        dbPathLock.unlock()

        return ok
    }

    /// 处理数据库错误并在必要时通知用户
    private func handleDBError(_ error: Error) {
        let details = extractDBErrorDetails(error)
        let errorMessage = details.message
        let errorCount = syncOnErrorStateQueue {
            consecutiveErrorCount += 1
            lastErrorTime = Date()
            return consecutiveErrorCount
        }

        log.error("DB operation failed (\(errorCount)/\(errorThreshold)): \(errorMessage) (domain=\(details.domain), code=\(details.code))")
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
            } else {
                syncOnErrorStateQueue {
                    if consecutiveErrorCount >= errorThreshold {
                        consecutiveErrorCount = 0
                    }
                }
            }
            return
        }

        let (shouldNotify, shouldAttemptRecovery) = syncOnErrorStateQueue { () -> (Bool, Bool) in
            if (consecutiveErrorCount >= errorThreshold || isCritical) && !hasNotifiedUser {
                hasNotifiedUser = true
                let shouldAttemptRecovery = details.isSQLiteDomain && isCritical
                return (true, shouldAttemptRecovery)
            }
            return (false, false)
        }

        if shouldAttemptRecovery {
            attemptDBRecovery(reason: "Critical SQLite error")
        }
        if shouldNotify {
            notifyUserOfDBError(errorMessage, isCritical: isCritical)
        }
    }

    private func attemptDBRecovery(reason: String) {
        let shouldProceed = syncOnErrorStateQueue {
            if recoveryInProgress {
                return false
            }
            recoveryInProgress = true
            return true
        }
        guard shouldProceed else { return }
        log.warn("Attempting database recovery: \(reason)")
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.reinitialize()
            self.syncOnErrorStateQueue {
                self.recoveryInProgress = false
            }
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
        syncOnErrorStateQueue {
            consecutiveErrorCount = 0
            hasNotifiedUser = false
            hasNotifiedEncryptionFailure = false
            lastErrorTime = nil
        }
    }

    /// 检查数据库健康状态
    func checkDatabaseHealth() -> (isHealthy: Bool, message: String) {
        guard syncOnDBQueue({ db != nil }) else {
            return (false, NSLocalizedString("数据库连接未建立", comment: "Database health: connection not established"))
        }

        // 检查数据库是否可读写
        let canWrite = withDB {
            guard let db = self.db else { return false }
            return (try db.scalar("SELECT 1") as? Int64) == 1
        } ?? false

        if !canWrite {
            return (false, NSLocalizedString("数据库无法正常访问", comment: "Database health: cannot access"))
        }

        // 检查最近是否有错误
        let recentErrorCount = syncOnErrorStateQueue { consecutiveErrorCount }
        if recentErrorCount > 0 {
            return (
                false,
                String(
                    format: NSLocalizedString("最近有 %d 次数据库操作失败", comment: "Database health: recent error count"),
                    recentErrorCount
                )
            )
        }

        // 轻量完整性检查（用于用户主动诊断）
        if !performIntegrityCheck() {
            return (false, NSLocalizedString("数据库完整性检查未通过", comment: "Database health: integrity check failed"))
        }

        return (true, NSLocalizedString("数据库运行正常", comment: "Database health: healthy"))
    }
    
    func setup() {
        initializeDatabase()
    }
    
    func reinitialize() {
        stopSecurityScopedAccess()
        Self.initLock.lock()
        Self.isInitialized = false
        Self.initLock.unlock()
        syncOnDBQueue {
            db = nil
            table = nil
            dbPathLock.lock()
            currentDBPath = nil
            lastDBFileCheckAt = 0
            lastDBFileCheckResult = true
            dbPathLock.unlock()
            vecReadyDimensions.removeAll()
            vecMissingDimensionLogged.removeAll()
            vecBrokenDimensions.removeAll()
            vecBrokenDimensionLogged.removeAll()
            vecActiveTableNames.removeAll()
            vecRecoveryInProgressDimensions.removeAll()
            vecCleanupDeferredTables.removeAll()
            vecRecoverySequence = 0
            vecIndexEnabled = false
            vecLegacyTableCleaned = false
            ftsUsesTrigram = false
        }
        invalidateSearchCache()  // 清空搜索缓存
        initializeDatabase()
    }
    
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Database Initialization (数据库初始化)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    
    /// 初始化数据库（线程安全，支持重复调用）
    /// - Note: 使用 `initLock` 确保只初始化一次
    /// - 执行流程：
    ///   1. 检查 `isInitialized` 标志，避免重复初始化
    ///   2. 获取存储路径（默认或自定义）
    ///   3. 创建数据库目录（如果不存在）
    ///   4. 检查是否需要从备份恢复
    ///   5. 打开数据库连接
    ///   6. 执行完整性检查，失败时尝试从备份恢复
    ///   7. 注册自定义函数（REGEXP）
    ///   8. 创建表结构
    ///   9. 应用 Schema 迁移
    ///   10. 启动后台任务（FTS trigram、备份、回填）
    private func initializeDatabase() {
        Self.initLock.lock()
        defer { Self.initLock.unlock() }

        if let lastFailure = lastInitFailureAt,
           Date().timeIntervalSince(lastFailure) < initRetryBackoff {
            return
        }

        guard !Self.isInitialized else { return }
        
        let basePath = getStoragePath()
        let paths = databasePaths(for: basePath)
        let dbPath = paths.dbPath
        let backupPath = paths.backupPath
        let backupEnabled = DeckUserDefaults.databaseAutoBackupEnabled
        
        var isDir = ObjCBool(false)
        if !FileManager.default.fileExists(atPath: basePath, isDirectory: &isDir) || !isDir.boolValue {
            do {
                try FileManager.default.createDirectory(atPath: basePath, withIntermediateDirectories: true)
            } catch {
                lastInitFailureAt = Date()
                log.error("Failed to create database directory: \(error.localizedDescription)")
                return
            }
        }

        if !backupEnabled {
            removeRecoveryBackupFiles(at: backupPath)
        }
        
        var restoredFromBackupAtStartup = false
        if backupEnabled,
            !FileManager.default.fileExists(atPath: dbPath) &&
            FileManager.default.fileExists(atPath: backupPath) {
            if restoreDatabaseFromBackup(dbPath: dbPath, backupPath: backupPath) {
                restoredFromBackupAtStartup = true
                log.info("Restored database from backup at startup")
            }
        }

        do {
            try syncOnDBQueue {
                try openDatabase(at: dbPath)

                if !performIntegrityCheckIfNeeded(force: restoredFromBackupAtStartup) {
                    log.warn("Database integrity check failed, attempting to restore from backup")
                    db = nil
                    if backupEnabled {
                        if restoreDatabaseFromBackup(dbPath: dbPath, backupPath: backupPath) {
                            try openDatabase(at: dbPath)
                            if !performIntegrityCheckIfNeeded(force: true) {
                                handleDBError(NSError(domain: "DeckSQL", code: -2, userInfo: [
                                    NSLocalizedDescriptionKey: "Database integrity check failed after restore"
                                ]))
                            }
                        } else {
                            handleDBError(NSError(domain: "DeckSQL", code: -3, userInfo: [
                                NSLocalizedDescriptionKey: "Database integrity check failed and no backup available"
                            ]))
                        }
                    } else {
                        handleDBError(NSError(domain: "DeckSQL", code: -4, userInfo: [
                            NSLocalizedDescriptionKey: "Database integrity check failed and automatic backups are disabled"
                        ]))
                    }
                }

                log.info("Database initialized at: \(dbPath)")
                Self.isInitialized = true
                lastInitFailureAt = nil
                registerCustomFunctions()
                createTable()
                applyMigrations()
            }

            backfillFileSearchTextIfNeeded()
            Task { @MainActor in
                DeckSQLManager.shared.ensureFTSTrigramIfAvailable()
            }
            if backupEnabled {
                Task {
                    DeckSQLManager.shared.backupDatabaseIfNeeded(dbPath: dbPath, backupPath: backupPath)
                }
            }
        } catch {
            lastInitFailureAt = Date()
            log.error("Database connection error: \(error.localizedDescription)")
        }
    }
    
    private func getStoragePath() -> String {
        var basePath: String

        if DeckUserDefaults.useCustomStorage {
            if let bookmarkData = DeckUserDefaults.storageBookmark {
                basePath = resolveSecurityScopedStoragePath(from: bookmarkData)
            } else if let customPath = DeckUserDefaults.customStoragePath {
                stopSecurityScopedAccess()
                basePath = customPath
            } else {
                stopSecurityScopedAccess()
                basePath = defaultStoragePath()
            }
        } else {
            stopSecurityScopedAccess()
            basePath = defaultStoragePath()
        }

        return (basePath as NSString).appendingPathComponent("Deck")
    }

    private func resolveSecurityScopedStoragePath(from bookmarkData: Data) -> String {
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            let result = ensureSecurityScopedAccess(for: url)
            if result.success {
                if result.didStart {
                    log.debug("Restored security-scoped access to \(url.path)")
                }
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
                return url.path
            }
        } catch {
            log.error("Failed to resolve bookmark: \(error)")
        }

        stopSecurityScopedAccess()
        return defaultStoragePath()
    }

    private func ensureSecurityScopedAccess(for url: URL) -> (success: Bool, didStart: Bool) {
        securityScopeLock.lock()
        defer { securityScopeLock.unlock() }

        if let currentURL = securityScopedURL,
           securityScopedAccessActive,
           currentURL.path == url.path {
            return (true, false)
        }

        if securityScopedAccessActive {
            securityScopedURL?.stopAccessingSecurityScopedResource()
            securityScopedAccessActive = false
            securityScopedURL = nil
        }

        guard url.startAccessingSecurityScopedResource() else {
            securityScopedURL = nil
            securityScopedAccessActive = false
            return (false, false)
        }

        securityScopedURL = url
        securityScopedAccessActive = true
        return (true, true)
    }

    private func stopSecurityScopedAccess() {
        securityScopeLock.lock()
        defer { securityScopeLock.unlock() }

        guard securityScopedAccessActive else {
            securityScopedURL = nil
            return
        }

        securityScopedURL?.stopAccessingSecurityScopedResource()
        securityScopedURL = nil
        securityScopedAccessActive = false
    }
    
    private func defaultStoragePath() -> String {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.path
            ?? (NSHomeDirectory() as NSString).appendingPathComponent("Library/Application Support")
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
        vecMissingDimensionLogged.removeAll()
        vecBrokenDimensions.removeAll()
        vecBrokenDimensionLogged.removeAll()
        vecRecoveryInProgressDimensions.removeAll()
        vecCleanupDeferredTables.removeAll()
        vecRecoverySequence = 0
        loadPersistedVecActiveTables()
        db = try Connection(dbPath)
        db?.busyTimeout = 5.0
        // Cache the opened db path so validity checks don't resolve security-scoped bookmarks on every query.
        dbPathLock.lock()
        currentDBPath = dbPath
        lastDBFileCheckAt = 0
        lastDBFileCheckResult = true
        dbPathLock.unlock()
        if let db = db {
            // Use a modest mmap size to reduce read overhead without inflating heap usage.
            do {
                try db.run("PRAGMA mmap_size = 134217728") // 128MB
            } catch {
                log.debug("Failed to set mmap_size: \(error.localizedDescription)")
            }
            // High-impact pragmas for a clipboard-history workload:
            // - WAL: readers don't block writers; fewer "database is locked" stalls under frequent inserts.
            // - synchronous NORMAL: good durability/perf tradeoff for WAL on desktop.
            // - temp_store MEMORY: reduce temp file I/O during sorts.
            // - cache_size: keep hot pages in memory; negative means KB.
            // - wal_autocheckpoint: cap WAL growth to keep checkpoint cost bounded.
            do { _ = try db.scalar("PRAGMA journal_mode = WAL") } catch { log.debug("Failed to set journal_mode WAL: \(error.localizedDescription)") }
            do { _ = try db.scalar("PRAGMA synchronous = NORMAL") } catch { log.debug("Failed to set synchronous NORMAL: \(error.localizedDescription)") }
            do { _ = try db.scalar("PRAGMA temp_store = MEMORY") } catch { log.debug("Failed to set temp_store MEMORY: \(error.localizedDescription)") }
            do { _ = try db.scalar("PRAGMA cache_size = -20000") } catch { log.debug("Failed to set cache_size: \(error.localizedDescription)") } // ~20MB
            do { _ = try db.scalar("PRAGMA wal_autocheckpoint = 1000") } catch { log.debug("Failed to set wal_autocheckpoint: \(error.localizedDescription)") }
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
        syncOnDBQueue {
            guard let db = db else { return }
            guard !DeckUserDefaults.securityModeEnabled else { return }

            var error: UnsafeMutablePointer<Int8>?
            // sqlite-vec is compiled with SQLITE_CORE, so pApi can be nil.
            let rc = sqlite3_vec_init(db.handle, &error, nil)
            if rc == SQLITE_OK {
                vecIndexEnabled = true
                log.info("sqlite-vec initialized via sqlite3_vec_init (static)")
                log.debug("sqlite-vec registered on db handle: \(String(describing: db.handle))")
                cleanupLegacyVecTableIfNeeded()
                scheduleVecIndexBackfillIfNeeded()
                return
            }

            let message = error.map { String(cString: $0) } ?? "unknown error"
            if let error { sqlite3_free(error) }
            vecIndexEnabled = false
            log.debug("sqlite-vec init failed (rc=\(rc)): \(message)")
        }
    }

    private func loadSQLiteVecExtensionIfAvailable() {
        // Static init succeeded; skip dynamic extension loading.
        if vecIndexEnabled { return }
        guard !DeckUserDefaults.securityModeEnabled else { return }

        let candidates = vecExtensionCandidateURLs()
        guard let url = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            log.debug("sqlite-vec extension not found, vector index disabled")
            return
        }

        guard let api = resolveSQLiteLoadExtensionAPI() else {
            log.debug("SQLite load_extension API not available, vector index disabled")
            return
        }

        let didEnable = syncOnDBQueue { () -> Bool in
            guard let db = db else { return false }
            if vecIndexEnabled {
                return true
            }
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
            return vecIndexEnabled
        }

        if didEnable {
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

    private func loadPersistedVecActiveTables() {
        guard let data = UserDefaults.standard.data(forKey: vecActiveTablesDefaultsKey),
              let raw = try? JSONDecoder().decode([String: String].self, from: data) else {
            vecActiveTableNames = [:]
            return
        }
        var mapped: [Int: String] = [:]
        for (dimensionText, tableName) in raw {
            guard let dimension = Int(dimensionText), dimension > 0 else { continue }
            guard !tableName.isEmpty else { continue }
            let defaultName = vecDefaultTableName(for: dimension)
            // 默认表是天然回退目标，不需要持久化；只持久化恢复表映射。
            guard tableName != defaultName else { continue }
            mapped[dimension] = tableName
        }
        vecActiveTableNames = mapped
    }

    private func persistVecActiveTables() {
        let persisted = vecActiveTableNames.filter { (dimension, tableName) in
            !tableName.isEmpty && tableName != vecDefaultTableName(for: dimension)
        }
        guard !persisted.isEmpty else {
            UserDefaults.standard.removeObject(forKey: vecActiveTablesDefaultsKey)
            return
        }
        let raw = Dictionary(uniqueKeysWithValues: persisted.map { (String($0.key), $0.value) })
        if let data = try? JSONEncoder().encode(raw) {
            UserDefaults.standard.set(data, forKey: vecActiveTablesDefaultsKey)
        }
    }

    private func vecDefaultTableName(for dimension: Int) -> String {
        "\(vecTableBaseName)_\(dimension)"
    }

    private func vecRecoveryTableName(for dimension: Int) -> String {
        vecRecoverySequence += 1
        let ts = Int(Date().timeIntervalSince1970)
        return "\(vecTableBaseName)_recovery_\(dimension)_\(ts)_\(vecRecoverySequence)"
    }

    private func vecTableName(for dimension: Int) -> String {
        vecActiveTableNames[dimension] ?? vecDefaultTableName(for: dimension)
    }

    private func setVecActiveTableName(dimension: Int, tableName: String) {
        guard dimension > 0 else { return }
        let defaultName = vecDefaultTableName(for: dimension)
        if tableName == defaultName {
            guard vecActiveTableNames.removeValue(forKey: dimension) != nil else { return }
            persistVecActiveTables()
            return
        }
        guard vecActiveTableNames[dimension] != tableName else { return }
        vecActiveTableNames[dimension] = tableName
        persistVecActiveTables()
    }

    private func vecLegacyTriggerName(for dimension: Int) -> String {
        "\(vecTableBaseName)_ad_\(dimension)"
    }

    private func vecTriggerName(for tableName: String) -> String {
        "\(tableName)_ad"
    }

    private func vecTriggerName(for tableName: String, dimension: Int) -> String {
        tableName == vecDefaultTableName(for: dimension)
            ? vecLegacyTriggerName(for: dimension)
            : vecTriggerName(for: tableName)
    }

    private func vecTableExists(_ tableName: String, db: Connection) -> Bool {
        let sql = "SELECT name FROM sqlite_master WHERE type='table' AND name=? LIMIT 1"
        return (try? db.scalar(sql, tableName) as? String) != nil
    }

    private func listVecTables() -> [String] {
        return (try? syncOnDBQueue {
            guard let db = db else { return [] }
            let sql = """
                SELECT name FROM sqlite_master
                WHERE type='table'
                  AND name LIKE ?
                  AND sql IS NOT NULL
                  AND sql LIKE 'CREATE VIRTUAL TABLE%'
                  AND instr(lower(sql), 'using vec0') > 0
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

    private func listVecTables(for dimension: Int, db: Connection) -> [String] {
        guard dimension > 0 else { return [] }
        let defaultName = vecDefaultTableName(for: dimension)
        let recoveryPattern = "\(vecTableBaseName)_recovery_\(dimension)_%"
        do {
            let sql = """
                SELECT name FROM sqlite_master
                WHERE type='table'
                  AND (name = ? OR name LIKE ?)
                  AND sql IS NOT NULL
                  AND sql LIKE 'CREATE VIRTUAL TABLE%'
                  AND instr(lower(sql), 'using vec0') > 0
                ORDER BY name
            """
            let stmt = try db.prepare(sql).bind(defaultName, recoveryPattern)
            var names: [String] = []
            while let row = try stmt.failableNext() {
                if let name = row[0] as? String {
                    names.append(name)
                }
            }
            return names
        } catch {
            return []
        }
    }

    private func resolveVecActiveTableName(dimension: Int, db: Connection) -> String {
        let defaultName = vecDefaultTableName(for: dimension)
        let recoveryPrefix = "\(vecTableBaseName)_recovery_\(dimension)_"
        let tables = listVecTables(for: dimension, db: db)
        let latestRecovery = tables.filter { $0.hasPrefix(recoveryPrefix) }.sorted().last

        if let active = vecActiveTableNames[dimension] {
            if vecTableExists(active, db: db) {
                if active.hasPrefix(recoveryPrefix) {
                    return active
                }
                if let latestRecovery {
                    if latestRecovery != active {
                        setVecActiveTableName(dimension: dimension, tableName: latestRecovery)
                    }
                    return latestRecovery
                }
                return active
            }
            vecActiveTableNames.removeValue(forKey: dimension)
            persistVecActiveTables()
        }

        if let latestRecovery {
            setVecActiveTableName(dimension: dimension, tableName: latestRecovery)
            return latestRecovery
        }
        setVecActiveTableName(dimension: dimension, tableName: defaultName)
        return defaultName
    }

    private func cleanupObsoleteVecTables(dimension: Int, activeTableName: String, db: Connection) {
        let tables = listVecTables(for: dimension, db: db)
        guard !tables.isEmpty else { return }
        let defaultName = vecDefaultTableName(for: dimension)
        for name in tables where name != activeTableName {
            guard !vecCleanupDeferredTables.contains(name) else { continue }
            var triggerNames = [vecTriggerName(for: name)]
            if name == defaultName {
                triggerNames.append(vecLegacyTriggerName(for: dimension))
            }
            for triggerName in Set(triggerNames) {
                do {
                    try db.run("DROP TRIGGER IF EXISTS \(triggerName)")
                } catch {
                    log.debug("Failed to drop vec trigger \(triggerName): \(error.localizedDescription)")
                }
            }
            if dropVecTableWithShadowCleanup(name, db: db) {
                vecCleanupDeferredTables.remove(name)
                log.info("Dropped obsolete vec table \(name)")
            } else {
                if vecCleanupDeferredTables.insert(name).inserted {
                    log.warn("Deferred obsolete vec table cleanup for \(name); will retry after future reinitialize")
                }
            }
        }
    }

    @discardableResult
    private func dropVecTableWithShadowCleanup(_ tableName: String, db: Connection) -> Bool {
        do {
            try db.run("DROP TABLE IF EXISTS \(tableName)")
            return true
        } catch {
            let merged = "\(error.localizedDescription) \(String(reflecting: error))".lowercased()
            if merged.contains("shadow") || merged.contains("may not be dropped") {
                // sqlite-vec 的 shadow 表不可直接 drop，延后到后续重启再清理即可。
                log.debug("Vec table \(tableName) cleanup deferred due to shadow dependency: \(error.localizedDescription)")
                return false
            }
            log.debug("Failed to drop vec table \(tableName): \(error.localizedDescription)")
            return false
        }
    }

    private func cleanupLegacyVecTableIfNeeded() {
        syncOnDBQueue {
            guard let db = db else { return }
            guard !vecLegacyTableCleaned else { return }
            vecLegacyTableCleaned = true
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
        syncOnDBQueue {
            guard let db = db else { return }
            let tables = listVecTables()
            for name in tables {
                do {
                    if let dimension = vecDimension(from: name) {
                        var triggerNames = [vecTriggerName(for: name)]
                        if name == vecDefaultTableName(for: dimension) {
                            triggerNames.append(vecLegacyTriggerName(for: dimension))
                        }
                        for triggerName in Set(triggerNames) {
                            try db.run("DROP TRIGGER IF EXISTS \(triggerName)")
                        }
                    }
                    try db.run("DROP TABLE IF EXISTS \(name)")
                } catch {
                    log.debug("Failed to drop vec table \(name): \(error.localizedDescription)")
                }
            }
            vecReadyDimensions.removeAll()
            vecBrokenDimensions.removeAll()
            vecBrokenDimensionLogged.removeAll()
            vecRecoveryInProgressDimensions.removeAll()
            vecCleanupDeferredTables.removeAll()
            vecRecoverySequence = 0
            vecActiveTableNames.removeAll()
            persistVecActiveTables()
        }
    }

    private func vecDimension(from tableName: String) -> Int? {
        let defaultPrefix = "\(vecTableBaseName)_"
        if tableName.hasPrefix(defaultPrefix),
           let value = Int(tableName.dropFirst(defaultPrefix.count)) {
            return value
        }

        let recoveryPrefix = "\(vecTableBaseName)_recovery_"
        guard tableName.hasPrefix(recoveryPrefix) else { return nil }
        let suffix = tableName.dropFirst(recoveryPrefix.count)
        guard let dimensionPart = suffix.split(separator: "_").first else { return nil }
        return Int(dimensionPart)
    }

    private func isVecInternalSQLiteError(_ error: Error) -> Bool {
        let nsError = error as NSError
        let merged = "\(nsError.localizedDescription) \(String(reflecting: error))".lowercased()
        return merged.contains("sqlite-vec") ||
               merged.contains("vec0") ||
               merged.contains("rowids get chunk position") ||
               merged.contains("could not fetch vector data") ||
               merged.contains("opening blob failed") ||
               merged.contains("vector blob")
    }

    private func isVecDimensionUsable(_ dimension: Int) -> Bool {
        guard dimension > 0 else { return false }
        guard !vecBrokenDimensions.contains(dimension) else {
            if vecBrokenDimensionLogged.insert(dimension).inserted {
                log.warn("Vec dimension \(dimension) temporarily disabled; vec index/search will use fallback until background recovery completes")
            }
            return false
        }
        return true
    }

    private func scheduleVecRecoveryBackfill(dimension: Int, db: Connection, reason: String) {
        guard dimension > 0 else { return }
        guard !vecRecoveryInProgressDimensions.contains(dimension) else { return }

        let recoveryTableName = vecRecoveryTableName(for: dimension)
        let createSQL = """
            CREATE VIRTUAL TABLE IF NOT EXISTS \(recoveryTableName) USING vec0(
                embedding float[\(dimension)]
            )
        """

        do {
            try db.run(createSQL)
            vecRecoveryInProgressDimensions.insert(dimension)
            vecReadyDimensions.remove(dimension)
            vecMissingDimensionLogged.remove(dimension)
            vecBrokenDimensions.insert(dimension)
            vecBrokenDimensionLogged.remove(dimension)
            log.warn("Vec recovery started for dim=\(dimension), table=\(recoveryTableName), reason=\(reason)")
            Task(priority: .background) { [weak self] in
                await self?.performVecRecoveryBackfill(
                    dimension: dimension,
                    recoveryTableName: recoveryTableName,
                    reason: reason
                )
            }
        } catch {
            vecBrokenDimensions.insert(dimension)
            log.error("Failed to create vec recovery table \(recoveryTableName): \(error.localizedDescription)")
            log.debug("Vec recovery create detail (\(recoveryTableName)): \(String(reflecting: error))")
        }
    }

    private func performVecRecoveryBackfill(dimension: Int, recoveryTableName: String, reason: String) async {
        let indexed: Int? = await withDBAsyncBackground {
            guard self.vecIndexEnabled, !DeckUserDefaults.securityModeEnabled else { return nil }
            guard let db = self.db else { return nil }
            guard self.vecRecoveryInProgressDimensions.contains(dimension) else { return nil }
            guard self.vecTableExists(recoveryTableName, db: db) else { return nil }

            let rowBytes = dimension * MemoryLayout<Float>.size
            let selectSQL = """
                SELECT id, embedding
                FROM ClipboardHistory_embedding
                WHERE length(embedding) = ?
                ORDER BY id DESC
            """

            let selectStmt = try db.prepare(selectSQL).bind(rowBytes)
            var indexed = 0
            try db.transaction {
                while let row = try selectStmt.failableNext() {
                    guard let id = self.bindingToInt64(row[0]),
                          let rawData = self.bindingToData(row[1]) else {
                        continue
                    }
                    let decoded = DeckUserDefaults.securityModeEnabled ? self.decryptData(rawData) : rawData
                    guard let vector = self.decodeEmbedding(decoded), vector.count == dimension else {
                        continue
                    }
                    let normalized = self.normalizeVector(vector)
                    guard !normalized.isEmpty else { continue }
                    let payload = self.vectorToJSONString(normalized)
                    try db.run(
                        "INSERT OR REPLACE INTO \(recoveryTableName)(rowid, embedding) VALUES (?, ?)",
                        id,
                        payload
                    )
                    indexed += 1
                }
            }

            let triggerName = self.vecTriggerName(for: recoveryTableName, dimension: dimension)
            try db.run("""
                CREATE TRIGGER IF NOT EXISTS \(triggerName)
                AFTER DELETE ON ClipboardHistory_embedding BEGIN
                    DELETE FROM \(recoveryTableName) WHERE rowid = old.id;
                END
            """)

            self.setVecActiveTableName(dimension: dimension, tableName: recoveryTableName)
            self.vecReadyDimensions.insert(dimension)
            self.vecBrokenDimensions.remove(dimension)
            self.vecBrokenDimensionLogged.remove(dimension)
            self.vecMissingDimensionLogged.remove(dimension)
            self.vecRecoveryInProgressDimensions.remove(dimension)
            self.cleanupObsoleteVecTables(dimension: dimension, activeTableName: recoveryTableName, db: db)
            return indexed
        } ?? nil

        if let indexed {
            await log.warn("Vec recovery completed for dim=\(dimension), table=\(recoveryTableName), indexed=\(indexed), reason=\(reason)")
        } else {
            syncOnDBQueue {
                vecRecoveryInProgressDimensions.remove(dimension)
                vecReadyDimensions.remove(dimension)
                vecBrokenDimensions.insert(dimension)
            }
            await log.error("Vec recovery failed for dim=\(dimension), table=\(recoveryTableName)")
        }
    }

    @discardableResult
    private func rebuildVecTable(dimension: Int, db: Connection, reason: String) -> Bool {
        guard dimension > 0 else { return false }
        scheduleVecRecoveryBackfill(dimension: dimension, db: db, reason: reason)
        // Recovery is asynchronous; caller should not retry vec write in current call.
        return false
    }

    private func ensureVecTable(dimension: Int) {
        syncOnDBQueue {
            guard vecIndexEnabled, dimension > 0 else { return }
            guard isVecDimensionUsable(dimension) else { return }
            guard let db = db else { return }
            if vecReadyDimensions.contains(dimension) { return }
            let tableName = resolveVecActiveTableName(dimension: dimension, db: db)
            let triggerName = vecTriggerName(for: tableName, dimension: dimension)
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
                setVecActiveTableName(dimension: dimension, tableName: tableName)
                vecReadyDimensions.insert(dimension)
            } catch {
                log.debug("Failed to create vec table: \(error.localizedDescription)")
                if isVecInternalSQLiteError(error) {
                    scheduleVecRecoveryBackfill(dimension: dimension, db: db, reason: "ensure vec table internal error")
                }
            }
        }
    }

    /// Returns true only when embeddings exist and all vec tables are empty.
    private func shouldScheduleVecIndexBackfill() -> Bool {
        return syncOnDBQueue {
            guard vecIndexEnabled, !DeckUserDefaults.securityModeEnabled else { return false }
            guard let db = db else { return false }

            guard (try? db.scalar("SELECT 1 FROM ClipboardHistory_embedding LIMIT 1")) != nil else {
                return false
            }

            let tables = listVecTables()
            for name in tables {
                do {
                    if (try db.scalar("SELECT rowid FROM \(name) LIMIT 1")) != nil {
                        return false
                    }
                } catch {
                    continue
                }
            }

            return true
        }
    }

    private func scheduleVecIndexBackfillIfNeeded() {
        guard shouldScheduleVecIndexBackfill() else {
            log.debug("Vec index backfill not needed; skip scheduling")
            return
        }
        let shouldStart = vecBackfillStateQueue.sync {
            if vecBackfillInProgress {
                return false
            }
            vecBackfillInProgress = true
            return true
        }
        guard shouldStart else {
            log.debug("Vec index backfill already in progress; skip scheduling")
            return
        }
        log.info("Vec index backfill started")
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
        guard shouldScheduleVecIndexBackfill() else { return }

        let batchSize = 100
        let maxItems = DeckUserDefaults.securityModeEnabled ? 300 : 1000
        var attempted = 0
        var indexed = 0
        var offset = 0
        var dimensionCounts: [Int: Int] = [:]
        while attempted < maxItems {
            guard !Task.isCancelled else { break }

            let rows: [(id: Int64, data: Data)] = syncOnDBBackgroundQueue {
                guard let db = db else { return [] }
                do {
                    let sql = """
                        SELECT e.id, e.embedding
                        FROM ClipboardHistory_embedding e
                        ORDER BY e.id DESC
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
                dimensionCounts[vector.count, default: 0] += 1
                if updateVecIndex(id: row.id, vector: vector) {
                    indexed += 1
                }
                attempted += 1
                if attempted >= maxItems { break }
            }

            offset += rows.count
            await Task.yield()
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        if attempted > 0 {
            let dimensionSummary = dimensionCounts
                .sorted(by: { $0.key < $1.key })
                .map { "\($0.key):\($0.value)" }
                .joined(separator: ", ")
            await log.info("Vec index backfill completed: attempted=\(attempted), indexed=\(indexed) (dims: [\(dimensionSummary)])")
        } else {
            await log.debug("Vec index backfill completed: attempted=0, indexed=0")
        }
    }

    private func performIntegrityCheckIfNeeded(force: Bool = false) -> Bool {
        if !force {
            if let lastRun = UserDefaults.standard.object(forKey: integrityCheckLastRunKey) as? Date {
                if Date().timeIntervalSince(lastRun) < integrityCheckInterval {
                    return true
                }
            }
        }

        let ok = performIntegrityCheck()
        if ok {
            UserDefaults.standard.set(Date(), forKey: integrityCheckLastRunKey)
        }
        return ok
    }

    private func performIntegrityCheck() -> Bool {
        let result: String? = syncOnDBQueue {
            guard let db = db else { return nil }
            return (try? db.scalar("PRAGMA quick_check(1)") as? String) ?? nil
        }
        if result == "ok" {
            return true
        }
        log.warn("Database integrity check returned: \(result ?? "unknown")")
        return false
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Backup & Recovery (备份与恢复)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    /// 获取数据库恢复备份文件路径（Deck.sqlite3.bak）
    func getDatabaseRecoveryBackupPath() -> String {
        let basePath = getStoragePath()
        return databasePaths(for: basePath).backupPath
    }

    /// 立即创建数据库恢复备份（可选同步执行）
    func createDatabaseRecoveryBackupNow(synchronous: Bool = false) {
        let basePath = getStoragePath()
        let paths = databasePaths(for: basePath)
        backupDatabaseIfNeeded(
            dbPath: paths.dbPath,
            backupPath: paths.backupPath,
            force: true,
            synchronous: synchronous
        )
    }

    /// 删除数据库恢复备份文件
    func deleteDatabaseRecoveryBackup() {
        let basePath = getStoragePath()
        let backupPath = databasePaths(for: basePath).backupPath
        removeRecoveryBackupFiles(at: backupPath)
    }

    /// 立即从数据库恢复备份还原数据库
    /// - Returns: 是否恢复成功
    func restoreDatabaseRecoveryBackupNow() -> Bool {
        guard DeckUserDefaults.databaseAutoBackupEnabled else {
            log.warn("Recovery backup restore skipped because automatic backup is disabled")
            return false
        }

        let basePath = getStoragePath()
        let paths = databasePaths(for: basePath)
        guard FileManager.default.fileExists(atPath: paths.backupPath) else {
            log.warn("Recovery backup restore skipped because backup file is missing")
            return false
        }

        return syncOnDBQueue {
            db = nil
            table = nil
            return restoreDatabaseFromBackup(dbPath: paths.dbPath, backupPath: paths.backupPath)
        }
    }

    private func removeRecoveryBackupFiles(at backupPath: String) {
        let fileManager = FileManager.default
        let tempPath = backupPath + ".tmp"
        if fileManager.fileExists(atPath: backupPath) {
            try? fileManager.removeItem(atPath: backupPath)
        }
        if fileManager.fileExists(atPath: tempPath) {
            try? fileManager.removeItem(atPath: tempPath)
        }
    }
    
    /// 自动备份数据库（如果需要）
    /// - Parameters:
    ///   - dbPath: 数据库文件路径
    ///   - backupPath: 备份文件路径
    ///   - force: 是否强制备份（忽略时间间隔）
    ///   - synchronous: 是否同步执行（默认异步）
    /// - Note: 默认 24 小时备份一次，使用文件拷贝方式
    /// - Warning: 备份失败不会影响数据库正常运行
    private func backupDatabaseIfNeeded(
        dbPath: String,
        backupPath: String,
        force: Bool = false,
        synchronous: Bool = false
    ) {
        guard DeckUserDefaults.databaseAutoBackupEnabled else { return }
        guard FileManager.default.fileExists(atPath: dbPath) else { return }

        if !force, let attrs = try? FileManager.default.attributesOfItem(atPath: backupPath),
           let modDate = attrs[.modificationDate] as? Date,
           Date().timeIntervalSince(modDate) < backupInterval {
            return
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

        let backupBlock = { [weak self] in
            guard let self, let db = self.db else { return }
            do {
                try db.run("PRAGMA wal_checkpoint(TRUNCATE)")
            } catch {
                log.debug("Failed to checkpoint WAL before backup: \(error.localizedDescription)")
            }
            copyBlock()
        }

        if synchronous {
            syncOnDBQueue {
                backupBlock()
            }
        } else {
            dbQueue.async {
                backupBlock()
            }
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
        syncOnDBQueue {
            guard let db = db else { return }

            // 注册 REGEXP 函数：regexp(pattern, text) -> Bool
            // 使用方式：WHERE search_text REGEXP 'pattern'
            db.createFunction("regexp", argumentCount: 2, deterministic: true) { args in
                guard args.count == 2,
                      let pattern = args[0] as? String,
                      let text = args[1] as? String else {
                    return Int64(0)
                }

                // 使用缓存的正则表达式
                guard let regex = RegexCache.shared.regex(for: pattern) else {
                    return Int64(0)
                }

                let range = NSRange(text.startIndex..., in: text)
                let isMatch = regex.firstMatch(in: text, range: range) != nil
                return isMatch ? Int64(1) : Int64(0)
            }
            log.debug("Registered custom REGEXP function for SQLite")
        }
    }

    /// 使用正则表达式搜索（在数据库层执行）
    func searchWithRegex(
        pattern: String,
        typeFilter: [String]? = nil,
        tagId: Int? = nil,
        limit: Int = 50
    ) async -> [Row] {
        guard !Task.isCancelled else { return [] }

        // 安全模式下需要内存解密后再匹配正则
        if DeckUserDefaults.securityModeEnabled {
            return await searchWithRegexInMemory(
                pattern: pattern,
                typeFilter: typeFilter,
                tagId: tagId,
                limit: limit
            )
        }

        return await withDBAsync {
            guard let db = self.db, let table = self.table else { return [] }
            // 构建查询
            let escapedPattern = pattern.replacingOccurrences(of: "'", with: "''")
            var query = self.listModeBaseQuery(table: table).filter(
                Expression<Bool>(
                    literal: "regexp('\(escapedPattern)', search_text) OR regexp('\(escapedPattern)', custom_title) OR regexp('\(escapedPattern)', app_name)"
                )
            )

            if let types = typeFilter, !types.isEmpty {
                query = query.filter(types.contains(Col.itemType))
            }

            if let tagId = tagId, tagId != -1 {
                query = query.filter(Col.tagId == tagId)
            }

            query = query.order(Col.ts.desc, Col.id.desc).limit(limit)

            return Array(try db.prepare(query))
        } ?? []
    }

    /// 安全模式下的正则搜索：在内存中解密后匹配
    /// 采用分批流式扫描，覆盖更多数据
    private func searchWithRegexInMemory(
        pattern: String,
        typeFilter: [String]?,
        tagId: Int?,
        limit: Int
    ) async -> [Row] {
        guard let regex = RegexCache.shared.regex(for: pattern) else { return [] }

        var matchingIds: [Int64] = []
        matchingIds.reserveCapacity(limit)
        let batchSize = 500
        // 关键优化：用 keyset pagination 替代 OFFSET 扫描
        var cursor: RowCursor? = nil
        var scanned = 0
        let dynamicScanFloor = max(limit * 50, 1000)
        let maxScan = min(5000, dynamicScanFloor)  // 安全模式下最多扫描 5000 条

        while matchingIds.count < limit && scanned < maxScan {
            // 支持任务取消
            guard !Task.isCancelled else { break }

            let rows: [Row] = await withDBAsync {
                guard let db = self.db, let table = self.table else { return [] }
                // 构建基础查询
                var query = table
                    .select(Col.id, Col.ts, Col.searchText, Col.appName, Col.customTitle)
                    .order(Col.ts.desc, Col.id.desc)
                    .limit(batchSize)

                if let cursor {
                    let cursorFilter = (Col.ts < cursor.timestamp) || (Col.ts == cursor.timestamp && Col.id < cursor.id)
                    query = query.filter(cursorFilter)
                }

                if let types = typeFilter, !types.isEmpty {
                    query = query.filter(types.contains(Col.itemType))
                }

                if let tagId = tagId, tagId != -1 {
                    query = query.filter(Col.tagId == tagId)
                }

                return Array(try db.prepare(query))
            } ?? []

            // 没有更多数据
            if rows.isEmpty { break }

            cursor = self.cursor(from: rows.last)

            for row in rows {
                guard matchingIds.count < limit else { break }
                guard !Task.isCancelled else { break }

                do {
                    let id = try row.get(Col.id)
                    let rawSearchText = try row.get(Col.searchText)
                    let rawAppName = try row.get(Col.appName)
                    let rawCustomTitle = (try? row.get(Col.customTitle)) ?? nil

                    let searchText = decryptString(rawSearchText)
                    let appName = decryptString(rawAppName)
                    let customTitle = rawCustomTitle.map { decryptString($0) } ?? ""

                    if !customTitle.isEmpty {
                        let range = NSRange(customTitle.startIndex..., in: customTitle)
                        if regex.firstMatch(in: customTitle, range: range) != nil {
                            matchingIds.append(id)
                            continue
                        }
                    }

                    if !searchText.isEmpty {
                        let range = NSRange(searchText.startIndex..., in: searchText)
                        if regex.firstMatch(in: searchText, range: range) != nil {
                            matchingIds.append(id)
                            continue
                        }
                    }

                    if !appName.isEmpty {
                        let range = NSRange(appName.startIndex..., in: appName)
                        if regex.firstMatch(in: appName, range: range) != nil {
                            matchingIds.append(id)
                            continue
                        }
                    }

                    if customTitle.isEmpty && searchText.isEmpty && appName.isEmpty {
                        let empty = ""
                        let range = NSRange(empty.startIndex..., in: empty)
                        if regex.firstMatch(in: empty, range: range) != nil {
                            matchingIds.append(id)
                        }
                    }
                } catch {
                    continue
                }
            }

            scanned += rows.count
            if rows.count < batchSize { break }

            // 批次间让出 CPU
            await Task.yield()
        }

        if scanned >= maxScan && matchingIds.count < limit {
            await log.info("Security mode regex search reached scan limit (\(maxScan) items), results may be incomplete")
        }

        guard !matchingIds.isEmpty else { return [] }

        // 分块查询避免 SQLite 变量上限
        let chunkSize = 900
        var fullRows: [Row] = []
        fullRows.reserveCapacity(matchingIds.count)
        var start = 0
        while start < matchingIds.count {
            let end = min(start + chunkSize, matchingIds.count)
            let chunk = Array(matchingIds[start..<end])
            let chunkRows: [Row] = await withDBAsync {
                guard let db = self.db, let table = self.table else { return [] }
                var query = self.listModeBaseQuery(table: table).filter(chunk.contains(Col.id))

                if let types = typeFilter, !types.isEmpty {
                    query = query.filter(types.contains(Col.itemType))
                }

                if let tagId = tagId, tagId != -1 {
                    query = query.filter(Col.tagId == tagId)
                }

                return Array(try db.prepare(query))
            } ?? []
            fullRows.append(contentsOf: chunkRows)
            start = end
        }

        var rowsById: [Int64: Row] = [:]
        rowsById.reserveCapacity(fullRows.count)
        for row in fullRows {
            if let id = try? row.get(Col.id) {
                rowsById[id] = row
            }
        }

        return matchingIds.compactMap { rowsById[$0] }
    }

    private func createTable() {
        do {
            try syncOnDBQueue {
                guard let db = db else { return }
                let tab = Table("ClipboardHistory")
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
                    t.column(Col.customTitle)
                    t.column(Col.sourceAnchor)
                    t.column(Col.searchText)
                    t.column(Col.length)
                    t.column(Col.tagId, defaultValue: -1)
                    t.column(Col.blobPath)
                    t.column(Col.isTemporary, defaultValue: false)
                    t.column(Col.isEncrypted, defaultValue: false)
                })

                try db.run(tab.createIndex(Col.ts, ifNotExists: true))
                // Composite index for stable (timestamp,id) ordering.
                // - Keyset pagination depends on this to avoid OFFSET scans.
                // - Also reduces sort work when many rows share the same timestamp.
                do {
                    try db.run("""
                        CREATE INDEX IF NOT EXISTS idx_clipboardhistory_ts_id
                        ON ClipboardHistory(timestamp DESC, id DESC)
                        """)
                } catch {
                    log.debug("Failed to create idx_clipboardhistory_ts_id: \(error.localizedDescription)")
                }
                // Create a partial unique index for non-empty unique_id to avoid sync duplicates.
                do {
                    try db.run("""
                        CREATE UNIQUE INDEX IF NOT EXISTS idx_clipboardhistory_unique_id
                        ON ClipboardHistory(unique_id)
                        WHERE unique_id <> ''
                        """)
                } catch {
                    log.error("Failed to create unique index for unique_id, attempting deduplication: \(error)")
                    do {
                        try db.run("""
                            DELETE FROM ClipboardHistory
                            WHERE unique_id <> ''
                              AND id NOT IN (
                                SELECT MAX(id) FROM ClipboardHistory
                                WHERE unique_id <> ''
                                GROUP BY unique_id
                              )
                            """)
                        try db.run("""
                            CREATE UNIQUE INDEX IF NOT EXISTS idx_clipboardhistory_unique_id
                            ON ClipboardHistory(unique_id)
                            WHERE unique_id <> ''
                            """)
                    } catch {
                        log.error("Deduplication/unique index creation failed, falling back to non-unique index: \(error)")
                        _ = try? db.run(tab.createIndex(Col.uniqueId, ifNotExists: true))
                    }
                }
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
        syncOnDBQueue {
            guard let db = db else { return }
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
                    custom_title,
                    content='ClipboardHistory',
                    content_rowid='id'
                )
            """

            let trigramSQL = """
                CREATE VIRTUAL TABLE IF NOT EXISTS ClipboardHistory_fts USING fts5(
                    search_text,
                    app_name,
                    custom_title,
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
                        INSERT INTO ClipboardHistory_fts(rowid, search_text, app_name, custom_title)
                        VALUES (new.id, new.search_text, new.app_name, new.custom_title);
                    END
                """)

                try db.run("""
                    CREATE TRIGGER IF NOT EXISTS ClipboardHistory_ad AFTER DELETE ON ClipboardHistory BEGIN
                        INSERT INTO ClipboardHistory_fts(ClipboardHistory_fts, rowid, search_text, app_name, custom_title)
                        VALUES ('delete', old.id, old.search_text, old.app_name, old.custom_title);
                    END
                """)

                try db.run("""
                    CREATE TRIGGER IF NOT EXISTS ClipboardHistory_au AFTER UPDATE ON ClipboardHistory BEGIN
                        INSERT INTO ClipboardHistory_fts(ClipboardHistory_fts, rowid, search_text, app_name, custom_title)
                        VALUES ('delete', old.id, old.search_text, old.app_name, old.custom_title);
                        INSERT INTO ClipboardHistory_fts(rowid, search_text, app_name, custom_title)
                        VALUES (new.id, new.search_text, new.app_name, new.custom_title);
                    END
                """)
            } catch {
                log.error("Failed to create FTS5 triggers: \(error.localizedDescription)")
            }

            ftsUsesTrigram = createdWithTrigram
        }

        updateFTSTokenizerState()
        let usesTrigram = syncOnDBQueue { ftsUsesTrigram }
        log.info("FTS5 table and triggers created successfully (trigram=\(usesTrigram))")
    }

    private func createEmbeddingTable() {
        do {
            try syncOnDBQueue {
                guard let db = db else { return }
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
        syncOnDBQueue {
            guard let db = db else { return }

            let sql = "SELECT sql FROM sqlite_master WHERE type='table' AND name='ClipboardHistory_fts' LIMIT 1"
            let ftsSQL: String? = (try? db.scalar(sql) as? String) ?? nil

            let normalized = ftsSQL?.lowercased() ?? ""
            let compact = normalized.components(separatedBy: .whitespacesAndNewlines).joined()
            ftsUsesTrigram = compact.contains("tokenize='trigram'") || compact.contains("tokenize=\"trigram\"")
            log.debug("FTS5 tokenizer detected: \(ftsUsesTrigram ? "trigram" : "default")")
        }
    }

    private func isFTSTrigramAvailable() -> Bool {
        syncOnDBQueue {
            guard let db = db else { return false }
            let testTable = "ClipboardHistory_fts_trigram_check"
            var available = false

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

            return available
        }
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
        if withDB({
            guard let db = self.db else { return false }
            try db.run("INSERT INTO ClipboardHistory_fts(ClipboardHistory_fts) VALUES ('rebuild')")
            return true
        }) == true {
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
    /// - 3: 添加 is_temporary 列
    /// - 4: 添加 source_anchor 列（IDE 溯源元数据）
    /// - 5: 添加 is_encrypted 列（逐行加密状态）
    /// - 6: 添加 custom_title 列（自定义标题）
    private static let currentSchemaVersion: Int32 = 6
    private static let fileSearchTextBackfillTargetVersion = 1

    private func getSchemaVersion() -> Int32 {
        return withDB {
            guard let db = self.db else { return 0 }
            return Int32(try db.scalar("PRAGMA user_version") as? Int64 ?? 0)
        } ?? 0
    }

    private func setSchemaVersion(_ version: Int32) {
        withDB {
            guard let db = self.db else { return }
            try db.run("PRAGMA user_version = \(version)")
        }
    }

    private func applyMigrations() {
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
        let needsTemporaryMigration = currentVersion < 3
        let needsSourceAnchorMigration = currentVersion < 4
        let needsEncryptionStateMigration = currentVersion < 5
        let needsCustomTitleMigration = currentVersion < 6

        let applyCustomTitleMigrationIfNeeded = { [weak self] in
            guard let self, needsCustomTitleMigration else { return }
            self.addCustomTitleColumnIfNeeded()
            self.rebuildFTSForCustomTitleMigration()
        }

        // Migration 0 -> 1: 添加 blob_path 列
        if needsLargeImageMigration {
            withDB {
                guard let db = self.db else { return }
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

            if needsTemporaryMigration {
                addTemporaryColumnIfNeeded()
            }
            if needsSourceAnchorMigration {
                addSourceAnchorColumnIfNeeded()
            }
            if needsEncryptionStateMigration {
                addEncryptionStateColumnIfNeeded()
            }
            applyCustomTitleMigrationIfNeeded()

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
            if needsTemporaryMigration {
                addTemporaryColumnIfNeeded()
            }
            if needsSourceAnchorMigration {
                addSourceAnchorColumnIfNeeded()
            }
            if needsEncryptionStateMigration {
                addEncryptionStateColumnIfNeeded()
            }
            applyCustomTitleMigrationIfNeeded()
            backfillSemanticEmbeddingsIfNeeded(targetVersion: Self.currentSchemaVersion)
            return
        }

        if needsTemporaryMigration || needsSourceAnchorMigration || needsEncryptionStateMigration || needsCustomTitleMigration {
            if needsTemporaryMigration {
                addTemporaryColumnIfNeeded()
            }
            if needsSourceAnchorMigration {
                addSourceAnchorColumnIfNeeded()
            }
            if needsEncryptionStateMigration {
                addEncryptionStateColumnIfNeeded()
            }
            applyCustomTitleMigrationIfNeeded()
            setSchemaVersion(Self.currentSchemaVersion)
        }

        // 未来的迁移可以继续添加:
    }

    private func addTemporaryColumnIfNeeded() {
        withDB {
            guard let db = self.db else { return }
            let stmt = try db.prepare("PRAGMA table_info(ClipboardHistory)")
            var columns: [String] = []
            while let row = try stmt.failableNext() {
                if let name = row[1] as? String {
                    columns.append(name)
                }
            }
            guard !columns.contains("is_temporary") else { return }
            try db.run("ALTER TABLE ClipboardHistory ADD COLUMN is_temporary INTEGER NOT NULL DEFAULT 0")
            log.info("Added is_temporary column for temporary items")
        }
    }

    private func addSourceAnchorColumnIfNeeded() {
        withDB {
            guard let db = self.db else { return }
            let stmt = try db.prepare("PRAGMA table_info(ClipboardHistory)")
            var columns: [String] = []
            while let row = try stmt.failableNext() {
                if let name = row[1] as? String {
                    columns.append(name)
                }
            }
            guard !columns.contains("source_anchor") else { return }
            try db.run("ALTER TABLE ClipboardHistory ADD COLUMN source_anchor TEXT")
            log.info("Added source_anchor column for IDE anchors")
        }
    }

    private func addEncryptionStateColumnIfNeeded() {
        withDB {
            guard let db = self.db else { return }
            let stmt = try db.prepare("PRAGMA table_info(ClipboardHistory)")
            var columns: [String] = []
            while let row = try stmt.failableNext() {
                if let name = row[1] as? String {
                    columns.append(name)
                }
            }
            guard !columns.contains("is_encrypted") else { return }
            try db.run("ALTER TABLE ClipboardHistory ADD COLUMN is_encrypted INTEGER NOT NULL DEFAULT 0")
            let encryptedValue = DeckUserDefaults.securityModeEnabled ? 1 : 0
            try db.run("UPDATE ClipboardHistory SET is_encrypted = ?", encryptedValue)
            log.info("Added is_encrypted column for encryption state")
        }
    }

    private func addCustomTitleColumnIfNeeded() {
        withDB {
            guard let db = self.db else { return }
            let stmt = try db.prepare("PRAGMA table_info(ClipboardHistory)")
            var columns: [String] = []
            while let row = try stmt.failableNext() {
                if let name = row[1] as? String {
                    columns.append(name)
                }
            }
            guard !columns.contains("custom_title") else { return }
            try db.run("ALTER TABLE ClipboardHistory ADD COLUMN custom_title TEXT")
            log.info("Added custom_title column for user-defined titles")
        }
    }

    private func rebuildFTSForCustomTitleMigration() {
        let preferTrigram = syncOnDBQueue { ftsUsesTrigram }
        createFTS5Table(forceRecreate: true, preferTrigram: preferTrigram)
        rebuildFTSIndex()
    }

    private func backfillFileSearchTextIfNeeded() {
        guard DeckUserDefaults.fileSearchTextBackfillVersion < Self.fileSearchTextBackfillTargetVersion else { return }

        Task(priority: .background) { [weak self] in
            guard let self else { return }
            await self.performFileSearchTextBackfill()
            DeckUserDefaults.fileSearchTextBackfillVersion = Self.fileSearchTextBackfillTargetVersion
        }
    }

    private func performFileSearchTextBackfill() async {
        let batchSize = 200
        var offset = 0
        var updated = 0

        while true {
            guard !Task.isCancelled else { break }

            let rows: [Row] = await withDBAsyncBackground {
                guard let db = self.db, let table = self.table else { return [] }
                let query = table
                    .select(Col.id, Col.data, Col.searchText, Col.type)
                    .filter(Col.type == PasteboardType.fileURL.rawValue)
                    .limit(batchSize, offset: offset)
                return Array(try db.prepare(query))
            } ?? []

            guard !rows.isEmpty else { break }

            for row in rows {
                guard !Task.isCancelled else { break }
                do {
                    let id = try row.get(Col.id)
                    let rawSearchText = try row.get(Col.searchText)
                    let existingSearchText = decryptString(rawSearchText)

                    let rawData = try row.get(Col.data)
                    let decodedData = decryptData(rawData)
                    guard let text = String(data: decodedData, encoding: .utf8) else { continue }
                    let paths = text.components(separatedBy: "\n").filter { !$0.isEmpty }
                    let newSearchText = ClipboardItem.searchTextForFilePaths(paths)
                    guard !newSearchText.isEmpty else { continue }

                    if existingSearchText == newSearchText {
                        continue
                    }

                    let existingLower = existingSearchText.lowercased()
                    if !existingLower.isEmpty {
                        let fileNames = paths.map { URL(fileURLWithPath: $0).lastPathComponent }
                        if fileNames.contains(where: { !($0.isEmpty) && existingLower.contains($0.lowercased()) }) {
                            continue
                        }
                    }

                    await updateSearchText(id: id, searchText: newSearchText)
                    updated += 1
                } catch {
                    continue
                }
            }

            if rows.count < batchSize { break }
            offset += batchSize
            await Task.yield()
        }

        if updated > 0 {
            await log.info("File search text backfill completed: \(updated) items updated")
        }
    }

    private func migrateLargeImagesIfNeeded(
        finalVersion: Int32,
        postMigration: (() async -> Void)? = nil
    ) {
        // 在后台线程执行迁移
        Task(priority: .background) { [weak self] in
            guard let self else { return }
            let completed = await self.performLargeImageMigration()
            guard completed else {
                await log.warn("Large image migration incomplete; schema version not updated")
                return
            }
            if let postMigration {
                await postMigration()
            }
            // 迁移完成后更新数据库版本
            self.setSchemaVersion(finalVersion)
            await log.info("Database schema updated to version \(finalVersion)")
        }
    }

    private func performLargeImageMigration() async -> Bool {
        guard syncOnDBBackgroundQueue({ db != nil && table != nil }) else { return false }

        // 使用分页查询避免一次性加载全部数据
        let batchSize = 50
        var lastId: Int64 = 0
        var totalMigrated = 0

        while true {
            // 支持任务取消
            guard !Task.isCancelled else {
                await log.info("Large image migration cancelled after \(totalMigrated) items")
                return false
            }

            // 每次只查询一批需要迁移的图片
            let rows: [Row] = await withDBAsyncBackground {
                guard let db = self.db, let table = self.table else { return [] }
                let blobIsNil = Expression<Bool>("blob_path IS NULL")
                let filter = (Col.itemType == ClipItemType.image.rawValue) && blobIsNil && (Col.id > lastId)
                let query = table
                    .filter(filter)
                    .order(Col.id.asc)
                    .limit(batchSize)
                return Array(try db.prepare(query))
            } ?? []

            guard !rows.isEmpty else { break }

            if let lastRow = rows.last, let rowId = try? lastRow.get(Col.id) {
                lastId = rowId
            }

            for row in rows {
                // 支持任务取消
                guard !Task.isCancelled else {
                    await log.info("Large image migration cancelled after \(totalMigrated) items")
                    return false
                }

                guard let item = rowToClipboardItem(row, isEncrypted: nil) else { continue }
                guard item.data.count > Const.largeBlobThreshold else { continue }
                guard let rowId = try? row.get(Col.id) else { continue }

                let path = await BlobStorage.shared.storeAsync(data: item.data, uniqueId: item.uniqueId)

                guard let path else { continue }

                // Avoid storing preview duplicates for blob-backed items.
                guard let encryptedData = encryptData(Data()) else { return false }

                _ = await withDBAsyncBackground {
                    guard let db = self.db, let table = self.table else { return }
                    let query = table.filter(Col.id == rowId)
                    try db.run(query.update(
                        Col.data <- encryptedData,
                        Col.blobPath <- path
                    ))
                }

                totalMigrated += 1
            }

            if rows.count < batchSize { break }

            // 批次间让出 CPU，避免长时间阻塞后台线程
            await Task.yield()
        }

        await log.info("Large image migration completed: \(totalMigrated) items migrated")
        await vacuumDatabase(reason: "blob migration")
        return true
    }

    private func backfillSemanticEmbeddingsIfNeeded(targetVersion: Int32) {
        Task(priority: .background) { [weak self] in
            guard let self else { return }
            await self.performSemanticEmbeddingBackfill()
            self.setSchemaVersion(targetVersion)
            await log.info("Database schema updated to version \(targetVersion)")
        }
    }

    private func performSemanticEmbeddingBackfill() async {
        let batchSize = 100
        let maxItems = DeckUserDefaults.securityModeEnabled ? 300 : 1000
        var processed = 0

        while processed < maxItems {
            guard !Task.isCancelled else { break }

            let rows: [(id: Int64, searchText: String)] = await withDBAsyncBackground {
                guard let db = self.db else { return [] }
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
            await log.info("Semantic embedding backfill completed: \(processed) items processed")
        }
    }

    private func vacuumDatabase(reason: String) async {
        let didCheckpoint = await withDBAsyncBackground {
            guard let db = self.db else { return false }
            try db.run("PRAGMA wal_checkpoint(TRUNCATE)")
            return true
        } == true

        if didCheckpoint {
            await log.info("WAL checkpoint completed (\(reason))")
        }

        let didVacuum = await withDBAsyncBackground {
            guard let db = self.db else { return false }
            try db.run("VACUUM")
            return true
        } == true

        if didVacuum {
            await log.info("Database vacuum completed (\(reason))")
        }
    }

    private func scheduleDatabaseVacuum(reason: String) {
        Task(priority: .background) { [weak self] in
            await self?.vacuumDatabase(reason: reason)
        }
    }
    
    deinit {
        stopSecurityScopedAccess()
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - Encryption Helpers (加密辅助函数)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//
//  安全模式下的加密/解密逻辑：
//  - 加密列：data, search_text, app_name, custom_title, embedding
//  - 加密算法：由 SecurityService 提供（AES-256-GCM + Keychain 密钥管理）
//  - 加密失败：返回 nil 并提示用户，避免安全模式下写入明文
//
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

extension DeckSQLManager {
    /// 加密二进制数据（用于 data、embedding 列）
    /// - Parameter data: 原始数据
    /// - Returns: 加密后的数据（安全模式下），或原始数据（非安全模式）；失败时返回 nil
    private func encryptData(_ data: Data) -> Data? {
        guard DeckUserDefaults.securityModeEnabled else { return data }
        guard let encrypted = SecurityService.shared.encrypt(data) else {
            log.error("Security mode enabled but data encryption failed; rejecting plaintext write")
            notifyEncryptionFailureIfNeeded()
            return nil
        }
        return encrypted
    }
    
    /// 解密二进制数据（用于 data、embedding 列）
    /// - Parameter data: 加密的数据
    /// - Returns: 解密后的数据（安全模式下），或原始数据（非安全模式）
    private func decryptData(_ data: Data, force: Bool = false) -> Data {
        guard DeckUserDefaults.securityModeEnabled || force else { return data }
        return SecurityService.shared.decrypt(data) ?? data
    }
    
    /// 加密字符串（用于 search_text、app_name、custom_title 列）
    /// - Parameter string: 原始字符串
    /// - Returns: Base64 编码的加密数据（安全模式下），或原始字符串（非安全模式）；失败时返回 nil
    private func encryptString(_ string: String) -> String? {
        guard DeckUserDefaults.securityModeEnabled else { return string }
        guard let data = string.data(using: .utf8) else {
            log.error("Security mode enabled but string encoding failed; rejecting plaintext write")
            notifyEncryptionFailureIfNeeded()
            return nil
        }
        guard let encrypted = SecurityService.shared.encrypt(data) else {
            log.error("Security mode enabled but string encryption failed; rejecting plaintext write")
            notifyEncryptionFailureIfNeeded()
            return nil
        }
        return encrypted.base64EncodedString()
    }
    
    /// 解密字符串（用于 search_text、app_name、custom_title 列）
    /// - Parameter string: Base64 编码的加密数据
    /// - Returns: 解密后的字符串（安全模式下），或原始字符串（非安全模式）
    private func decryptString(_ string: String, force: Bool = false) -> String {
        guard DeckUserDefaults.securityModeEnabled || force else { return string }
        guard let data = Data(base64Encoded: string),
              let decrypted = SecurityService.shared.decrypt(data),
              let result = String(data: decrypted, encoding: .utf8) else { return string }
        return result
    }

    private func isEncryptedPayload(_ data: Data) -> Bool {
        guard !data.isEmpty else { return false }
        return SecurityService.shared.decryptSilently(data) != nil
    }

    private func isEncryptedStringPayload(_ string: String) -> Bool {
        guard let decoded = Data(base64Encoded: string),
              let decrypted = SecurityService.shared.decryptSilently(decoded),
              String(data: decrypted, encoding: .utf8) != nil else { return false }
        return true
    }

    private func encryptDataIfNeeded(_ data: Data) -> Data? {
        if isEncryptedPayload(data) {
            return data
        }
        return SecurityService.shared.encrypt(data)
    }

    private func decryptStringSilently(_ string: String) -> String {
        guard let data = Data(base64Encoded: string),
              let decrypted = SecurityService.shared.decryptSilently(data),
              let result = String(data: decrypted, encoding: .utf8) else { return string }
        return result
    }

    private func encryptStringIfNeeded(_ string: String) -> String? {
        if isEncryptedStringPayload(string) {
            return string
        }
        guard let data = string.data(using: .utf8),
              let encrypted = SecurityService.shared.encrypt(data) else { return nil }
        return encrypted.base64EncodedString()
    }

    private func notifyEncryptionFailureIfNeeded() {
        let shouldNotify = syncOnErrorStateQueue {
            if hasNotifiedEncryptionFailure {
                return false
            }
            hasNotifiedEncryptionFailure = true
            return true
        }
        guard shouldNotify else { return }
        notifyUserOfDBError(
            NSLocalizedString("安全模式加密失败，请重新认证或关闭安全模式后重试", comment: "Security mode encryption failed"),
            isCritical: true
        )
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
        var sumSquares: Float = 0
        vDSP_svesq(vector, 1, &sumSquares, vDSP_Length(vector.count))
        let norm = sqrt(sumSquares)
        guard norm > 0 else { return vector }
        var normalized = vector
        var scale = Float(1.0) / norm
        vDSP_vsmul(normalized, 1, &scale, &normalized, 1, vDSP_Length(normalized.count))
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

    @discardableResult
    private func updateVecIndex(id: Int64, vector: [Float]) -> Bool {
        guard !vector.isEmpty else { return false }
        let canIndex = syncOnDBQueue { vecIndexEnabled } && !DeckUserDefaults.securityModeEnabled
        guard canIndex else { return false }

        let normalized = normalizeVector(vector)
        guard !normalized.isEmpty else { return false }
        let dimension = normalized.count

        // Broken dimension should short-circuit early (avoid withDB and failure logs in hot path).
        let dimensionUsable = syncOnDBQueue { self.isVecDimensionUsable(dimension) }
        guard dimensionUsable else { return false }

        // Serialize outside dbQueue to avoid blocking DB operations on CPU work.
        let payload = vectorToJSONString(normalized)

        let outcome = withDB { () -> (succeeded: Bool, shouldLogFailure: Bool) in
            guard vecIndexEnabled, !DeckUserDefaults.securityModeEnabled else { return (false, false) }
            guard let db = self.db else { return (false, false) }
            guard self.isVecDimensionUsable(dimension) else { return (false, false) }
            ensureVecTable(dimension: dimension)
            guard vecReadyDimensions.contains(dimension) else {
                if vecMissingDimensionLogged.insert(dimension).inserted {
                    log.debug("Vec table not ready for dimension \(dimension); skipping updates")
                }
                let shouldLogFailure = !self.vecBrokenDimensions.contains(dimension)
                return (false, shouldLogFailure)
            }

            var tableName = self.resolveVecActiveTableName(dimension: dimension, db: db)
            let upsertRow = { (targetTableName: String) in
                try db.run(
                    "INSERT OR REPLACE INTO \(targetTableName)(rowid, embedding) VALUES (?, ?)",
                    id,
                    payload
                )
            }
            do {
                _ = try upsertRow(tableName)
            } catch {
                let resolvedTableName = self.resolveVecActiveTableName(dimension: dimension, db: db)
                if resolvedTableName != tableName {
                    do {
                        _ = try upsertRow(resolvedTableName)
                        return (true, false)
                    } catch {
                        tableName = resolvedTableName
                    }
                }
                if self.isVecInternalSQLiteError(error) {
                    let rebuilt = self.rebuildVecTable(dimension: dimension, db: db, reason: "vec upsert internal error")
                    guard rebuilt else { return (false, false) }
                    do {
                        _ = try upsertRow(tableName)
                        return (true, false)
                    } catch {
                        log.debug("Vec upsert still failed after rebuild: \(error.localizedDescription)")
                        let shouldLogFailure = !self.vecBrokenDimensions.contains(dimension)
                        return (false, shouldLogFailure)
                    }
                }
                do {
                    try db.run("DELETE FROM \(tableName) WHERE rowid = ?", id)
                    try db.run(
                        "INSERT INTO \(tableName)(rowid, embedding) VALUES (?, ?)",
                        id,
                        payload
                    )
                } catch {
                    log.debug("Vec upsert failed on table \(tableName): \(error.localizedDescription)")
                    let shouldLogFailure = !self.vecBrokenDimensions.contains(dimension)
                    return (false, shouldLogFailure)
                }
            }
            return (true, false)
        }

        let succeeded = (outcome?.succeeded == true)
        if !succeeded {
            let shouldLog = outcome?.shouldLogFailure ?? false
            if shouldLog {
                log.debug("Vec index update failed for id=\(id), dim=\(dimension)")
            }
        }
        return succeeded
    }

    private func storeSemanticEmbedding(id: Int64, textHash: String, vector: [Float]) {
        let encoded = encodeEmbedding(vector)
        let storedData: Data
        if DeckUserDefaults.securityModeEnabled {
            guard let encrypted = encryptData(encoded) else { return }
            storedData = encrypted
        } else {
            storedData = encoded
        }

        withDB {
            guard let db = self.db else { return }
            let tab = Table("ClipboardHistory_embedding")
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

        return await withDBAsync {
            guard let db = self.db else { return [:] }
            var result: [Int64: [Float]] = [:]
            let rows = Array(try db.prepare(query))
            for row in rows {
                let id = try row.get(EmbeddingCol.id)
                let storedHash = try row.get(EmbeddingCol.textHash)
                guard let expectedHash = expectedHashes[id], expectedHash == storedHash else { continue }
                let rawData = try row.get(EmbeddingCol.embedding)
                let decodedData = DeckUserDefaults.securityModeEnabled ? self.decryptData(rawData) : rawData
                guard let vector = self.decodeEmbedding(decodedData) else { continue }
                result[id] = vector
            }
            return result
        } ?? [:]
    }

    var isVecSearchAvailable: Bool {
        syncOnDBQueue { vecIndexEnabled } && !DeckUserDefaults.securityModeEnabled
    }

    func searchVecIds(queryVector: [Float], limit: Int) async -> [Int64] {
        let candidates = await searchVecCandidates(queryVector: queryVector, limit: limit)
        return candidates.map { $0.id }
    }

    func searchVecCandidates(queryVector: [Float], limit: Int) async -> [(id: Int64, distance: Double)] {
        guard !Task.isCancelled else { return [] }
        guard !queryVector.isEmpty else { return [] }

        let normalized = normalizeVector(queryVector)
        guard !normalized.isEmpty else { return [] }
        let isReady = syncOnDBQueue { () -> Bool in
            guard vecIndexEnabled, !DeckUserDefaults.securityModeEnabled else { return false }
            guard self.isVecDimensionUsable(normalized.count) else { return false }
            ensureVecTable(dimension: normalized.count)
            guard vecReadyDimensions.contains(normalized.count) else {
                if vecMissingDimensionLogged.insert(normalized.count).inserted {
                    log.debug("Vec table not ready for dimension \(normalized.count); search fallback")
                }
                return false
            }
            return true
        }
        guard isReady else { return [] }

        let payload = vectorToJSONString(normalized)
        await log.debug("Vec search: dim=\(normalized.count), limit=\(limit)")
        let results: [(id: Int64, distance: Double)] = await withDBAsync({ () throws -> [(id: Int64, distance: Double)] in
            guard let db = self.db else { return [] }
            let tableName = self.resolveVecActiveTableName(dimension: normalized.count, db: db)
            do {
                let sql = """
                    SELECT rowid, distance FROM \(tableName)
                    WHERE embedding MATCH ?
                    ORDER BY distance
                    LIMIT ?
                """
                let stmt = try db.prepare(sql).bind(payload, limit)
                var rows: [(id: Int64, distance: Double)] = []
                while let row = try stmt.failableNext() {
                    guard let id = self.bindingToInt64(row[0]),
                          let distance = self.bindingToDouble(row[1]) else {
                        continue
                    }
                    rows.append((id: id, distance: distance))
                }
                return rows
            } catch {
                if self.isVecInternalSQLiteError(error) {
                    _ = self.rebuildVecTable(dimension: normalized.count, db: db, reason: "vec search internal error")
                    return []
                }
                throw error
            }
        }) ?? []
        await log.debug("Vec search results: count=\(results.count)")
        return results
    }

    // MARK: - Search Cache Helpers

    /// 获取缓存的搜索字符串，如果未缓存则解密并缓存
    /// 安全模式下也使用缓存，但会在失焦/会话切换时清空以降低明文驻留
    /// - Parameters:
    ///   - id: 行 ID
    ///   - rawSearchText: 原始搜索文本（可能已加密）
    ///   - appName: 应用名称
    ///   - rawCustomTitle: 自定义标题（可能已加密）
    ///   - isSecurityMode: 是否处于安全模式
    /// - Returns: 解密且小写化后的缓存条目
    private func getCachedSearchEntry(
        id: Int64,
        rawSearchText: String,
        appName: String,
        rawCustomTitle: String?,
        isSecurityMode: Bool
    ) -> SearchCacheEntry {
        let cacheKey = NSNumber(value: id)

        // 尝试从缓存获取
        if let cached = searchTextCache.object(forKey: cacheKey) {
            return cached
        }

        let resolvedSearchText: String
        let resolvedAppName: String
        let resolvedCustomTitle: String
        if isSecurityMode {
            resolvedSearchText = decryptString(rawSearchText)
            resolvedAppName = decryptString(appName)
            resolvedCustomTitle = rawCustomTitle.map { decryptString($0) } ?? ""
        } else {
            resolvedSearchText = rawSearchText
            resolvedAppName = appName
            resolvedCustomTitle = rawCustomTitle ?? ""
        }

        // 缓存未命中，小写化后存入缓存
        let entry = SearchCacheEntry(
            searchText: resolvedSearchText.lowercased(),
            appName: resolvedAppName.lowercased(),
            customTitle: resolvedCustomTitle.lowercased()
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

    func shrinkMemory() async {
        _ = await withDBAsync {
            guard let db = self.db else { return false }
            try db.run("PRAGMA shrink_memory")
            return true
        }
    }
}

// MARK: - Database Operations

extension DeckSQLManager {
    /// Preserve existing user tag when the new payload is untagged (`-1`).
    /// This prevents duplicate-copy upserts from silently clearing manual tags.
    private static func mergedTagId(incoming: Int, existing: Int?) -> Int {
        guard incoming == -1, let existing, existing != -1 else { return incoming }
        return existing
    }

    var totalCount: Int {
        return withDB {
            guard let db = self.db, let table = self.table else { return 0 }
            return try db.scalar(table.count)
        } ?? 0
    }

    private struct InsertPayload {
        let uniqueId: String
        let pasteboardType: String
        let itemType: String
        let data: Data
        let previewData: Data?
        let timestamp: Int64
        let appPath: String
        let appName: String
        let customTitle: String?
        let sourceAnchor: String?
        let searchText: String
        let contentLength: Int
        let tagId: Int
        let blobPath: String?
        let isTemporary: Bool
        let isEncrypted: Bool
        let searchTextPlain: String
    }

    private func prepareInsertPayload(for item: ClipboardItem) async -> InsertPayload? {
        var dataToStore = item.data
        var blobPath = item.blobPath
        var previewData = item.previewData
        let isSecurityMode = DeckUserDefaults.securityModeEnabled

        if item.itemType == .image && item.data.count > Const.largeBlobThreshold {
            // Large image blobs can be 10s-100s of MB. Persisting them synchronously on the
            // caller's executor (often MainActor via UI-driven insert) causes visible UI stalls.
            // Offload to BlobStorage's IO queue while preserving the exact insert semantics.
            if let path = await BlobStorage.shared.storeAsync(
                data: item.data,
                uniqueId: item.uniqueId,
                encrypt: isSecurityMode
            ) {
                blobPath = path

                if previewData?.isEmpty ?? true {
                    previewData = await ClipboardItem.generatePreviewThumbnailDataAsync(from: item.data, maxSize: 200)
                    await log.debug("Pre-generated thumbnail for large image (\(item.data.count) bytes)")
                }

                dataToStore = Data()
            }
        } else if item.isUnsupported && item.data.count > Const.largeBlobThreshold {
            // Unsupported payloads can be large; offload to blob storage to avoid DB bloat.
            if let path = await BlobStorage.shared.storeAsync(
                data: item.data,
                uniqueId: item.uniqueId,
                encrypt: isSecurityMode
            ) {
                blobPath = path
                dataToStore = Data()
            }
        } else if item.itemType == .image && item.data.count > 50 * 1024 && (previewData?.isEmpty ?? true) {
            previewData = await ClipboardItem.generatePreviewThumbnailDataAsync(from: item.data, maxSize: 200)
            await log.debug("Pre-generated thumbnail for medium image (\(item.data.count) bytes)")
        }

        let encodedSourceAnchor = item.sourceAnchor?.toJSON()
        let normalizedCustomTitle = ClipboardItem.normalizedCustomTitle(item.customTitle)
        let encryptedData: Data
        let encryptedPreviewData: Data?
        let encryptedSearchText: String
        let encryptedAppName: String
        let encryptedCustomTitle: String?
        let encryptedSourceAnchor: String?

        if isSecurityMode {
            guard let data = encryptData(dataToStore),
                  let searchText = encryptString(item.searchText),
                  let appName = encryptString(item.appName) else {
                return nil
            }
            if let previewData = previewData {
                guard let encryptedPreview = encryptData(previewData) else { return nil }
                encryptedPreviewData = encryptedPreview
            } else {
                encryptedPreviewData = nil
            }
            encryptedData = data
            encryptedSearchText = searchText
            encryptedAppName = appName
            if let normalizedCustomTitle {
                guard let encryptedTitle = encryptString(normalizedCustomTitle) else { return nil }
                encryptedCustomTitle = encryptedTitle
            } else {
                encryptedCustomTitle = nil
            }
            if let encodedSourceAnchor {
                guard let encryptedAnchor = encryptString(encodedSourceAnchor) else { return nil }
                encryptedSourceAnchor = encryptedAnchor
            } else {
                encryptedSourceAnchor = nil
            }
        } else {
            encryptedData = dataToStore
            encryptedPreviewData = previewData
            encryptedSearchText = item.searchText
            encryptedAppName = item.appName
            encryptedCustomTitle = normalizedCustomTitle
            encryptedSourceAnchor = encodedSourceAnchor
        }

        return InsertPayload(
            uniqueId: item.uniqueId,
            pasteboardType: item.pasteboardType.rawValue,
            itemType: item.itemType.rawValue,
            data: encryptedData,
            previewData: encryptedPreviewData,
            timestamp: item.timestamp,
            appPath: item.appPath,
            appName: encryptedAppName,
            customTitle: encryptedCustomTitle,
            sourceAnchor: encryptedSourceAnchor,
            searchText: encryptedSearchText,
            contentLength: item.contentLength,
            tagId: item.tagId,
            blobPath: blobPath,
            isTemporary: item.isTemporary,
            isEncrypted: isSecurityMode,
            searchTextPlain: item.searchText
        )
    }
    
    func insert(item: ClipboardItem) async -> Int64 {
        guard let payload = await prepareInsertPayload(for: item) else { return -1 }

        let result: (rowId: Int64, usedUpsert: Bool)? = await withDBAsync {
            guard let db = self.db, let table = self.table else { return (-1, false) }

            // Prefer UPSERT to avoid delete+insert write amplification on hot-path inserts.
            if self.supportsUniqueIdUpsert {
                do {
                    let sql = """
                    INSERT INTO ClipboardHistory (
                        unique_id,
                        type,
                        item_type,
                        data,
                        preview_data,
                        timestamp,
                        app_path,
                        app_name,
                        custom_title,
                        source_anchor,
                        search_text,
                        content_length,
                        tag_id,
                        blob_path,
                        is_temporary,
                        is_encrypted
                    ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                    ON CONFLICT(unique_id) WHERE unique_id <> '' DO UPDATE SET
                        type = excluded.type,
                        item_type = excluded.item_type,
                        data = excluded.data,
                        preview_data = excluded.preview_data,
                        timestamp = excluded.timestamp,
                        app_path = excluded.app_path,
                        app_name = excluded.app_name,
                        custom_title = excluded.custom_title,
                        source_anchor = excluded.source_anchor,
                        search_text = excluded.search_text,
                        content_length = excluded.content_length,
                        tag_id = CASE
                            WHEN excluded.tag_id = -1 AND ClipboardHistory.tag_id != -1
                            THEN ClipboardHistory.tag_id
                            ELSE excluded.tag_id
                        END,
                        blob_path = excluded.blob_path,
                        is_temporary = excluded.is_temporary,
                        is_encrypted = excluded.is_encrypted
                    RETURNING id
                    """

                    let dataBlob = SQLite.Blob(bytes: [UInt8](payload.data))
                    let previewBlob = payload.previewData.map { SQLite.Blob(bytes: [UInt8]($0)) }
                    let stmt = try db.prepare(sql).bind(
                        payload.uniqueId,
                        payload.pasteboardType,
                        payload.itemType,
                        dataBlob,
                        previewBlob,
                        payload.timestamp,
                        payload.appPath,
                        payload.appName,
                        payload.customTitle,
                        payload.sourceAnchor,
                        payload.searchText,
                        payload.contentLength,
                        payload.tagId,
                        payload.blobPath,
                        payload.isTemporary,
                        payload.isEncrypted
                    )

                    if let row = try stmt.failableNext(), let rowId = row[0] as? Int64 {
                        return (rowId, true)
                    }
                } catch {
                    // Likely reasons:
                    // - SQLite < 3.24 (no UPSERT) / < 3.35 (no RETURNING)
                    // - Unique constraint not present / not matched
                    self.supportsUniqueIdUpsert = false
                    log.debug("UPSERT(unique_id) unavailable, fallback to delete+insert: \(error.localizedDescription)")
                }
            }

            // Fallback path: delete duplicates then insert.
            do {
                let deleteQuery = table.filter(Col.uniqueId == payload.uniqueId)
                let existingTagId = try db.pluck(deleteQuery.select(Col.tagId))?.get(Col.tagId)
                let mergedTagId = Self.mergedTagId(incoming: payload.tagId, existing: existingTagId)
                _ = try db.run(deleteQuery.delete())

                let insert = table.insert(
                    Col.uniqueId <- payload.uniqueId,
                    Col.type <- payload.pasteboardType,
                    Col.itemType <- payload.itemType,
                    Col.data <- payload.data,
                    Col.previewData <- payload.previewData,
                    Col.ts <- payload.timestamp,
                    Col.appPath <- payload.appPath,
                    Col.appName <- payload.appName,
                    Col.customTitle <- payload.customTitle,
                    Col.sourceAnchor <- payload.sourceAnchor,
                    Col.searchText <- payload.searchText,
                    Col.length <- payload.contentLength,
                    Col.tagId <- mergedTagId,
                    Col.blobPath <- payload.blobPath,
                    Col.isTemporary <- payload.isTemporary,
                    Col.isEncrypted <- payload.isEncrypted
                )

                let rowId = try db.run(insert)
                return (rowId, false)
            } catch {
                return (-1, false)
            }
        }

        guard let result, result.rowId > 0 else { return -1 }

        // Invalidate only this id in the search cache (cheaper than nuking everything).
        invalidateSearchCache(ids: [result.rowId])

        await log.debug("Inserted item with id: \(result.rowId)")
        scheduleSemanticEmbeddingUpdate(id: result.rowId, searchText: payload.searchTextPlain)
        return result.rowId
    }

    func insertBatch(_ items: [ClipboardItem]) async -> [Int64] {
        guard !items.isEmpty else { return [] }

        var payloads: [InsertPayload] = []
        payloads.reserveCapacity(items.count)
        for item in items {
            if let payload = await prepareInsertPayload(for: item) {
                payloads.append(payload)
            }
        }

        guard !payloads.isEmpty else { return [] }

        let result: (rowIds: [Int64], deleted: Int)? = await withDBAsync {
            guard let db = self.db, let table = self.table else { return ([], 0) }
            var rowIds: [Int64] = []
            var deletedTotal = 0

            try db.transaction {
                for payload in payloads {
                    let deleteQuery = table.filter(Col.uniqueId == payload.uniqueId)
                    let existingTagId = try db.pluck(deleteQuery.select(Col.tagId))?.get(Col.tagId)
                    let mergedTagId = Self.mergedTagId(incoming: payload.tagId, existing: existingTagId)
                    deletedTotal += try db.run(deleteQuery.delete())
                    let insert = table.insert(
                        Col.uniqueId <- payload.uniqueId,
                        Col.type <- payload.pasteboardType,
                        Col.itemType <- payload.itemType,
                        Col.data <- payload.data,
                        Col.previewData <- payload.previewData,
                        Col.ts <- payload.timestamp,
                        Col.appPath <- payload.appPath,
                        Col.appName <- payload.appName,
                        Col.customTitle <- payload.customTitle,
                        Col.sourceAnchor <- payload.sourceAnchor,
                        Col.searchText <- payload.searchText,
                        Col.length <- payload.contentLength,
                        Col.tagId <- mergedTagId,
                        Col.blobPath <- payload.blobPath,
                        Col.isTemporary <- payload.isTemporary,
                        Col.isEncrypted <- payload.isEncrypted
                    )
                    rowIds.append(try db.run(insert))
                }
            }

            return (rowIds, deletedTotal)
        }

        guard let result else { return [] }
        if result.deleted > 0 {
            invalidateSearchCache()
        }

        for (index, rowId) in result.rowIds.enumerated() where rowId > 0 {
            await log.debug("Inserted item with id: \(rowId)")
            scheduleSemanticEmbeddingUpdate(id: rowId, searchText: payloads[index].searchTextPlain)
        }

        return result.rowIds.filter { $0 > 0 }
    }
    
    func delete(filter: SQLite.Expression<Bool>) async {
        if let count: Int = await withDBAsync({
            guard let db = self.db, let table = self.table else { return 0 }
            let query = table.filter(filter)
            return try db.run(query.delete())
        }) {
            await log.debug("Deleted \(count) items")
            // 无法确定具体删除了哪些 ID，清空所有缓存
            invalidateSearchCache()
        }
    }

    func deleteAll() {
        _ = withDB {
            guard let db = self.db, let table = self.table else { return false }
            try db.run(table.delete())
            return true
        }
        _ = withDB {
            guard let db = self.db else { return false }
            try db.run("DELETE FROM ClipboardHistory_embedding")
            return true
        }
        dropVecTables()
        invalidateSearchCache()  // 清空所有搜索缓存
        log.info("Deleted all items from database")
        scheduleDatabaseVacuum(reason: "delete all")
    }

    func delete(id: Int64) async {
        if let count: Int = await withDBAsync({
            guard let db = self.db, let table = self.table else { return 0 }
            let query = table.filter(Col.id == id)
            return try db.run(query.delete())
        }) {
            await log.debug("Deleted item with id \(id): \(count) rows")
            invalidateSearchCache(ids: [id])  // 只失效被删除的项
        }
    }

    func update(id: Int64, item: ClipboardItem) async {
        // Keep update behavior aligned with insert, including blob storage handling.
        var dataToStore = item.data
        var previewData = item.previewData
        var blobPathToStore = item.blobPath
        let isSecurityMode = DeckUserDefaults.securityModeEnabled

        if item.itemType == .image, item.hasFullData, item.data.count > Const.largeBlobThreshold {
            // Large updates can also be triggered from UI flows (e.g., edits / reprocessing).
            // Persist off the caller's executor to keep UI responsive.
            if let path = await BlobStorage.shared.storeAsync(
                data: item.data,
                uniqueId: item.uniqueId,
                encrypt: isSecurityMode
            ) {
                blobPathToStore = path

                if previewData?.isEmpty ?? true {
                    previewData = await ClipboardItem.generatePreviewThumbnailDataAsync(from: item.data, maxSize: 200)
                    await log.debug("Pre-generated thumbnail for large image (\(item.data.count) bytes) during update")
                }

                dataToStore = Data()
            }
        } else if item.isUnsupported, item.hasFullData, item.data.count > Const.largeBlobThreshold {
            if let path = await BlobStorage.shared.storeAsync(
                data: item.data,
                uniqueId: item.uniqueId,
                encrypt: isSecurityMode
            ) {
                blobPathToStore = path
                dataToStore = Data()
            }
        } else if item.itemType == .image, item.data.count > 50 * 1024, (previewData?.isEmpty ?? true) {
            previewData = await ClipboardItem.generatePreviewThumbnailDataAsync(from: item.data, maxSize: 200)
            await log.debug("Pre-generated thumbnail for medium image (\(item.data.count) bytes) during update")
        }

        if blobPathToStore != nil {
            if let preview = previewData, !preview.isEmpty {
                dataToStore = Data()
            } else {
                dataToStore = previewData ?? dataToStore
            }
        } else if !item.hasFullData, let fullData = item.loadFullData() {
            dataToStore = fullData
        }

        let encryptedData: Data
        let encryptedPreviewData: Data?
        let encryptedSearchText: String
        let encryptedAppName: String
        let encryptedCustomTitle: String?
        let encryptedSourceAnchor: String?
        let encodedSourceAnchor = item.sourceAnchor?.toJSON()
        let normalizedCustomTitle = ClipboardItem.normalizedCustomTitle(item.customTitle)

        if isSecurityMode {
            guard let data = encryptData(dataToStore),
                  let searchText = encryptString(item.searchText),
                  let appName = encryptString(item.appName) else {
                return
            }
            if let previewData {
                guard let encryptedPreview = encryptData(previewData) else { return }
                encryptedPreviewData = encryptedPreview
            } else {
                encryptedPreviewData = nil
            }
            encryptedData = data
            encryptedSearchText = searchText
            encryptedAppName = appName
            if let normalizedCustomTitle {
                guard let encryptedTitle = encryptString(normalizedCustomTitle) else { return }
                encryptedCustomTitle = encryptedTitle
            } else {
                encryptedCustomTitle = nil
            }
            if let encodedSourceAnchor {
                guard let encryptedAnchor = encryptString(encodedSourceAnchor) else { return }
                encryptedSourceAnchor = encryptedAnchor
            } else {
                encryptedSourceAnchor = nil
            }
        } else {
            encryptedData = dataToStore
            encryptedPreviewData = previewData
            encryptedSearchText = item.searchText
            encryptedAppName = item.appName
            encryptedCustomTitle = normalizedCustomTitle
            encryptedSourceAnchor = encodedSourceAnchor
        }

        let result: (count: Int, oldBlobPathToRemove: String?)? = await withDBAsync({
            guard let db = self.db, let table = self.table else { return (0, nil) }
            let query = table.filter(Col.id == id)
            let oldBlobPath = try? db.pluck(query.select(Col.blobPath))?.get(Col.blobPath)
            let update = query.update(
                Col.type <- item.pasteboardType.rawValue,
                Col.itemType <- item.itemType.rawValue,
                Col.data <- encryptedData,
                Col.previewData <- encryptedPreviewData,
                Col.ts <- item.timestamp,
                Col.appPath <- item.appPath,
                Col.appName <- encryptedAppName,
                Col.customTitle <- encryptedCustomTitle,
                Col.sourceAnchor <- encryptedSourceAnchor,
                Col.searchText <- encryptedSearchText,
                Col.length <- item.contentLength,
                Col.tagId <- item.tagId,
                Col.blobPath <- blobPathToStore,
                Col.isTemporary <- item.isTemporary,
                Col.isEncrypted <- isSecurityMode
            )
            let count = try db.run(update)
            if count > 0, let old = oldBlobPath, old != blobPathToStore {
                return (count, old)
            }
            return (count, nil)
        })

        if let result {
            await log.debug("Updated \(result.count) items")
            invalidateSearchCache(ids: [id])  // 失效被更新的项（searchText 可能已变化）
            scheduleSemanticEmbeddingUpdate(id: id, searchText: item.searchText)

            if let oldPath = result.oldBlobPathToRemove {
                BlobStorage.shared.remove(path: oldPath)
            }
        }
    }
    
    func updateItemTag(id: Int64, tagId: Int) async {
        if let count: Int = await withDBAsync({
            guard let db = self.db, let table = self.table else { return 0 }
            var query = table.filter(Col.id == id)
            if tagId == DeckTag.importantTagId {
                query = query.filter(Col.isTemporary == false)
            }
            let update = query.update(Col.tagId <- tagId)
            return try db.run(update)
        }) {
            await log.debug("Updated tag for \(count) items")
        }
    }

    func updateItemTemporary(id: Int64, isTemporary: Bool) async {
        if let count: Int = await withDBAsync({
            guard let db = self.db, let table = self.table else { return 0 }
            var query = table.filter(Col.id == id)
            if isTemporary {
                query = query.filter(Col.tagId != DeckTag.importantTagId)
            }
            let update = query.update(Col.isTemporary <- isTemporary)
            return try db.run(update)
        }) {
            await log.debug("Updated temporary flag for \(count) items")
        }
    }

    func updateCustomTitle(id: Int64, customTitle: String?) async {
        let normalized = ClipboardItem.normalizedCustomTitle(customTitle)
        let isSecurityMode = DeckUserDefaults.securityModeEnabled
        let encryptedTitle: String?

        if isSecurityMode {
            if let normalized {
                guard let encrypted = encryptString(normalized) else {
                    await log.error("Failed to encrypt customTitle for item \(id)")
                    return
                }
                encryptedTitle = encrypted
            } else {
                encryptedTitle = nil
            }
        } else {
            encryptedTitle = normalized
        }

        if let count: Int = await withDBAsync({
            guard let db = self.db, let table = self.table else { return 0 }
            let query = table.filter(Col.id == id)
            let update = query.update(Col.customTitle <- encryptedTitle)
            return try db.run(update)
        }) {
            if count > 0 {
                invalidateSearchCache(ids: [id])
            }
            await log.debug("Updated customTitle for \(count) items")
        }
    }

    /// 更新项目的 searchText（用于 OCR 结果）
    /// 注意：FTS 索引会通过 ClipboardHistory_au 触发器自动更新
    /// 更新 searchText（主要由 OCR / 文件索引回填触发）。默认走后台 DB 队列，避免与用户交互抢 CPU。
    func updateSearchText(id: Int64, searchText: String, useBackgroundQueue: Bool = true) async {
        let isReady: Bool = useBackgroundQueue
            ? syncOnDBBackgroundQueue({ db != nil && table != nil })
            : syncOnDBQueue({ db != nil && table != nil })

        guard isReady else {
            await log.error("OCR DB: Database not initialized")
            return
        }

        await log.info("OCR DB: Updating searchText for item \(id), text length: \(searchText.count)")

        // 根据安全模式决定是否加密
        guard let textToStore = encryptString(searchText) else {
            await log.error("OCR DB: Failed to encrypt searchText for item \(id)")
            return
        }

        let count: Int? = useBackgroundQueue
            ? await withDBAsyncBackground({
                guard let db = self.db, let table = self.table else { return 0 }
                let query = table.filter(Col.id == id)
                let update = query.update(Col.searchText <- textToStore)
                return try db.run(update)
            })
            : await withDBAsync({
                guard let db = self.db, let table = self.table else { return 0 }
                let query = table.filter(Col.id == id)
                let update = query.update(Col.searchText <- textToStore)
                return try db.run(update)
            })

        if let count {
            await log.info("OCR DB: Successfully updated searchText for \(count) items (FTS auto-synced via trigger)")
            invalidateSearchCache(ids: [id])
            scheduleSemanticEmbeddingUpdate(id: id, searchText: searchText)
        } else {
            await log.error("OCR DB: Failed to update searchText for item \(id)")
        }
    }

    func search(
        filter: SQLite.Expression<Bool>? = nil,
        order: [Expressible]? = nil,
        limit: Int? = nil,
        offset: Int? = nil
    ) async -> [Row] {
        guard !Task.isCancelled else { return [] }
        let ord = order ?? [Col.ts.desc, Col.id.desc]

        return await withDBAsync {
            guard let db = self.db, let table = self.table else { return [] }
            var query = table.order(ord)
            if let f = filter { query = query.filter(f) }
            if let l = limit { query = query.limit(l, offset: offset ?? 0) }
            return Array(try db.prepare(query))
        } ?? []
    }

    // MARK: - List-mode Queries (避免加载大 blob)

    /// 列表模式下的轻量查询：
    /// - 投影 `data` 列（大内容返回空 BLOB），避免把大 blob materialize 到 Swift Data
    /// - 维持与 UI 一致的排序：timestamp DESC, id DESC
    private func listModeBaseQuery(table: Table) -> Table {
        table.select(
            Col.id,
            Col.uniqueId,
            Col.type,
            Col.itemType,
            listModeProjectedDataExpr,
            Col.previewData,
            Col.ts,
            Col.appPath,
            Col.appName,
            Col.customTitle,
            Col.sourceAnchor,
            Col.searchText,
            Col.length,
            Col.tagId,
            Col.blobPath,
            Col.isTemporary,
            Col.isEncrypted
        )
    }

    struct RowCursor: Sendable, Equatable {
        let timestamp: Int64
        let id: Int64
    }

    func cursor(from row: Row?) -> RowCursor? {
        guard let row else { return nil }
        guard let ts = try? row.get(Col.ts), let id = try? row.get(Col.id) else { return nil }
        return RowCursor(timestamp: ts, id: id)
    }

    func cursor(from item: ClipboardItem?) -> RowCursor? {
        guard let item, let id = item.id else { return nil }
        return RowCursor(timestamp: item.timestamp, id: id)
    }

    /// Cursor-based pagination for the main list (keyset pagination).
    /// - This avoids OFFSET scans which get slower as the list grows.
    func fetchListPage(
        filter: SQLite.Expression<Bool>? = nil,
        limit: Int,
        cursor: RowCursor? = nil
    ) async -> [Row] {
        guard !Task.isCancelled else { return [] }

        return await withDBAsync {
            guard let db = self.db, let table = self.table else { return [] }
            var query = self.listModeBaseQuery(table: table)

            if let f = filter { query = query.filter(f) }
            if let cursor {
                let cursorFilter = (Col.ts < cursor.timestamp) || (Col.ts == cursor.timestamp && Col.id < cursor.id)
                query = query.filter(cursorFilter)
            }

            query = query.order(Col.ts.desc, Col.id.desc).limit(limit)
            return Array(try db.prepare(query))
        } ?? []
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

    private func runFTSQuery(_ ftsQuery: String, limit: Int) async -> [Int64] {
        return await withDBAsync {
            guard let db = self.db else { return [] }
            let sql = """
                SELECT rowid, bm25(ClipboardHistory_fts) AS score
                FROM ClipboardHistory_fts
                WHERE ClipboardHistory_fts MATCH ?
                ORDER BY score
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

    private func searchWithSQLLike(keyword: String, limit: Int) async -> [Int64] {
        let escaped = escapeForLike(keyword)
        let pattern = "%\(escaped)%"

        return await withDBAsync {
            guard let db = self.db else { return [] }
            let sql = """
                SELECT id FROM ClipboardHistory
                WHERE search_text LIKE ? ESCAPE '\\'
                   OR app_name LIKE ? ESCAPE '\\'
                   OR custom_title LIKE ? ESCAPE '\\'
                ORDER BY timestamp DESC
                LIMIT ?
            """
            let stmt = try db.prepare(sql).bind(pattern, pattern, pattern, limit)
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
        guard !keyword.isEmpty else { return [] }
        guard syncOnDBQueue({ db != nil }) else { return [] }

        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)

        // 安全模式下 FTS 索引存储的是加密内容，无法直接匹配
        // 需要使用内存解密搜索
        if DeckUserDefaults.securityModeEnabled {
            return await searchWithLike(keyword: trimmed, limit: limit)
        }

        let usesTrigram = syncOnDBQueue { ftsUsesTrigram }
        if usesTrigram {
            let ftsQuery = buildFTSQuery(from: trimmed, useTrigram: true)
            guard !ftsQuery.isEmpty else {
                return await searchWithSQLLike(keyword: trimmed, limit: limit)
            }
            return await runFTSQuery(ftsQuery, limit: limit)
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
            let sqlIds = await searchWithSQLLike(keyword: trimmed, limit: limit)
            if !sqlIds.isEmpty {
                return sqlIds
            }
            return await searchWithLike(keyword: trimmed, limit: limit)
        }

        let ftsQuery = buildFTSQuery(from: trimmed, useTrigram: false)
        guard !ftsQuery.isEmpty else { return [] }
        return await runFTSQuery(ftsQuery, limit: limit)
    }

    /// In-memory fallback search (security mode or CJK without trigram support)
    /// 安全模式/无 trigram 时使用内存搜索，避免 FTS5 无法匹配
    /// 使用缓存避免重复解密和 lowercased 转换，显著提升频繁搜索性能
    /// 采用分批流式扫描，覆盖全量数据
    private func searchWithLike(keyword: String, limit: Int) async -> [Int64] {
        var matchingIds: [Int64] = []
        let lowercasedKeyword = keyword.lowercased()
        let isSecurityMode = DeckUserDefaults.securityModeEnabled

        // 分批扫描参数
        let batchSize = 500
        // 关键优化：用 (timestamp,id) cursor 做 keyset pagination，
        // 避免 OFFSET 在大表上越来越慢（SQLite 需要扫描+丢弃 offset 行）
        var cursor: RowCursor? = nil
        var scanned = 0
        // 安全模式下最多扫描 5000 条（解密开销大），普通模式扫描全量
        let maxScan = isSecurityMode
            ? min(max(5000, limit * 200), 20000)
            : Int.max

        while matchingIds.count < limit && scanned < maxScan {
            // 支持任务取消
            guard !Task.isCancelled else { break }

            let rows: [Row] = await withDBAsync {
                guard let db = self.db, let table = self.table else { return [] }
                var query = table
                    .select(Col.id, Col.ts, Col.searchText, Col.appName, Col.customTitle)
                    .order(Col.ts.desc, Col.id.desc)
                    .limit(batchSize)

                if let cursor {
                    let cursorFilter = (Col.ts < cursor.timestamp) || (Col.ts == cursor.timestamp && Col.id < cursor.id)
                    query = query.filter(cursorFilter)
                }
                return Array(try db.prepare(query))
            } ?? []

            // 没有更多数据
            if rows.isEmpty { break }

            // 记录下一批 cursor（用最后一条记录）
            cursor = self.cursor(from: rows.last)

            for row in rows {
                // 早停：已找到足够的匹配项
                guard matchingIds.count < limit else { break }

                // 支持任务取消
                guard !Task.isCancelled else { break }

                do {
                    let id = try row.get(Col.id)
                    let rawSearchText = try row.get(Col.searchText)
                    let appName = try row.get(Col.appName)
                    let rawCustomTitle = (try? row.get(Col.customTitle)) ?? nil

                    // 使用缓存获取解密且小写化后的搜索文本
                    // 热路径优化：避免重复解密和 lowercased 转换
                    let cached = getCachedSearchEntry(
                        id: id,
                        rawSearchText: rawSearchText,
                        appName: appName,
                        rawCustomTitle: rawCustomTitle,
                        isSecurityMode: isSecurityMode
                    )

                    // 匹配搜索文本或应用名称（都已预先小写化）
                    if cached.searchText.contains(lowercasedKeyword) ||
                       cached.appName.contains(lowercasedKeyword) ||
                       cached.customTitle.contains(lowercasedKeyword) {
                        matchingIds.append(id)
                    }
                } catch {
                    continue
                }
            }

            scanned += rows.count
            if rows.count < batchSize { break }

            // 批次间让出 CPU，避免长时间阻塞
            await Task.yield()
        }

        // 安全模式下如果达到扫描上限且未找到足够结果，记录日志提示
        if isSecurityMode && scanned >= maxScan && matchingIds.count < limit {
            await log.info("Security mode search reached scan limit (\(maxScan) items), results may be incomplete")
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

        let hasFilters = (typeFilter?.isEmpty == false) || (tagId != nil && tagId != -1)
        let initialLimit = max(limit * 2, limit)
        let maxLimit = min(max(limit * 20, 2000), 5000)

        var searchLimit = initialLimit
        var matchingIds: [Int64] = []
        var rows: [Row] = []
        while true {
            // Get matching IDs from FTS
            matchingIds = await searchFTS(keyword: keyword, limit: searchLimit)
            guard !matchingIds.isEmpty else { return [] }

            rows = await fetchRowsForIds(matchingIds, typeFilter: typeFilter, tagId: tagId)

            if !hasFilters ||
                rows.count >= limit ||
                matchingIds.count < searchLimit ||
                searchLimit >= maxLimit {
                break
            }
            searchLimit = min(searchLimit * 2, maxLimit)
        }
        guard rows.count > 1 else { return rows }

        var rowsById: [Int64: Row] = [:]
        rowsById.reserveCapacity(rows.count)
        for row in rows {
            if let id = try? row.get(Col.id) {
                rowsById[id] = row
            }
        }

        var ordered: [Row] = []
        ordered.reserveCapacity(min(limit, matchingIds.count))
        for id in matchingIds {
            guard let row = rowsById[id] else { continue }
            ordered.append(row)
            if ordered.count >= limit { break }
        }
        return ordered
    }

    private func fetchRowsForIds(
        _ ids: [Int64],
        typeFilter: [String]?,
        tagId: Int?
    ) async -> [Row] {
        guard !ids.isEmpty else { return [] }

        // 分块查询避免 SQLite 变量上限
        let chunkSize = 900
        var rows: [Row] = []
        rows.reserveCapacity(ids.count)
        var start = 0
        while start < ids.count {
            guard !Task.isCancelled else { break }
            let end = min(start + chunkSize, ids.count)
            let chunk = Array(ids[start..<end])
            let chunkRows = await withDBAsync { () throws -> [Row] in
                guard let db = self.db, let table = self.table else { return [Row]() }
                var query = self.listModeBaseQuery(table: table).filter(chunk.contains(Col.id))

                if let types = typeFilter, !types.isEmpty {
                    query = query.filter(types.contains(Col.itemType))
                }

                if let tagId = tagId, tagId != -1 {
                    query = query.filter(Col.tagId == tagId)
                }

                return Array(try db.prepare(query))
            } ?? []
            rows.append(contentsOf: chunkRows)
            start = end
        }
        return rows
    }
    
    func fetchAll(limit: Int = 10000, offset: Int = 0, loadFullData: Bool = false) async -> [ClipboardItem] {
        let rows = await withDBAsync { () throws -> [Row] in
            guard let db = self.db, let table = self.table else { return [Row]() }
            let query = table.order(Col.ts.desc).limit(limit, offset: offset)
            return Array(try db.prepare(query))
        } ?? []
        return rows.compactMap { rowToClipboardItem($0, loadFullData: loadFullData) }
    }

    func fetchAllBeforeCursor(
        limit: Int = 10000,
        beforeTimestamp: Int64? = nil,
        beforeId: Int64? = nil,
        loadFullData: Bool = false
    ) async -> [ClipboardItem] {
        let rows = await withDBAsync { () throws -> [Row] in
            guard let db = self.db, let table = self.table else { return [Row]() }
            var query = table
            if let beforeTimestamp, let beforeId {
                let cursorFilter = (Col.ts < beforeTimestamp) || (Col.ts == beforeTimestamp && Col.id < beforeId)
                query = query.filter(cursorFilter)
            }
            query = query.order(Col.ts.desc, Col.id.desc).limit(limit)
            return Array(try db.prepare(query))
        } ?? []
        return rows.compactMap { rowToClipboardItem($0, loadFullData: loadFullData) }
    }

    func fetchAll(limit: Int = 10000, offset: Int = 0, loadFullData: Bool = false) -> [ClipboardItem] {
        let rows = withDB { () throws -> [Row] in
            guard let db = self.db, let table = self.table else { return [Row]() }
            let query = table.order(Col.ts.desc).limit(limit, offset: offset)
            return Array(try db.prepare(query))
        } ?? []
        return rows.compactMap { rowToClipboardItem($0, loadFullData: loadFullData) }
    }
    
    func fetch(id: Int64) async -> Row? {
        return await withDBAsync { () throws -> Row? in
            guard let db = self.db, let table = self.table else { return nil }
            let query = table.filter(Col.id == id)
            return try db.pluck(query)
        } ?? nil
    }

    func fetchRow(uniqueId: String) async -> Row? {
        return await withDBAsync { () throws -> Row? in
            guard let db = self.db, let table = self.table else { return nil }
            let query = table.filter(Col.uniqueId == uniqueId).order(Col.ts.desc).limit(1)
            return try db.pluck(query)
        } ?? nil
    }

    func fetchTagId(uniqueId: String) async -> Int? {
        return await withDBAsync { () throws -> Int? in
            guard let db = self.db, let table = self.table else { return nil }
            let query = table.select(Col.tagId).filter(Col.uniqueId == uniqueId).order(Col.ts.desc).limit(1)
            return try db.pluck(query)?.get(Col.tagId)
        } ?? nil
    }

    /// Ensure a non-empty unique_id for the given item, backfilling legacy rows if needed.
    func ensureNonEmptyUniqueId(for item: ClipboardItem) async -> String {
        if !item.uniqueId.isEmpty { return item.uniqueId }
        guard let id = item.id else { return UUID().uuidString }

        if let row = await fetch(id: id),
           let existing = try? row.get(Col.uniqueId),
           !existing.isEmpty {
            return existing
        }

        let resolvedUniqueId = syncOnDBQueue {
            if let pending = pendingUniqueIdBackfill[id] {
                return pending
            }
            let newId = UUID().uuidString
            pendingUniqueIdBackfill[id] = newId
            return newId
        }

        backfillUniqueIdIfNeeded(id: id, uniqueId: resolvedUniqueId)
        return resolvedUniqueId
    }

    /// Fetch raw data payload for a single item (used for lazy loading).
    func fetchData(for id: Int64, isEncrypted: Bool? = nil) -> Data? {
        return withDB { () -> Data? in
            guard let db = self.db, let table = self.table else { return nil }
            let query = table.select(Col.data).filter(Col.id == id).limit(1)
            guard let row = try db.pluck(query) else { return nil }
            let rawData = try row.get(Col.data)
            let shouldDecrypt = isEncrypted ?? DeckUserDefaults.securityModeEnabled
            return decryptData(rawData, force: shouldDecrypt)
        } ?? nil
    }

    /// 批量获取多个 ID 的记录（自动分块避免 SQLite 变量上限）
    func fetchBatch(ids: [Int64]) async -> [Row] {
        guard !ids.isEmpty else { return [] }
        // SQLite 默认变量限制 999，分块查询避免超限
        let chunkSize = 900
        var results: [Row] = []
        results.reserveCapacity(ids.count)

        var start = 0
        while start < ids.count {
            let end = min(start + chunkSize, ids.count)
            let chunk = Array(ids[start..<end])
            let rows: [Row] = await withDBAsync {
                guard let db = self.db, let table = self.table else { return [Row]() }
                let query = self.listModeBaseQuery(table: table).filter(chunk.contains(Col.id))
                return Array(try db.prepare(query))
            } ?? []
            results.append(contentsOf: rows)
            start = end
        }

        return results
    }

    func count(typeFilter: [String]? = nil) async -> Int {
        return await withDBAsync {
            guard let db = self.db, let table = self.table else { return 0 }
            var query = table
            if let types = typeFilter, !types.isEmpty {
                query = query.filter(types.contains(Col.itemType))
            }
            return try db.scalar(query.count)
        } ?? 0
    }

    // MARK: - Lightweight Statistics Queries (avoid loading large blobs)

    func count(since timestamp: Int64) async -> Int {
        return await withDBAsync {
            guard let db = self.db, let table = self.table else { return 0 }
            let query = table.filter(Col.ts >= timestamp)
            return try db.scalar(query.count)
        } ?? 0
    }

    /// Fetch timestamps since the given unix timestamp (seconds).
    /// Only selects the `ts` column to keep memory stable.
    func fetchTimestamps(since timestamp: Int64) async -> [Int64] {
        guard !Task.isCancelled else { return [] }
        return await withDBAsync {
            guard let db = self.db, let table = self.table else { return [] }
            let query = table
                .select(Col.ts)
                .filter(Col.ts >= timestamp)
                .order(Col.ts.desc)

            var results: [Int64] = []
            for row in try db.prepare(query) {
                results.append(try row.get(Col.ts))

                // Allow cooperative cancellation for very large datasets.
                if results.count % 2000 == 0, Task.isCancelled { break }
            }
            return results
        } ?? []
    }

    struct TypeCountRow: Sendable {
        let type: String
        let count: Int
    }

    struct AppPathCountRow: Sendable {
        let appPath: String
        let count: Int
    }

    /// Type distribution across the whole database (metadata-only, no blobs).
    func fetchTypeCounts() async -> [TypeCountRow] {
        guard !Task.isCancelled else { return [] }
        return await withDBAsync {
            guard let db = self.db else { return [] }

            let sql = """
            SELECT item_type, COUNT(*) AS c
            FROM ClipboardHistory
            GROUP BY item_type
            ORDER BY c DESC
            """

            var results: [TypeCountRow] = []
            let stmt = try db.prepare(sql)
            while let row = try stmt.failableNext() {
                guard let type = row[0] as? String,
                      let countValue = self.bindingToInt64(row[1]) else {
                    continue
                }
                results.append(
                    TypeCountRow(
                        type: type,
                        count: Int(countValue)
                    )
                )

                if results.count % 50 == 0, Task.isCancelled { break }
            }
            return results
        } ?? []
    }

    /// Top app paths across the whole database (metadata-only, no blobs).
    func fetchTopAppPaths(limit: Int = 5) async -> [AppPathCountRow] {
        guard limit > 0 else { return [] }
        guard !Task.isCancelled else { return [] }

        // Avoid pathological values.
        let safeLimit = max(1, min(limit, 50))

        return await withDBAsync {
            guard let db = self.db else { return [] }

            let sql = """
            SELECT app_path, COUNT(*) AS c
            FROM ClipboardHistory
            GROUP BY app_path
            ORDER BY c DESC
            LIMIT \(safeLimit)
            """

            var results: [AppPathCountRow] = []
            results.reserveCapacity(safeLimit)

            let stmt = try db.prepare(sql)
            while let row = try stmt.failableNext() {
                guard let appPath = row[0] as? String,
                      let countValue = self.bindingToInt64(row[1]) else {
                    continue
                }
                results.append(
                    AppPathCountRow(
                        appPath: appPath,
                        count: Int(countValue)
                    )
                )
            }
            return results
        } ?? []
    }

    private func backfillUniqueIdIfNeeded(id: Int64, uniqueId: String) {
        Task { [weak self] in
            guard let self else { return }
            let didUpdate = await self.withDBAsync {
                guard let db = self.db, let table = self.table else { return false }
                let query = table.filter(Col.id == id && Col.uniqueId == "")
                return try db.run(query.update(Col.uniqueId <- uniqueId)) > 0
            } ?? false

            if didUpdate {
                _ = self.syncOnDBQueue {
                    self.pendingUniqueIdBackfill.removeValue(forKey: id)
                }
            }
        }
    }
    
    func rowToClipboardItem(_ row: Row, isEncrypted: Bool? = nil, loadFullData: Bool = true) -> ClipboardItem? {
        do {
            let type = try row.get(Col.type)
            let rawData: Data
            do {
                rawData = try row.get(Col.data)
            } catch {
                // 列表模式 select 的是 listModeProjectedDataExpr（CASE ... AS data）
                rawData = (try? row.get(listModeProjectedDataExpr)) ?? Data()
            }
            let timestamp = try row.get(Col.ts)
            let id = try row.get(Col.id)
            let rawAppName = try row.get(Col.appName)
            let rawCustomTitle = (try? row.get(Col.customTitle)) ?? nil
            let rawSourceAnchor = (try? row.get(Col.sourceAnchor)) ?? nil
            let appPath = try row.get(Col.appPath)
            let rawPreviewData = try row.get(Col.previewData)
            let rawSearchText = try row.get(Col.searchText)
            let length = try row.get(Col.length)
            let tagId = try row.get(Col.tagId)
            let blobPath = try row.get(Col.blobPath)
            let storedUniqueId = try row.get(Col.uniqueId)
            let resolvedUniqueId: String
            if storedUniqueId.isEmpty {
                resolvedUniqueId = syncOnDBQueue {
                    if let pending = pendingUniqueIdBackfill[id] {
                        return pending
                    }
                    let newId = UUID().uuidString
                    pendingUniqueIdBackfill[id] = newId
                    return newId
                }
                backfillUniqueIdIfNeeded(id: id, uniqueId: resolvedUniqueId)
            } else {
                resolvedUniqueId = storedUniqueId
            }
            let storedItemType = try row.get(Col.itemType)
            let rawIsTemporary = (try? row.get(Col.isTemporary)) ?? false
            let storedIsEncrypted = try? row.get(Col.isEncrypted)
            let isTemporary = tagId == DeckTag.importantTagId ? false : rawIsTemporary
            if tagId == DeckTag.importantTagId && rawIsTemporary {
                Task { [weak self] in
                    await self?.updateItemTemporary(id: id, isTemporary: false)
                }
            }
            
            // Decrypt lightweight fields up-front (needed for list rendering / filtering).
            let shouldDecrypt = isEncrypted ?? storedIsEncrypted ?? DeckUserDefaults.securityModeEnabled
            let previewData = rawPreviewData.map { decryptData($0, force: shouldDecrypt) }
            let searchText = decryptString(rawSearchText, force: shouldDecrypt)
            let appName = decryptString(rawAppName, force: shouldDecrypt)
            let customTitle = rawCustomTitle.map { decryptString($0, force: shouldDecrypt) }
            let sourceAnchorString = rawSourceAnchor.map { decryptString($0, force: shouldDecrypt) }
            let sourceAnchor = SourceAnchor.fromJSON(sourceAnchorString)

            // IMPORTANT:
            // The history panel loads items with `loadFullData == false` (pagination).
            // Previously we decrypted & inlined the full `data` blob for every item regardless,
            // which caused memory to grow with scroll distance and spiked CPU during fast scrolling.
            // Here we keep only lightweight inline payloads and lazily fetch full data on demand.

            var inlineData = Data()
            var dataIsFull = loadFullData

            // Keep small payloads inline to avoid extra DB fetch for common items,
            // but never keep large payloads inline when loadFullData == false.
            let maxInlineBytesForNonImage: Int = 32 * 1024
            // File URL payloads are typically small (newline-separated paths), but keep a higher
            // ceiling to avoid breaking paste for multi-select file copies.
            let maxInlineBytesForFile: Int = 256 * 1024
            // If an image has no preview (e.g. very small images), keep a slightly larger inline
            // budget so the UI can still render a thumbnail without fetching.
            let maxInlineBytesForImageWithoutPreview: Int = 256 * 1024

            let itemType = ClipItemType(rawValue: storedItemType)
            // 当列表查询使用了 data 列投影（大内容返回 X''）时，这里 rawData 会是空，但 content_length 仍然是原始长度。
            // 如果不特殊处理，会被误判为 dataIsFull=true，导致后续无法懒加载真实数据。
            let projectedEmptyData = (!loadFullData && blobPath == nil && rawData.isEmpty && length > 0)

            if let blobPath {
                // Full payload is stored in an external blob. Only load it if explicitly requested.
                if loadFullData, let fullData = BlobStorage.shared.load(path: blobPath) {
                    inlineData = fullData
                    dataIsFull = true
                } else {
                    dataIsFull = false
                    if let preview = previewData, !preview.isEmpty {
                        inlineData = preview
                    }
                }
            } else if loadFullData {
                // Caller explicitly asked for full data.
                inlineData = decryptData(rawData, force: shouldDecrypt)
                dataIsFull = true
            } else if projectedEmptyData {
                // List-mode query projected `data` to an empty blob to avoid loading large payloads.
                // Keep preview for images; otherwise keep empty and rely on lazy-load when needed.
                if itemType == .image, let preview = previewData, !preview.isEmpty {
                    inlineData = preview
                } else {
                    inlineData = Data()
                }
                dataIsFull = false
            } else if itemType == .image, let preview = previewData, !preview.isEmpty {
                // Image list mode: keep only thumbnail inline.
                inlineData = preview
                dataIsFull = false
            } else {
                // Non-image list mode: inline only very small payloads; otherwise lazy-load.
                let maxInlineBytes = (itemType == .file) ? maxInlineBytesForFile : maxInlineBytesForNonImage

                if rawData.count <= maxInlineBytes || (itemType == .image && rawData.count <= maxInlineBytesForImageWithoutPreview) {
                    inlineData = decryptData(rawData, force: shouldDecrypt)
                    dataIsFull = true
                } else {
                    inlineData = Data()
                    dataIsFull = false
                }
            }
            
            let item = ClipboardItem(
                pasteboardType: PasteboardType(type),
                data: inlineData,
                previewData: previewData,
                timestamp: timestamp,
                appPath: appPath,
                appName: appName,
                customTitle: customTitle,
                sourceAnchor: sourceAnchor,
                searchText: searchText,
                contentLength: length,
                tagId: tagId,
                isTemporary: isTemporary,
                id: id,
                uniqueId: resolvedUniqueId,
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

    func mapRowsToClipboardItems(_ rows: [Row], loadFullData: Bool = false) async -> [ClipboardItem] {
        guard !rows.isEmpty else { return [] }
        guard !Task.isCancelled else { return [] }
        let rowBatch = UnsafeRowBatch(rows: rows)

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [weak self, rowBatch] in
                guard let self else {
                    continuation.resume(returning: [])
                    return
                }
                let items = rowBatch.rows.compactMap { self.rowToClipboardItem($0, loadFullData: loadFullData) }
                continuation.resume(returning: items)
            }
        }
    }
    
    // MARK: - Encryption Migration

    /// Re-encrypt or decrypt all existing data when security mode changes
    /// - Parameter encrypt: true to encrypt, false to decrypt
    /// - Returns: true if migration succeeded, false if failed
    func migrateEncryption(encrypt: Bool) async -> Bool {
        guard syncOnDBQueue({ db != nil && table != nil }) else {
            await log.error("Database not initialized for encryption migration")
            return false
        }

        await log.info("Starting encryption migration: encrypt=\(encrypt)")

        // 使用分批处理避免一次性加载全表到内存
        let batchSize = 100
        var lastId: Int64 = 0
        var totalProcessed = 0
        var hasError = false

        while !hasError {
            // 分批查询，只获取 id 和需要迁移的字段
            let batchResult: (rows: [Row], count: Int)? = await withDBAsync {
                guard let db = self.db, let table = self.table else { return ([], 0) }
                let query = table
                    .select(Col.id, Col.data, Col.previewData, Col.searchText, Col.appName, Col.customTitle, Col.sourceAnchor, Col.isEncrypted)
                    .filter(Col.id > lastId)
                    .order(Col.id.asc)
                    .limit(batchSize)
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
            let batchSuccess = await withDBAsync {
                guard let db = self.db, let table = self.table else { return false }
                do {
                    try db.transaction {
                        for row in batch.rows {
                            let id = try row.get(Col.id)
                            let rawData = try row.get(Col.data)
                            let rawPreviewData = try row.get(Col.previewData)
                            let rawSearchText = try row.get(Col.searchText)
                            let rawAppName = try row.get(Col.appName)
                            let rawCustomTitle = try row.get(Col.customTitle)
                            let rawSourceAnchor = try row.get(Col.sourceAnchor)
                            let rawIsEncrypted = (try? row.get(Col.isEncrypted)) ?? false

                            let newData: Data
                            let newPreviewData: Data?
                            let newSearchText: String
                            let newAppName: String
                            let newCustomTitle: String?
                            let newSourceAnchor: String?

                            if encrypt {
                                guard let encryptedData = self.encryptDataIfNeeded(rawData) else {
                                    self.notifyEncryptionFailureIfNeeded()
                                    throw NSError(domain: "DeckSQL", code: -10, userInfo: nil)
                                }
                                newData = encryptedData
                                if let rawPreviewData = rawPreviewData {
                                    guard let encryptedPreview = self.encryptDataIfNeeded(rawPreviewData) else {
                                        self.notifyEncryptionFailureIfNeeded()
                                        throw NSError(domain: "DeckSQL", code: -11, userInfo: nil)
                                    }
                                    newPreviewData = encryptedPreview
                                } else {
                                    newPreviewData = nil
                                }
                                guard let encryptedSearch = self.encryptStringIfNeeded(rawSearchText) else {
                                    self.notifyEncryptionFailureIfNeeded()
                                    throw NSError(domain: "DeckSQL", code: -12, userInfo: nil)
                                }
                                newSearchText = encryptedSearch
                                guard let encryptedAppName = self.encryptStringIfNeeded(rawAppName) else {
                                    self.notifyEncryptionFailureIfNeeded()
                                    throw NSError(domain: "DeckSQL", code: -13, userInfo: nil)
                                }
                                newAppName = encryptedAppName
                                if let rawCustomTitle {
                                    guard let encryptedTitle = self.encryptStringIfNeeded(rawCustomTitle) else {
                                        self.notifyEncryptionFailureIfNeeded()
                                        throw NSError(domain: "DeckSQL", code: -15, userInfo: nil)
                                    }
                                    newCustomTitle = encryptedTitle
                                } else {
                                    newCustomTitle = nil
                                }
                                if let rawSourceAnchor {
                                    guard let encryptedAnchor = self.encryptStringIfNeeded(rawSourceAnchor) else {
                                        self.notifyEncryptionFailureIfNeeded()
                                        throw NSError(domain: "DeckSQL", code: -14, userInfo: nil)
                                    }
                                    newSourceAnchor = encryptedAnchor
                                } else {
                                    newSourceAnchor = nil
                                }
                            } else {
                                let decryptedData = SecurityService.shared.decryptSilently(rawData)
                                if rawIsEncrypted && decryptedData == nil && !rawData.isEmpty {
                                    throw NSError(domain: "DeckSQL", code: -16, userInfo: nil)
                                }
                                newData = decryptedData ?? rawData

                                if let rawPreviewData {
                                    let decryptedPreview = SecurityService.shared.decryptSilently(rawPreviewData)
                                    if rawIsEncrypted && decryptedPreview == nil && !rawPreviewData.isEmpty {
                                        throw NSError(domain: "DeckSQL", code: -17, userInfo: nil)
                                    }
                                    newPreviewData = decryptedPreview ?? rawPreviewData
                                } else {
                                    newPreviewData = nil
                                }

                                let maybeDecryptedSearch = self.decryptStringSilently(rawSearchText)
                                if rawIsEncrypted,
                                   maybeDecryptedSearch == rawSearchText,
                                   !rawSearchText.isEmpty,
                                   Data(base64Encoded: rawSearchText) != nil {
                                    throw NSError(domain: "DeckSQL", code: -18, userInfo: nil)
                                }
                                newSearchText = maybeDecryptedSearch

                                let maybeDecryptedAppName = self.decryptStringSilently(rawAppName)
                                if rawIsEncrypted,
                                   maybeDecryptedAppName == rawAppName,
                                   !rawAppName.isEmpty,
                                   Data(base64Encoded: rawAppName) != nil {
                                    throw NSError(domain: "DeckSQL", code: -19, userInfo: nil)
                                }
                                newAppName = maybeDecryptedAppName

                                if let rawCustomTitle {
                                    let maybeDecryptedTitle = self.decryptStringSilently(rawCustomTitle)
                                    if rawIsEncrypted,
                                       maybeDecryptedTitle == rawCustomTitle,
                                       !rawCustomTitle.isEmpty,
                                       Data(base64Encoded: rawCustomTitle) != nil {
                                        throw NSError(domain: "DeckSQL", code: -20, userInfo: nil)
                                    }
                                    newCustomTitle = maybeDecryptedTitle
                                } else {
                                    newCustomTitle = nil
                                }

                                if let rawSourceAnchor {
                                    let maybeDecryptedAnchor = self.decryptStringSilently(rawSourceAnchor)
                                    if rawIsEncrypted,
                                       maybeDecryptedAnchor == rawSourceAnchor,
                                       !rawSourceAnchor.isEmpty,
                                       Data(base64Encoded: rawSourceAnchor) != nil {
                                        throw NSError(domain: "DeckSQL", code: -21, userInfo: nil)
                                    }
                                    newSourceAnchor = maybeDecryptedAnchor
                                } else {
                                    newSourceAnchor = nil
                                }
                            }

                            let query = table.filter(Col.id == id)
                            let update = query.update(
                                Col.data <- newData,
                                Col.previewData <- newPreviewData,
                                Col.searchText <- newSearchText,
                                Col.appName <- newAppName,
                                Col.customTitle <- newCustomTitle,
                                Col.sourceAnchor <- newSourceAnchor,
                                Col.isEncrypted <- encrypt
                            )
                            try db.run(update)
                        }
                    }
                    return true
                } catch {
                    return false
                }
            }

            if batchSuccess != true {
                hasError = true
                break
            }

            totalProcessed += batch.count
            if let lastRow = batch.rows.last, let newLastId = try? lastRow.get(Col.id) {
                if newLastId <= lastId { break }
                lastId = newLastId
            } else {
                break
            }

            // 批次间让出 CPU，避免长时间阻塞
            await Task.yield()
        }

        if hasError {
            await log.error("Encryption migration failed after processing \(totalProcessed) items")
            return false
        }

        await log.info("Encryption migration completed: \(totalProcessed) items processed")

        // 迁移 blob 文件的加密状态
        let blobMigrated = await BlobStorage.shared.migrateEncryption(encrypt: encrypt)
        guard blobMigrated else {
            await log.error("Encryption migration failed: blob migration failed")
            return false
        }

        // 更新数据库中的 blob_path（加密后缀变化）
        let blobPathUpdated = await updateBlobPathsAfterMigration(encrypt: encrypt)
        guard blobPathUpdated else {
            await log.error("Encryption migration failed: blob_path update failed")
            return false
        }

        // 迁移语义向量缓存表的加密状态
        await migrateEmbeddingEncryption(encrypt: encrypt)

        // 加密状态变化后，缓存的解密文本全部失效
        invalidateSearchCache()
        return true
    }

    /// 更新数据库中的 blob_path 字段（加密迁移后路径后缀变化）
    private func updateBlobPathsAfterMigration(encrypt: Bool) async -> Bool {
        let rows: [Row] = await withDBAsync {
            guard let db = self.db, let table = self.table else { return [] }
            // 查找所有有 blob_path 的记录
            let query = table.select(Col.id, Col.blobPath)
                .filter(Col.blobPath != nil)
            return Array(try db.prepare(query))
        } ?? []

        var hasError = false
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
                    guard FileManager.default.fileExists(atPath: newPath) else {
                        hasError = true
                        await log.error("Blob path migration missing file for id=\(id): \(newPath)")
                        continue
                    }
                    let updated: Bool = await withDBAsync {
                        guard let db = self.db, let table = self.table else { return false }
                        let updateQuery = table.filter(Col.id == id)
                        return try db.run(updateQuery.update(Col.blobPath <- newPath)) > 0
                    } ?? false
                    if !updated {
                        hasError = true
                    }
                }
            } catch {
                hasError = true
                continue
            }
        }
        return !hasError
    }

    private func migrateEmbeddingEncryption(encrypt: Bool) async {
        let tab = Table("ClipboardHistory_embedding")
        let batchSize = 200
        var lastId: Int64 = 0

        while true {
            guard !Task.isCancelled else { break }

            let rows: [Row] = await withDBAsync {
                guard let db = self.db else { return [] }
                let query = tab.select(EmbeddingCol.id, EmbeddingCol.embedding)
                    .filter(EmbeddingCol.id > lastId)
                    .order(EmbeddingCol.id.asc)
                    .limit(batchSize)
                return Array(try db.prepare(query))
            } ?? []

            guard !rows.isEmpty else { break }

            var lastBatchId = lastId
            if let lastRow = rows.last, let id = try? lastRow.get(EmbeddingCol.id) {
                lastBatchId = id
            }
            var shouldAbort = false
            let batchSuccess = await withDBAsync {
                guard let db = self.db else { return false }
                do {
                    try db.transaction {
                        for row in rows {
                            if shouldAbort { break }
                            do {
                                let id = try row.get(EmbeddingCol.id)
                                let rawEmbedding = try row.get(EmbeddingCol.embedding)

                                let newEmbedding: Data
                                if encrypt {
                                    if SecurityService.shared.decryptSilently(rawEmbedding) != nil {
                                        newEmbedding = rawEmbedding
                                    } else if let encrypted = SecurityService.shared.encrypt(rawEmbedding) {
                                        newEmbedding = encrypted
                                    } else {
                                        self.notifyEncryptionFailureIfNeeded()
                                        shouldAbort = true
                                        break
                                    }
                                } else {
                                    newEmbedding = SecurityService.shared.decrypt(rawEmbedding) ?? rawEmbedding
                                }

                                let updateQuery = tab.filter(EmbeddingCol.id == id)
                                try db.run(updateQuery.update(EmbeddingCol.embedding <- newEmbedding))
                            } catch {
                                continue
                            }
                        }
                    }
                    return !shouldAbort
                } catch {
                    return false
                }
            }

            guard batchSuccess == true else { return }
            if lastBatchId <= lastId { break }
            lastId = lastBatchId

            if rows.count < batchSize { break }
            await Task.yield()
        }

        if encrypt {
            dropVecTables()
        } else {
            loadSQLiteVecExtensionIfAvailable()
            if syncOnDBQueue({ vecIndexEnabled }) {
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
