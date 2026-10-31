// Memory benchmark for lossless optimization rounds.
// Runs only when tmp/memopt/active.json points at an isolated database.
// Never reads or writes the user's real Deck library.

import CryptoKit
import Foundation
import SQLite3

enum MemOptBenchmark {
    @MainActor
    static func run() async throws {
        guard let active = MemOptIsolation.active else {
            throw BenchError("memopt active file missing")
        }
        let storage = active.storage
        guard storage.contains("Deck-memopt-50"), !storage.contains("/Library/") else {
            throw BenchError("refusing storage outside the memopt worktree: \(storage)")
        }

        let manager = DeckSQLManager.shared
        let dbDirectory = manager.getStorageDirectory()
        guard dbDirectory.contains("Deck-memopt-50") else {
            throw BenchError("database path escaped isolation: \(dbDirectory)")
        }
        let dbPath = (dbDirectory as NSString).appendingPathComponent("Deck.sqlite3")
        print("MEMOPT_DB \(dbPath)")

        switch active.scenario {
        case "build":
            try await buildFixture(manager: manager, dbPath: dbPath, active: active)
        case "suite":
            try await runSuite(manager: manager, dbPath: dbPath, active: active)
        default:
            throw BenchError("unknown scenario \(active.scenario)")
        }
    }
}

// MARK: - Corpus

private struct LCG {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1
        return state
    }
    mutating func int(_ upper: Int) -> Int {
        Int(next() % UInt64(upper))
    }
}

private enum Corpus {
    static let version = 1
    static let count = 1_500
    static let baseTimestamp: Int64 = 1_700_000_000_000

    static func makeItems() -> [ClipboardItem] {
        var rng = LCG(state: 0xDEC0_0050)
        let words = [
            "clipboard", "history", "window", "swift", "memory", "search", "panel",
            "token", "buffer", "index", "query", "result", "cache", "row", "table"
        ]
        let apps = ["Safari", "Notes", "Xcode", "Terminal", "Finder"]
        var items: [ClipboardItem] = []
        items.reserveCapacity(count)
        for index in 0..<count {
            let planted = plant(index)
            let text: String
            let title: String?
            if let planted {
                text = planted.text
                title = planted.title
            } else if index % 37 == 0 {
                text = filler(&rng, words: words, length: 48 * 1024, salt: index)
                title = nil
            } else {
                text = filler(&rng, words: words, length: 700 + (index % 19) * 90, salt: index)
                title = nil
            }
            let data = Data(text.utf8)
            let app = apps[index % apps.count]
            items.append(ClipboardItem(
                pasteboardType: .string,
                data: data,
                previewData: nil,
                timestamp: baseTimestamp - Int64(index),
                appPath: "/Applications/\(app).app",
                appName: app,
                customTitle: title,
                searchText: text,
                contentLength: data.count,
                uniqueId: String(format: "memopt-%06d", index),
                itemType: .text
            ))
        }
        return items
    }

    private static func plant(_ index: Int) -> (text: String, title: String?)? {
        if index % 50 == 0 {
            let title = (index % 100 == 0) ? "Pinned alphaneedle" : nil
            return ("Project alphaneedle note \(index) kept for clipboard search", title)
        }
        if index % 53 == 0 {
            return ("A banana smoothie recipe with milk oats and honey \(index)", nil)
        }
        if index % 59 == 0 {
            return ("香蕉牛奶冰沙的做法和配料 \(index)", nil)
        }
        return nil
    }

    private static func filler(_ rng: inout LCG, words: [String], length: Int, salt: Int) -> String {
        var text = "item \(salt)"
        while text.utf8.count < length {
            text.append(" ")
            text.append(words[rng.int(words.count)])
        }
        if text.count > length {
            text = String(text.prefix(length))
        }
        return text
    }
}

// MARK: - Build / suite

private struct FixtureMarker: Codable {
    var version: Int
    var count: Int
    var persistence: String
}

