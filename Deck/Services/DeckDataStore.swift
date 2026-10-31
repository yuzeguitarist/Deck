// Copyright © 2024–2026 Yuze Pan. 保留一切权利。

//
//  DeckDataStore.swift
//  Deck
//
//  Deck Clipboard Manager - SQLite-based storage with pagination
//

import AppKit
import Dispatch
import Observation
@preconcurrency import SQLite

typealias Expression = SQLite.Expression

private struct PreparedSnapshot: @unchecked Sendable {
    let items: [ClipboardItem]
    let totalCount: Int
    let hasMoreData: Bool
    let cursor: DeckSQLManager.RowCursor?
}

struct AIClipboardSearchResult {
    let items: [ClipboardItem]
    let usedMode: SearchMode
}

/// DeckDataStore 使用 @MainActor 确保所有可观察状态的读写都在主线程进行，
/// 避免数据竞争和状态抖动。
@Observable
@MainActor
final class DeckDataStore {
    static let shared = DeckDataStore()
    
    var items: [ClipboardItem] = []
    @ObservationIgnored
    private var recentItemsCache: [ClipboardItem] = []
    private(set) var totalCount: Int = 0
    private(set) var currentPage: Int = 0
    @ObservationIgnored
    private var paginationCursor: DeckSQLManager.RowCursor? = nil
    private(set) var isLoading: Bool = false
    private(set) var hasMoreData: Bool = false
    private(set) var hasNewerDataBeforeCurrentWindow: Bool = false
    private(set) var isPanelActive: Bool = false
    private(set) var isPreparingInitialPresentation: Bool = false
    @ObservationIgnored
    private var isPanelPresenting: Bool = false
    
    enum ChangeType {
        case loadMore
        case loadPrevious
        case search
        case reset
        /// 单次从数据库拉取末尾一页并替换列表（不经过中间分页）。
        case listTail
        /// 单次从数据库拉取最新一页并替换列表（与 listTail 对称，用于 ⌃A 真·回到最新）。
        case listHead
    }
    private(set) var lastChangeType: ChangeType = .reset
    private(set) var isFiltered: Bool = false
    
    private var currentFilter: Expression<Bool>?
    private var currentRuleFilters: SearchRuleFilters = .init()
    private var searchTask: Task<Void, Error>?
    /// Monotonic id of the latest `search` call. Benchmarks wait until
    /// `appliedSearchSerial` catches this value. Not user-visible.
    @ObservationIgnored
    private(set) var searchSerial: UInt64 = 0
    @ObservationIgnored
    private(set) var appliedSearchSerial: UInt64 = 0
    private var paginationTask: Task<Void, Never>?
    private var searchResultsCache: [ClipboardItem] = []
    /// Full hit order without retaining every `ClipboardItem`. Pages are materialized on demand.
    private var searchResultOrder: [Int64] = []
    private struct SearchTitleOverride {
        var value: String?
    }
    private var searchTitleOverrides: [Int64: SearchTitleOverride] = [:]
    private var searchTextOverrides: [Int64: String] = [:]
    private var isSearchCacheActive: Bool = false
    private struct SearchContext: Equatable {
        let keyword: String
        let typeFilter: [String]?
        let tagId: Int
        let ruleFilters: SearchRuleFilters
        let mode: SearchMode
    }
    private var lastSearchContext: SearchContext?
    private var searchCacheCandidateLimit: Int = 0
    private var searchCacheTask: Task<Void, Never>?
    private let sqlManager = DeckSQLManager.shared
    @ObservationIgnored
    private var preparedSnapshot: PreparedSnapshot?
    @ObservationIgnored
    private var preparedTask: Task<Void, Never>?
    @ObservationIgnored
    private var preparedCommitArmed: Bool = false
    @ObservationIgnored
    private var preparedCommitWhenReady: Bool = false
    @ObservationIgnored
    private var preparedCommittedDuringPresentation: Bool = false
    @ObservationIgnored
    private var presentationLiveInserts: [ClipboardItem] = []
    @ObservationIgnored
    private var pendingMissingFileUniqueIds: Set<String> = []
    @ObservationIgnored
    private var preparedGeneration: UInt = 0
    private var isPanelVisibleOrPresenting: Bool {
        isPanelActive || isPanelPresenting
    }

    private var memoryPressureSource: DispatchSourceMemoryPressure?
    private let memoryPressurePresentationCacheLimit = 12
    private let initialPresentationPageSize = 24
    
    private init() {
        startMemoryPressureMonitoring()
    }

