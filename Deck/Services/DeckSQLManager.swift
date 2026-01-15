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
//       - Value: 解密后的 searchText + appName（已 lowercased）
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
import SQLite
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
    static let sourceAnchor = Expression<String?>("source_anchor")
    static let searchText = Expression<String>("search_text")
    static let length = Expression<Int>("content_length")
    static let tagId = Expression<Int>("tag_id")
    static let blobPath = Expression<String?>("blob_path")
    static let isTemporary = Expression<Bool>("is_temporary")
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

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Thread Safety (线程安全)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    
    /// 数据库操作队列：SQLite 连接非线程安全，所有 DB 操作必须在此队列上串行执行
    /// - Label: "com.deck.sqlite.queue"
    /// - QoS: .userInitiated - 用户发起的操作，需要快速响应
    /// - 使用方式：通过 `withDB` / `withDBAsync` / `syncOnDBQueue` / `asyncOnDBQueue` 包装
    private let dbQueue = DispatchQueue(label: "com.deck.sqlite.queue", qos: .userInitiated)
    
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
    /// - Value: SearchCacheEntry (解密且小写化后的 searchText + appName)
    /// - Limit: 300 条（平衡性能与内存占用）
    /// - 失效时机：`reinitialize()` / `invalidateSearchCache()`
    private let searchTextCache: NSCache<NSNumber, SearchCacheEntry> = {
        let cache = NSCache<NSNumber, SearchCacheEntry>()
        cache.countLimit = 300  // 限制缓存条目，降低常驻内存
        return cache
    }()

    /// 单例初始化（设置队列检测机制）
    /// - Note: 设置 `dbQueueKey` 用于检测当前是否在 dbQueue 上执行
    override private init() {
        super.init()
        dbQueue.setSpecific(key: dbQueueKey, value: ())
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
            return (false, "数据库连接未建立")
        }

        // 检查数据库是否可读写
        let canWrite = withDB {
            guard let db = self.db else { return false }
            return (try db.scalar("SELECT 1") as? Int64) == 1
        } ?? false

        if !canWrite {
            return (false, "数据库无法正常访问")
        }

        // 检查最近是否有错误
        let recentErrorCount = syncOnErrorStateQueue { consecutiveErrorCount }
        if recentErrorCount > 0 {
            return (false, "最近有 \(recentErrorCount) 次数据库操作失败")
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
        stopSecurityScopedAccess()
        Self.initLock.lock()
        Self.isInitialized = false
        Self.initLock.unlock()
        syncOnDBQueue {
            db = nil
            table = nil
            vecReadyDimensions.removeAll()
            vecMissingDimensionLogged.removeAll()
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
            try syncOnDBQueue {
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
            }

            backfillFileSearchTextIfNeeded()
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
        vecMissingDimensionLogged.removeAll()
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

    private func vecTableName(for dimension: Int) -> String {
        "\(vecTableBaseName)_\(dimension)"
    }

    private func vecTriggerName(for dimension: Int) -> String {
        "\(vecTableBaseName)_ad_\(dimension)"
    }

    private func listVecTables() -> [String] {
        return (try? syncOnDBQueue {
            guard let db = db else { return [] }
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
            guard !tables.isEmpty else { return }
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
            vecReadyDimensions.removeAll()
        }
    }

    private func vecDimension(from tableName: String) -> Int? {
        let prefix = "\(vecTableBaseName)_"
        guard tableName.hasPrefix(prefix) else { return nil }
        return Int(tableName.dropFirst(prefix.count))
    }

    private func ensureVecTable(dimension: Int) {
        syncOnDBQueue {
            guard vecIndexEnabled, dimension > 0 else { return }
            guard let db = db else { return }
            if vecReadyDimensions.contains(dimension) { return }
            let tableName = vecTableName(for: dimension)
            let triggerName = vecTriggerName(for: dimension)
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
        guard syncOnDBQueue({ vecIndexEnabled }) else { return }
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
        guard syncOnDBQueue({ vecIndexEnabled && db != nil }) else { return }

        let batchSize = 100
        let maxItems = DeckUserDefaults.securityModeEnabled ? 300 : 1000
        var processed = 0
        var offset = 0
        var dimensionCounts: [Int: Int] = [:]
        while processed < maxItems {
            guard !Task.isCancelled else { break }

            let rows: [(id: Int64, data: Data)] = syncOnDBQueue {
                guard let db = db else { return [] }
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
                dimensionCounts[vector.count, default: 0] += 1
                updateVecIndex(id: row.id, vector: vector)
                processed += 1
            }

            offset += rows.count
            await Task.yield()
        }

        if processed > 0 {
            let dimensionSummary = dimensionCounts
                .sorted(by: { $0.key < $1.key })
                .map { "\($0.key):\($0.value)" }
                .joined(separator: ", ")
            log.info("Vec index backfill completed: \(processed) items processed (dims: [\(dimensionSummary)])")
        } else {
            log.debug("Vec index backfill completed: 0 items processed")
        }
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
        guard FileManager.default.fileExists(atPath: dbPath) else { return }

        if !force, let attrs = try? FileManager.default.attributesOfItem(atPath: backupPath),
           let modDate = attrs[.modificationDate] as? Date,
           Date().timeIntervalSince(modDate) < backupInterval {
            return
        }

        syncOnDBQueue {
            guard let db = db else { return }
            do {
                try db.run("PRAGMA wal_checkpoint(TRUNCATE)")
            } catch {
                log.debug("Failed to checkpoint WAL before backup: \(error.localizedDescription)")
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
        let batchSize = 500
        var offset = 0
        let maxScan = 5000  // 安全模式下最多扫描 5000 条

        while matchingIds.count < limit && offset < maxScan {
            // 支持任务取消
            guard !Task.isCancelled else { break }

            let rows: [Row] = await withDBAsync {
                guard let db = self.db, let table = self.table else { return [] }
                // 构建基础查询
                var query = table
                    .select(Col.id, Col.searchText)
                    .order(Col.ts.desc)
                    .limit(batchSize, offset: offset)

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

                return Array(try db.prepare(query))
            } ?? []

            // 没有更多数据
            if rows.isEmpty { break }

            for row in rows {
                guard matchingIds.count < limit else { break }
                guard !Task.isCancelled else { break }

                do {
                    let id = try row.get(Col.id)
                    let rawSearchText = try row.get(Col.searchText)
                    let searchText = decryptString(rawSearchText)

                    let range = NSRange(searchText.startIndex..., in: searchText)
                    if regex.firstMatch(in: searchText, range: range) != nil {
                        matchingIds.append(id)
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

        if offset >= maxScan && matchingIds.count < limit {
            log.info("Security mode regex search reached scan limit (\(maxScan) items), results may be incomplete")
        }

        guard !matchingIds.isEmpty else { return [] }

        let fullRows: [Row] = await withDBAsync {
            guard let db = self.db, let table = self.table else { return [] }
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

            return Array(try db.prepare(query))
        } ?? []

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
                    t.column(Col.sourceAnchor)
                    t.column(Col.searchText)
                    t.column(Col.length)
                    t.column(Col.tagId, defaultValue: -1)
                    t.column(Col.blobPath)
                    t.column(Col.isTemporary, defaultValue: false)
                })

                try db.run(tab.createIndex(Col.ts, ifNotExists: true))
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
    private static let currentSchemaVersion: Int32 = 4
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
            backfillSemanticEmbeddingsIfNeeded(targetVersion: Self.currentSchemaVersion)
            return
        }

        if needsTemporaryMigration || needsSourceAnchorMigration {
            if needsTemporaryMigration {
                addTemporaryColumnIfNeeded()
            }
            if needsSourceAnchorMigration {
                addSourceAnchorColumnIfNeeded()
            }
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

            let rows: [Row] = await withDBAsync {
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
            log.info("File search text backfill completed: \(updated) items updated")
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
                log.warn("Large image migration incomplete; schema version not updated")
                return
            }
            if let postMigration {
                await postMigration()
            }
            // 迁移完成后更新数据库版本
            self.setSchemaVersion(finalVersion)
            log.info("Database schema updated to version \(finalVersion)")
        }
    }

    private func performLargeImageMigration() async -> Bool {
        guard syncOnDBQueue({ db != nil && table != nil }) else { return false }

        // 使用分页查询避免一次性加载全部数据
        let batchSize = 50
        var lastId: Int64 = 0
        var totalMigrated = 0

        while true {
            // 支持任务取消
            guard !Task.isCancelled else {
                log.info("Large image migration cancelled after \(totalMigrated) items")
                return false
            }

            // 每次只查询一批需要迁移的图片
            let rows: [Row] = await withDBAsync {
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
                    log.info("Large image migration cancelled after \(totalMigrated) items")
                    return false
                }

                guard let item = rowToClipboardItem(row, isEncrypted: nil) else { continue }
                guard item.data.count > Const.largeBlobThreshold else { continue }
                guard let rowId = try? row.get(Col.id) else { continue }

                let path = await BlobStorage.shared.storeAsync(data: item.data, uniqueId: item.uniqueId)

                guard let path else { continue }

                // Avoid storing preview duplicates for blob-backed items.
                guard let encryptedData = encryptData(Data()) else { return false }

                _ = await withDBAsync {
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

        log.info("Large image migration completed: \(totalMigrated) items migrated")
        await vacuumDatabase(reason: "blob migration")
        return true
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
        let batchSize = 100
        let maxItems = DeckUserDefaults.securityModeEnabled ? 300 : 1000
        var processed = 0

        while processed < maxItems {
            guard !Task.isCancelled else { break }

            let rows: [(id: Int64, searchText: String)] = await withDBAsync {
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
            log.info("Semantic embedding backfill completed: \(processed) items processed")
        }
    }

    private func vacuumDatabase(reason: String) async {
        let didCheckpoint = await withDBAsync {
            guard let db = self.db else { return false }
            try db.run("PRAGMA wal_checkpoint(TRUNCATE)")
            return true
        } == true

        if didCheckpoint {
            log.info("WAL checkpoint completed (\(reason))")
        }

        let didVacuum = await withDBAsync {
            guard let db = self.db else { return false }
            try db.run("VACUUM")
            return true
        } == true

        if didVacuum {
            log.info("Database vacuum completed (\(reason))")
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
//  - 加密列：data, search_text, app_name, embedding
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
    private func decryptData(_ data: Data) -> Data {
        guard DeckUserDefaults.securityModeEnabled else { return data }
        return SecurityService.shared.decrypt(data) ?? data
    }
    
    /// 加密字符串（用于 search_text、app_name 列）
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
    
    /// 解密字符串（用于 search_text、app_name 列）
    /// - Parameter string: Base64 编码的加密数据
    /// - Returns: 解密后的字符串（安全模式下），或原始字符串（非安全模式）
    private func decryptString(_ string: String) -> String {
        guard DeckUserDefaults.securityModeEnabled else { return string }
        guard let data = Data(base64Encoded: string),
              let decrypted = SecurityService.shared.decrypt(data),
              let result = String(data: decrypted, encoding: .utf8) else { return string }
        return result
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
        notifyUserOfDBError("安全模式加密失败，请重新认证或关闭安全模式后重试", isCritical: true)
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

    private func updateVecIndex(id: Int64, vector: [Float]) {
        guard !vector.isEmpty else { return }
        let normalized = normalizeVector(vector)
        syncOnDBQueue {
            guard vecIndexEnabled, !DeckUserDefaults.securityModeEnabled else { return }
            guard let db = db else { return }
            ensureVecTable(dimension: normalized.count)
            guard vecReadyDimensions.contains(normalized.count) else {
                if vecMissingDimensionLogged.insert(normalized.count).inserted {
                    log.debug("Vec table not ready for dimension \(normalized.count); skipping updates")
                }
                return
            }
            let tableName = vecTableName(for: normalized.count)
            let payload = vectorToJSONString(normalized)
            let success = withDB {
                try db.run("DELETE FROM \(tableName) WHERE rowid = ?", id)
                try db.run(
                    "INSERT INTO \(tableName)(rowid, embedding) VALUES (?, ?)",
                    id,
                    payload
                )
                return true
            }
            if success != true {
                log.debug("Vec index update failed for id=\(id), dim=\(normalized.count)")
            }
        }
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

        let tableName = vecTableName(for: normalized.count)
        let payload = vectorToJSONString(normalized)
        log.debug("Vec search: dim=\(normalized.count), table=\(tableName), limit=\(limit)")
        let results: [(id: Int64, distance: Double)] = await withDBAsync({ () throws -> [(id: Int64, distance: Double)] in
            guard let db = self.db else { return [] }
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
        }) ?? []
        log.debug("Vec search results: count=\(results.count)")
        return results
    }

    // MARK: - Search Cache Helpers

    /// 获取缓存的搜索字符串，如果未缓存则解密并缓存
    /// 安全模式下也使用缓存，但会在失焦/会话切换时清空以降低明文驻留
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
        let cacheKey = NSNumber(value: id)

        // 尝试从缓存获取
        if let cached = searchTextCache.object(forKey: cacheKey) {
            return cached
        }

        let resolvedSearchText: String
        let resolvedAppName: String
        if isSecurityMode {
            resolvedSearchText = decryptString(rawSearchText)
            resolvedAppName = decryptString(appName)
        } else {
            resolvedSearchText = rawSearchText
            resolvedAppName = appName
        }

        // 缓存未命中，小写化后存入缓存
        let entry = SearchCacheEntry(
            searchText: resolvedSearchText.lowercased(),
            appName: resolvedAppName.lowercased()
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
        let sourceAnchor: String?
        let searchText: String
        let contentLength: Int
        let tagId: Int
        let blobPath: String?
        let isTemporary: Bool
        let searchTextPlain: String
    }

    private func prepareInsertPayload(for item: ClipboardItem) async -> InsertPayload? {
        var dataToStore = item.data
        var blobPath = item.blobPath
        var previewData = item.previewData
        let isSecurityMode = DeckUserDefaults.securityModeEnabled

        if item.itemType == .image && item.data.count > Const.largeBlobThreshold {
            if let path = BlobStorage.shared.store(data: item.data, uniqueId: item.uniqueId, encrypt: isSecurityMode) {
                blobPath = path

                if previewData == nil || previewData!.isEmpty {
                    previewData = await ClipboardItem.generatePreviewThumbnailDataAsync(from: item.data, maxSize: 200)
                    log.debug("Pre-generated thumbnail for large image (\(item.data.count) bytes)")
                }

                dataToStore = Data()
            }
        } else if item.itemType == .image && item.data.count > 50 * 1024 && (previewData == nil || previewData!.isEmpty) {
            previewData = await ClipboardItem.generatePreviewThumbnailDataAsync(from: item.data, maxSize: 200)
            log.debug("Pre-generated thumbnail for medium image (\(item.data.count) bytes)")
        }

        let encodedSourceAnchor = item.sourceAnchor?.toJSON()
        let encryptedData: Data
        let encryptedPreviewData: Data?
        let encryptedSearchText: String
        let encryptedAppName: String
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
            sourceAnchor: encryptedSourceAnchor,
            searchText: encryptedSearchText,
            contentLength: item.contentLength,
            tagId: item.tagId,
            blobPath: blobPath,
            isTemporary: item.isTemporary,
            searchTextPlain: item.searchText
        )
    }
    
    func insert(item: ClipboardItem) async -> Int64 {
        guard let payload = await prepareInsertPayload(for: item) else { return -1 }

        let result: (rowId: Int64, deleted: Int)? = await withDBAsync {
            guard let db = self.db, let table = self.table else { return (-1, 0) }
            let deleteQuery = table.filter(Col.uniqueId == payload.uniqueId)
            let deleted = try db.run(deleteQuery.delete())
            let insert = table.insert(
                Col.uniqueId <- payload.uniqueId,
                Col.type <- payload.pasteboardType,
                Col.itemType <- payload.itemType,
                Col.data <- payload.data,
                Col.previewData <- payload.previewData,
                Col.ts <- payload.timestamp,
                Col.appPath <- payload.appPath,
                Col.appName <- payload.appName,
                Col.sourceAnchor <- payload.sourceAnchor,
                Col.searchText <- payload.searchText,
                Col.length <- payload.contentLength,
                Col.tagId <- payload.tagId,
                Col.blobPath <- payload.blobPath,
                Col.isTemporary <- payload.isTemporary
            )
            let rowId = try db.run(insert)
            return (rowId, deleted)
        }

        if let result {
            if result.deleted > 0 {
                invalidateSearchCache()
            }
            if result.rowId > 0 {
                log.debug("Inserted item with id: \(result.rowId)")
                scheduleSemanticEmbeddingUpdate(id: result.rowId, searchText: payload.searchTextPlain)
                return result.rowId
            }
        }
        return -1
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
                        Col.sourceAnchor <- payload.sourceAnchor,
                        Col.searchText <- payload.searchText,
                        Col.length <- payload.contentLength,
                        Col.tagId <- payload.tagId,
                        Col.blobPath <- payload.blobPath,
                        Col.isTemporary <- payload.isTemporary
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
            log.debug("Inserted item with id: \(rowId)")
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
            log.debug("Deleted \(count) items")
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
            log.debug("Deleted item with id \(id): \(count) rows")
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
            if let path = BlobStorage.shared.store(data: item.data, uniqueId: item.uniqueId, encrypt: isSecurityMode) {
                blobPathToStore = path

                if previewData == nil || previewData!.isEmpty {
                    previewData = await ClipboardItem.generatePreviewThumbnailDataAsync(from: item.data, maxSize: 200)
                    log.debug("Pre-generated thumbnail for large image (\(item.data.count) bytes) during update")
                }

                dataToStore = Data()
            }
        } else if item.itemType == .image, item.data.count > 50 * 1024, (previewData == nil || previewData!.isEmpty) {
            previewData = await ClipboardItem.generatePreviewThumbnailDataAsync(from: item.data, maxSize: 200)
            log.debug("Pre-generated thumbnail for medium image (\(item.data.count) bytes) during update")
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
        let encryptedSourceAnchor: String?
        let encodedSourceAnchor = item.sourceAnchor?.toJSON()

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
                Col.sourceAnchor <- encryptedSourceAnchor,
                Col.searchText <- encryptedSearchText,
                Col.length <- item.contentLength,
                Col.tagId <- item.tagId,
                Col.blobPath <- blobPathToStore,
                Col.isTemporary <- item.isTemporary
            )
            let count = try db.run(update)
            if count > 0, let old = oldBlobPath, old != blobPathToStore {
                return (count, old)
            }
            return (count, nil)
        })

        if let result {
            log.debug("Updated \(result.count) items")
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
            log.debug("Updated tag for \(count) items")
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
            log.debug("Updated temporary flag for \(count) items")
        }
    }

    /// 更新项目的 searchText（用于 OCR 结果）
    /// 注意：FTS 索引会通过 ClipboardHistory_au 触发器自动更新
    func updateSearchText(id: Int64, searchText: String) async {
        guard syncOnDBQueue({ db != nil && table != nil }) else {
            log.error("OCR DB: Database not initialized")
            return
        }

        log.info("OCR DB: Updating searchText for item \(id), text length: \(searchText.count)")

        // 根据安全模式决定是否加密
        guard let textToStore = encryptString(searchText) else {
            log.error("OCR DB: Failed to encrypt searchText for item \(id)")
            return
        }

        if let count: Int = await withDBAsync({
            guard let db = self.db, let table = self.table else { return 0 }
            let query = table.filter(Col.id == id)
            let update = query.update(Col.searchText <- textToStore)
            return try db.run(update)
        }) {
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
        let ord = order ?? [Col.ts.desc]

        return await withDBAsync {
            guard let db = self.db, let table = self.table else { return [] }
            var query = table.order(ord)
            if let f = filter { query = query.filter(f) }
            if let l = limit { query = query.limit(l, offset: offset ?? 0) }
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

    private func searchWithSQLLike(keyword: String, limit: Int) async -> [Int64] {
        let escaped = escapeForLike(keyword)
        let pattern = "%\(escaped)%"

        return await withDBAsync {
            guard let db = self.db else { return [] }
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
        var offset = 0
        // 安全模式下最多扫描 5000 条（解密开销大），普通模式扫描全量
        let maxScan = isSecurityMode ? 5000 : Int.max

        while matchingIds.count < limit && offset < maxScan {
            // 支持任务取消
            guard !Task.isCancelled else { break }

            let rows: [Row] = await withDBAsync {
                guard let db = self.db, let table = self.table else { return [] }
                let query = table.select(Col.id, Col.searchText, Col.appName)
                    .order(Col.ts.desc)
                    .limit(batchSize, offset: offset)
                return Array(try db.prepare(query))
            } ?? []

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

        // Get matching IDs from FTS
        let matchingIds = await searchFTS(keyword: keyword, limit: limit * 2)
        guard !matchingIds.isEmpty else { return [] }

        let rows = await withDBAsync { () throws -> [Row] in
            guard let db = self.db, let table = self.table else { return [Row]() }
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

            query = query.limit(matchingIds.count)
            return Array(try db.prepare(query))
        } ?? []
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
    
    func fetchAll(limit: Int = 10000, offset: Int = 0, loadFullData: Bool = false) async -> [ClipboardItem] {
        let rows = await withDBAsync { () throws -> [Row] in
            guard let db = self.db, let table = self.table else { return [Row]() }
            let query = table.order(Col.ts.desc).limit(limit, offset: offset)
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

    /// Fetch raw data payload for a single item (used for lazy loading).
    func fetchData(for id: Int64, isEncrypted: Bool? = nil) -> Data? {
        return withDB { () -> Data? in
            guard let db = self.db, let table = self.table else { return nil }
            let query = table.select(Col.data).filter(Col.id == id).limit(1)
            guard let row = try db.pluck(query) else { return nil }
            let rawData = try row.get(Col.data)
            let shouldDecrypt = isEncrypted ?? DeckUserDefaults.securityModeEnabled
            return shouldDecrypt ? decryptData(rawData) : rawData
        } ?? nil
    }

    /// 批量获取多个 ID 的记录，使用单次 SQL 查询
    func fetchBatch(ids: [Int64]) async -> [Row] {
        guard !ids.isEmpty else { return [] }
        return await withDBAsync {
            guard let db = self.db, let table = self.table else { return [] }
            // 使用 WHERE id IN (...) 查询
            let query = table.filter(ids.contains(Col.id))
            return Array(try db.prepare(query))
        } ?? []
    }

    func count(typeFilter: [String]? = nil) async -> Int {
        return await withDBAsync {
            guard let db = self.db, let table = self.table else { return 0 }
            var query = table
            if let types = typeFilter, !types.isEmpty {
                let typeCondition = types.map { Col.itemType == $0 }.reduce(
                    Expression<Bool>(value: false)
                ) { result, condition in
                    result || condition
                }
                query = query.filter(typeCondition)
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
    
    func rowToClipboardItem(_ row: Row, isEncrypted: Bool? = nil, loadFullData: Bool = true) -> ClipboardItem? {
        do {
            let type = try row.get(Col.type)
            let rawData = try row.get(Col.data)
            let timestamp = try row.get(Col.ts)
            let id = try row.get(Col.id)
            let rawAppName = try row.get(Col.appName)
            let rawSourceAnchor = (try? row.get(Col.sourceAnchor)) ?? nil
            let appPath = try row.get(Col.appPath)
            let rawPreviewData = try row.get(Col.previewData)
            let rawSearchText = try row.get(Col.searchText)
            let length = try row.get(Col.length)
            let tagId = try row.get(Col.tagId)
            let blobPath = try row.get(Col.blobPath)
            let storedUniqueId = try row.get(Col.uniqueId)
            let storedItemType = try row.get(Col.itemType)
            let rawIsTemporary = (try? row.get(Col.isTemporary)) ?? false
            let isTemporary = tagId == DeckTag.importantTagId ? false : rawIsTemporary
            if tagId == DeckTag.importantTagId && rawIsTemporary {
                Task { [weak self] in
                    await self?.updateItemTemporary(id: id, isTemporary: false)
                }
            }
            
            // Decrypt data if security mode is enabled
            let shouldDecrypt = isEncrypted ?? DeckUserDefaults.securityModeEnabled
            let data = shouldDecrypt ? decryptData(rawData) : rawData
            let previewData = rawPreviewData.map { shouldDecrypt ? decryptData($0) : $0 }
            let searchText = shouldDecrypt ? decryptString(rawSearchText) : rawSearchText
            let appName = shouldDecrypt ? decryptString(rawAppName) : rawAppName
            let sourceAnchorString = rawSourceAnchor.map { shouldDecrypt ? decryptString($0) : $0 }
            let sourceAnchor = SourceAnchor.fromJSON(sourceAnchorString)

            var inlineData = data
            var dataIsFull = true

            if blobPath != nil {
                dataIsFull = false
                if inlineData.isEmpty, let preview = previewData, !preview.isEmpty {
                    inlineData = preview
                }
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
                sourceAnchor: sourceAnchor,
                searchText: searchText,
                contentLength: length,
                tagId: tagId,
                isTemporary: isTemporary,
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
        guard syncOnDBQueue({ db != nil && table != nil }) else {
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
            let batchResult: (rows: [Row], count: Int)? = await withDBAsync {
                guard let db = self.db, let table = self.table else { return ([], 0) }
                let query = table
                    .select(Col.id, Col.data, Col.previewData, Col.searchText, Col.appName, Col.sourceAnchor)
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
            let batchSuccess = await withDBAsync {
                guard let db = self.db, let table = self.table else { return false }
                for row in batch.rows {
                    let id = try row.get(Col.id)
                    let rawData = try row.get(Col.data)
                    let rawPreviewData = try row.get(Col.previewData)
                    let rawSearchText = try row.get(Col.searchText)
                    let rawAppName = try row.get(Col.appName)
                    let rawSourceAnchor = try row.get(Col.sourceAnchor)

                    let newData: Data
                    let newPreviewData: Data?
                    let newSearchText: String
                    let newAppName: String
                    let newSourceAnchor: String?

                    if encrypt {
                        // Encrypting: data is currently unencrypted
                        guard let encryptedData = SecurityService.shared.encrypt(rawData) else {
                            self.notifyEncryptionFailureIfNeeded()
                            return false
                        }
                        newData = encryptedData
                        if let rawPreviewData = rawPreviewData {
                            guard let encryptedPreview = SecurityService.shared.encrypt(rawPreviewData) else {
                                self.notifyEncryptionFailureIfNeeded()
                                return false
                            }
                            newPreviewData = encryptedPreview
                        } else {
                            newPreviewData = nil
                        }
                        guard let searchData = rawSearchText.data(using: .utf8),
                              let encryptedSearch = SecurityService.shared.encrypt(searchData) else {
                            self.notifyEncryptionFailureIfNeeded()
                            return false
                        }
                        newSearchText = encryptedSearch.base64EncodedString()
                        guard let appNameData = rawAppName.data(using: .utf8),
                              let encryptedAppName = SecurityService.shared.encrypt(appNameData) else {
                            self.notifyEncryptionFailureIfNeeded()
                            return false
                        }
                        newAppName = encryptedAppName.base64EncodedString()
                        if let rawSourceAnchor {
                            guard let anchorData = rawSourceAnchor.data(using: .utf8),
                                  let encryptedAnchor = SecurityService.shared.encrypt(anchorData) else {
                                self.notifyEncryptionFailureIfNeeded()
                                return false
                            }
                            newSourceAnchor = encryptedAnchor.base64EncodedString()
                        } else {
                            newSourceAnchor = nil
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
                        if let decoded = Data(base64Encoded: rawAppName),
                           let decrypted = SecurityService.shared.decrypt(decoded),
                           let str = String(data: decrypted, encoding: .utf8) {
                            newAppName = str
                        } else {
                            newAppName = rawAppName
                        }
                        if let rawSourceAnchor,
                           let decoded = Data(base64Encoded: rawSourceAnchor),
                           let decrypted = SecurityService.shared.decrypt(decoded),
                           let str = String(data: decrypted, encoding: .utf8) {
                            newSourceAnchor = str
                        } else {
                            newSourceAnchor = rawSourceAnchor
                        }
                    }

                    // Update the row
                    let query = table.filter(Col.id == id)
                    let update = query.update(
                        Col.data <- newData,
                        Col.previewData <- newPreviewData,
                        Col.searchText <- newSearchText,
                        Col.appName <- newAppName,
                        Col.sourceAnchor <- newSourceAnchor
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
        let rows: [Row] = await withDBAsync {
            guard let db = self.db, let table = self.table else { return [] }
            // 查找所有有 blob_path 的记录
            let query = table.select(Col.id, Col.blobPath)
                .filter(Col.blobPath != nil)
            return Array(try db.prepare(query))
        } ?? []

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
                    _ = await withDBAsync {
                        guard let db = self.db, let table = self.table else { return }
                        let updateQuery = table.filter(Col.id == id)
                        try db.run(updateQuery.update(Col.blobPath <- newPath))
                    }
                }
            } catch {
                continue
            }
        }
    }

    private func migrateEmbeddingEncryption(encrypt: Bool) async {
        let tab = Table("ClipboardHistory_embedding")
        let batchSize = 200
        var offset = 0

        while true {
            guard !Task.isCancelled else { break }

            let rows: [Row] = await withDBAsync {
                guard let db = self.db else { return [] }
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
                        guard let encrypted = SecurityService.shared.encrypt(rawEmbedding) else {
                            notifyEncryptionFailureIfNeeded()
                            return
                        }
                        newEmbedding = encrypted
                    } else {
                        newEmbedding = SecurityService.shared.decrypt(rawEmbedding) ?? rawEmbedding
                    }

                    _ = await withDBAsync {
                        guard let db = self.db else { return }
                        let updateQuery = tab.filter(EmbeddingCol.id == id)
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