@MainActor
private func buildFixture(manager: DeckSQLManager, dbPath: String, active: MemOptIsolation.Active) async throws {
    let counts = dbCounts(dbPath)
    if counts.items > 0 {
        manager.deleteAll()
    }
    print("MEMOPT_PROGRESS insert \(Corpus.count)")
    let items = Corpus.makeItems()
    for (offset, item) in items.enumerated() {
        let id = await manager.insert(item: item, scheduleSemanticEmbedding: false)
        if id <= 0 {
            throw BenchError("insert failed at \(offset)")
        }
        if offset % 250 == 0 {
            print("MEMOPT_PROGRESS inserted \(offset)")
        }
    }
    print("MEMOPT_PROGRESS wait-embeddings")
    manager.reinitialize()
    let ready = await waitForEmbeddings(dbPath: dbPath, timeout: 900)
    if !ready {
        let left = dbCounts(dbPath)
        throw BenchError("embeddings did not finish items=\(left.items) embedded=\(left.embedded)")
    }
    print("MEMOPT_PROGRESS vacuum")
    let vacuumed = await manager.vacuumNow(reason: "memopt-fixture")
    if !vacuumed {
        throw BenchError("fixture vacuum failed")
    }
    let persistence = try persistenceDigest(dbPath: dbPath)
    let fixtureDir = URL(fileURLWithPath: active.fixture, isDirectory: true)
    try FileManager.default.createDirectory(at: fixtureDir, withIntermediateDirectories: true)
    let destination = fixtureDir.appendingPathComponent("Deck.sqlite3")
    for suffix in ["", "-wal", "-shm"] {
        let sourceURL = URL(fileURLWithPath: dbPath + suffix)
        let destinationURL = URL(fileURLWithPath: destination.path + suffix)
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        if FileManager.default.fileExists(atPath: sourceURL.path) {
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        }
    }
    let integrity = try RawSQLite.integrityDescription(path: destination.path)
    if integrity != "ok" {
        throw BenchError("fixture integrity check returned \(integrity)")
    }
    let marker = FixtureMarker(version: Corpus.version, count: Corpus.count, persistence: persistence)
    let markerData = try JSONEncoder().encode(marker)
    try markerData.write(to: fixtureDir.appendingPathComponent("marker.json"))
    print("MEMOPT_FIXTURE \(destination.path) persistence=\(persistence)")
}

@MainActor
private func runSuite(manager: DeckSQLManager, dbPath: String, active: MemOptIsolation.Active) async throws {
    let markerURL = URL(fileURLWithPath: active.fixture, isDirectory: true).appendingPathComponent("marker.json")
    let marker = try JSONDecoder().decode(FixtureMarker.self, from: Data(contentsOf: markerURL))
    guard marker.version == Corpus.version, marker.count == Corpus.count else {
        throw BenchError("fixture marker mismatch")
    }
    manager.reinitialize()
    let counts = dbCounts(dbPath)
    guard counts.items == Corpus.count else {
        throw BenchError("fixture item count \(counts.items) != \(Corpus.count)")
    }
    _ = await waitForEmbeddings(dbPath: dbPath, timeout: 60)
    try await Task.sleep(nanoseconds: 300_000_000)

    let store = DeckDataStore.shared
    store.setPanelActive(true)
    var reports: [ScenarioReport] = []

    reports.append(try await measureLoad(store: store))
    let queries: [(String, SearchMode, String)] = [
        ("exact", .exact, "alphaneedle"),
        ("fuzzy", .fuzzy, "alphneedle"),
        ("mixed", .mixed, "alphaneedle"),
        ("mixed_fuzzy", .mixed, "alphneedle"),
        ("regex", .regex, "alpha[a-z]*needle"),
        ("semantic_en", .semantic, "banana smoothie"),
        ("semantic_zh", .semantic, "香蕉牛奶")
    ]
    var canonicalByName: [String: String] = [:]
    for query in queries {
        let report = try await measureSearch(store: store, name: query.0, mode: query.1, keyword: query.2)
        canonicalByName[query.0] = report.canonical_sha256
        reports.append(report)
        if query.0 != "semantic_en" && query.0 != "semantic_zh" && report.result_count == 0 {
            throw BenchError("\(query.0) returned no rows")
        }
    }

    reports.append(try await measureExtreme(store: store, expectedFuzzy: canonicalByName["mixed_fuzzy"] ?? ""))
    let maintained = try await measureMaintain(store: store, manager: manager, expectedExact: canonicalByName["exact"] ?? "")
    reports.append(maintained)

    let persistence = try persistenceDigest(dbPath: dbPath)
    if persistence != marker.persistence {
        throw BenchError("persistence bytes changed \(marker.persistence) -> \(persistence)")
    }

    let finalCounts = dbCounts(dbPath)
    let run = RunReport(
        run: active.run,
        db_path: dbPath,
        item_count: Int(finalCounts.items),
        embedding_count: Int(finalCounts.embedded),
        persistence_sha256: persistence,
        scenarios: reports
    )
    let outputDir = URL(fileURLWithPath: active.output, isDirectory: true)
    try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
    let data = try JSONEncoder.pretty.encode(run)
    let outputURL = outputDir.appendingPathComponent("run-\(active.run).json")
    try data.write(to: outputURL)
    print("MEMOPT_RUN \(outputURL.path)")
}

