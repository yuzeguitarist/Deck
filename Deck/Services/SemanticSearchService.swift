// Copyright © 2024–2026 Yuze Pan. 保留一切权利。

//
//  SemanticSearchService.swift
//  Deck
//
//  On-device semantic search using NLEmbedding
//

import Foundation
import NaturalLanguage
import Accelerate

final class SemanticSearchService: @unchecked Sendable {
    nonisolated static let shared = SemanticSearchService()
    nonisolated static let embeddingModelVersion = "nl-embedding-v3-cjk-word-space"
#if DEBUG
    nonisolated(unsafe) static var lexicalKeyInputObserver: (@Sendable (_ byteCount: Int) -> Void)?
#endif

    private nonisolated enum EmbeddingStrategy: String {
        case englishSentence = "sentence-en"
        case chineseWordMean = "word-mean-zh-Hans"
    }

    private nonisolated final class EmbeddingBox: NSObject, @unchecked Sendable {
        let vector: [Float]
        let norm: Float

        init(vector: [Float], norm: Float) {
            self.vector = vector
            self.norm = norm
        }
    }

    private nonisolated struct RankCandidate: @unchecked Sendable {
        let item: ClipboardItem
        let id: Int64?
        let uniqueId: String
        let searchText: String
    }

    private nonisolated final class StoreEmbeddingBox: @unchecked Sendable {
        let store: ((Int64, String, [Float]) -> Void)?

        init(_ store: ((Int64, String, [Float]) -> Void)?) {
            self.store = store
        }
    }

    private nonisolated final class CacheBox: @unchecked Sendable {
        let cache: NSCache<NSString, EmbeddingBox>

        init() {
            let cache = NSCache<NSString, EmbeddingBox>()
            cache.countLimit = 400
            self.cache = cache
        }
    }

    private nonisolated let cacheBox = CacheBox()

    private nonisolated let minQueryLength = 2
    private nonisolated let minScore = 0.08
    private nonisolated let minScoreMediumQuery = 0.12
    private nonisolated let minScoreShortQuery = 0.18
    private nonisolated let shortQueryLength = 2
    private nonisolated let mediumQueryLength = 4
    private nonisolated let matrixBlockSize = 256
    private nonisolated let maxWordEmbeddingTokens = 32

    private nonisolated(unsafe) var englishEmbedding: NLEmbedding?
    private nonisolated(unsafe) var chineseEmbedding: NLEmbedding?
    private nonisolated(unsafe) var chineseWordEmbedding: NLEmbedding?
    private nonisolated let embeddingLock = NSRecursiveLock()
    private nonisolated(unsafe) var loggedEmbeddingKeys = Set<String>()
    private nonisolated(unsafe) var embeddingReleaseWorkItem: DispatchWorkItem?
    private nonisolated let embeddingReleaseLock = NSLock()
    private nonisolated let embeddingReleaseDelay: TimeInterval = 30.0

    private nonisolated init() {}

    nonisolated static func normalizedSemanticText(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if let end = trimmed.index(trimmed.startIndex, offsetBy: Const.maxSemanticTextLength, limitedBy: trimmed.endIndex),
           end != trimmed.endIndex {
            return String(trimmed[..<end])
        }
        return trimmed
    }

    nonisolated static func semanticTextHash(_ text: String) -> String {
        semanticTextHash(normalizedText: normalizedSemanticText(text))
    }

    nonisolated static func semanticTextHash(normalizedText: String) -> String {
        Data("\(embeddingModelVersion):\(normalizedText)".utf8).sha256Hex
    }

    func rank(
        query: String,
        items: [ClipboardItem],
        limit: Int,
        precomputedEmbeddings: [Int64: [Float]] = [:],
        storeEmbedding: ((Int64, String, [Float]) -> Void)? = nil
    ) async -> [ClipboardItem] {
        cancelEmbeddingRelease()
        let normalizedQuery = Self.normalizedSemanticText(query)
        guard normalizedQuery.count >= minQueryLength else { return [] }
        guard let queryBox = embeddingBox(for: normalizedQuery, cacheKey: "q:\(normalizedQuery)") else { return [] }
        let queryVector = queryBox.vector
        let queryNorm = queryBox.norm
        guard queryNorm > 0, !queryVector.isEmpty else { return [] }
        let scoreThreshold = minimumScore(for: normalizedQuery)
        let candidates = items.map {
            RankCandidate(item: $0, id: $0.id, uniqueId: $0.uniqueId, searchText: $0.searchText)
        }
        let storeEmbeddingBox = StoreEmbeddingBox(storeEmbedding)

        return await rankCandidatesOffMain(
            candidates: candidates,
            limit: limit,
            queryVector: queryVector,
            queryNorm: queryNorm,
            scoreThreshold: scoreThreshold,
            precomputedEmbeddings: precomputedEmbeddings,
            storeEmbeddingBox: storeEmbeddingBox
        )
    }

