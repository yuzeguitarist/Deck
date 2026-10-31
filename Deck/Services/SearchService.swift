// Copyright © 2024–2026 Yuze Pan. 保留一切权利。

//
//  SearchService.swift
//  Deck
//
//  Deck Clipboard Manager - Hybrid Search Service
//  Supports Exact / Fuzzy / Regex / Mixed search modes
//

import Foundation
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Search Mode

enum SearchMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case exact
    case fuzzy
    case regex
    case mixed
    case semantic

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .exact:
            return String(localized: "SearchMode.exact")
        case .fuzzy:
            return String(localized: "SearchMode.fuzzy")
        case .regex:
            return String(localized: "SearchMode.regex")
        case .mixed:
            return String(localized: "SearchMode.mixed")
        case .semantic:
            return String(localized: "SearchMode.semantic")
        }
    }

    var description: String {
        switch self {
        case .exact:
            return String(localized: "SearchMode.exact.description")
        case .fuzzy:
            return String(localized: "SearchMode.fuzzy.description")
        case .regex:
            return String(localized: "SearchMode.regex.description")
        case .mixed:
            return String(localized: "SearchMode.mixed.description")
        case .semantic:
            return String(localized: "SearchMode.semantic.description")
        }
    }
}

// MARK: - Search Result

nonisolated struct SearchMatch {
    let item: ClipboardItem
    var score: Double?
    var matchRanges: [Range<String.Index>]

    init(item: ClipboardItem, score: Double? = nil, matchRanges: [Range<String.Index>] = []) {
        self.item = item
        self.score = score
        self.matchRanges = matchRanges
    }
}

struct SearchSnapshot: Sendable {
    let uniqueId: String
    let rowId: Int64
    let timestamp: Int64
    let title: String
    let text: String
    let appName: String
}

struct SearchRank: Sendable {
    var uniqueId: String
    var rowId: Int64
    var timestamp: Int64
    var title: String
    var score: Double
    var exact: Bool
}

// MARK: - Fuse Algorithm (Bitap-based Fuzzy Search)

/// A Swift implementation of fuzzy string matching algorithm
/// Based on the Bitap algorithm with modifications for better fuzzy matching
final class FuseSearch {
    /// Threshold for fuzzy matching (0.0 = exact, 1.0 = match anything)
    /// Lower values require closer matches
    let threshold: Double

    /// Maximum length of pattern for bitap algorithm
    private let maxPatternLength = 32

    /// Search limit for very long strings to prevent performance issues
    private let fuzzySearchLimit = 5000

    nonisolated init(threshold: Double = 0.6) {
        self.threshold = threshold
    }

    /// Represents a fuzzy search result
    struct FuseResult {
        let score: Double
        let ranges: [Range<Int>]
    }

    // MARK: - Public Methods

    /// Search for pattern in text
    /// - Parameters:
    ///   - pattern: The search pattern
    ///   - text: The text to search in
    /// - Returns: FuseResult if match found, nil otherwise
    nonisolated func search(_ pattern: String, in text: String) -> FuseResult? {
        guard !pattern.isEmpty, !text.isEmpty else { return nil }

        let patternLower = pattern.lowercased()
        let patternChars = Array(patternLower)
        let searchText = prepareLowercasedText(text)

        return searchLowercased(patternLower: patternLower, patternChars: patternChars, in: searchText)
    }

    /// Prepare lowercased text with length cap to reduce per-item work.
    nonisolated func prepareLowercasedText(_ text: String) -> String {
        // Limit text length for performance without forcing a full `count` traversal on very
        // long strings (which would defeat the cap).
        if let end = text.index(text.startIndex, offsetBy: fuzzySearchLimit, limitedBy: text.endIndex),
           end != text.endIndex {
            return String(text[..<end]).lowercased()
        }
        return text.lowercased()
    }