// MARK: - Scenarios

@MainActor
private func measureLoad(store: DeckDataStore) async throws -> ScenarioReport {
    print("MEMOPT_PROGRESS load")
    return try await measure(name: "load") {
        var samples: [Double] = []
        for _ in 0..<3 {
            store.setPanelActive(false)
            store.setPanelActive(true)
            let started = DispatchTime.now().uptimeNanoseconds
            await store.loadInitialData()
            for _ in 0..<12 {
                let before = store.items.count
                guard store.hasMoreData || before < Const.pageSize else { break }
                store.loadNextPage()
                _ = await wait(30) {
                    store.items.count > before || (!store.isLoading && !store.hasMoreData)
                }
            }
            samples.append(elapsedMillis(since: started))
        }
        let canonical = canonicalText(store.items)
        return (samples, canonical, store.items.count)
    }
}

@MainActor
private func measureSearch(
    store: DeckDataStore,
    name: String,
    mode: SearchMode,
    keyword: String
) async throws -> ScenarioReport {
    print("MEMOPT_PROGRESS \(name)")
    return try await measure(name: name) {
        store.setPanelActive(true)
        var samples: [Double] = []
        for iteration in 0..<4 {
            let started = DispatchTime.now().uptimeNanoseconds
            _ = await store.searchItemsForAI(
                keyword: keyword,
                typeFilter: nil,
                tagId: -1,
                ruleFilters: SearchRuleFilters(),
                preferredMode: mode,
                useAutoMode: false,
                limit: 50
            )
            let millis = elapsedMillis(since: started)
            if iteration > 0 {
                samples.append(millis)
            }
        }
        try await runUISearch(store: store, keyword: keyword, mode: mode)
        let canonical = canonicalText(store.items)
        return (samples, canonical, store.items.count)
    }
}

private nonisolated func searchForExtreme(mode: SearchMode, keyword: String) async {
    _ = await DeckDataStore.shared.searchItemsForAI(
        keyword: keyword,
        typeFilter: nil,
        tagId: -1,
        ruleFilters: SearchRuleFilters(),
        preferredMode: mode,
        useAutoMode: false,
        limit: 50
    )
}

@MainActor
private func measureExtreme(store: DeckDataStore, expectedFuzzy: String) async throws -> ScenarioReport {
    print("MEMOPT_PROGRESS extreme")
    let report = try await measure(name: "extreme") {
        store.setPanelActive(true)
        let started = DispatchTime.now().uptimeNanoseconds
        let batch: [(SearchMode, String)] = [
            (.exact, "alphaneedle"),
            (.mixed, "alphneedle"),
            (.regex, "alpha[a-z]*needle"),
            (.semantic, "banana smoothie")
        ]
        await withTaskGroup(of: Void.self) { group in
            for entry in batch {
                let mode = entry.0
                let keyword = entry.1
                group.addTask {
                    await searchForExtreme(mode: mode, keyword: keyword)
                }
            }
        }
        let millis = elapsedMillis(since: started)
        try await runUISearch(store: store, keyword: "alphneedle", mode: .mixed)
        return ([millis], canonicalText(store.items), store.items.count)
    }
    if report.canonical_sha256 != expectedFuzzy {
        throw BenchError("extreme mixed_fuzzy diverged from serial mixed_fuzzy")
    }
    return report
}

@MainActor
private func measureMaintain(
    store: DeckDataStore,
    manager: DeckSQLManager,
    expectedExact: String
) async throws -> ScenarioReport {
    print("MEMOPT_PROGRESS maintain")
    let report = try await measure(name: "maintain") {
        let started = DispatchTime.now().uptimeNanoseconds
        manager.rebuildFTSIndex()
        let vacuumed = await manager.vacuumNow(reason: "memopt-bench")
        if !vacuumed {
            throw BenchError("benchmark vacuum failed")
        }
        await manager.shrinkMemory()
        let millis = elapsedMillis(since: started)
        return ([millis], "maintain", 0)
    }
    try await runUISearch(store: store, keyword: "alphaneedle", mode: .exact)
    let exact = SHA256Hex(canonicalText(store.items))
    if exact != expectedExact {
        throw BenchError("maintain changed exact search bytes")
    }
    return report
}