    private nonisolated func rankCandidatesOffMain(
        candidates: [RankCandidate],
        limit: Int,
        queryVector: [Float],
        queryNorm: Float,
        scoreThreshold: Double,
        precomputedEmbeddings: [Int64: [Float]],
        storeEmbeddingBox: StoreEmbeddingBox
    ) async -> [ClipboardItem] {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var scored: [(ClipboardItem, Double)] = []
                scored.reserveCapacity(min(candidates.count, limit))

                let dim = queryVector.count
                let invQueryNorm = 1.0 / Double(queryNorm)

                var blockMatrix: [Float] = []
                blockMatrix.reserveCapacity(self.matrixBlockSize * dim)

                var blockNorms: [Float] = []
                blockNorms.reserveCapacity(self.matrixBlockSize)

                var blockItems: [ClipboardItem] = []
                blockItems.reserveCapacity(self.matrixBlockSize)

                var dotBuffer: [Float] = Array(repeating: 0, count: self.matrixBlockSize)

                func flushBlock() {
                    let rowCount = blockItems.count
                    guard rowCount > 0 else { return }

                    self.sgemvRowMajor(
                        matrix: blockMatrix,
                        rows: rowCount,
                        cols: dim,
                        vector: queryVector,
                        result: &dotBuffer
                    )

                    for i in 0..<rowCount {
                        let candNorm = blockNorms[i]
                        guard candNorm > 0 else { continue }
                        let score = Double(dotBuffer[i]) * invQueryNorm / Double(candNorm)
                        guard score >= scoreThreshold else { continue }
                        scored.append((blockItems[i], score))
                    }

                    blockMatrix.removeAll(keepingCapacity: true)
                    blockNorms.removeAll(keepingCapacity: true)
                    blockItems.removeAll(keepingCapacity: true)
                }

                for candidate in candidates {
                    if Task.isCancelled { break }
                    let normalizedText = Self.normalizedSemanticText(candidate.searchText)
                    guard !normalizedText.isEmpty else { continue }

                    let textHash = Self.semanticTextHash(normalizedText: normalizedText)
                    let cacheId = candidate.id.map(String.init) ?? candidate.uniqueId
                    let cacheKey = "i:\(cacheId)-\(textHash)"
                    let box: EmbeddingBox?
                    if let id = candidate.id, let precomputed = precomputedEmbeddings[id] {
                        box = self.cachePrecomputedBox(vector: precomputed, cacheKey: cacheKey)
                    } else {
                        box = self.embeddingBox(for: normalizedText, cacheKey: cacheKey)
                        if let id = candidate.id, let vector = box?.vector {
                            storeEmbeddingBox.store?(id, textHash, vector)
                        }
                    }
                    guard let box else { continue }
                    guard box.vector.count == dim else { continue }
                    guard box.norm > 0 else { continue }

                    blockItems.append(candidate.item)
                    blockNorms.append(box.norm)
                    blockMatrix.append(contentsOf: box.vector)

                    if blockItems.count >= self.matrixBlockSize {
                        flushBlock()
                    }
                }

                flushBlock()

                scored.sort { $0.1 > $1.1 }
                let results = scored.prefix(limit).map { $0.0 }
                self.scheduleEmbeddingRelease()
                continuation.resume(returning: results)
            }
        }
    }

    nonisolated func canUseSemanticSearch(query: String) -> Bool {
        let normalizedQuery = Self.normalizedSemanticText(query)
        guard normalizedQuery.count >= minQueryLength else { return false }
        return embeddingBox(for: normalizedQuery, cacheKey: "q:\(normalizedQuery)") != nil
    }

    nonisolated func vector(for text: String, cacheKey: String) -> [Float]? {
        cancelEmbeddingRelease()
        let vector = embeddingBox(for: text, cacheKey: cacheKey)?.vector
        scheduleEmbeddingRelease()
        return vector
    }

    nonisolated func vectorCandidateLimit(for resultLimit: Int, query: String) -> Int {
        let normalized = Self.normalizedSemanticText(query)
        let floor = 200
        let cap = normalized.count <= mediumQueryLength ? 600 : 900
        return min(max(resultLimit, floor), cap)
    }

    @MainActor
    func rerankByLexicalMatch(_ items: [ClipboardItem], keyword: String) -> [ClipboardItem] {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, items.count > 1 else { return items }

        let queryKey = lexicalMatchKey(for: trimmed)
        guard !queryKey.isEmpty else { return items }

        let ranked = items.enumerated().map { offset, item in
            (
                offset: offset,
                strength: lexicalMatchStrength(
                    queryKey: queryKey,
                    rawQuery: trimmed,
                    text: item.searchText,
                    title: item.displayTitle,
                    appName: item.appName
                ),
                item: item
            )
        }
        guard ranked.contains(where: { $0.strength > 0 }) else { return items }

        return ranked.sorted { lhs, rhs in
            if lhs.strength != rhs.strength {
                return lhs.strength > rhs.strength
            }
            return lhs.offset < rhs.offset
        }.map(\.item)
    }

    nonisolated func lexicalMatchStrength(query: String, text: String, title: String?, appName: String) -> Int {
        let rawQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let queryKey = lexicalMatchKey(for: rawQuery)
        return lexicalMatchStrength(
            queryKey: queryKey,
            rawQuery: rawQuery,
            text: text,
            title: title,
            appName: appName
        )
    }

    nonisolated func lexicalMatchKey(for query: String) -> String {
        Self.lexicalKey(query)
    }

    nonisolated func lexicalMatchStrength(queryKey: String, rawQuery: String, text: String, title: String?, appName: String) -> Int {
        guard !queryKey.isEmpty else { return 0 }

        let titleKey = Self.lexicalKey(title ?? "")
        if titleKey == queryKey || Self.lexicalEquals(text, queryKey: queryKey) {
            return 4
        }
        if titleKey.contains(queryKey) {
            return 3
        }
        if Self.lexicalContains(text, queryKey: queryKey, rawQuery: rawQuery) {
            return 2
        }
        let appKey = Self.lexicalKey(appName)
        if appKey.contains(queryKey) {
            return 1
        }
        return 0
    }

    nonisolated func clearCache() {
        cacheBox.cache.removeAllObjects()
    }

    nonisolated func setPanelActive(_ active: Bool) {
        if active {
            cancelEmbeddingRelease()
        } else {
            cancelEmbeddingRelease()
            unloadEmbeddings()
        }
    }

    private nonisolated func embeddingBox(for text: String, cacheKey: String) -> EmbeddingBox? {
        let clipped = Self.normalizedSemanticText(text)
        guard !clipped.isEmpty else { return nil }

        if let cached = cacheBox.cache.object(forKey: cacheKey as NSString) {
            return cached
        }

        guard let floatVector = vectorForText(clipped) else { return nil }
        let norm = vectorNorm(floatVector)
        let box = EmbeddingBox(vector: floatVector, norm: norm)
        cacheBox.cache.setObject(box, forKey: cacheKey as NSString)
        return box
    }

    private nonisolated func cachePrecomputedBox(vector: [Float], cacheKey: String) -> EmbeddingBox {
        if let cached = cacheBox.cache.object(forKey: cacheKey as NSString) {
            return cached
        }
        let norm = vectorNorm(vector)
        let box = EmbeddingBox(vector: vector, norm: norm)
        cacheBox.cache.setObject(box, forKey: cacheKey as NSString)
        return box
    }

    private nonisolated func vectorForText(_ text: String) -> [Float]? {
        let strategy = embeddingStrategy(for: text)
        embeddingLock.lock()
        defer { embeddingLock.unlock() }

        switch strategy {
        case .chineseWordMean:
            guard let wordEmbedding = loadEmbeddingLocked(.simplifiedChinese, kind: "word") else {
                guard let vector = loadEmbeddingLocked(.simplifiedChinese, kind: "sentence")?.vector(for: text) else {
                    return nil
                }
                return vector.map { Float($0) }
            }
            return chineseWordVector(for: text, embedding: wordEmbedding)
        case .englishSentence:
            guard let vector = (loadEmbeddingLocked(.english, kind: "sentence") ?? loadEmbeddingLocked(.simplifiedChinese, kind: "sentence"))?.vector(for: text) else {
                return nil
            }
            return vector.map { Float($0) }
        }
    }

    private nonisolated func embeddingStrategy(for text: String) -> EmbeddingStrategy {
        guard containsChinese(text) else { return .englishSentence }
        // Keep all CJK vectors in one embedding space. Mixing short wordEmbedding
        // queries with longer sentenceEmbedding items makes cosine scores invalid
        // even when dimensions happen to match.
        return .chineseWordMean
    }

    private nonisolated func containsChinese(_ text: String) -> Bool {
        text.contains { $0.isChineseCharacter }
    }

    private nonisolated func loadEmbeddingLocked(_ language: NLLanguage, kind: String) -> NLEmbedding? {
        let logKey = "\(kind):\(language.rawValue)"
        defer {
            if !loggedEmbeddingKeys.contains(logKey) {
                if embeddingLoaded(language: language, kind: kind) {
                    log.info("NLEmbedding loaded for \(logKey)")
                } else {
                    log.warn("NLEmbedding unavailable for \(logKey); semantic search will fall back")
                }
                loggedEmbeddingKeys.insert(logKey)
            }
        }

        switch (language, kind) {
        case (.english, "sentence"):
            if englishEmbedding == nil {
                englishEmbedding = NLEmbedding.sentenceEmbedding(for: .english)
            }
            return englishEmbedding
        case (.simplifiedChinese, "sentence"):
            if chineseEmbedding == nil {
                chineseEmbedding = NLEmbedding.sentenceEmbedding(for: .simplifiedChinese)
            }
            return chineseEmbedding
        case (.simplifiedChinese, "word"):
            if chineseWordEmbedding == nil {
                chineseWordEmbedding = NLEmbedding.wordEmbedding(for: .simplifiedChinese)
            }
            return chineseWordEmbedding
        default:
            return nil
        }
    }

    private nonisolated func embeddingLoaded(language: NLLanguage, kind: String) -> Bool {
        switch (language, kind) {
        case (.english, "sentence"):
            return englishEmbedding != nil
        case (.simplifiedChinese, "sentence"):
            return chineseEmbedding != nil
        case (.simplifiedChinese, "word"):
            return chineseWordEmbedding != nil
        default:
            return false
        }
    }

    private nonisolated func chineseWordVector(for text: String, embedding: NLEmbedding) -> [Float]? {
        if embedding.contains(text), let vector = embedding.vector(for: text) {
            return vector.map { Float($0) }
        }

        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text

        var sum: [Float] = []
        var tokenCount = 0
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            guard tokenCount < maxWordEmbeddingTokens else { return false }
            let token = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty, token.contains(where: { $0.isChineseCharacter }) else { return true }
            guard embedding.contains(token), let vector = embedding.vector(for: token) else { return true }
            if sum.isEmpty {
                sum = Array(repeating: 0, count: vector.count)
            }
            guard sum.count == vector.count else { return true }
            for i in vector.indices {
                sum[i] += Float(vector[i])
            }
            tokenCount += 1
            return true
        }

        guard tokenCount > 0, !sum.isEmpty else { return nil }
        var divisor = Float(tokenCount)
        var averaged = sum
        vDSP_vsdiv(sum, 1, &divisor, &averaged, 1, vDSP_Length(sum.count))
        return averaged
    }

    private nonisolated func minimumScore(for query: String) -> Double {
        let count = query.count
        if count <= shortQueryLength {
            return minScoreShortQuery
        }
        if count <= mediumQueryLength {
            return minScoreMediumQuery
        }
        return minScore
    }

    nonisolated func maxDistance(for query: String) -> Double {
        let score = minimumScore(for: query)
        let clamped = max(-1.0, min(1.0, score))
        // For unit vectors: cosine = 1 - (distance^2 / 2).
        let value = 2.0 * (1.0 - clamped)
        return sqrt(max(0, value))
    }

    private nonisolated static func lexicalKey(_ text: String) -> String {
#if DEBUG
        lexicalKeyInputObserver?(text.utf8.count)
#endif
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let folded = trimmed.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        var result = String()
        result.reserveCapacity(folded.utf8.count)
        var pendingWhitespace = false
        for scalar in folded.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                pendingWhitespace = !result.isEmpty
                continue
            }
            if pendingWhitespace {
                result.append(" ")
                pendingWhitespace = false
            }
            result.unicodeScalars.append(scalar)
        }
        return result
    }

    private nonisolated static func lexicalEquals(_ text: String, queryKey: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let exactLimit = max(queryKey.count * 4, queryKey.count + 64)
        guard trimmed.index(trimmed.startIndex, offsetBy: exactLimit + 1, limitedBy: trimmed.endIndex) == nil else {
            return false
        }
        return lexicalKey(String(trimmed)) == queryKey
    }

    private nonisolated static func lexicalContains(_ text: String, queryKey: String, rawQuery: String) -> Bool {
        guard !text.isEmpty else { return false }
        let query = rawQuery.isEmpty ? queryKey : rawQuery
        if text.range(
            of: query,
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            range: nil,
            locale: Locale(identifier: "en_US_POSIX")
        ) != nil {
            return true
        }

        let fallbackLimit = max(queryKey.count * 8, queryKey.count + 128)
        guard text.index(text.startIndex, offsetBy: fallbackLimit + 1, limitedBy: text.endIndex) == nil else {
            return false
        }
        return lexicalKey(text).contains(queryKey)
    }

    private nonisolated func scheduleEmbeddingRelease() {
        embeddingReleaseLock.lock()
        embeddingReleaseWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.unloadEmbeddings()
        }
        embeddingReleaseWorkItem = workItem
        embeddingReleaseLock.unlock()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + embeddingReleaseDelay, execute: workItem)
    }

    private nonisolated func cancelEmbeddingRelease() {
        embeddingReleaseLock.lock()
        embeddingReleaseWorkItem?.cancel()
        embeddingReleaseWorkItem = nil
        embeddingReleaseLock.unlock()
    }

    /// Drop the NLEmbedding models. The next semantic query loads them again.
    nonisolated func releaseEmbeddingsNow() {
        cancelEmbeddingRelease()
        unloadEmbeddings()
    }

    private nonisolated func unloadEmbeddings() {
        embeddingLock.lock()
        defer { embeddingLock.unlock() }
        englishEmbedding = nil
        chineseEmbedding = nil
        chineseWordEmbedding = nil
    }

    private nonisolated func vectorNorm(_ v: [Float]) -> Float {
        guard !v.isEmpty else { return 0 }
        var sumSquares: Float = 0
        vDSP_svesq(v, 1, &sumSquares, vDSP_Length(v.count))
        return sqrt(sumSquares)
    }

    private nonisolated func sgemvRowMajor(
        matrix: [Float],
        rows: Int,
        cols: Int,
        vector: [Float],
        result: inout [Float]
    ) {
        guard rows > 0, cols > 0 else { return }
        guard vector.count == cols else { return }
        if result.count < rows {
            result = Array(repeating: 0, count: rows)
        }

        matrix.withUnsafeBufferPointer { aPtr in
            vector.withUnsafeBufferPointer { xPtr in
                result.withUnsafeMutableBufferPointer { yPtr in
                    guard let A = aPtr.baseAddress,
                          let x = xPtr.baseAddress,
                          let y = yPtr.baseAddress else {
                        return
                    }

                    vDSP_mmul(
                        A,
                        1,
                        x,
                        1,
                        y,
                        1,
                        vDSP_Length(rows),
                        1,
                        vDSP_Length(cols)
                    )
                }
            }
        }
    }

    private nonisolated func cosineSimilarity(queryVector: [Float], queryNorm: Float, candidateVector: [Float]) -> Double {
        guard queryVector.count == candidateVector.count, !queryVector.isEmpty else { return 0 }
        var dot: Float = 0
        vDSP_dotpr(queryVector, 1, candidateVector, 1, &dot, vDSP_Length(queryVector.count))

        var sumSquaresB: Float = 0
        vDSP_svesq(candidateVector, 1, &sumSquaresB, vDSP_Length(candidateVector.count))
        let denom = Double(queryNorm) * Double(sqrt(sumSquaresB))
        guard denom > 0 else { return 0 }
        return Double(dot) / denom
    }
}