    /// Search using pre-lowercased inputs to avoid repeated conversions.
    nonisolated func searchLowercased(
        patternLower: String,
        patternChars: [Character],
        in lowercasedText: String
    ) -> FuseResult? {
        guard !patternLower.isEmpty, !lowercasedText.isEmpty else { return nil }

        // Try exact substring match first (fastest)
        if let range = lowercasedText.range(of: patternLower) {
            let startIndex = lowercasedText.distance(from: lowercasedText.startIndex, to: range.lowerBound)
            let endIndex = lowercasedText.distance(from: lowercasedText.startIndex, to: range.upperBound)
            return FuseResult(score: 0.0, ranges: [startIndex..<endIndex])
        }

        // Fall back to fuzzy search (avoid allocating `[Character]` per item)
        return fuzzyMatch(patternChars: patternChars, in: lowercasedText)
    }

    // MARK: - Private Methods

    /// Perform fuzzy matching using a simplified algorithm
    nonisolated private func fuzzyMatch(patternChars: [Character], in text: String) -> FuseResult? {
        guard !patternChars.isEmpty else { return nil }

        var matchedIndices: [Int] = []
        matchedIndices.reserveCapacity(patternChars.count)
        var patternIndex = 0
        var lastMatchIndex = -1
        var totalDistance = 0
        var textLength = 0

        for char in text {
            if patternIndex < patternChars.count && char == patternChars[patternIndex] {
                matchedIndices.append(textLength)

                // Calculate distance penalty for non-consecutive matches
                if lastMatchIndex >= 0 {
                    let gap = textLength - lastMatchIndex - 1
                    totalDistance += gap
                }

                lastMatchIndex = textLength
                patternIndex += 1
            }
            textLength += 1
        }

        // All pattern characters must be found
        guard patternIndex == patternChars.count else { return nil }

        // Calculate score based on:
        // 1. How consecutive the matches are
        // 2. How early in the text the matches start
        // 3. The ratio of matched characters to total text length

        let denom = Double(max(1, textLength))
        let consecutiveBonus = 1.0 - (Double(totalDistance) / denom)
        let startBonus = 1.0 - (Double(matchedIndices.first ?? 0) / denom)
        let coverageRatio = Double(patternChars.count) / denom

        let score = 1.0 - (consecutiveBonus * 0.5 + startBonus * 0.3 + coverageRatio * 0.2)

        // Check if score is within threshold
        guard score <= threshold else { return nil }

        // Convert matched indices to ranges
        let ranges = convertToRanges(matchedIndices)

        return FuseResult(score: score, ranges: ranges)
    }

    /// Convert array of indices to array of consecutive ranges
    nonisolated private func convertToRanges(_ indices: [Int]) -> [Range<Int>] {
        guard !indices.isEmpty else { return [] }

        var ranges: [Range<Int>] = []
        var rangeStart = indices[0]
        var rangeEnd = indices[0]

        for i in 1..<indices.count {
            if indices[i] == rangeEnd + 1 {
                // Consecutive, extend the range
                rangeEnd = indices[i]
            } else {
                // Non-consecutive, save current range and start new one
                ranges.append(rangeStart..<(rangeEnd + 1))
                rangeStart = indices[i]
                rangeEnd = indices[i]
            }
        }

        // Don't forget the last range
        ranges.append(rangeStart..<(rangeEnd + 1))

        return ranges
    }
}

// MARK: - Search Service

nonisolated final class SearchService: @unchecked Sendable {
    nonisolated static let shared = SearchService()

    nonisolated private let fuse = FuseSearch(threshold: 0.6)

    /// Cache prepared lowercased texts across keystrokes to avoid repeated work while typing.
    /// Keep memory bounded with count/cost limits.
    nonisolated(unsafe) private let preparedLowercasedTextCache: NSCache<NSString, NSString> = {
        let cache = NSCache<NSString, NSString>()
        cache.countLimit = 800
        cache.totalCostLimit = 8 * 1024 * 1024
        return cache
    }()

    private var sensitiveCacheObservers: [NSObjectProtocol] = []

    private init() {
#if canImport(AppKit)
        // In security mode, clear plaintext cache when the app/session becomes inactive.
        sensitiveCacheObservers.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.willResignActiveNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.invalidateSensitiveCachesIfNeeded()
                }
            }
        )
        sensitiveCacheObservers.append(
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.sessionDidResignActiveNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.invalidateSensitiveCachesIfNeeded()
                }
            }
        )