@MainActor
private func runUISearch(store: DeckDataStore, keyword: String, mode: SearchMode) async throws {
    store.setPanelActive(true)
    store.search(
        keyword: keyword,
        typeFilter: nil,
        tagId: -1,
        ruleFilters: SearchRuleFilters(),
        searchMode: mode
    )
    let finished = await wait(120) { store.appliedSearchSerial == store.searchSerial }
    if !finished {
        throw BenchError("search timed out for \(keyword) mode=\(mode.rawValue)")
    }
    malloc_zone_pressure_relief(malloc_default_zone(), 0)
    let snap = MemoryProbe.sample()
    PanelMemoryHold.shared.sample = snap
    if let sampler = PanelMemoryHold.shared.sampler {
        let peak = sampler.checkpoint()
        PanelMemoryHold.shared.peakPhys = max(peak.phys, snap.phys)
        PanelMemoryHold.shared.peakRSS = max(peak.rss, snap.rss)
    }
    var steps = 0
    while store.hasMoreData && steps < 40 {
        let before = store.items.count
        store.loadNextPage()
        _ = await wait(30) {
            store.items.count > before || (!store.isLoading && !store.hasMoreData)
        }
        if store.items.count == before {
            break
        }
        steps += 1
    }
}

// MARK: - Measurement

private struct ScenarioReport: Codable {
    var name: String
    var phys_before: UInt64
    var phys_peak: UInt64
    var phys_after: UInt64
    var rss_before: UInt64
    var rss_peak: UInt64
    var rss_after: UInt64
    var malloc_in_use: UInt64
    var sqlite_mem: Int64
    var sqlite_highwater: Int64
    var latency_ms: [Double]
    var canonical_sha256: String
    var result_count: Int
}

private struct RunReport: Codable {
    var run: String
    var db_path: String
    var item_count: Int
    var embedding_count: Int
    var persistence_sha256: String
    var scenarios: [ScenarioReport]
}

nonisolated private struct MemorySample: Sendable {
    var phys: UInt64
    var rss: UInt64
    var mallocInUse: UInt64
    var sqliteMem: Int64
    var sqliteHighwater: Int64
}

nonisolated private final class PanelMemoryHold: @unchecked Sendable {
    static let shared = PanelMemoryHold()
    var sample: MemorySample?
    var peakPhys: UInt64 = 0
    var peakRSS: UInt64 = 0
    weak var sampler: PeakSampler?

    func clear() {
        sample = nil
        peakPhys = 0
        peakRSS = 0
    }
}

nonisolated private final class PeakSampler: @unchecked Sendable {
    private let lock = NSLock()
    private var running = true
    private var phys: UInt64 = 0
    private var rss: UInt64 = 0

    func start() {
        let seed = MemoryProbe.sample()
        note(seed)
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            while let self, self.isRunning {
                self.note(MemoryProbe.sample())
                Thread.sleep(forTimeInterval: 0.002)
            }
        }
    }

    func checkpoint() -> (phys: UInt64, rss: UInt64) {
        lock.lock()
        let phys = self.phys
        let rss = self.rss
        lock.unlock()
        return (phys, rss)
    }

    func stop(floor: MemorySample) -> (phys: UInt64, rss: UInt64) {
        lock.lock()
        running = false
        let phys = max(self.phys, floor.phys)
        let rss = max(self.rss, floor.rss)
        lock.unlock()
        Thread.sleep(forTimeInterval: 0.01)
        let tail = MemoryProbe.sample()
        return (max(phys, tail.phys), max(rss, tail.rss))
    }

    private var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return running
    }

    private func note(_ sample: MemorySample) {
        lock.lock()
        phys = max(phys, sample.phys)
        rss = max(rss, sample.rss)
        lock.unlock()
    }
}