    private func startMemoryPressureMonitoring() {
        let queue = DispatchQueue.global(qos: .utility)
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: queue)
        source.setEventHandler(handler: Self.makeMemoryPressureEventHandler(source: source))
        source.resume()
        memoryPressureSource = source
    }

    private nonisolated static func makeMemoryPressureEventHandler(
        source: DispatchSourceMemoryPressure
    ) -> () -> Void {
        { [weak source] in
            let event = source?.data ?? []
            Task { @MainActor in
                Self.shared.handleMemoryPressure(event)
            }
        }
    }

    private func handleMemoryPressure(_ event: DispatchSource.MemoryPressureEvent) {
        // Always drop transient caches first
        sqlManager.clearSearchCache()
        SearchRuleFilters.clearLanguageCache()
        SemanticSearchService.shared.clearCache()
        SearchService.shared.clearPreparedTextCache()
        Task { await SmartContentCache.shared.clearAll() }
        Task(priority: .utility) {
            await sqlManager.shrinkMemory()
        }

        // Only drop UI items when panel is not active to avoid breaking the visible UI.
        if !isPanelActive && (event.contains(.warning) || event.contains(.critical)) {
            releaseMemory()
        } else if event.contains(.critical) {
            // Under critical pressure, at least reset in-memory search results to reduce footprint.
            resetSearchCache()
        }
    }

    private func resetSearchCache() {
        searchResultsCache = []
        searchResultOrder = []
        searchTitleOverrides = [:]
        searchTextOverrides = [:]
        isSearchCacheActive = false
        lastSearchContext = nil
        searchCacheCandidateLimit = 0
        searchCacheTask?.cancel()
        searchCacheTask = nil
    }

    private var searchResultCount: Int {
        searchResultOrder.isEmpty ? searchResultsCache.count : searchResultOrder.count
    }

    /// Remember hit order and keep only `visible` objects alive.
    private func installSearchWindow(_ results: [ClipboardItem], visible: [ClipboardItem]) {
        if !results.isEmpty, results.allSatisfy({ $0.id != nil }) {
            searchResultOrder = results.compactMap(\.id)
            searchResultsCache = visible
        } else {
            searchResultOrder = []
            searchResultsCache = results
        }
    }

    private func materializedItem(id: Int64) -> ClipboardItem? {
        if let item = items.first(where: { $0.id == id }) {
            return item
        }
        return searchResultsCache.first(where: { $0.id == id })
    }

    private func applySearchOverrides(_ item: ClipboardItem) {
        guard let id = item.id else { return }
        if let title = searchTitleOverrides[id] {
            item.customTitle = title.value
        }
        if let text = searchTextOverrides[id], item.searchText != text {
            item.searchText = text
        }
    }

    private func materializeSearchItems(_ ids: [Int64]) async -> [ClipboardItem] {
        guard !ids.isEmpty else { return [] }
        var ordered: [ClipboardItem] = []
        ordered.reserveCapacity(ids.count)
        var missing: [Int64] = []
        missing.reserveCapacity(ids.count)
        for id in ids {
            if let existing = materializedItem(id: id) {
                ordered.append(existing)
            } else {
                missing.append(id)
            }
        }
        if missing.isEmpty {
            return ordered
        }
        let rows = await sqlManager.fetchRowsByIdsUnordered(ids: missing)
        let fetched = await mapRowsToItems(rows)
        var byId: [Int64: ClipboardItem] = [:]
        byId.reserveCapacity(fetched.count)
        for item in fetched {
            if let id = item.id {
                applySearchOverrides(item)
                byId[id] = item
            }
        }
        ordered.removeAll(keepingCapacity: true)
        for id in ids {
            if let existing = materializedItem(id: id) ?? byId[id] {
                ordered.append(existing)
            }
        }
        return ordered
    }

    private func setPreparingInitialPresentation(_ isPreparing: Bool) {
        guard isPreparingInitialPresentation != isPreparing else { return }
        isPreparingInitialPresentation = isPreparing
    }
    
    func setup() {
        sqlManager.setup()
        Task {
            totalCount = await sqlManager.count()
            if isPanelActive {
                await loadInitialData()
            }
        }
    }
    
    func reinitializeStorage() {
        sqlManager.reinitialize()
        Task {
            await loadInitialData()
        }
    }
    
    func getStoragePath() -> String {
        sqlManager.getStorageDirectory()
    }
    
    // MARK: - Data Operations
    
    func loadInitialData() async {
        currentPage = 0
        paginationCursor = nil
        currentFilter = nil
        currentRuleFilters = .init()
        isFiltered = false
        resetSearchCache()

        let pageLimit = initialPresentationPageSize
        let rows = await sqlManager.fetchListPage(limit: pageLimit, cursor: nil)
        paginationCursor = sqlManager.cursor(from: rows.last)
        let loaded = await mapRowsToItems(rows)
        cacheRecentItems(loaded)
        guard isPanelActive else { return }

        items = loaded
        hasMoreData = rows.count == pageLimit
        hasNewerDataBeforeCurrentWindow = false
        lastChangeType = .reset

        let count = await sqlManager.count()
        totalCount = count
        if isPanelActive, lastChangeType == .reset {
            hasMoreData = count > items.count
        }
    }

    func fetchRecentItems(limit: Int, types: [ClipItemType]) async -> [ClipboardItem] {
        guard limit > 0 else { return [] }

        let source = !recentItemsCache.isEmpty ? recentItemsCache : items
        if !source.isEmpty {
            let filtered = types.isEmpty ? source : source.filter { types.contains($0.itemType) }
            return Array(filtered.prefix(limit))
        }

        var filter: Expression<Bool>?
        if !types.isEmpty {
            let rawTypes = types.map(\.rawValue)
            filter = rawTypes.contains(Col.itemType)
        }

        let rows = await sqlManager.fetchListPage(filter: filter, limit: limit, cursor: nil)
        return await mapRowsToItems(rows)
    }

    /// 历史里「最近一条」可被 iOS 同步拉取的纯文本类条目（规则同 `IOSSyncService.firstPullableItem`）。
    /// SQL 层仅按可拉取类型过滤；是否可拉取还需解密后的 `searchText`，故用 keyset 分页逐批拉取，直到命中或历史耗尽，避免单次 `limit` 截断误判为空。
    func fetchLatestIOSSyncPullableItem() async -> ClipboardItem? {
        await Self.fetchLatestIOSSyncPullableItemFromSQL()
    }

    /// iOS 同步后台拉取入口；DB 读取仍走 `DeckSQLManager` 串行队列，Row -> ClipboardItem 映射复用主 actor 上的既有逻辑，避免跨 actor 传递 SQLite.Row。
    static func fetchLatestIOSSyncPullableItemFromSQL() async -> ClipboardItem? {
        let types: [ClipItemType] = [.text, .code, .url, .color, .richText]
        let rawTypes = types.map(\.rawValue)
        let filter = rawTypes.contains(Col.itemType)
        let batchSize = 500
        var cursor: DeckSQLManager.RowCursor?
        let sql = DeckSQLManager.shared

        while !Task.isCancelled {
            let rows = await sql.fetchListPage(filter: filter, limit: batchSize, cursor: cursor)
            if rows.isEmpty { break }

            for row in rows {
                guard !Task.isCancelled else { return nil }
                guard let item = sql.rowToClipboardItem(row, loadFullData: false) else { continue }
                if IOSSyncService.isPullableItem(item) {
                    return item
                }
            }

            if rows.count < batchSize { break }

            cursor = sql.cursor(from: rows.last)
            await Task.yield()
        }

        return nil
    }

    /// 历史里「最近一条」可被 iOS 统一下载入口拉取的内容：文本类、单张图片（可恢复字节）、单个仍在磁盘的文件。
    static func fetchLatestIOSSyncUnifiedPullableItemFromSQL() async -> ClipboardItem? {
        let types: [ClipItemType] = [.text, .code, .url, .color, .richText, .image, .file]
        let rawTypes = types.map(\.rawValue)
        let filter = rawTypes.contains(Col.itemType)
        let batchSize = 500
        var cursor: DeckSQLManager.RowCursor?
        let sql = DeckSQLManager.shared

        while !Task.isCancelled {
            let rows = await sql.fetchListPage(filter: filter, limit: batchSize, cursor: cursor)
            if rows.isEmpty { break }

            for row in rows {
                guard !Task.isCancelled else { return nil }
                guard let item = sql.rowToClipboardItem(row, loadFullData: false) else { continue }
                if IOSSyncService.isUnifiedPullableItem(item) {
                    return item
                }
            }

            if rows.count < batchSize { break }

            cursor = sql.cursor(from: rows.last)
            await Task.yield()
        }

        return nil
    }

    /// iOS 同步 push：SQL 插入已在主线程外完成后，刷新可观察状态（不写入剪贴板）；分支语义对齐 `insertItem`。
    func applyIOSSyncInsertAfterSave(savedItem: ClipboardItem, shouldSyncToCloud: Bool) async {
        totalCount = await sqlManager.count()

        if DeckViewModel.shared.isSearching {
            updateRecentItemsCache(with: savedItem)
            recordPresentationLiveInsert(savedItem)
            return
        }

        if !isPanelVisibleOrPresenting {
            updateRecentItemsCache(with: savedItem)
            return
        }

        applyLiveInsert(savedItem)

        if DeckBuildFlags.isCloudSyncCompiledIn,
           DeckUserDefaults.iCloudSyncEnabled && shouldSyncToCloud,
           let itemId = savedItem.id, itemId > 0 {
            Task.detached(priority: .utility) {
                await CloudSyncService.shared.syncItem(id: itemId)
            }
        }
    }

    func fetchItem(uniqueId: String, loadFullData: Bool = true) async -> ClipboardItem? {
        if let cached = items.first(where: { $0.uniqueId == uniqueId }) {
            if loadFullData {
                _ = cached.resolvedData()
            }
            return cached
        }

        guard let row = await sqlManager.fetchRow(uniqueId: uniqueId) else { return nil }
        return sqlManager.rowToClipboardItem(row, loadFullData: loadFullData)
    }
    
    func loadNextPage() {
        // 防止重复加载
        guard !isLoading else { return }
        guard isPanelActive else { return }

        if isSearchCacheActive {
            let currentOffset = items.count
            let total = searchResultCount
            guard currentOffset < total else {
                expandSearchCacheIfNeeded(currentOffset: currentOffset)
                return
            }

            if searchResultOrder.isEmpty {
                isLoading = true
                defer { isLoading = false }

                currentPage += 1

                let nextItems = Array(searchResultsCache.dropFirst(currentOffset).prefix(Const.pageSize))
                guard !nextItems.isEmpty else {
                    hasMoreData = false
                    return
                }

                items.append(contentsOf: nextItems)
                hasMoreData = items.count < searchResultsCache.count
                lastChangeType = .loadMore
                return
            }

            let end = min(currentOffset + Const.pageSize, searchResultOrder.count)
            let ids = Array(searchResultOrder[currentOffset..<end])
            isLoading = true
            paginationTask?.cancel()
            paginationTask = Task { [weak self] in
                guard let self else { return }
                defer { self.isLoading = false }
                let nextItems = await self.materializeSearchItems(ids)
                guard !Task.isCancelled, self.isPanelActive else { return }
                guard !nextItems.isEmpty else {
                    self.hasMoreData = false
                    return
                }
                self.currentPage += 1
                self.items.append(contentsOf: nextItems)
                self.searchResultsCache.append(contentsOf: nextItems)
                self.hasMoreData = self.items.count < self.searchResultOrder.count
                self.lastChangeType = .loadMore
            }
            return
        }

        guard hasMoreData else { return }
        
        let filter = isFiltered ? currentFilter : nil
        
        paginationTask?.cancel()
        paginationTask = Task { [weak self] in
            guard let self else { return }
            self.isLoading = true
            defer { self.isLoading = false }
            
            let nextPage = self.currentPage + 1
            self.currentPage = nextPage

            // 关键优化：keyset pagination（cursor-based），避免 OFFSET 在大表上的扫描+丢弃成本
            let cursor = self.paginationCursor

            let rows: [Row]
            if let filter = filter {
                rows = await sqlManager.fetchListPage(
                    filter: filter,
                    limit: Const.pageSize,
                    cursor: cursor
                )
            } else {
                rows = await sqlManager.fetchListPage(
                    limit: Const.pageSize,
                    cursor: cursor
                )
            }

            // 基于 DB rows 推进 cursor（不要用 in-memory filtering 后的结果，否则可能重复/死循环）
            let nextCursor = sqlManager.cursor(from: rows.last)
            var newItems = await self.mapRowsToItems(rows)

            guard !Task.isCancelled else { return }
            guard isPanelActive else { return }
            guard !newItems.isEmpty else {
                hasMoreData = false
                return
            }

            paginationCursor = nextCursor
            let fetchedCount = rows.count
            if !currentRuleFilters.isEmpty {
                newItems = currentRuleFilters.apply(to: newItems)
            }

            items.append(contentsOf: newItems)
            hasMoreData = fetchedCount == Const.pageSize
            lastChangeType = .loadMore
        }
    }

    /// `⌃E` 会直接把列表窗口替换成最旧一页；用户再往回滚时，需要从当前窗口前方
    /// 逐页补回更新记录，而不是让 ScrollView 先露出窗口左侧的 survey 卡片。
    @discardableResult
    func loadNewerPageBeforeCurrentWindow() async -> Bool {
        guard !isLoading else { return false }
        guard isPanelActive else { return false }
        guard hasNewerDataBeforeCurrentWindow else { return false }
        guard let firstItem = items.first else {
            hasNewerDataBeforeCurrentWindow = false
            return false
        }

        if isSearchCacheActive {
            let firstIndex: Int?
            if searchResultOrder.isEmpty {
                firstIndex = searchResultsCache.firstIndex(where: { $0.uniqueId == firstItem.uniqueId })
            } else if let firstId = firstItem.id {
                firstIndex = searchResultOrder.firstIndex(of: firstId)
            } else {
                firstIndex = nil
            }
            guard let firstIndex else {
                hasNewerDataBeforeCurrentWindow = false
                return false
            }
            guard firstIndex > 0 else {
                hasNewerDataBeforeCurrentWindow = false
                return false
            }

            isLoading = true
            defer { isLoading = false }

            let startIndex = max(0, firstIndex - Const.pageSize)
            let nextWindow: [ClipboardItem]
            if searchResultOrder.isEmpty {
                nextWindow = Array(searchResultsCache[startIndex..<firstIndex])
            } else {
                let ids = Array(searchResultOrder[startIndex..<firstIndex])
                nextWindow = await materializeSearchItems(ids)
            }
            guard !nextWindow.isEmpty else {
                hasNewerDataBeforeCurrentWindow = false
                return false
            }

            items.insert(contentsOf: nextWindow, at: 0)
            searchResultsCache.insert(contentsOf: nextWindow, at: 0)
            hasNewerDataBeforeCurrentWindow = startIndex > 0
            lastChangeType = .loadPrevious
            return true
        }

        guard let cursor = sqlManager.cursor(from: firstItem) else {
            hasNewerDataBeforeCurrentWindow = false
            return false
        }

        isLoading = true
        defer { isLoading = false }

        let filter = isFiltered ? currentFilter : nil
        let needsRulePass = !currentRuleFilters.isEmpty
        let scanLimit = needsRulePass ? min(Const.pageSize * 40, 2000) : Const.pageSize
        let rows = await sqlManager.fetchListNewerPage(filter: filter, limit: scanLimit, cursor: cursor)
        guard !Task.isCancelled, isPanelActive else { return false }

        var newItems = await mapRowsToItems(rows)
        if needsRulePass {
            await prepareLanguageRuleCacheIfNeeded(currentRuleFilters, for: newItems)
            newItems = currentRuleFilters.apply(to: newItems)
        }

        guard !newItems.isEmpty else {
            hasNewerDataBeforeCurrentWindow = false
            return false
        }

        let adjacentSlice: [ClipboardItem]
        if newItems.count > Const.pageSize {
            adjacentSlice = Array(newItems.prefix(Const.pageSize))
        } else {
            adjacentSlice = newItems
        }

        items.insert(contentsOf: adjacentSlice.reversed(), at: 0)
        hasNewerDataBeforeCurrentWindow = !isFiltered
            ? (totalCount > 0 ? totalCount > items.count : rows.count == scanLimit)
            : (rows.count == scanLimit)
        lastChangeType = .loadPrevious
        return true
    }

    /// 跳到「真·最后一项」：只发 **一次** 数据库/搜索拉取，用末尾一页替换当前 `items`，不逐页加载中间内容。
    /// - 关键词搜索：一次性按上限拉候选，再只保留结果列表的最后 `pageSize` 条（上限与 `expandSearchCacheIfNeeded` 对齐并封顶，避免超大库乱扫）。
    /// - 普通浏览：`ORDER BY ts ASC` 取最旧的一段；有内存规则时单次多取若干行再过滤取末页，仍 capped。
    ///
    /// - Note: 不使用 `isLoading` 互斥，避免与 `loadNextPage` 或其它加载路径互相卡住，导致 ⌃E「只能用一次」。
    @discardableResult
    func jumpToTrueListTail() async -> Bool {
        guard isPanelActive else { return false }

        paginationTask?.cancel()
        paginationTask = nil
        searchCacheTask?.cancel()
        searchCacheTask = nil

        let page = Const.pageSize
        let searchMaxCap = min(max(Const.pageSize * 200, 2000), 10_000)

        if isSearchCacheActive,
           let ctx = lastSearchContext,
           !ctx.keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let isExplicitRegex = ctx.keyword.hasPrefix("/") && ctx.keyword.hasSuffix("/") && ctx.keyword.count > 2
            let searchPattern = isExplicitRegex ? String(ctx.keyword.dropFirst().dropLast()) : ctx.keyword

            let dbRows = await sqlManager.count()
            let cappedLimit: Int
            if dbRows > 80_000 {
                cappedLimit = min(searchMaxCap, max(Const.semanticCandidateLimit, Const.pageSize * 16))
            } else if dbRows > 20_000 {
                cappedLimit = min(searchMaxCap, 4000)
            } else {
                cappedLimit = searchMaxCap
            }

            guard let results = await searchKeywordResults(
                keyword: ctx.keyword,
                searchPattern: searchPattern,
                isExplicitRegex: isExplicitRegex,
                typeFilter: ctx.typeFilter,
                tagId: ctx.tagId,
                ruleFilters: ctx.ruleFilters,
                mode: ctx.mode,
                candidateLimit: cappedLimit,
                debounceFuzzy: false
            ) else {
                return false
            }

            guard !Task.isCancelled, isPanelActive else { return false }

            let tail: [ClipboardItem]
            if results.count > page {
                tail = Array(results.suffix(page))
            } else {
                tail = results
            }

            items = tail
            installSearchWindow(results, visible: tail)
            hasMoreData = false
            hasNewerDataBeforeCurrentWindow = results.count > tail.count
            paginationCursor = nil
            currentPage = 0
            lastChangeType = .listTail
            return true
        }

        let filter = isFiltered ? currentFilter : nil
        let needsRulePass = !currentRuleFilters.isEmpty
        let overscan = needsRulePass ? min(Const.pageSize * 40, 2000) : page

        let rows = await sqlManager.fetchListTailPage(filter: filter, limit: overscan)
        guard !Task.isCancelled, isPanelActive else { return false }

        var newItems = await mapRowsToItems(rows)
        if needsRulePass {
            await prepareLanguageRuleCacheIfNeeded(currentRuleFilters, for: newItems)
            newItems = currentRuleFilters.apply(to: newItems)
        }

        let slice: [ClipboardItem]
        if newItems.count > page {
            slice = Array(newItems.suffix(page))
        } else {
            slice = newItems
        }

        let display = Array(slice.reversed())
        items = display
        if isSearchCacheActive {
            searchResultsCache = display
        }
        paginationCursor = slice.last.flatMap { sqlManager.cursor(from: $0) }
        hasMoreData = false
        hasNewerDataBeforeCurrentWindow = !isFiltered
            ? (totalCount > 0 ? totalCount > display.count : rows.count == overscan)
            : (rows.count == overscan)
        currentPage = 0
        // 末尾一页是最旧的记录，不能写进「最近记录」缓存，否则下次打开面板会把旧记录当成最新一页（#196）。
        lastChangeType = .listTail
        return true
    }

    /// 跳到「真·最新一页」：与 `jumpToTrueListTail` 对称，单次拉取 `ts DESC` 头部一页并替换 `items`，恢复 ⌃E 后丢失的「更晚历史」与向左滑动空间。
    @discardableResult
    func jumpToTrueListHead() async -> Bool {
        guard isPanelActive else { return false }

        paginationTask?.cancel()
        paginationTask = nil
        searchCacheTask?.cancel()
        searchCacheTask = nil

        let page = Const.pageSize
        let searchMaxCap = min(max(Const.pageSize * 200, 2000), 10_000)

        if isSearchCacheActive,
           let ctx = lastSearchContext,
           !ctx.keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let isExplicitRegex = ctx.keyword.hasPrefix("/") && ctx.keyword.hasSuffix("/") && ctx.keyword.count > 2
            let searchPattern = isExplicitRegex ? String(ctx.keyword.dropFirst().dropLast()) : ctx.keyword

            let dbRows = await sqlManager.count()
            let cappedLimit: Int
            if dbRows > 80_000 {
                cappedLimit = min(searchMaxCap, max(Const.semanticCandidateLimit, Const.pageSize * 16))
            } else if dbRows > 20_000 {
                cappedLimit = min(searchMaxCap, 4000)
            } else {
                cappedLimit = searchMaxCap
            }

            guard let results = await searchKeywordResults(
                keyword: ctx.keyword,
                searchPattern: searchPattern,
                isExplicitRegex: isExplicitRegex,
                typeFilter: ctx.typeFilter,
                tagId: ctx.tagId,
                ruleFilters: ctx.ruleFilters,
                mode: ctx.mode,
                candidateLimit: cappedLimit,
                debounceFuzzy: false
            ) else {
                return false
            }

            guard !Task.isCancelled, isPanelActive else { return false }

            let head: [ClipboardItem]
            if results.count > page {
                head = Array(results.prefix(page))
            } else {
                head = results
            }

            items = head
            installSearchWindow(results, visible: head)
            hasMoreData = results.count > head.count
            hasNewerDataBeforeCurrentWindow = false
            paginationCursor = nil
            currentPage = 0
            lastChangeType = .listHead
            return true
        }

        let filter = isFiltered ? currentFilter : nil
        let needsRulePass = !currentRuleFilters.isEmpty
        let overscan = needsRulePass ? min(Const.pageSize * 40, 2000) : page

        let fetchedCount: Int
        var newItems: [ClipboardItem]
        let rows = await sqlManager.fetchListPage(filter: filter, limit: overscan, cursor: nil)
        guard !Task.isCancelled, isPanelActive else { return false }
        fetchedCount = rows.count
        newItems = await mapRowsToItems(rows)
        if needsRulePass {
            await prepareLanguageRuleCacheIfNeeded(currentRuleFilters, for: newItems)
            newItems = currentRuleFilters.apply(to: newItems)
        }

        let slice: [ClipboardItem]
        if newItems.count > page {
            slice = Array(newItems.prefix(page))
        } else {
            slice = newItems
        }

        items = slice

        if isSearchCacheActive {
            searchResultsCache = newItems
            hasMoreData = newItems.count > slice.count
            paginationCursor = nil
        } else {
            paginationCursor = slice.last.flatMap { sqlManager.cursor(from: $0) }
            if slice.count < page {
                hasMoreData = false
            } else {
                hasMoreData = (newItems.count > slice.count) || (fetchedCount == overscan)
            }
        }

        currentPage = 0
        // 只有未筛选的默认列表头部才代表「最近记录」（#196）。
        if !isFiltered, !isSearchCacheActive, currentRuleFilters.isEmpty {
            cacheRecentItems(slice)
        }
        hasNewerDataBeforeCurrentWindow = false
        lastChangeType = .listHead
        return true
    }
    
    func resetToDefault() {
        // Cancel any ongoing search to prevent race condition
        searchTask?.cancel()
        paginationTask?.cancel()
        paginationTask = nil

        // 已在默认列表且无搜索态时，避免重复全量 reload（清空搜索框等路径会频繁触发）。
        if !isFiltered,
           !isSearchCacheActive,
           lastSearchContext == nil,
           currentPage == 0,
           !isLoading,
           !hasNewerDataBeforeCurrentWindow,
           lastChangeType != .listTail,
           lastChangeType != .loadPrevious,
           currentFilter == nil,
           currentRuleFilters.isEmpty {
            resetSearchCache()
            return
        }

        resetSearchCache()
        searchTask = Task(priority: .userInitiated) {
            await loadInitialData()
        }
    }

    /// Prepare initial data without touching published state.
    /// The prepared snapshot can be committed once the panel animation completes.
    func prepareInitialData(commitWhenReady: Bool = false) {
        setPreparingInitialPresentation(items.isEmpty)
        preparedTask?.cancel()
        preparedTask = nil
        preparedSnapshot = nil
        preparedCommitArmed = false
        preparedCommitWhenReady = commitWhenReady
        preparedCommittedDuringPresentation = false
        preparedGeneration &+= 1
        let generation = preparedGeneration

        preparedTask = Task { [weak self] in
            guard let self else { return }
            let pageLimit = self.initialPresentationPageSize
            let rows = await self.sqlManager.fetchListPage(limit: pageLimit, cursor: nil)
            let loaded = await self.mapRowsToItems(rows)
            guard !Task.isCancelled else { return }
            guard self.preparedGeneration == generation else { return }
            let snapshotItems = self.mergePresentationLiveInserts(into: loaded)
            let snapshotTotalCount = max(self.totalCount, snapshotItems.count)

            self.preparedSnapshot = PreparedSnapshot(
                items: snapshotItems,
                totalCount: snapshotTotalCount,
                hasMoreData: rows.count == pageLimit || snapshotTotalCount > snapshotItems.count,
                cursor: self.sqlManager.cursor(from: rows.last)
            )

            if self.preparedCommitWhenReady {
                _ = self.commitPreparedSnapshotIfAvailable()
            } else if self.preparedCommitArmed && self.isPanelActive {
                _ = self.commitPreparedSnapshotIfAvailable()
            }

            let totalCount = await self.sqlManager.count()
            guard !Task.isCancelled else { return }
            guard self.preparedGeneration == generation else { return }

            self.totalCount = totalCount
            if let snapshot = self.preparedSnapshot {
                self.preparedSnapshot = PreparedSnapshot(
                    items: snapshot.items,
                    totalCount: max(totalCount, snapshot.items.count),
                    hasMoreData: snapshot.hasMoreData || totalCount > snapshot.items.count,
                    cursor: snapshot.cursor
                )
            } else if self.isPanelActive && self.lastChangeType == .reset {
                self.hasMoreData = totalCount > self.items.count
            }
        }
    }

    @discardableResult
    private func commitPreparedSnapshotIfAvailable() -> Bool {
        guard let snapshot = preparedSnapshot else { return false }
        let committedItems = mergePresentationLiveInserts(into: snapshot.items)
        let committedTotalCount = max(snapshot.totalCount, totalCount, committedItems.count)
        preparedSnapshot = nil
        preparedCommitArmed = false
        preparedCommitWhenReady = false
        preparedCommittedDuringPresentation = true
        presentationLiveInserts.removeAll(keepingCapacity: true)

        searchTask?.cancel()
        searchTask = nil
        paginationTask?.cancel()
        paginationTask = nil
        resetSearchCache()
        isLoading = false
        currentPage = 0
        paginationCursor = nil
        currentFilter = nil
        currentRuleFilters = .init()
        isFiltered = false
        lastChangeType = .reset

        items = committedItems
        paginationCursor = sqlManager.cursor(from: committedItems.last) ?? snapshot.cursor
        totalCount = committedTotalCount
        cacheRecentItems(committedItems)
        hasMoreData = snapshot.hasMoreData || committedTotalCount > committedItems.count
        hasNewerDataBeforeCurrentWindow = false
        setPreparingInitialPresentation(false)
        return true
    }

    private func cancelPreparedSnapshot() {
        preparedCommitArmed = false
        preparedCommitWhenReady = false
        preparedCommittedDuringPresentation = false
        preparedTask?.cancel()
        preparedTask = nil
        preparedSnapshot = nil
        presentationLiveInserts.removeAll(keepingCapacity: true)
        setPreparingInitialPresentation(false)
    }

    /// Mark the panel as already visible to the data pipeline as soon as the
    /// presentation starts. During the slide animation `isPanelActive` remains
    /// false to avoid arming every active-panel behavior, but newly saved
    /// clipboard items still need to refresh the currently appearing UI.
    func notePanelWillPresent() {
        isPanelPresenting = true
        presentationLiveInserts.removeAll(keepingCapacity: true)
    }

    /// Preload the last lightweight history snapshot before the panel becomes visible.
    /// Doing this before the animation starts avoids the "blank first, then cards" flash
    /// without forcing a fresh DB snapshot to commit during the animation.
    func primePresentationCacheIfNeeded() {
        guard !isPanelActive else { return }
        guard items.isEmpty else { return }
        _ = applyRecentItemsCacheIfNeeded()
    }

    /// AI 工具专用的只读搜索入口。
    /// 不会修改 UI 状态（items/currentPage/isFiltered 等），仅复用现有搜索链路返回结果。
    func searchItemsForAI(
        keyword: String,
        typeFilter: [String]?,
        tagId: Int,
        ruleFilters: SearchRuleFilters,
        preferredMode: SearchMode?,
        useAutoMode: Bool,
        limit: Int
    ) async -> AIClipboardSearchResult? {
        let normalizedKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTypeFilter = (typeFilter?.isEmpty == false) ? typeFilter : nil
        let normalizedTagId = tagId
        let safeLimit = max(1, min(50, limit))

        if normalizedKeyword.isEmpty {
            var filter: Expression<Bool>?
            if let types = normalizedTypeFilter, !types.isEmpty {
                filter = types.contains(Col.itemType)
            }

            if normalizedTagId != -1 {
                let tagCondition = Col.tagId == normalizedTagId
                if let existingFilter = filter {
                    filter = existingFilter && tagCondition
                } else {
                    filter = tagCondition
                }
            }

            if let ruleExpr = buildRuleFilterExpression(ruleFilters) {
                if let existingFilter = filter {
                    filter = existingFilter && ruleExpr
                } else {
                    filter = ruleExpr
                }
            }

            let needsInMemoryRuleFiltering = ruleFilters.requiresInMemoryFiltering ||
                (DeckUserDefaults.securityModeEnabled && (!ruleFilters.appNames.isEmpty || !ruleFilters.appNamesExclude.isEmpty))
            let scanLimit = needsInMemoryRuleFiltering
                ? max(Const.pageSize * 200, safeLimit * 80)
                : max(Const.pageSize, safeLimit * 2)

            let rows = await sqlManager.fetchListPage(filter: filter, limit: scanLimit, cursor: nil)
            var results = await mapRowsToItems(rows)
            await prepareLanguageRuleCacheIfNeeded(ruleFilters, for: results)
            if !ruleFilters.isEmpty {
                results = ruleFilters.apply(to: results)
            }

            let usedMode = preferredMode ?? .exact
            return AIClipboardSearchResult(
                items: Array(results.prefix(safeLimit)),
                usedMode: usedMode
            )
        }

        let isExplicitRegex = normalizedKeyword.hasPrefix("/") &&
            normalizedKeyword.hasSuffix("/") &&
            normalizedKeyword.count > 2
        let searchPattern = isExplicitRegex
            ? String(normalizedKeyword.dropFirst().dropLast())
            : normalizedKeyword

        let modeChain: [SearchMode]
        if useAutoMode {
            modeChain = isExplicitRegex ? [.regex] : [.semantic, .mixed, .exact]
        } else if let preferredMode {
            modeChain = [preferredMode]
        } else {
            modeChain = [DeckUserDefaults.searchMode]
        }

        var lastMode = modeChain.last ?? .exact
        for mode in modeChain {
            let candidateLimit = defaultCandidateLimit(mode: mode, isExplicitRegex: isExplicitRegex)
            guard let results = await searchKeywordResults(
                keyword: normalizedKeyword,
                searchPattern: searchPattern,
                isExplicitRegex: isExplicitRegex,
                typeFilter: normalizedTypeFilter,
                tagId: normalizedTagId,
                ruleFilters: ruleFilters,
                mode: mode,
                candidateLimit: candidateLimit,
                debounceFuzzy: false
            ) else {
                return nil
            }
            lastMode = mode
            if !results.isEmpty {
                return AIClipboardSearchResult(
                    items: Array(results.prefix(safeLimit)),
                    usedMode: mode
                )
            }
        }

        return AIClipboardSearchResult(items: [], usedMode: lastMode)
    }
    
    func search(
        keyword: String,
        typeFilter: [String]?,
        tagId: Int,
        ruleFilters: SearchRuleFilters,
        searchMode: SearchMode? = nil
    ) {
        searchTask?.cancel()
        // Prevent an in-flight pagination from appending stale items after a new search.
        paginationTask?.cancel()
        paginationTask = nil
        searchCacheTask?.cancel()
        searchCacheTask = nil
        searchSerial &+= 1
        let searchSerial = self.searchSerial
        searchTask = Task {
            defer {
                if !Task.isCancelled {
                    self.appliedSearchSerial = searchSerial
                }
            }
            currentPage = 0
            paginationCursor = nil
            currentFilter = nil
            currentRuleFilters = ruleFilters

            let isKeywordSearch = !keyword.isEmpty
            let hasRuleFilters = !ruleFilters.isEmpty
            let needsInMemoryRuleFiltering = ruleFilters.requiresInMemoryFiltering ||
                (DeckUserDefaults.securityModeEnabled && (!ruleFilters.appNames.isEmpty || !ruleFilters.appNamesExclude.isEmpty))
            let inMemoryRuleScanLimit = max(Const.pageSize * 200, 2000)

            isFiltered = isKeywordSearch || typeFilter != nil || tagId != -1 || hasRuleFilters
            searchResultsCache = []
            searchResultOrder = []
            isSearchCacheActive = isKeywordSearch || needsInMemoryRuleFiltering
            if !isKeywordSearch && !needsInMemoryRuleFiltering {
                lastSearchContext = nil
                searchCacheCandidateLimit = 0
            }

            let mode = searchMode ?? DeckUserDefaults.searchMode

            // Check if explicitly using regex syntax (pattern: /regex/)
            let isExplicitRegex = keyword.hasPrefix("/") && keyword.hasSuffix("/") && keyword.count > 2
            let searchPattern = isExplicitRegex ? String(keyword.dropFirst().dropLast()) : keyword

            var results: [ClipboardItem]
            var nextCursor: DeckSQLManager.RowCursor? = nil
            var canExpandFilteredListCache = false
            if isKeywordSearch {
                let candidateLimit = defaultCandidateLimit(mode: mode, isExplicitRegex: isExplicitRegex)
                lastSearchContext = SearchContext(
                    keyword: keyword,
                    typeFilter: typeFilter,
                    tagId: tagId,
                    ruleFilters: ruleFilters,
                    mode: mode
                )
                searchCacheCandidateLimit = candidateLimit

                guard let keywordResults = await searchKeywordResults(
                    keyword: keyword,
                    searchPattern: searchPattern,
                    isExplicitRegex: isExplicitRegex,
                    typeFilter: typeFilter,
                    tagId: tagId,
                    ruleFilters: ruleFilters,
                    mode: mode,
                    candidateLimit: candidateLimit
                ) else {
                    lastSearchContext = nil
                    searchCacheCandidateLimit = 0
                    items = []
                    hasMoreData = false
                    hasNewerDataBeforeCurrentWindow = false
                    lastChangeType = .search
                    return
                }
                results = keywordResults
            } else {
                if needsInMemoryRuleFiltering {
                    lastSearchContext = SearchContext(
                        keyword: "",
                        typeFilter: typeFilter,
                        tagId: tagId,
                        ruleFilters: ruleFilters,
                        mode: mode
                    )
                    searchCacheCandidateLimit = inMemoryRuleScanLimit
                }

                // No keyword, just filter by type/tag
                var filter: Expression<Bool>?

                if let types = typeFilter, !types.isEmpty {
                    filter = types.contains(Col.itemType)
                }

                if tagId != -1 {
                    let tagCondition = Col.tagId == tagId
                    if let existingFilter = filter {
                        filter = existingFilter && tagCondition
                    } else {
                        filter = tagCondition
                    }
                }

                if let ruleExpr = buildRuleFilterExpression(ruleFilters) {
                    if let existingFilter = filter {
                        filter = existingFilter && ruleExpr
                    } else {
                        filter = ruleExpr
                    }
                }

                currentFilter = filter
                let scanLimit = needsInMemoryRuleFiltering ? inMemoryRuleScanLimit : Const.pageSize
                let rows = await sqlManager.fetchListPage(filter: filter, limit: scanLimit, cursor: nil)
                nextCursor = sqlManager.cursor(from: rows.last)
                canExpandFilteredListCache = needsInMemoryRuleFiltering &&
                    rows.count == scanLimit &&
                    nextCursor != nil
                results = await mapRowsToItems(rows)
                await prepareLanguageRuleCacheIfNeeded(ruleFilters, for: results)
                if !ruleFilters.isEmpty {
                    results = ruleFilters.apply(to: results)
                }
            }

            // Limit results
            let finalResults = Array(results.prefix(Const.pageSize))

            try Task.checkCancellation()

            guard isPanelActive else { return }
            items = finalResults
            hasNewerDataBeforeCurrentWindow = false
            if isSearchCacheActive {
                if searchResultOrder.isEmpty {
                    installSearchWindow(results, visible: finalResults)
                } else {
                    searchResultsCache = finalResults
                }
                paginationCursor = isKeywordSearch ? nil : nextCursor
                let totalHits = searchResultOrder.isEmpty ? results.count : searchResultOrder.count
                hasMoreData = totalHits > finalResults.count ||
                    (!isKeywordSearch && canExpandFilteredListCache && results.count == finalResults.count)
            } else {
                hasMoreData = results.count == Const.pageSize
                paginationCursor = nextCursor
            }
            results.removeAll(keepingCapacity: false)
            await sqlManager.shrinkMemory()
            if isKeywordSearch, log.isEnabled(.debug) {
                let preview = results.prefix(10).compactMap { $0.id }.map(String.init).joined(separator: ", ")
                if !preview.isEmpty {
                    await log.debug("Search results (top10 ids): [\(preview)]")
                }
            }
            lastChangeType = .search
        }
    }

    private func defaultCandidateLimit(mode: SearchMode, isExplicitRegex: Bool) -> Int {
        if mode == .semantic {
            return Const.semanticCandidateLimit
        }
        if isExplicitRegex || mode == .regex {
            return Const.pageSize * 2
        }
        let useFuzzy = mode == .fuzzy || mode == .mixed
        return useFuzzy ? Const.pageSize * 4 : Const.pageSize * 2
    }

    private func searchKeywordResults(
        keyword: String,
        searchPattern: String,
        isExplicitRegex: Bool,
        typeFilter: [String]?,
        tagId: Int,
        ruleFilters: SearchRuleFilters,
        mode: SearchMode,
        candidateLimit: Int,
        debounceFuzzy: Bool = true
    ) async -> [ClipboardItem]? {
        guard !keyword.isEmpty else { return [] }

        // Determine search strategy based on mode
        let useRegex = isExplicitRegex || mode == .regex
        let useFuzzy = mode == .fuzzy || mode == .mixed
        let useSemantic = mode == .semantic

        var results: [ClipboardItem]

        if useSemantic {
            results = await semanticSearchResults(
                keyword: keyword,
                typeFilter: typeFilter,
                tagId: tagId,
                limit: candidateLimit,
                fallbackToFTS: true
            )
        } else if useRegex && !searchPattern.isEmpty {
            // Regex search: 使用 SQLite 自定义 REGEXP 函数在数据库层过滤
            // 验证正则表达式有效性
            guard RegexCache.shared.regex(for: searchPattern) != nil else {
                return nil
            }

            // 警告：正则搜索在大数据集上可能较慢（全表扫描）
            let currentCount = totalCount
            if currentCount > 5000 {
                await log.info("[PERF WARNING] Regex search on large dataset (\(currentCount) items) may be slow")
            }

            let rows = await sqlManager.searchWithRegex(
                pattern: searchPattern,
                typeFilter: typeFilter,
                tagId: tagId != -1 ? tagId : nil,
                limit: candidateLimit
            )
            results = await mapRowsToItems(rows)
        } else if mode == .exact {
            // Exact mode is a literal containment filter. Do not let FTS/BM25
            // relevance reorder equal substring hits; users expect newest
            // clipboard entries first when each result contains the query.
            let exactKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
            let rows: [Row]
            if DeckUserDefaults.securityModeEnabled {
                // Security mode cannot SQL-LIKE encrypted fields; `searchWithFTS`
                // falls back to the decrypted in-memory exact search, ordered by
                // timestamp DESC / id DESC.
                rows = await sqlManager.searchWithFTS(
                    keyword: exactKeyword,
                    typeFilter: typeFilter,
                    tagId: tagId != -1 ? tagId : nil,
                    limit: candidateLimit
                )
            } else {
                rows = await sqlManager.searchWithSQLLikeRows(
                    keyword: exactKeyword,
                    typeFilter: typeFilter,
                    tagId: tagId != -1 ? tagId : nil,
                    limit: candidateLimit
                )
            }
            results = await mapRowsToItems(rows)
        } else {
            // Fetch lightweight rows first. In fuzzy/mixed mode we rank snapshots and only
            // materialize ClipboardItem objects for the ordered hits; this avoids allocating
            // full ClipboardItem graphs for candidates that will be discarded by fuzzy scoring.
            var candidateRows = await sqlManager.searchWithFTS(
                keyword: keyword,
                typeFilter: typeFilter,
                tagId: tagId != -1 ? tagId : nil,
                limit: candidateLimit
            )

            if useFuzzy {
                let exactIds: [String]
                if DeckUserDefaults.securityModeEnabled, mode == .mixed, !candidateRows.isEmpty {
                    // In security mode `searchWithFTS` already falls back to an exact,
                    // decrypted in-memory match. Re-running exact ranking over decrypted
                    // snapshots duplicates the hottest work in encrypted mixed search.
                    exactIds = candidateRows.compactMap { row in
                        try? row.get(Col.uniqueId)
                    }
                } else if mode == .mixed, !candidateRows.isEmpty {
                    exactIds = await orderedUniqueIdsFromSearchSnapshots(
                        query: keyword,
                        snapshots: mapRowsToSearchSnapshots(candidateRows),
                        mode: .exact
                    )
                } else {
                    exactIds = []
                }

                // If we already have exact hits in mixed mode, skip expensive fuzzy fallback.
                if mode == .mixed, !exactIds.isEmpty {
                    results = await orderedClipboardItemsForSearch(uniqueIds: exactIds, rows: candidateRows)
                } else {
                    if debounceFuzzy {
                        // Wait for a short idle window so we don't run fuzzy on every keystroke.
                        try? await Task.sleep(nanoseconds: 200_000_000)
                    }
                    guard !Task.isCancelled else { return [] }

                    // If FTS returns very few candidates, try a limited LIKE search to broaden cheaply.
                    if candidateRows.count < 10, !DeckUserDefaults.securityModeEnabled {
                        let likeRows = await sqlManager.searchWithSQLLikeRows(
                            keyword: keyword,
                            typeFilter: typeFilter,
                            tagId: tagId != -1 ? tagId : nil,
                            limit: candidateLimit
                        )
                        candidateRows = mergeRows(primary: candidateRows, secondary: likeRows, limit: candidateLimit)
                    }

                    // If fuzzy/mixed mode and we still didn't find enough results, fetch more and filter in memory.
                    if candidateRows.count < 10 {
                        var allFilter: Expression<Bool>?

                        if let types = typeFilter, !types.isEmpty {
                            allFilter = types.contains(Col.itemType)
                        }

                        if tagId != -1 {
                            let tagCondition = Col.tagId == tagId
                            if let existingFilter = allFilter {
                                allFilter = existingFilter && tagCondition
                            } else {
                                allFilter = tagCondition
                            }
                        }

                        // Hard cap to avoid multi-second scans that spike CPU / energy.
                        let scanLimit = min(Const.pageSize * 100, 2000)
                        let batchSize = Const.pageSize * 2
                        var cursor: DeckSQLManager.RowCursor? = nil
                        var allRows: [Row] = []
                        allRows.reserveCapacity(min(scanLimit, batchSize))

                        while allRows.count < scanLimit {
                            guard !Task.isCancelled else { return [] }

                            let remaining = scanLimit - allRows.count
                            let limit = min(batchSize, remaining)
                            let batchRows = await sqlManager.fetchListPage(
                                filter: allFilter,
                                limit: limit,
                                cursor: cursor
                            )

                            guard !batchRows.isEmpty else { break }
                            allRows.append(contentsOf: batchRows)

                            cursor = sqlManager.cursor(from: batchRows.last)
                            if batchRows.count < limit || cursor == nil { break }
                            await Task.yield()
                        }

                        results = await runInMemorySearchRows(
                            query: keyword,
                            rows: allRows,
                            mode: mode,
                            useRegex: useRegex
                        )
                    } else if !candidateRows.isEmpty {
                        // Re-rank using SearchService for better fuzzy matching.
                        results = await runInMemorySearchRows(
                            query: keyword,
                            rows: candidateRows,
                            mode: mode,
                            useRegex: useRegex
                        )
                    } else {
                        results = []
                    }
                }
            } else {
                results = await mapRowsToItems(candidateRows)
            }
            // 混合模式不再使用语义搜索，仅在切换到"语义搜索"模式时才使用
        }

        if mode != .exact && searchResultOrder.isEmpty {
            results = prioritizeTitleMatches(results, keyword: searchPattern, useRegex: useRegex)
        }
        await prepareLanguageRuleCacheIfNeeded(ruleFilters, for: results)
        if !ruleFilters.isEmpty {
            results = ruleFilters.apply(to: results)
        }
        return results
    }

    private func expandSearchCacheIfNeeded(currentOffset: Int) {
        guard !isLoading else { return }
        guard let context = lastSearchContext else {
            hasMoreData = false
            return
        }

        if context.keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            expandFilteredListCacheIfNeeded(currentOffset: currentOffset, context: context)
            return
        }

        let isExplicitRegex = context.keyword.hasPrefix("/") && context.keyword.hasSuffix("/") && context.keyword.count > 2
        let searchPattern = isExplicitRegex ? String(context.keyword.dropFirst().dropLast()) : context.keyword
        let currentLimit = max(searchCacheCandidateLimit, Const.pageSize * 2)
        let maxLimit = max(Const.pageSize * 200, 2000)
        let nextLimit = min(max(currentLimit * 2, currentLimit + Const.pageSize * 2), maxLimit)

        guard nextLimit > currentLimit else {
            hasMoreData = false
            return
        }

        isLoading = true
        searchCacheTask?.cancel()
        searchCacheTask = Task { [weak self] in
            guard let self else { return }
            defer { self.isLoading = false }

            guard let results = await self.searchKeywordResults(
                keyword: context.keyword,
                searchPattern: searchPattern,
                isExplicitRegex: isExplicitRegex,
                typeFilter: context.typeFilter,
                tagId: context.tagId,
                ruleFilters: context.ruleFilters,
                mode: context.mode,
                candidateLimit: nextLimit,
                debounceFuzzy: false
            ) else {
                self.hasMoreData = false
                return
            }

            guard !Task.isCancelled else { return }
            guard self.isPanelActive else { return }
            guard self.lastSearchContext == context else { return }

            let previousCount = self.searchResultCount
            let useNew = results.count >= previousCount
            if useNew {
                self.installSearchWindow(results, visible: self.items)
            }
            let totalCount = self.searchResultCount
            guard totalCount > currentOffset else {
                self.hasMoreData = false
                return
            }

            self.searchCacheCandidateLimit = nextLimit
            let nextItems: [ClipboardItem]
            if !self.searchResultOrder.isEmpty {
                let end = min(currentOffset + Const.pageSize, self.searchResultOrder.count)
                let ids = Array(self.searchResultOrder[currentOffset..<end])
                nextItems = await self.materializeSearchItems(ids)
            } else {
                let source = useNew ? results : self.searchResultsCache
                nextItems = Array(source.dropFirst(currentOffset).prefix(Const.pageSize))
            }
            guard !nextItems.isEmpty else {
                self.hasMoreData = false
                return
            }

            self.currentPage += 1
            self.items.append(contentsOf: nextItems)
            self.searchResultsCache.append(contentsOf: nextItems)
            self.hasMoreData = self.items.count < totalCount
            self.lastChangeType = .loadMore
        }
    }

    private func expandFilteredListCacheIfNeeded(currentOffset: Int, context: SearchContext) {
        guard let cursor = paginationCursor else {
            hasMoreData = false
            return
        }

        let scanLimit = max(searchCacheCandidateLimit, max(Const.pageSize * 200, 2000))
        isLoading = true
        searchCacheTask?.cancel()
        searchCacheTask = Task { [weak self] in
            guard let self else { return }
            defer { self.isLoading = false }

            let rows = await self.sqlManager.fetchListPage(
                filter: self.currentFilter,
                limit: scanLimit,
                cursor: cursor
            )
            let nextCursor = self.sqlManager.cursor(from: rows.last)
            var results = await self.mapRowsToItems(rows)
            await self.prepareLanguageRuleCacheIfNeeded(context.ruleFilters, for: results)
            if !context.ruleFilters.isEmpty {
                results = context.ruleFilters.apply(to: results)
            }

            guard !Task.isCancelled else { return }
            guard self.isPanelActive else { return }
            guard self.lastSearchContext == context else { return }

            self.paginationCursor = nextCursor
            if !results.isEmpty, results.allSatisfy({ $0.id != nil }) {
                self.searchResultOrder.append(contentsOf: results.compactMap(\.id))
            } else if !results.isEmpty {
                self.searchResultsCache.append(contentsOf: results)
            }

            guard self.searchResultCount > currentOffset else {
                self.hasMoreData = nextCursor != nil && rows.count == scanLimit
                return
            }

            let nextItems: [ClipboardItem]
            if !self.searchResultOrder.isEmpty {
                let end = min(currentOffset + Const.pageSize, self.searchResultOrder.count)
                let ids = Array(self.searchResultOrder[currentOffset..<end])
                nextItems = await self.materializeSearchItems(ids)
            } else {
                nextItems = Array(self.searchResultsCache.dropFirst(currentOffset).prefix(Const.pageSize))
            }
            guard !nextItems.isEmpty else {
                self.hasMoreData = nextCursor != nil && rows.count == scanLimit
                return
            }

            self.currentPage += 1
            self.items.append(contentsOf: nextItems)
            self.searchResultsCache.append(contentsOf: nextItems)
            self.hasMoreData = self.items.count < self.searchResultCount ||
                (nextCursor != nil && rows.count == scanLimit)
            self.lastChangeType = .loadMore
        }
    }

    private func buildRuleFilterExpression(_ ruleFilters: SearchRuleFilters) -> Expression<Bool>? {
        var expr: Expression<Bool>?

        if !ruleFilters.dateIntervals.isEmpty {
            var includeExpr: Expression<Bool>?
            for interval in ruleFilters.dateIntervals {
                let start = Int64(interval.start.timeIntervalSince1970)
                let end = Int64(interval.end.timeIntervalSince1970)
                let dateExpr = (Col.ts >= start) && (Col.ts < end)
                if let existing = includeExpr {
                    includeExpr = existing || dateExpr
                } else {
                    includeExpr = dateExpr
                }
            }
            if let includeExpr {
                expr = expr == nil ? includeExpr : (expr! && includeExpr)
            }
        }

        if !ruleFilters.dateIntervalsExclude.isEmpty {
            var excludeExpr: Expression<Bool>?
            for interval in ruleFilters.dateIntervalsExclude {
                let start = Int64(interval.start.timeIntervalSince1970)
                let end = Int64(interval.end.timeIntervalSince1970)
                let dateExpr = (Col.ts >= start) && (Col.ts < end)
                if let existing = excludeExpr {
                    excludeExpr = existing || dateExpr
                } else {
                    excludeExpr = dateExpr
                }
            }
            if let excludeExpr {
                expr = expr == nil ? !excludeExpr : (expr! && !excludeExpr)
            }
        }

        if !ruleFilters.appNames.isEmpty, !DeckUserDefaults.securityModeEnabled {
            let lowerApp = Expression<String>(literal: "LOWER(app_name)")
            let noSpaceApp = Expression<String>(literal: "REPLACE(LOWER(app_name), ' ', '')")
            var includeExpr: Expression<Bool>?
            for rawApp in ruleFilters.appNames {
                let normalized = rawApp.trimmingCharacters(in: .whitespacesAndNewlines)
                if normalized.isEmpty { continue }
                let q = normalized.lowercased()
                let qNoSpaces = q.replacingOccurrences(of: " ", with: "")
                let appExpr = lowerApp.like("%\(q)%") || noSpaceApp.like("%\(qNoSpaces)%")
                if let existing = includeExpr {
                    includeExpr = existing || appExpr
                } else {
                    includeExpr = appExpr
                }
            }
            if let includeExpr {
                expr = expr == nil ? includeExpr : (expr! && includeExpr)
            }
        }

        if !ruleFilters.appNamesExclude.isEmpty, !DeckUserDefaults.securityModeEnabled {
            let lowerApp = Expression<String>(literal: "LOWER(app_name)")
            let noSpaceApp = Expression<String>(literal: "REPLACE(LOWER(app_name), ' ', '')")
            var excludeExpr: Expression<Bool>?
            for rawApp in ruleFilters.appNamesExclude {
                let normalized = rawApp.trimmingCharacters(in: .whitespacesAndNewlines)
                if normalized.isEmpty { continue }
                let q = normalized.lowercased()
                let qNoSpaces = q.replacingOccurrences(of: " ", with: "")
                let appExpr = lowerApp.like("%\(q)%") || noSpaceApp.like("%\(qNoSpaces)%")
                if let existing = excludeExpr {
                    excludeExpr = existing || appExpr
                } else {
                    excludeExpr = appExpr
                }
            }
            if let excludeExpr {
                expr = expr == nil ? !excludeExpr : (expr! && !excludeExpr)
            }
        }

        func typeExpr(for type: SearchRuleContentType) -> Expression<Bool>? {
            switch type {
            case .image:
                return Col.itemType == "image"
            case .code:
                return Col.itemType == "code"
            case .url:
                return Col.itemType == "url"
            case .file:
                return Col.itemType == "file"
            case .text:
                return (Col.itemType == "text") || (Col.itemType == "richText")
            case .color:
                return Col.itemType == "color"
            case .lan:
                return Col.receivedFromLan == true
            }
        }

        if !ruleFilters.includeTypes.isEmpty {
            var includeExpr: Expression<Bool>?
            for t in ruleFilters.includeTypes {
                guard let tExpr = typeExpr(for: t) else { continue }
                if let existing = includeExpr {
                    includeExpr = existing || tExpr
                } else {
                    includeExpr = tExpr
                }
            }
            if let includeExpr {
                expr = expr == nil ? includeExpr : (expr! && includeExpr)
            }
        }

        if !ruleFilters.excludeTypes.isEmpty {
            var excludeExpr: Expression<Bool>?
            for t in ruleFilters.excludeTypes {
                guard let tExpr = typeExpr(for: t) else { continue }
                if let existing = excludeExpr {
                    excludeExpr = existing || tExpr
                } else {
                    excludeExpr = tExpr
                }
            }
            if let excludeExpr {
                expr = expr == nil ? !excludeExpr : (expr! && !excludeExpr)
            }
        }

        if !ruleFilters.includeLanguages.isEmpty {
            let langTypeExpr: Expression<Bool> = (Col.itemType == "text") ||
                (Col.itemType == "richText") ||
                (Col.itemType == "code")
            expr = expr == nil ? langTypeExpr : (expr! && langTypeExpr)
        }

        if !ruleFilters.sizeFilters.isEmpty || !ruleFilters.sizeFiltersExclude.isEmpty {
            let textLikeExpr: Expression<Bool> = (Col.itemType == "text") ||
                (Col.itemType == "richText") ||
                (Col.itemType == "code") ||
                (Col.itemType == "url") ||
                (Col.itemType == "color")

            func lengthExpr(for filter: SearchRuleSizeFilter) -> Expression<Bool> {
                switch filter.op {
                case .greaterThan:
                    return Col.length > filter.value
                case .lessThan:
                    return Col.length < filter.value
                case .equals:
                    return Col.length == filter.value
                }
            }

            if !ruleFilters.sizeFilters.isEmpty {
                var includeExpr: Expression<Bool>?
                for filter in ruleFilters.sizeFilters {
                    let filterExpr = lengthExpr(for: filter)
                    if let existing = includeExpr {
                        includeExpr = existing || filterExpr
                    } else {
                        includeExpr = filterExpr
                    }
                }
                if let includeExpr {
                    let sizeExpr = (textLikeExpr && includeExpr) || !textLikeExpr
                    expr = expr == nil ? sizeExpr : (expr! && sizeExpr)
                }
            }

            if !ruleFilters.sizeFiltersExclude.isEmpty {
                var excludeExpr: Expression<Bool>?
                for filter in ruleFilters.sizeFiltersExclude {
                    let filterExpr = lengthExpr(for: filter)
                    if let existing = excludeExpr {
                        excludeExpr = existing || filterExpr
                    } else {
                        excludeExpr = filterExpr
                    }
                }
                if let excludeExpr {
                    let sizeExpr = (textLikeExpr && !excludeExpr) || !textLikeExpr
                    expr = expr == nil ? sizeExpr : (expr! && sizeExpr)
                }
            }
        }

        return expr
    }

    private func prioritizeTitleMatches(
        _ items: [ClipboardItem],
        keyword: String,
        useRegex: Bool
    ) -> [ClipboardItem] {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return items }

        let regex = useRegex ? RegexCache.shared.regex(for: trimmed) : nil
        let compareOptions: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        var matches: [ClipboardItem] = []
        var rest: [ClipboardItem] = []
        matches.reserveCapacity(min(items.count, 64))
        rest.reserveCapacity(items.count)

        for item in items {
            guard let title = item.displayTitle, !title.isEmpty else {
                rest.append(item)
                continue
            }

            let isMatch: Bool
            if let regex {
                let range = NSRange(title.startIndex..., in: title)
                isMatch = regex.firstMatch(in: title, options: [], range: range) != nil
            } else {
                isMatch = title.range(of: trimmed, options: compareOptions) != nil
            }

            if isMatch {
                matches.append(item)
            } else {
                rest.append(item)
            }
        }

        guard !matches.isEmpty else { return items }
        matches.append(contentsOf: rest)
        return matches
    }

    private func semanticSearchResults(
        keyword: String,
        typeFilter: [String]?,
        tagId: Int,
        limit: Int,
        fallbackToFTS: Bool
    ) async -> [ClipboardItem] {
        let canUseSemantic = SemanticSearchService.shared.canUseSemanticSearch(query: keyword)
        await log.debug("Semantic search start: queryLen=\(keyword.count), normalizedLen=\(SemanticSearchService.normalizedSemanticText(keyword).count), canUseSemantic=\(canUseSemantic), vecEnabled=\(sqlManager.isVecSearchAvailable)")

        if !canUseSemantic {
            guard fallbackToFTS else { return [] }
            let rows = await sqlManager.searchWithFTS(
                keyword: keyword,
                typeFilter: typeFilter,
                tagId: tagId != -1 ? tagId : nil,
                limit: Const.pageSize * 2
            )
            await log.debug("Semantic search fallback to FTS: rows=\(rows.count)")
            return await mapRowsToItems(rows)
        }

        var filter: Expression<Bool>?
        if let types = typeFilter, !types.isEmpty {
            filter = types.contains(Col.itemType)
        }

        if tagId != -1 {
            let tagCondition = Col.tagId == tagId
            if let existingFilter = filter {
                filter = existingFilter && tagCondition
            } else {
                filter = tagCondition
            }
        }

        let normalizedQuery = SemanticSearchService.normalizedSemanticText(keyword)
        let effectiveLimit = max(limit, Const.pageSize)

        if sqlManager.isVecSearchAvailable,
           let queryVector = SemanticSearchService.shared.vector(for: normalizedQuery, cacheKey: "q:\(normalizedQuery)") {
            let candidateLimit = SemanticSearchService.shared.vectorCandidateLimit(
                for: effectiveLimit,
                query: normalizedQuery
            )
            await log.debug("Semantic vec query: dim=\(queryVector.count), candidateLimit=\(candidateLimit)")
            let vecCandidates = await sqlManager.searchVecCandidates(queryVector: queryVector, limit: candidateLimit)
            await log.debug("Semantic vec candidates: count=\(vecCandidates.count)")
            if !vecCandidates.isEmpty, log.isEnabled(.debug) {
                let preview = vecCandidates.prefix(10).map { candidate in
                    "(\(candidate.id),\(String(format: "%.4f", candidate.distance)))"
                }.joined(separator: ", ")
                await log.debug("Semantic vec distances (top10): [\(preview)]")
            }
            if !vecCandidates.isEmpty {
                var vecIds = vecCandidates.map { $0.id }
                var lexicalIds: [Int64] = []
                if !DeckUserDefaults.securityModeEnabled {
                    let lexicalRows = await sqlManager.searchWithSQLLikeRows(
                        keyword: normalizedQuery,
                        typeFilter: typeFilter,
                        tagId: tagId != -1 ? tagId : nil,
                        limit: min(Const.pageSize * 2, effectiveLimit)
                    )
                    if !lexicalRows.isEmpty {
                        lexicalIds = lexicalRows.compactMap { try? $0.get(Col.id) }
                        var seenIds = Set(vecIds)
                        for id in lexicalIds where seenIds.insert(id).inserted {
                            vecIds.append(id)
                        }
                    }
                }
                let rows = await sqlManager.fetchRowsByIdsUnordered(ids: vecIds, filter: filter)
                let candidates = await mapRowsToItems(rows)
                let maxDistance = SemanticSearchService.shared.maxDistance(for: normalizedQuery)
                var itemsById: [Int64: ClipboardItem] = [:]
                itemsById.reserveCapacity(candidates.count)
                for item in candidates {
                    if let id = item.id {
                        itemsById[id] = item
                    }
                }
                var ordered: [ClipboardItem] = []
                ordered.reserveCapacity(min(vecCandidates.count, effectiveLimit))
                var preview: [String] = []
                preview.reserveCapacity(10)
                for candidate in vecCandidates {
                    guard candidate.distance <= maxDistance else { continue }
                    guard let item = itemsById[candidate.id] else { continue }
                    if ordered.count < effectiveLimit {
                        ordered.append(item)
                    }
                    if preview.count < 10 {
                        preview.append("(\(candidate.id),\(String(format: "%.4f", candidate.distance)))")
                    }
                    if ordered.count >= effectiveLimit, preview.count >= 10 {
                        break
                    }
                }
                if ordered.count < effectiveLimit, !lexicalIds.isEmpty {
                    var orderedIds = Set(ordered.compactMap(\.id))
                    for id in lexicalIds {
                        guard orderedIds.insert(id).inserted else { continue }
                        guard let item = itemsById[id] else { continue }
                        ordered.append(item)
                        if ordered.count >= effectiveLimit {
                            break
                        }
                    }
                }
                let results = prioritizeSemanticExactMatches(ordered, keyword: keyword)
                if !preview.isEmpty {
                    await log.debug("Semantic vec results (top10): [\(preview.joined(separator: ", "))]")
                }
                await log.debug("Semantic vec results: count=\(results.count)")
                return results
            }
        }

        let rows = await sqlManager.fetchListPage(
            filter: filter,
            limit: effectiveLimit,
            cursor: nil
        )
        await log.debug("Semantic fallback to rank: rows=\(rows.count)")
        let candidates = await mapRowsToItems(rows)
        let embeddingMap = await sqlManager.fetchSemanticEmbeddings(for: candidates)
        return await SemanticSearchService.shared.rank(
            query: keyword,
            items: candidates,
            limit: effectiveLimit,
            precomputedEmbeddings: embeddingMap
        ) { [weak sqlManager] id, textHash, vector in
            sqlManager?.scheduleSemanticEmbeddingStore(id: id, textHash: textHash, vector: vector)
        }
    }

    private func prioritizeSemanticExactMatches(
        _ items: [ClipboardItem],
        keyword: String
    ) -> [ClipboardItem] {
        SemanticSearchService.shared.rerankByLexicalMatch(items, keyword: keyword)
    }

    private func mergeRows(
        primary: [Row],
        secondary: [Row],
        limit: Int
    ) -> [Row] {
        var merged: [Row] = []
        merged.reserveCapacity(min(primary.count + secondary.count, limit))
        var seen = Set<Int64>()
        seen.reserveCapacity(min(primary.count + secondary.count, limit))

        func append(_ row: Row) -> Bool {
            guard let id = try? row.get(Col.id) else { return merged.count >= limit }
            guard seen.insert(id).inserted else { return merged.count >= limit }
            merged.append(row)
            return merged.count >= limit
        }

        for row in primary where !Task.isCancelled {
            if append(row) { return merged }
        }

        for row in secondary where !Task.isCancelled {
            if append(row) { break }
        }
        return merged
    }
    
    func addNewItem(_ pasteboard: NSPasteboard) {
        guard let item = ClipboardItem(with: pasteboard) else { return }
        insertItem(item)
    }
    
    func addNewItemWithRules(_ pasteboard: NSPasteboard) {
        guard let item = ClipboardItem(with: pasteboard) else { return }
        addParsedItemWithRules(item)
    }
    
    /// 添加已解析的 item 并应用规则（避免重复解析）
    /// - Parameter item: 已解析的 ClipboardItem
    func addParsedItemWithRules(_ item: ClipboardItem, shouldScheduleSemanticEmbedding: Bool = true) {
        Task { [weak self] in
            await self?.processParsedItemWithRules(
                item,
                shouldScheduleSemanticEmbedding: shouldScheduleSemanticEmbedding
            )
        }
    }

    private func processParsedItemWithRules(
        _ item: ClipboardItem,
        shouldScheduleSemanticEmbedding: Bool = true
    ) async {
        var workingItem = item

        // Process through smart rules
        let actions = SmartRuleService.shared.processItem(workingItem)
        if actions.contains(where: { if case .ignore = $0 { return true }; return false }) {
            await log.debug("Item ignored by smart rule")
            return
        }

        // Apply transform before persisting so stored data matches rule result
        if let transformName = actions.compactMap({ action -> String? in
            if case .transform(let typeName) = action { return typeName }
            return nil
        }).first,
           workingItem.pasteboardType == .string {
            if let transformType = TransformType.fromStableCode(transformName) ?? TransformType(rawValue: transformName),
               let transformedText = TextTransformer.shared.transform(workingItem.searchText, type: transformType) {
                workingItem = makeTransformedItem(from: workingItem, newText: transformedText)
                await log.debug("Applied transform '\(transformName)' before saving item")
            } else if let pluginId = RuleAction.scriptPluginId(fromTransformValue: transformName) {
                let result = await ScriptPluginService.shared.executeTransformAsync(
                    pluginId: pluginId,
                    input: workingItem.searchText
                )
                if result.success, let output = result.output {
                    workingItem = makeTransformedItem(from: workingItem, newText: output)
                    await log.debug("Applied script plugin '\(pluginId)' before saving item")
                } else if let error = result.error {
                    await log.warn("Script plugin '\(pluginId)' failed: \(error)")
                } else {
                    await log.warn("Script plugin '\(pluginId)' returned empty output")
                }
            } else {
                await log.warn("Unknown transform '\(transformName)', skipping")
            }
        }

        // Apply non-delayed actions before saving
        for action in actions {
            switch action {
            case .addTag(let tagName):
                if let tag = DeckUserDefaults.userTags.first(where: { $0.name == tagName }) {
                    workingItem.tagId = tag.id
                }
            case .markSensitive:
                workingItem.tagId = 999  // Sensitive tag
            default:
                break
            }
        }

        // Insert the item and then run actions that require a persisted id
        insertItem(
            workingItem,
            completion: { savedItem in
                SmartRuleService.shared.applyActions(actions, to: savedItem)
            },
            shouldScheduleSemanticEmbedding: shouldScheduleSemanticEmbedding
        )
    }
    
    func insertItem(
        _ item: ClipboardItem,
        completion: ((ClipboardItem) -> Void)? = nil,
        shouldSyncToCloud: Bool = true,
        shouldScheduleSemanticEmbedding: Bool = true
    ) {
        Task {
            let itemId = await sqlManager.insert(
                item: item,
                scheduleSemanticEmbedding: shouldScheduleSemanticEmbedding
            )
            item.id = itemId

            // 注意：若是超大图片（例如 100MB），`item.data` 会在内存中常驻。
            // SQL 层可能已将其落盘到 blob（并在 DB 内只保留 previewData）。
            // 这里重新以 loadFullData=false 的方式取回“瘦身版” ClipboardItem，
            // 避免将完整 Data 存进 `items` 数组，造成长期占用。
            var savedItem = item
            if item.itemType == .image && savedItem.data.count > Const.largeBlobThreshold {
                if let row = await sqlManager.fetch(id: itemId),
                   let trimmed = sqlManager.rowToClipboardItem(row, loadFullData: false) {
                    savedItem = trimmed
                }
            }

            totalCount = await sqlManager.count()

            // 对图片进行 OCR 识别（在后台异步执行）
            if item.itemType == .image {
                OCRService.shared.processImageItem(savedItem)
            }

            if DeckViewModel.shared.isSearching { 
                updateRecentItemsCache(with: savedItem)
                recordPresentationLiveInsert(savedItem)
                completion?(savedItem)
                return 
            }

            if !isPanelVisibleOrPresenting {
                updateRecentItemsCache(with: savedItem)
                completion?(savedItem)
                return
            }

            applyLiveInsert(savedItem)

            // Sync to iCloud in background
            if DeckBuildFlags.isCloudSyncCompiledIn,
               DeckUserDefaults.iCloudSyncEnabled && shouldSyncToCloud {
                if itemId > 0 {
                    Task.detached(priority: .utility) {
                        await CloudSyncService.shared.syncItem(id: itemId)
                    }
                }
            }

            completion?(savedItem)
        }
    }
    
    func moveItemToFirst(_ item: ClipboardItem) {
        // Keep recent cache in sync with panel ordering so Cursor Assistant
        // (which reads recentItemsCache first) stays consistent after paste.
        var cacheTarget = item

        if let index = items.firstIndex(where: { $0.uniqueId == item.uniqueId }) {
            let existing = items[index]
            cacheTarget = existing
            if index != 0 {
                items.remove(at: index)
                items.insert(existing, at: 0)
                hasNewerDataBeforeCurrentWindow = false
                lastChangeType = .reset
            }
        }

        updateRecentItemsCache(with: cacheTarget)
    }
    
    func deleteItem(_ item: ClipboardItem, shouldSyncToCloud: Bool = true) {
        guard let id = item.id else {
            log.warn("deleteItem: item.id is nil, cannot delete")
            return
        }

        let uniqueId = item.uniqueId
        log.info("deleteItem: deleting item with id=\(id)")
        Task {
            LANReceivedCleanup.removeArtifactsForDeletedClipboardItem(paths: item.normalizedFilePaths)
            await sqlManager.delete(filter: Col.id == id)
            BlobStorage.shared.remove(path: item.blobPath)

            totalCount = await sqlManager.count()
            items.removeAll { $0.id == id }
            await log.info("deleteItem: item removed from memory, remaining count=\(items.count)")

            // Sync deletion to iCloud in background
            if DeckBuildFlags.isCloudSyncCompiledIn,
               DeckUserDefaults.iCloudSyncEnabled && shouldSyncToCloud {
                Task.detached(priority: .utility) {
                    await CloudSyncService.shared.deleteItem(uniqueId: uniqueId)
                }
            }
        }
    }

    func markMissingFileItem(_ item: ClipboardItem) {
        guard !item.isMissingFile else { return }
        item.isMissingFile = true
        pendingMissingFileUniqueIds.insert(item.uniqueId)
    }

    func purgeMissingFileItems() {
        guard !pendingMissingFileUniqueIds.isEmpty else { return }
        let uniqueIds = pendingMissingFileUniqueIds
        pendingMissingFileUniqueIds.removeAll()
        Task.detached(priority: .utility) {
            for uniqueId in uniqueIds {
                if let tagId = await DeckSQLManager.shared.fetchTagId(uniqueId: uniqueId),
                   tagId != -1 {
                    await log.debug("purgeMissingFileItems: skip tagged missing-file item uniqueId=\(uniqueId)")
                    continue
                }
                _ = await DeckDataStore.shared.deleteItemByUniqueId(uniqueId)
            }
        }
    }
    
    func removeTagFromItems(_ tagId: Int) {
        guard tagId != -1 else { return }
        items
            .filter { $0.tagId == tagId }
            .forEach { $0.updateTag(-1) }

        Task {
            await sqlManager.clearTagFromItems(tagId: tagId)
        }
    }
    
    func updateItem(id: Int64, item: ClipboardItem) {
        Task {
            await sqlManager.update(id: id, item: item)
        }
    }
    
    func updateItemTag(itemId: Int64, tagId: Int) {
        if let item = items.first(where: { $0.id == itemId }) {
            if tagId == DeckTag.importantTagId && item.isTemporary {
                log.warn("updateItemTag: skip important tag for temporary item id=\(itemId)")
                return
            }
            item.updateTag(tagId)
        }

        if tagId != -1 {
            SmartRuleService.shared.cancelAutoDeletion(itemId: itemId)
        }

        Task {
            await sqlManager.updateItemTag(id: itemId, tagId: tagId)
        }
    }

    func updateItemTemporary(itemId: Int64, isTemporary: Bool) {
        if let item = items.first(where: { $0.id == itemId }) {
            if isTemporary && item.tagId == DeckTag.importantTagId {
                log.warn("updateItemTemporary: skip temporary flag for important item id=\(itemId)")
                return
            }
            item.isTemporary = isTemporary
        }

        Task {
            await sqlManager.updateItemTemporary(id: itemId, isTemporary: isTemporary)
        }
    }

    func updateItemCustomTitle(itemId: Int64, customTitle: String?) {
        let normalized = ClipboardItem.normalizedCustomTitle(customTitle)
        var updatedItem: ClipboardItem?

        if let item = items.first(where: { $0.id == itemId }) {
            item.customTitle = normalized
            updatedItem = item
        }
        if isSearchCacheActive {
            searchTitleOverrides[itemId] = SearchTitleOverride(value: normalized)
            if let index = searchResultsCache.firstIndex(where: { $0.id == itemId }) {
                searchResultsCache[index].customTitle = normalized
            }
        }
        if let index = recentItemsCache.firstIndex(where: { $0.id == itemId }) {
            recentItemsCache[index].customTitle = normalized
        }

        if let uid = updatedItem?.uniqueId ?? items.first(where: { $0.id == itemId })?.uniqueId {
            SearchService.shared.invalidatePreparedTextCache(for: uid)
        } else {
            SearchService.shared.clearPreparedTextCache()
        }

        if let updatedItem {
            let actions = SmartRuleService.shared.processItem(updatedItem)
            let applicableActions = actions.filter { action in
                switch action {
                case .ignore, .transform, .aiPrompt:
                    return false
                default:
                    return true
                }
            }
            if !applicableActions.isEmpty {
                SmartRuleService.shared.applyActions(applicableActions, to: updatedItem)
            }
        }

        Task {
            await sqlManager.updateCustomTitle(id: itemId, customTitle: normalized)
        }
    }

    /// 更新项目的 searchText（用于 OCR 结果）
    func updateItemSearchText(itemId: Int64, searchText: String) async {
        // 更新内存中的项目
        searchTextOverrides[itemId] = searchText
        if let item = items.first(where: { $0.id == itemId }) {
            item.searchText = searchText
            let ocrLength = item.ocrTextForImage?.count ?? 0
            await log.debug(
                "OCR: In-memory update id=\(itemId) len=\(searchText.count) type=\(item.itemType.rawValue) pasteboard=\(item.pasteboardType.rawValue) fileURLImage=\(item.isFileURLImage) ocrLen=\(ocrLength)"
            )
            SearchService.shared.invalidatePreparedTextCache(for: item.uniqueId)
            await SmartContentCache.shared.invalidate(id: item.uniqueId)
        }

        // 更新数据库
        await sqlManager.updateSearchText(id: itemId, searchText: searchText)
    }

    func clearExpiredData() {
        let retentionDays = DeckUserDefaults.historyRetentionDays
        guard retentionDays > 0 else { return }

        guard let deadlineDate = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date()) else {
            return
        }
        let deadlineTimestamp = Int64(deadlineDate.timeIntervalSince1970)
        
        Task {
            let filter = Col.ts < deadlineTimestamp && Col.tagId == -1
            let blobPaths = await collectBlobPaths(filter: filter)
            await sqlManager.delete(filter: filter)

            if !blobPaths.isEmpty {
                blobPaths.forEach { BlobStorage.shared.remove(path: $0) }
            }

            totalCount = await sqlManager.count()
            items.removeAll { $0.timestamp < deadlineTimestamp && $0.tagId == -1 }
        }
    }

    func clearTransientVisualCachesForPanelDismiss() {
        var visited = Set<String>()

        func clear(_ item: ClipboardItem) {
            guard visited.insert(item.uniqueId).inserted else { return }
            item.clearTransientVisualCaches()
        }

        items.forEach(clear)
        recentItemsCache.forEach(clear)
        searchResultsCache.forEach(clear)
        preparedSnapshot?.items.forEach(clear)
        presentationLiveInserts.forEach(clear)
    }
    
    func clearAllData() {
        cancelInFlightTasksForReset()
        sqlManager.deleteAll()
        // 同时清理 blob 文件，避免磁盘残留
        BlobStorage.shared.clearAll()

        resetSearchCache()
        preparedGeneration &+= 1
        preparedSnapshot = nil
        pendingMissingFileUniqueIds.removeAll()
        currentFilter = nil
        currentRuleFilters = .init()
        isFiltered = false
        isLoading = false
        hasMoreData = false
        hasNewerDataBeforeCurrentWindow = false
        currentPage = 0
        paginationCursor = nil
        lastChangeType = .reset
        totalCount = 0
        items = []
        recentItemsCache.removeAll(keepingCapacity: false)
    }

    func setPanelActive(_ active: Bool) {
        if active {
            // Arm commit for prepared data; if already available, commit before observers fire.
            preparedCommitArmed = true
            let didCommitPrepared = commitPreparedSnapshotIfAvailable()

            isPanelPresenting = false
            isPanelActive = true
            SemanticSearchService.shared.setPanelActive(active)
            if !didCommitPrepared && !preparedCommittedDuringPresentation {
                let appliedCache = applyRecentItemsCacheIfNeeded()
                if appliedCache || !items.isEmpty {
                    setPreparingInitialPresentation(false)
                }
            }
        } else {
            isPanelPresenting = false
            isPanelActive = false
            SemanticSearchService.shared.setPanelActive(active)
            cancelPreparedSnapshot()
            trimForInactivePanel()
            sqlManager.scheduleIdleWALCheckpoint(reason: "panel inactive")
        }
    }

    /// Keep a small warm cache when the panel closes to avoid full cold rebuilds on next open.
    private func trimForInactivePanel() {
        let shouldCache = !isFiltered && !isSearchCacheActive && currentRuleFilters.isEmpty
            && lastChangeType != .search && lastChangeType != .listTail && lastChangeType != .loadPrevious
        if shouldCache && !items.isEmpty {
            cacheRecentItems(items)
        }

        searchTask?.cancel()
        searchTask = nil
        paginationTask?.cancel()
        paginationTask = nil
        resetSearchCache()
        isLoading = false
        currentPage = 0
        paginationCursor = nil
        currentFilter = nil
        currentRuleFilters = .init()
        isFiltered = false
        lastChangeType = .reset

        if items.count > Const.pageSize {
            items = Array(items.prefix(Const.pageSize))
        }
        hasMoreData = items.count == Const.pageSize
        hasNewerDataBeforeCurrentWindow = false

        sqlManager.clearSearchCache()
        Task(priority: .utility) {
            await sqlManager.shrinkMemory()
        }
        SemanticSearchService.shared.clearCache()
        Task {
            await SmartContentCache.shared.clearAll()
        }
    }

    private func cancelInFlightTasksForReset() {
        searchTask?.cancel()
        searchTask = nil
        paginationTask?.cancel()
        paginationTask = nil
        searchCacheTask?.cancel()
        searchCacheTask = nil
        preparedTask?.cancel()
        preparedTask = nil
        cancelPreparedSnapshot()
    }

    @discardableResult
    private func applyRecentItemsCacheIfNeeded() -> Bool {
        guard !recentItemsCache.isEmpty else { return false }
        let cachedFirstId = recentItemsCache.first?.uniqueId
        let currentFirstId = items.first?.uniqueId
        if items.isEmpty || items.count != recentItemsCache.count || currentFirstId != cachedFirstId {
            items = recentItemsCache
        }
        currentPage = 0
        paginationCursor = sqlManager.cursor(from: recentItemsCache.last)
        hasMoreData = totalCount > recentItemsCache.count || recentItemsCache.count == Const.pageSize
        hasNewerDataBeforeCurrentWindow = false
        lastChangeType = .reset
        return true
    }

    private func cacheRecentItems(_ source: [ClipboardItem], limit: Int? = nil) {
        let requestedLimit = limit ?? Const.pageSize
        let safeLimit = max(1, min(requestedLimit, Const.pageSize))
        if source.count > safeLimit {
            recentItemsCache = Array(source.prefix(safeLimit))
        } else {
            recentItemsCache = source
        }
    }

    private func updateRecentItemsCache(with item: ClipboardItem) {
        recentItemsCache.removeAll { $0.uniqueId == item.uniqueId }
        recentItemsCache.insert(item, at: 0)
        if recentItemsCache.count > Const.pageSize {
            recentItemsCache = Array(recentItemsCache.prefix(Const.pageSize))
        }
    }

    private func applyLiveInsert(_ savedItem: ClipboardItem) {
        items.removeAll { $0.uniqueId == savedItem.uniqueId }
        items.insert(savedItem, at: 0)
        if items.count > Const.pageSize {
            items = Array(items.prefix(Const.pageSize))
        }
        hasMoreData = totalCount > items.count || items.count >= Const.pageSize
        hasNewerDataBeforeCurrentWindow = false
        lastChangeType = .reset
        updateRecentItemsCache(with: savedItem)
        recordPresentationLiveInsert(savedItem)
    }

    private func recordPresentationLiveInsert(_ savedItem: ClipboardItem) {
        guard isPanelPresenting || isPreparingInitialPresentation || preparedSnapshot != nil else { return }

        presentationLiveInserts.removeAll { $0.uniqueId == savedItem.uniqueId }
        presentationLiveInserts.insert(savedItem, at: 0)
        if presentationLiveInserts.count > Const.pageSize {
            presentationLiveInserts = Array(presentationLiveInserts.prefix(Const.pageSize))
        }

        guard let snapshot = preparedSnapshot else { return }
        let mergedItems = mergePresentationLiveInserts(into: snapshot.items)
        preparedSnapshot = PreparedSnapshot(
            items: mergedItems,
            totalCount: max(snapshot.totalCount, totalCount, mergedItems.count),
            hasMoreData: snapshot.hasMoreData || totalCount > mergedItems.count,
            cursor: snapshot.cursor
        )
    }

    private func mergePresentationLiveInserts(into baseItems: [ClipboardItem]) -> [ClipboardItem] {
        guard !presentationLiveInserts.isEmpty else { return baseItems }

        var seen = Set<String>()
        var merged: [ClipboardItem] = []
        merged.reserveCapacity(min(Const.pageSize, presentationLiveInserts.count + baseItems.count))

        for item in presentationLiveInserts {
            guard seen.insert(item.uniqueId).inserted else { continue }
            merged.append(item)
            if merged.count >= Const.pageSize { return merged }
        }

        for item in baseItems {
            guard seen.insert(item.uniqueId).inserted else { continue }
            merged.append(item)
            if merged.count >= Const.pageSize { break }
        }

        return merged
    }

    private func releaseMemory() {
        searchTask?.cancel()
        searchTask = nil
        paginationTask?.cancel()
        paginationTask = nil
        resetSearchCache()
        isLoading = false
        currentPage = 0
        paginationCursor = nil
        currentFilter = nil
        currentRuleFilters = .init()
        isFiltered = false
        hasMoreData = false
        hasNewerDataBeforeCurrentWindow = false
        lastChangeType = .reset
        let preservedPresentationCache = !recentItemsCache.isEmpty ? recentItemsCache : items
        cacheRecentItems(preservedPresentationCache, limit: memoryPressurePresentationCacheLimit)
        items.removeAll(keepingCapacity: false)
        sqlManager.clearSearchCache()
        Task(priority: .utility) {
            await sqlManager.shrinkMemory()
        }
        SemanticSearchService.shared.clearCache()
        Task {
            await SmartContentCache.shared.clearAll()
        }
    }

    private func mapRowsToItems(_ rows: [Row]) async -> [ClipboardItem] {
        guard !rows.isEmpty else { return [] }
        guard !Task.isCancelled else { return [] }
        return await sqlManager.mapRowsToClipboardItems(rows, loadFullData: false)
    }

    private func prepareLanguageRuleCacheIfNeeded(
        _ ruleFilters: SearchRuleFilters,
        for items: [ClipboardItem]
    ) async {
        guard ruleFilters.hasLanguageFilters else { return }
        let candidates = ruleFilters.languageDetectionCandidates(from: items)
        guard !candidates.isEmpty else { return }
        await SearchRuleFilters.prepareLanguageCache(items: candidates, limit: candidates.count)
    }

    private func mapRowsToSearchSnapshots(_ rows: [Row]) -> [SearchSnapshot] {
        sqlManager.searchSnapshots(from: rows)
    }

    private func orderedUniqueIdsFromSearchSnapshots(
        query: String,
        snapshots: [SearchSnapshot],
        mode: SearchMode
    ) async -> [String] {
        guard !snapshots.isEmpty else { return [] }
        guard !Task.isCancelled else { return [] }
        let lexicalMode: SearchMode = (mode == .semantic) ? .mixed : mode
        let task = Task.detached(priority: .userInitiated) { [snapshots, query, lexicalMode] () -> [String] in
            if Task.isCancelled { return [] }
            return SearchService.shared.searchUniqueIds(query: query, within: snapshots, mode: lexicalMode)
        }
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private func orderedClipboardItemsForSearch(uniqueIds: [String], rows: [Row]) async -> [ClipboardItem] {
        guard !uniqueIds.isEmpty else { return [] }
        guard !Task.isCancelled else { return [] }
        var rowByUnique: [String: Row] = [:]
        rowByUnique.reserveCapacity(rows.count)
        for row in rows {
            rowByUnique[row[Col.uniqueId]] = row
        }
        let orderedRows = uniqueIds.compactMap { rowByUnique[$0] }
        return await mapRowsToItems(orderedRows)
    }

    private func runInMemorySearchRows(
        query: String,
        rows: [Row],
        mode: SearchMode,
        useRegex: Bool
    ) async -> [ClipboardItem] {
        guard !rows.isEmpty else { return [] }
        guard !Task.isCancelled else { return [] }
        let snapshots = mapRowsToSearchSnapshots(rows)
        let orderedUniqueIds = await orderedUniqueIdsFromSearchSnapshots(
            query: query,
            snapshots: snapshots,
            mode: mode
        )
        var idByUnique: [String: Int64] = [:]
        var titleById: [Int64: String] = [:]
        idByUnique.reserveCapacity(snapshots.count)
        titleById.reserveCapacity(snapshots.count)
        for snapshot in snapshots {
            idByUnique[snapshot.uniqueId] = snapshot.rowId
            titleById[snapshot.rowId] = snapshot.title
        }
        var ids = orderedUniqueIds.compactMap { idByUnique[$0] }
        ids = prioritizeHitIDs(ids, titles: titleById, keyword: query, useRegex: useRegex)
        searchResultOrder = ids
        let pageIDs = Array(ids.prefix(Const.pageSize))
        return await orderedItemsFromRows(ids: pageIDs, rows: rows)
    }

    private func prioritizeHitIDs(
        _ ids: [Int64],
        titles: [Int64: String],
        keyword: String,
        useRegex: Bool
    ) -> [Int64] {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ids }
        let regex = useRegex ? RegexCache.shared.regex(for: trimmed) : nil
        let compareOptions: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        var matches: [Int64] = []
        var rest: [Int64] = []
        matches.reserveCapacity(min(ids.count, 64))
        rest.reserveCapacity(ids.count)
        for id in ids {
            let title = titles[id]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !title.isEmpty else {
                rest.append(id)
                continue
            }
            let isMatch: Bool
            if let regex {
                let range = NSRange(title.startIndex..., in: title)
                isMatch = regex.firstMatch(in: title, options: [], range: range) != nil
            } else {
                isMatch = title.range(of: trimmed, options: compareOptions) != nil
            }
            if isMatch {
                matches.append(id)
            } else {
                rest.append(id)
            }
        }
        guard !matches.isEmpty else { return ids }
        matches.append(contentsOf: rest)
        return matches
    }

    private func orderedItemsFromRows(ids: [Int64], rows: [Row]) async -> [ClipboardItem] {
        guard !ids.isEmpty else { return [] }
        var rowById: [Int64: Row] = [:]
        rowById.reserveCapacity(rows.count)
        for row in rows {
            if let id = try? row.get(Col.id) {
                rowById[id] = row
            }
        }
        let orderedRows = ids.compactMap { rowById[$0] }
        return await mapRowsToItems(orderedRows)
    }
    
    /// 迁移数据库加密状态
    /// - Parameter encrypt: true 表示加密，false 表示解密
    /// - Returns: 迁移是否成功。只有成功时才会更新 securityModeEnabled 标志
    func resaveWithCurrentEncryption(encrypt: Bool) async -> Bool {
        let success = await sqlManager.migrateEncryption(encrypt: encrypt)

        guard success else {
            await log.error("Encryption migration failed, flag and key will not be changed")
            return false
        }

        // 重要：只有迁移成功才更新安全模式标志
        // 先更新标志，再重新加载数据，否则 loadInitialData 会根据旧的 securityModeEnabled 值尝试解密/加密数据
        DeckUserDefaults.securityModeEnabled = encrypt

        // Reload data after migration
        await loadInitialData()
        return true
    }
    
    func isDataEncrypted() -> Bool {
        return DeckUserDefaults.securityModeEnabled
    }
    
    // MARK: - App Intents Support
    
    func fetchRecent(count: Int, typeFilter: [String]? = nil) async -> [ClipboardItem] {
        var filter: Expression<Bool>?
        
        if let types = typeFilter, !types.isEmpty {
            filter = types.contains(Col.itemType)
        }
        
        let rows = await sqlManager.fetchListPage(filter: filter, limit: count, cursor: nil)
        return rows.compactMap { sqlManager.rowToClipboardItem($0, loadFullData: false) }
    }

    /// 获取某个标签下的全部项目，用于分组共享
    func fetchAllItemsForTag(_ tagId: Int) async -> [ClipboardItem] {
        let rows = await sqlManager.search(filter: Col.tagId == tagId)
        return rows.compactMap { sqlManager.rowToClipboardItem($0, loadFullData: false) }
    }
    
    func fetchItems(ids: [Int64]) async -> [ClipboardItem] {
        // 使用单次批量查询替代 N 次单独查询
        let rows = await sqlManager.fetchBatch(ids: ids)
        let items = rows.compactMap { sqlManager.rowToClipboardItem($0, loadFullData: false) }

        // 按原始 ids 顺序排序结果
        let idToItem = Dictionary(uniqueKeysWithValues: items.compactMap { item -> (Int64, ClipboardItem)? in
            guard let id = item.id else { return nil }
            return (id, item)
        })
        return ids.compactMap { idToItem[$0] }
    }
    
    func searchItems(keyword: String, limit: Int) async -> [ClipboardItem] {
        let pattern = "%\(keyword)%"
        let customTitleLike = Expression<String>("IFNULL(custom_title, '')").like(pattern)
        let filter = Col.searchText.like(pattern) || Col.appName.like(pattern) || customTitleLike
        let rows = await sqlManager.fetchListPage(filter: filter, limit: limit, cursor: nil)
        return rows.compactMap { sqlManager.rowToClipboardItem($0, loadFullData: false) }
    }

    /// 按来源应用获取剪贴板记录（用于 Shortcuts）
    func fetchByApp(appName: String, limit: Int) async -> [ClipboardItem] {
        let pattern = "%\(appName)%"
        let filter = Col.appName.like(pattern)
        let rows = await sqlManager.fetchListPage(filter: filter, limit: limit, cursor: nil)
        return rows.compactMap { sqlManager.rowToClipboardItem($0, loadFullData: false) }
    }
    
    func clearAll() async {
        cancelInFlightTasksForReset()
        sqlManager.deleteAll()
        // 同时清理 blob 文件，避免磁盘残留
        BlobStorage.shared.clearAll()
        resetSearchCache()
        preparedGeneration &+= 1
        preparedSnapshot = nil
        pendingMissingFileUniqueIds.removeAll()
        currentFilter = nil
        currentRuleFilters = .init()
        isFiltered = false
        isLoading = false
        hasMoreData = false
        hasNewerDataBeforeCurrentWindow = false
        currentPage = 0
        paginationCursor = nil
        lastChangeType = .reset
        totalCount = 0
        items = []
        recentItemsCache.removeAll(keepingCapacity: false)
    }
    
    func getCount(typeFilter: [String]? = nil) async -> Int {
        return await sqlManager.count(typeFilter: typeFilter)
    }
    
    func updateItemTagById(id: Int64, tagId: Int) async {
        if let index = items.firstIndex(where: { $0.id == id }) {
            if tagId == DeckTag.importantTagId && items[index].isTemporary {
                await log.warn("updateItemTagById: skip important tag for temporary item id=\(id)")
                return
            }
        }
        await sqlManager.updateItemTag(id: id, tagId: tagId)
        if let index = items.firstIndex(where: { $0.id == id }) {
            items[index].tagId = tagId
        }

        if tagId != -1 {
            SmartRuleService.shared.cancelAutoDeletion(itemId: id)
        }
    }
    
    func deleteItemById(id: Int64) async {
        if let rowItem = items.first(where: { $0.id == id }) {
            LANReceivedCleanup.removeArtifactsForDeletedClipboardItem(paths: rowItem.normalizedFilePaths)
        }
        var blobPath = items.first(where: { $0.id == id })?.blobPath
        if blobPath == nil, let row = await sqlManager.fetch(id: id) {
            blobPath = row[Col.blobPath]
        }
        await sqlManager.delete(id: id)
        BlobStorage.shared.remove(path: blobPath)
        totalCount = await sqlManager.count()
        items.removeAll { $0.id == id }
    }

    func deleteItemByUniqueId(_ uniqueId: String, shouldSyncToCloud: Bool = true) async -> Bool {
        let trimmed = uniqueId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        if let item = items.first(where: { $0.uniqueId == trimmed }) {
            guard let id = item.id else {
                await log.warn("deleteItemByUniqueId: missing id for uniqueId=\(trimmed)")
                return false
            }

            LANReceivedCleanup.removeArtifactsForDeletedClipboardItem(paths: item.normalizedFilePaths)
            await sqlManager.delete(filter: Col.id == id)
            BlobStorage.shared.remove(path: item.blobPath)

            totalCount = await sqlManager.count()
            items.removeAll { $0.id == id }

            if DeckBuildFlags.isCloudSyncCompiledIn,
               DeckUserDefaults.iCloudSyncEnabled && shouldSyncToCloud {
                let uniqueId = item.uniqueId
                Task.detached(priority: .utility) {
                    await CloudSyncService.shared.deleteItem(uniqueId: uniqueId)
                }
            }

            return true
        }

        let blobPath = await sqlManager.fetchRow(uniqueId: trimmed)?[Col.blobPath]
        await sqlManager.delete(filter: Col.uniqueId == trimmed)
        BlobStorage.shared.remove(path: blobPath)
        totalCount = await sqlManager.count()
        items.removeAll { $0.uniqueId == trimmed }
        return true
    }

    private func collectBlobPaths(filter: Expression<Bool>) async -> [String] {
        var paths: [String] = []
        let batchSize = 500
        var cursor: DeckSQLManager.RowCursor?

        while true {
            let rows = await sqlManager.fetchListPage(filter: filter, limit: batchSize, cursor: cursor)
            guard !rows.isEmpty else { break }
            paths.append(contentsOf: rows.compactMap { $0[Col.blobPath] })
            cursor = sqlManager.cursor(from: rows.last)

            if rows.count < batchSize { break }
            await Task.yield()
        }

        return paths
    }
    
    // MARK: - LAN Group Sharing

    /// 接收局域网共享的分组
    /// - Parameters:
    ///   - groupName: 分组名称
    ///   - colorHex: 颜色索引字符串
    ///   - items: 接收到的剪贴板项目
    func receiveGroup(name groupName: String, colorHex: String, items receivedItems: [ClipboardItem]) async {
        // 1. 在主线程查找或创建分组（快速操作）
        let targetTag = ensureTagExists(name: groupName, colorHex: colorHex)
        let shouldUpdateMemory = !DeckViewModel.shared.isSearching
        let tagId = targetTag.id

        // 2. 在主线程设置 tagId（因为 ClipboardItem 是 MainActor 隔离的）
        for item in receivedItems {
            item.tagId = tagId
            item.receivedFromLAN = true
        }

        // 3. 在后台线程执行数据库插入（避免阻塞 UI）
        // 返回 (uniqueId, insertedId) 映射
        var idMap: [String: Int64] = [:]
        idMap.reserveCapacity(receivedItems.count)

        for item in receivedItems {
            let itemId = await sqlManager.insert(item: item)
            idMap[item.uniqueId] = itemId
        }

        // 4. 主线程一次性设置 id 并更新内存列表（O(n) 而非 O(n²)）
        for item in receivedItems {
            item.id = idMap[item.uniqueId]
        }

        totalCount = await sqlManager.count()

        if shouldUpdateMemory {
            let newIds = Set(receivedItems.map(\.uniqueId))
            var merged = self.items.filter { !newIds.contains($0.uniqueId) }
            merged.insert(contentsOf: receivedItems, at: 0)
            if merged.count > Const.pageSize {
                merged = Array(merged.prefix(Const.pageSize))
            }
            self.items = merged
        }

        hasMoreData = self.items.count >= Const.pageSize
        hasNewerDataBeforeCurrentWindow = false
        lastChangeType = .reset

        await log.info("Received group '\(groupName)' with \(receivedItems.count) items")
    }

    /// 查找或创建指定名称的标签
    /// - Parameters:
    ///   - name: 标签名称
    ///   - colorHex: 颜色十六进制字符串
    /// - Returns: 找到或新建的标签
    private func ensureTagExists(name: String, colorHex: String) -> DeckTag {
        var existingTags = DeckUserDefaults.userTags

        if let existing = existingTags.first(where: { $0.name == name }) {
            log.debug("receiveGroup: Using existing tag '\(name)' with id \(existing.id)")
            return existing
        }

        // 创建新分组
        let maxId = (existingTags.map { $0.id }.max() ?? 4) + 1
        let colorIndex = DeckTag.colorIndex(from: colorHex)
        let newTag = DeckTag(
            id: maxId,
            name: name,
            colorIndex: colorIndex,
            isSystem: false
        )
        existingTags.append(newTag)
        DeckUserDefaults.userTags = existingTags

        log.info("receiveGroup: Created new tag '\(name)' with id \(maxId), colorIndex \(colorIndex)")

        // 通知 ViewModel 刷新标签列表
        DeckViewModel.shared.reloadTags()

        return newTag
    }

    private func makeTransformedItem(from item: ClipboardItem, newText: String) -> ClipboardItem {
        let attributed = NSAttributedString(string: newText)
        let previewAttr = attributed.length > 250
            ? attributed.attributedSubstring(from: NSMakeRange(0, 250))
            : attributed
        let previewData = previewAttr.toData(with: item.pasteboardType)
        
        return ClipboardItem(
            pasteboardType: item.pasteboardType,
            data: newText.data(using: .utf8) ?? item.data,
            previewData: previewData,
            timestamp: item.timestamp,
            appPath: item.appPath,
            appName: item.appName,
            sourceAnchor: item.sourceAnchor,
            searchText: newText,
            contentLength: attributed.length,
            tagId: item.tagId,
            isTemporary: item.isTemporary,
            receivedFromLAN: item.receivedFromLAN,
            id: item.id,
            uniqueId: nil,
            blobPath: nil
        )
    }
}