#endif
    }

    @MainActor
    private func invalidateSensitiveCachesIfNeeded() {
        guard DeckUserDefaults.securityModeEnabled else { return }
        preparedLowercasedTextCache.removeAllObjects()
    }

    func clearPreparedTextCache() {
        preparedLowercasedTextCache.removeAllObjects()
    }

    func invalidatePreparedTextCache(for uniqueId: String) {
        preparedLowercasedTextCache.removeObject(forKey: uniqueId as NSString)
    }

    /// Search items using the specified mode
    /// - Parameters:
    ///   - query: Search query string
    ///   - items: Items to search within
    ///   - mode: Search mode to use
    /// - Returns: Array of search matches sorted by relevance
    @MainActor
    func search(query: String, within items: [ClipboardItem], mode: SearchMode) -> [SearchMatch] {
        // Frequently called while user is typing; bail out early when cancelled.
        guard !Task.isCancelled else { return [] }
        guard !query.isEmpty else {
            return items.map { SearchMatch(item: $0) }
        }

        switch mode {
        case .exact:
            return exactSearch(query: query, within: items)
        case .fuzzy:
            return fuzzySearch(query: query, within: items)
        case .regex:
            return regexSearch(query: query, within: items)
        case .mixed:
            return mixedSearch(query: query, within: items)
        case .semantic:
            return mixedSearch(query: query, within: items)
        }
    }

    /// Search snapshots off the main actor and return ordered uniqueIds.
    /// Unsorted hits for one batch. Callers sort the merged list so a full scan
    /// does not have to keep every row alive.
    nonisolated func collectRanks(query: String, within snapshots: [SearchSnapshot], mode: SearchMode) -> [SearchRank] {
        guard !Task.isCancelled, !query.isEmpty else { return [] }
        let wantExact = mode == .exact || mode == .mixed || mode == .semantic
        let wantFuzzy = mode == .fuzzy || mode == .mixed || mode == .semantic
        let options: NSString.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        let patternLower = query.lowercased()
        let patternChars = Array(patternLower)
        var ranks: [SearchRank] = []
        ranks.reserveCapacity(min(snapshots.count, 64))
        for snapshot in snapshots {
            if Task.isCancelled { return [] }
            let exact = wantExact && (
                Self.containsExactQuery(query, in: snapshot.title, options: options)
                    || Self.containsExactQuery(query, in: snapshot.appName, options: options)
                    || Self.containsExactQuery(query, in: snapshot.text, options: options)
            )
            var bestScore: Double?
            if wantFuzzy {
                if !snapshot.title.isEmpty,
                   let match = fuse.searchLowercased(patternLower: patternLower, patternChars: patternChars, in: snapshot.title.lowercased()) {
                    bestScore = match.score
                }
                if !snapshot.appName.isEmpty,
                   let match = fuse.searchLowercased(patternLower: patternLower, patternChars: patternChars, in: snapshot.appName.lowercased()) {
                    bestScore = min(bestScore ?? match.score, match.score)
                }
                let nsKey = snapshot.uniqueId as NSString
                let lowerText: String
                if let cached = preparedLowercasedTextCache.object(forKey: nsKey) {
                    lowerText = cached as String
                } else {
                    let prepared = fuse.prepareLowercasedText(snapshot.text)
                    preparedLowercasedTextCache.setObject(prepared as NSString, forKey: nsKey, cost: prepared.utf16.count * 2)
                    lowerText = prepared
                }
                if let match = fuse.searchLowercased(patternLower: patternLower, patternChars: patternChars, in: lowerText) {
                    bestScore = min(bestScore ?? match.score, match.score)
                }
            }
            if exact || bestScore != nil {
                ranks.append(SearchRank(
                    uniqueId: snapshot.uniqueId,
                    rowId: snapshot.rowId,
                    timestamp: snapshot.timestamp,
                    title: snapshot.title,
                    score: bestScore ?? 0,
                    exact: exact
                ))
            }
        }
        return ranks
    }

    nonisolated func orderedUniqueIds(from ranks: [SearchRank], mode: SearchMode) -> [String] {
        if mode == .exact || mode == .mixed || mode == .semantic {
            let exacts = ranks.filter(\.exact)
            if !exacts.isEmpty {
                return exacts.sorted { lhs, rhs in
                    if lhs.timestamp != rhs.timestamp { return lhs.timestamp > rhs.timestamp }
                    return lhs.rowId > rhs.rowId
                }.map(\.uniqueId)
            }
            if mode == .exact { return [] }
        }
        return ranks.sorted { lhs, rhs in
            if let better = Self.isBetterScore(lhs.score, than: rhs.score) { return better }
            if lhs.timestamp != rhs.timestamp { return lhs.timestamp > rhs.timestamp }
            return lhs.rowId > rhs.rowId
        }.map(\.uniqueId)
    }

    nonisolated func searchUniqueIds(query: String, within snapshots: [SearchSnapshot], mode: SearchMode) -> [String] {
        guard !Task.isCancelled else { return [] }
        guard !query.isEmpty else { return snapshots.map { $0.uniqueId } }

        switch mode {
        case .exact:
            return exactSearchIds(query: query, within: snapshots)
        case .fuzzy:
            return fuzzySearchIds(query: query, within: snapshots)
        case .regex:
            return regexSearchIds(query: query, within: snapshots)
        case .mixed, .semantic:
            return mixedSearchIds(query: query, within: snapshots)
        }
    }

    // MARK: - Exact Search

    @MainActor
    private func exactSearch(query: String, within items: [ClipboardItem]) -> [SearchMatch] {
        var results: [SearchMatch] = []
        results.reserveCapacity(min(items.count, 64))

        for item in items {
            if Task.isCancelled { return [] }
            let searchText = item.searchableText
            if let range = searchText.range(of: query, options: .caseInsensitive) {
                results.append(SearchMatch(item: item, score: 0, matchRanges: [range]))
            }
        }

        return results.sorted { lhs, rhs in
            Self.isMoreRecent(lhs.item, than: rhs.item)
        }
    }

    nonisolated private func exactSearchIds(query: String, within snapshots: [SearchSnapshot]) -> [String] {
        var results: [SearchSnapshot] = []
        results.reserveCapacity(min(snapshots.count, 64))

        let options: NSString.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        for snapshot in snapshots {
            if Task.isCancelled { return [] }
            if Self.containsExactQuery(query, in: snapshot.title, options: options)
                || Self.containsExactQuery(query, in: snapshot.appName, options: options)
                || Self.containsExactQuery(query, in: snapshot.text, options: options) {
                results.append(snapshot)
            }
        }

        results.sort { lhs, rhs in
            Self.isMoreRecent(lhs, than: rhs)
        }
        return results.map { $0.uniqueId }
    }

    nonisolated private static func containsExactQuery(
        _ query: String,
        in text: String,
        options: NSString.CompareOptions
    ) -> Bool {
        guard !text.isEmpty else { return false }
        return (text as NSString).range(of: query, options: options).location != NSNotFound
    }

    // MARK: - Fuzzy Search

    @MainActor
    private func fuzzySearch(query: String, within items: [ClipboardItem]) -> [SearchMatch] {
        var results: [SearchMatch] = []
        results.reserveCapacity(min(items.count, 64))
        let patternLower = query.lowercased()
        let patternChars = Array(patternLower)

        for item in items {
            if Task.isCancelled { return [] }
            let searchText = item.searchableText
            let cacheKey = item.uniqueId
            let nsKey = cacheKey as NSString
            let lowercased: String
            if let cached = preparedLowercasedTextCache.object(forKey: nsKey) {
                lowercased = cached as String
            } else {
                let prepared = fuse.prepareLowercasedText(searchText)
                preparedLowercasedTextCache.setObject(
                    prepared as NSString,
                    forKey: nsKey,
                    cost: prepared.utf16.count * 2
                )
                lowercased = prepared
            }

            guard let result = fuse.searchLowercased(
                patternLower: patternLower,
                patternChars: patternChars,
                in: lowercased
            ) else {
                continue
            }

            // Convert Int ranges to String.Index ranges without forcing `count` on long strings.
            let stringRanges: [Range<String.Index>] = result.ranges.compactMap { intRange in
                guard let startIndex = searchText.index(
                    searchText.startIndex,
                    offsetBy: intRange.lowerBound,
                    limitedBy: searchText.endIndex
                ),
                let endIndex = searchText.index(
                    searchText.startIndex,
                    offsetBy: intRange.upperBound,
                    limitedBy: searchText.endIndex
                ) else {
                    return nil
                }
                return startIndex..<endIndex
            }

            results.append(SearchMatch(item: item, score: result.score, matchRanges: stringRanges))
        }

        if Task.isCancelled { return [] }

        // Sort by score (lower is better), then recency for equal-scored hits.
        return results.sorted { lhs, rhs in
            Self.isBetterScore(lhs.score, than: rhs.score) ?? Self.isMoreRecent(lhs.item, than: rhs.item)
        }
    }

    nonisolated private func fuzzySearchIds(query: String, within snapshots: [SearchSnapshot]) -> [String] {
        var results: [(snapshot: SearchSnapshot, score: Double)] = []
        results.reserveCapacity(min(snapshots.count, 64))
        let patternLower = query.lowercased()
        let patternChars = Array(patternLower)

        for snapshot in snapshots {
            if Task.isCancelled { return [] }
            let cacheKey = snapshot.uniqueId
            var bestScore: Double?
            if !snapshot.title.isEmpty,
               let r = fuse.searchLowercased(
                patternLower: patternLower,
                patternChars: patternChars,
                in: snapshot.title.lowercased()
               ) {
                bestScore = r.score
            }
            if !snapshot.appName.isEmpty,
               let r = fuse.searchLowercased(
                patternLower: patternLower,
                patternChars: patternChars,
                in: snapshot.appName.lowercased()
               ) {
                bestScore = min(bestScore ?? r.score, r.score)
            }
            let nsKey = cacheKey as NSString
            let lowerText: String
            if let cached = preparedLowercasedTextCache.object(forKey: nsKey) {
                lowerText = cached as String
            } else {
                let prepared = fuse.prepareLowercasedText(snapshot.text)
                preparedLowercasedTextCache.setObject(prepared as NSString, forKey: nsKey, cost: prepared.utf16.count * 2)
                lowerText = prepared
            }
            if let r = fuse.searchLowercased(patternLower: patternLower, patternChars: patternChars, in: lowerText) {
                bestScore = min(bestScore ?? r.score, r.score)
            }
            guard let score = bestScore else { continue }
            results.append((snapshot, score))
        }

        if Task.isCancelled { return [] }

        results.sort { lhs, rhs in
            Self.isBetterScore(lhs.score, than: rhs.score) ?? Self.isMoreRecent(lhs.snapshot, than: rhs.snapshot)
        }
        return results.map { $0.snapshot.uniqueId }
    }

    nonisolated private static func isBetterScore(_ lhs: Double?, than rhs: Double?) -> Bool? {
        let lhsScore = lhs.map { $0.isNaN ? 1.0 : $0 } ?? 1.0
        let rhsScore = rhs.map { $0.isNaN ? 1.0 : $0 } ?? 1.0
        if lhsScore < rhsScore { return true }
        if lhsScore > rhsScore { return false }
        return nil
    }

    @MainActor
    private static func isMoreRecent(_ lhs: ClipboardItem, than rhs: ClipboardItem) -> Bool {
        if lhs.timestamp != rhs.timestamp {
            return lhs.timestamp > rhs.timestamp
        }
        return (lhs.id ?? Int64.min) > (rhs.id ?? Int64.min)
    }

    nonisolated private static func isMoreRecent(_ lhs: SearchSnapshot, than rhs: SearchSnapshot) -> Bool {
        if lhs.timestamp != rhs.timestamp {
            return lhs.timestamp > rhs.timestamp
        }
        return lhs.rowId > rhs.rowId
    }

    // MARK: - Regex Search

    @MainActor
    private func regexSearch(query: String, within items: [ClipboardItem]) -> [SearchMatch] {
        // Validate regex
        guard let regex = RegexCache.shared.regex(for: query) else {
            return []
        }

        var results: [SearchMatch] = []
        results.reserveCapacity(min(items.count, 64))

        for item in items {
            if Task.isCancelled { return [] }
            let searchText = item.searchableText
            let nsRange = NSRange(searchText.startIndex..., in: searchText)

            if let match = regex.firstMatch(in: searchText, options: [], range: nsRange),
               let range = Range(match.range, in: searchText) {
                results.append(SearchMatch(item: item, score: 0, matchRanges: [range]))
            }
        }

        return results
    }

    nonisolated private func regexSearchIds(query: String, within snapshots: [SearchSnapshot]) -> [String] {
        guard let regex = RegexCache.shared.regex(for: query) else {
            return []
        }

        var results: [String] = []
        results.reserveCapacity(min(snapshots.count, 64))

        for snapshot in snapshots {
            if Task.isCancelled { return [] }
            if regex.firstMatch(
                in: snapshot.title,
                options: [],
                range: NSRange(snapshot.title.startIndex..., in: snapshot.title)
            ) != nil
                || regex.firstMatch(
                    in: snapshot.appName,
                    options: [],
                    range: NSRange(snapshot.appName.startIndex..., in: snapshot.appName)
                ) != nil
                || regex.firstMatch(
                    in: snapshot.text,
                    options: [],
                    range: NSRange(snapshot.text.startIndex..., in: snapshot.text)
                ) != nil {
                results.append(snapshot.uniqueId)
            }
        }

        return results
    }

    // MARK: - Mixed Search

    /// Mixed search: tries exact → regex → fuzzy in order
    @MainActor
    private func mixedSearch(query: String, within items: [ClipboardItem]) -> [SearchMatch] {
        // 1. Try exact match first
        var results = exactSearch(query: query, within: items)
        if Task.isCancelled { return [] }
        if !results.isEmpty {
            return results
        }

        // 2. Try regex if query looks like a regex pattern
        if looksLikeRegex(query) {
            results = regexSearch(query: query, within: items)
            if Task.isCancelled { return [] }
            if !results.isEmpty {
                return results
            }
        }

        // 3. Fall back to fuzzy search
        results = fuzzySearch(query: query, within: items)
        return results
    }

    nonisolated private func mixedSearchIds(query: String, within snapshots: [SearchSnapshot]) -> [String] {
        var results = exactSearchIds(query: query, within: snapshots)
        if Task.isCancelled { return [] }
        if !results.isEmpty {
            return results
        }

        if looksLikeRegex(query) {
            results = regexSearchIds(query: query, within: snapshots)
            if Task.isCancelled { return [] }
            if !results.isEmpty {
                return results
            }
        }

        results = fuzzySearchIds(query: query, within: snapshots)
        return results
    }

    /// Check if query looks like a regex pattern
    nonisolated func looksLikeRegex(_ query: String) -> Bool {
        // Check for common regex metacharacters
        let regexIndicators: [Character] = ["*", "+", "?", "^", "$", "[", "]", "(", ")", "{", "}", "|", "\\", "."]
        return query.contains(where: { regexIndicators.contains($0) })
    }
}