nonisolated private enum MemoryProbe {
    static func sample() -> MemorySample {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let vmResult = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        let phys = vmResult == KERN_SUCCESS ? UInt64(info.phys_footprint) : 0

        var basic = mach_task_basic_info()
        var basicCount = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.stride / MemoryLayout<integer_t>.stride)
        let basicResult = withUnsafeMutablePointer(to: &basic) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(basicCount)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &basicCount)
            }
        }
        let rss = basicResult == KERN_SUCCESS ? UInt64(basic.resident_size) : 0

        var stats = malloc_statistics_t()
        malloc_zone_statistics(nil, &stats)

        var sqliteCurrent: Int64 = 0
        var sqliteHigh: Int64 = 0
        sqlite3_status64(SQLITE_STATUS_MEMORY_USED, &sqliteCurrent, &sqliteHigh, 0)

        return MemorySample(
            phys: phys,
            rss: rss,
            mallocInUse: UInt64(stats.size_in_use),
            sqliteMem: sqliteCurrent,
            sqliteHighwater: sqliteHigh
        )
    }
}

@MainActor
private func measure(
    name: String,
    _ body: () async throws -> ([Double], String, Int)
) async throws -> ScenarioReport {
    await cleanupTransientCaches()
    let before = MemoryProbe.sample()
    let sampler = PeakSampler()
    PanelMemoryHold.shared.clear()
    PanelMemoryHold.shared.sampler = sampler
    sampler.start()
    let (latency, canonical, count) = try await body()
    let peak = sampler.stop(floor: before)
    if PanelMemoryHold.shared.sample == nil {
        malloc_zone_pressure_relief(malloc_default_zone(), 0)
    }
    let after = MemoryProbe.sample()
    let held = PanelMemoryHold.shared.sample
    let heldPeakPhys = PanelMemoryHold.shared.peakPhys
    let heldPeakRSS = PanelMemoryHold.shared.peakRSS
    PanelMemoryHold.shared.sampler = nil
    PanelMemoryHold.shared.clear()
    await cleanupTransientCaches()
    let physAfter = held?.phys ?? after.phys
    let rssAfter = held?.rss ?? after.rss
    let mallocAfter = held?.mallocInUse ?? after.mallocInUse
    let physPeak = held == nil ? max(peak.phys, after.phys) : max(heldPeakPhys, physAfter)
    let rssPeak = held == nil ? max(peak.rss, after.rss) : max(heldPeakRSS, rssAfter)
    return ScenarioReport(
        name: name,
        phys_before: before.phys,
        phys_peak: physPeak,
        phys_after: physAfter,
        rss_before: before.rss,
        rss_peak: rssPeak,
        rss_after: rssAfter,
        malloc_in_use: mallocAfter,
        sqlite_mem: after.sqliteMem,
        sqlite_highwater: after.sqliteHighwater,
        latency_ms: latency,
        canonical_sha256: SHA256Hex(canonical),
        result_count: count
    )
}

@MainActor
private func cleanupTransientCaches() async {
    let store = DeckDataStore.shared
    if store.isPanelActive {
        store.setPanelActive(false)
    }
    SearchService.shared.clearPreparedTextCache()
    SemanticSearchService.shared.clearCache()
    DeckSQLManager.shared.clearSearchCache()
    await SmartContentCache.shared.clearAll()
    await DeckSQLManager.shared.shrinkMemory()
}

// MARK: - Canonical + sqlite

private func canonicalText(_ items: [ClipboardItem]) -> String {
    items.map { item in
        [
            String(item.id ?? -1),
            item.uniqueId,
            String(item.timestamp),
            item.itemType.rawValue,
            item.appName,
            item.customTitle ?? "",
            String(item.contentLength),
            SHA256Hex(item.searchText)
        ].joined(separator: "\t")
    }.joined(separator: "\n")
}

private func SHA256Hex(_ text: String) -> String {
    let digest = SHA256.hash(data: Data(text.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
}

private func elapsedMillis(since start: UInt64) -> Double {
    Double(DispatchTime.now().uptimeNanoseconds &- start) / 1_000_000
}

@MainActor
private func wait(_ timeout: TimeInterval, _ predicate: @MainActor () -> Bool) async -> Bool {
    let start = Date()
    while Date().timeIntervalSince(start) < timeout {
        if predicate() { return true }
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
    return predicate()
}

private func waitForEmbeddings(dbPath: String, timeout: TimeInterval) async -> Bool {
    let start = Date()
    var stable = 0
    var previousMissing = Int64.min
    while Date().timeIntervalSince(start) < timeout {
        let counts = dbCounts(dbPath)
        let missing = counts.items - counts.embedded
        if counts.items > 0, missing <= 0 {
            stable += 1
            if stable >= 2 { return true }
        } else if missing == previousMissing {
            stable += 1
        } else {
            stable = 0
        }
        previousMissing = missing
        print("MEMOPT_PROGRESS embeddings missing=\(missing) items=\(counts.items)")
        try? await Task.sleep(nanoseconds: 400_000_000)
    }
    let counts = dbCounts(dbPath)
    return counts.items > 0 && counts.embedded >= counts.items
}

private struct DBCounts {
    var items: Int64
    var embedded: Int64
}

private func dbCounts(_ path: String) -> DBCounts {
    guard let db = RawSQLite(path: path) else {
        return DBCounts(items: 0, embedded: 0)
    }
    let items = db.int64("SELECT COUNT(*) FROM ClipboardHistory") ?? 0
    let embedded = db.int64("SELECT COUNT(*) FROM ClipboardHistory_embedding") ?? 0
    return DBCounts(items: items, embedded: embedded)
}

private func hashColumns(_ stmt: OpaquePointer?, count: Int32, into hasher: inout SHA256) {
    for column in 0..<count {
        let type = sqlite3_column_type(stmt, column)
        switch type {
        case SQLITE_INTEGER:
            var value = sqlite3_column_int64(stmt, column).littleEndian
            withUnsafeBytes(of: &value) { hasher.update(bufferPointer: $0) }
        case SQLITE_FLOAT:
            var value = sqlite3_column_double(stmt, column).bitPattern.littleEndian
            withUnsafeBytes(of: &value) { hasher.update(bufferPointer: $0) }
        case SQLITE_TEXT, SQLITE_BLOB:
            if let blob = sqlite3_column_blob(stmt, column) {
                let size = Int(sqlite3_column_bytes(stmt, column))
                if size > 0 {
                    hasher.update(data: Data(bytes: blob, count: size))
                }
            }
        default:
            break
        }
        hasher.update(data: Data([UInt8(type)]))
    }
}

private func persistenceDigest(dbPath: String) throws -> String {
    guard let db = RawSQLite(path: dbPath) else {
        throw BenchError("unable to open \(dbPath) for persistence digest")
    }
    var hasher = SHA256()
    try db.stream(
        """
        SELECT id, unique_id, item_type, type, app_name, IFNULL(custom_title, ''),
               search_text, content_length, data, IFNULL(preview_data, X'')
        FROM ClipboardHistory ORDER BY id
        """
    ) { stmt in
        hasher.update(data: Data("row\n".utf8))
        hashColumns(stmt, count: 10, into: &hasher)
    }
    try db.stream(
        """
        SELECT id, text_hash, embedding
        FROM ClipboardHistory_embedding ORDER BY id
        """
    ) { stmt in
        hasher.update(data: Data("emb\n".utf8))
        hashColumns(stmt, count: 3, into: &hasher)
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
}

private final class RawSQLite: @unchecked Sendable {
    nonisolated(unsafe) private var db: OpaquePointer?

    init?(path: String) {
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(path, &db, flags, nil) == SQLITE_OK else {
            return nil
        }
        sqlite3_busy_timeout(db, 5_000)
    }

    deinit {
        sqlite3_close(db)
    }

    static func integrityDescription(path: String) throws -> String {
        guard let db = RawSQLite(path: path) else {
            throw BenchError("unable to open \(path) for integrity check")
        }
        return db.text("PRAGMA integrity_check") ?? "unavailable"
    }

    func text(_ sql: String) -> String? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        guard let cString = sqlite3_column_text(stmt, 0) else { return nil }
        return String(cString: cString)
    }

    func int64(_ sql: String) -> Int64? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return sqlite3_column_int64(stmt, 0)
    }

    func stream(_ sql: String, _ row: (OpaquePointer?) -> Void) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw BenchError("prepare failed: \(sql)")
        }
        defer { sqlite3_finalize(stmt) }
        while true {
            let status = sqlite3_step(stmt)
            if status == SQLITE_ROW {
                row(stmt)
            } else if status == SQLITE_DONE {
                return
            } else {
                throw BenchError("step failed \(status)")
            }
        }
    }
}

private struct BenchError: Error, CustomStringConvertible {
    var description: String
    init(_ description: String) { self.description = description }
}

private extension JSONEncoder {
    static let pretty: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
}
