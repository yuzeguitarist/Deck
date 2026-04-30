// Copyright © 2024–2026 Yuze Pan. 保留一切权利。

//
//  AppleStreamingMetadataResolver.swift
//  Deck
//
//  Apple Music / Apple Podcasts 链接元数据解析
//

import Foundation

actor AppleStreamingMetadataResolver {
    static let shared = AppleStreamingMetadataResolver()

    enum Provider: String, Sendable {
        case appleMusic
        case applePodcasts
    }

    enum CardIconKind: Sendable {
        case none
        case podcast
        case appleMusicSong
        case appleMusicAlbum
    }

    struct Enrichment: Sendable {
        let canonicalURL: URL
        let provider: Provider
        let providerName: String
        let providerSymbolName: String

        let title: String?
        let summary: String?
        let artworkURL: URL?

        let publishedAt: Date?
        let duration: TimeInterval?
        let descriptionText: String?
        let sourceURL: URL?
    }

    private let session: URLSession

    private let cacheLimit = 256
    private var cacheOrder: [String] = []
    private var cache: [String: Enrichment] = [:]

    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8.0
        config.timeoutIntervalForResource = 15.0
        config.waitsForConnectivity = true
        config.urlCache = URLCache(memoryCapacity: 1 * 1024 * 1024, diskCapacity: 0, diskPath: nil)
        session = URLSession(configuration: config)
    }

    nonisolated static func isCandidateURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        if host == "apple.co" { return true }
        if host == "music.apple.com" { return true }
        if host == "podcasts.apple.com" { return true }
        if host == "itunes.apple.com" || host.hasSuffix(".itunes.apple.com") {
            let path = url.path.lowercased()
            if path.contains("/podcast") { return true }
            if path.contains("/album") || path.contains("/song") || path.contains("/music") {
                return true
            }
        }
        return false
    }

    nonisolated static func classifyForCardIcon(url: URL) -> CardIconKind {
        guard let provider = detectProvider(for: url) else {
            return .none
        }

        switch provider {
        case .applePodcasts:
            return .podcast
        case .appleMusic:
            let path = url.path.lowercased()
            if Self.intQueryItem(url: url, name: "i") != nil || path.contains("/song/") {
                return .appleMusicSong
            }
            if path.contains("/album/") {
                return .appleMusicAlbum
            }
            return .appleMusicSong
        }
    }

    func enrich(url: URL, includeDetails: Bool) async -> Enrichment? {
        guard Self.isCandidateURL(url) else { return nil }

        let canonical = await resolveCanonicalURLIfNeeded(url)
        guard let provider = Self.detectProvider(for: canonical) else { return nil }

        let key = canonical.absoluteString + (includeDetails ? "|d1" : "|d0")
        if let cached = cache[key] {
            return cached
        }

        let country = Self.storefrontCountryCode(from: canonical) ?? Self.defaultCountryCode()

        let enrichment: Enrichment?
        switch provider {
        case .appleMusic:
            enrichment = await enrichAppleMusic(url: canonical, country: country)
        case .applePodcasts:
            enrichment = await enrichApplePodcasts(url: canonical, country: country, includeDetails: includeDetails)
        }

        if let enrichment {
            cache[key] = enrichment
            cacheOrder.append(key)
            trimCacheIfNeeded()
        }

        return enrichment
    }

    private static func detectProvider(for url: URL) -> Provider? {
        guard let host = url.host?.lowercased() else { return nil }
        if host == "music.apple.com" { return .appleMusic }
        if host == "podcasts.apple.com" { return .applePodcasts }

        if host == "itunes.apple.com" || host.hasSuffix(".itunes.apple.com") {
            let path = url.path.lowercased()
            if path.contains("/podcast") { return .applePodcasts }
            if path.contains("/album") || path.contains("/song") || path.contains("/music") {
                return .appleMusic
            }
        }

        return nil
    }

    private static func storefrontCountryCode(from url: URL) -> String? {
        let comps = url.path.split(separator: "/", omittingEmptySubsequences: true)
        guard let first = comps.first else { return nil }
        let code = String(first).lowercased()
        guard code.count == 2 else { return nil }
        guard code.range(of: "^[a-z]{2}$", options: .regularExpression) != nil else { return nil }
        return code
    }

    private static func defaultCountryCode() -> String {
        if let region = Locale.current.region?.identifier.lowercased(), region.count == 2 {
            return region
        }
        return "us"
    }

    private func enrichAppleMusic(url: URL, country: String) async -> Enrichment? {
        let trackId = Self.intQueryItem(url: url, name: "i")
        let collectionId = Self.lastPathNumericID(url: url)
        guard let id = trackId ?? collectionId else { return nil }

        guard let response = await lookupITunes(id: id, country: country) else { return nil }

        // Prefer an exact match by trackId first, then collectionId.
        // This fixes Apple Music `/song/<trackId>` URLs which don't include the `?i=` query item.
        // In that case `id` is still a trackId, and iTunes lookup returns a track item.
        let item =
            response.results.first(where: { $0.trackId == id }) ??
            response.results.first(where: { $0.collectionId == id }) ??
            response.results.first

        guard let item else { return nil }

        let pathLower = url.path.lowercased()
        let isSongPath = pathLower.contains("/song/")
        let isTrack: Bool = {
            if trackId != nil { return true }
            if isSongPath { return true }
            if let wrapperType = item.wrapperType?.lowercased(), wrapperType == "track" { return true }
            if let kind = item.kind?.lowercased(), kind == "song" { return true }
            if item.trackId == id { return true }
            return false
        }()

        let title: String? = isTrack
            ? (item.trackName ?? item.collectionName)
            : (item.collectionName ?? item.trackName)

        let artist = item.artistName
        let album = item.collectionName

        let providerName = "Apple Music"
        let providerSymbolName = "music.note"

        let summary: String? = {
            if let artist, !artist.isEmpty, let album, !album.isEmpty, isTrack {
                return "\(providerName) · \(artist) • \(album)"
            }
            if let artist, !artist.isEmpty {
                return "\(providerName) · \(artist)"
            }
            return providerName
        }()

        let artworkURL = Self.bestArtworkURL(from: item)

        return Enrichment(
            canonicalURL: url,
            provider: .appleMusic,
            providerName: providerName,
            providerSymbolName: providerSymbolName,
            title: title,
            summary: summary,
            artworkURL: artworkURL,
            publishedAt: nil,
            duration: nil,
            descriptionText: nil,
            sourceURL: nil
        )
    }

    private func enrichApplePodcasts(url: URL, country: String, includeDetails: Bool) async -> Enrichment? {
        let showId = Self.firstIDPrefixedComponent(url: url) ?? Self.lastPathNumericID(url: url)
        guard let showId else { return nil }

        let episodeId = Self.intQueryItem(url: url, name: "i")

        let providerName = "Apple Podcasts"
        let providerSymbolName = "dot.radiowaves.left.and.right"

        if let episodeId {
            let episodeResponse = await lookupITunes(id: episodeId, country: country)
            let episodeItem = episodeResponse?.results.first { $0.trackId == episodeId } ?? episodeResponse?.results.first

            let showResponse = await lookupITunes(id: showId, country: country)
            let showItem = showResponse?.results.first { $0.collectionId == showId } ?? showResponse?.results.first

            let title: String? = episodeItem?.trackName ?? episodeItem?.collectionName
            let showName = episodeItem?.collectionName ?? showItem?.collectionName
            let author = episodeItem?.artistName ?? showItem?.artistName

            let publishedAt: Date? = Self.parseISO8601Date(episodeItem?.releaseDate)

            let duration: TimeInterval? = {
                guard let ms = episodeItem?.trackTimeMillis else { return nil }
                return TimeInterval(ms) / 1000.0
            }()

            let descriptionText: String? = {
                guard includeDetails else { return nil }
                let raw = episodeItem?.description ?? episodeItem?.shortDescription
                return Self.normalizeDescription(raw)
            }()

            let feedURL: URL? = {
                guard let feed = showItem?.feedUrl, !feed.isEmpty else { return nil }
                return URL(string: feed)
            }()

            let artworkURL: URL? = {
                if let ep = episodeItem.flatMap(Self.bestArtworkURL(from:)) { return ep }
                if let show = showItem.flatMap(Self.bestArtworkURL(from:)) { return show }
                return nil
            }()

            let summary: String? = {
                var parts: [String] = [providerName]
                if let showName, !showName.isEmpty {
                    parts.append(showName)
                }
                if let author, !author.isEmpty {
                    let showLower = (showName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    let authorLower = author.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    if !authorLower.isEmpty, authorLower != showLower {
                        parts.append(author)
                    }
                }
                return parts.joined(separator: " · ")
            }()

            return Enrichment(
                canonicalURL: url,
                provider: .applePodcasts,
                providerName: providerName,
                providerSymbolName: providerSymbolName,
                title: title,
                summary: summary,
                artworkURL: artworkURL,
                publishedAt: publishedAt,
                duration: duration,
                descriptionText: descriptionText,
                sourceURL: feedURL
            )
        }

        let showResponse = await lookupITunes(id: showId, country: country)
        let showItem = showResponse?.results.first { $0.collectionId == showId } ?? showResponse?.results.first
        guard let showItem else { return nil }

        let title = showItem.collectionName ?? showItem.trackName
        let author = showItem.artistName

        let feedURL: URL? = {
            guard let feed = showItem.feedUrl, !feed.isEmpty else { return nil }
            return URL(string: feed)
        }()

        let summary: String? = {
            if let author, !author.isEmpty {
                return "\(providerName) · \(author)"
            }
            return providerName
        }()

        let artworkURL = Self.bestArtworkURL(from: showItem)

        return Enrichment(
            canonicalURL: url,
            provider: .applePodcasts,
            providerName: providerName,
            providerSymbolName: providerSymbolName,
            title: title,
            summary: summary,
            artworkURL: artworkURL,
            publishedAt: nil,
            duration: nil,
            descriptionText: nil,
            sourceURL: feedURL
        )
    }

    private struct ITunesLookupResponse: Decodable {
        let resultCount: Int
        let results: [ITunesResult]
    }

    private struct ITunesResult: Decodable {
        let wrapperType: String?
        let kind: String?

        let trackId: Int?
        let collectionId: Int?

        let trackName: String?
        let collectionName: String?
        let artistName: String?

        let artworkUrl60: String?
        let artworkUrl100: String?
        let artworkUrl600: String?

        let releaseDate: String?
        let trackTimeMillis: Int?

        let description: String?
        let shortDescription: String?

        let feedUrl: String?
    }

    private func lookupITunes(id: Int, country: String) async -> ITunesLookupResponse? {
        guard var comps = URLComponents(string: "https://itunes.apple.com/lookup") else { return nil }
        comps.queryItems = [
            URLQueryItem(name: "id", value: String(id)),
            URLQueryItem(name: "country", value: country)
        ]
        guard let url = comps.url else { return nil }

        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        request.setValue(
            "Deck/1.0 (macOS) AppleStreamingMetadataResolver",
            forHTTPHeaderField: "User-Agent"
        )

        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                return nil
            }
            return try JSONDecoder().decode(ITunesLookupResponse.self, from: data)
        } catch {
            return nil
        }
    }

    private func resolveCanonicalURLIfNeeded(_ url: URL) async -> URL {
        guard let host = url.host?.lowercased(), host == "apple.co" else { return url }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "HEAD"
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 8.0
            let (_, response) = try await session.data(for: request)
            if let finalURL = response.url {
                return finalURL
            }
        } catch {}

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 8.0
            request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
            let (_, response) = try await session.data(for: request)
            if let finalURL = response.url {
                return finalURL
            }
        } catch {}

        return url
    }

    private func trimCacheIfNeeded() {
        while cacheOrder.count > cacheLimit {
            let victim = cacheOrder.removeFirst()
            cache.removeValue(forKey: victim)
        }
    }

    private static func intQueryItem(url: URL, name: String) -> Int? {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        return comps.queryItems?.first(where: { $0.name == name })?.value.flatMap { Int($0) }
    }

    private static func lastPathNumericID(url: URL) -> Int? {
        let comps = url.path.split(separator: "/", omittingEmptySubsequences: true)
        guard let last = comps.last else { return nil }
        let raw = String(last)
        if let value = Int(raw) { return value }
        if raw.hasPrefix("id"), let value = Int(raw.dropFirst(2)) { return value }
        return nil
    }

    private static func firstIDPrefixedComponent(url: URL) -> Int? {
        let comps = url.path.split(separator: "/", omittingEmptySubsequences: true)
        for comp in comps.reversed() {
            let raw = String(comp)
            if raw.hasPrefix("id"), let value = Int(raw.dropFirst(2)) {
                return value
            }
        }
        return nil
    }

    private static func bestArtworkURL(from item: ITunesResult) -> URL? {
        if let u = item.artworkUrl600, let url = URL(string: u) { return url }
        if let upgraded = upgradedArtworkURL(item.artworkUrl100, targetSize: 600) { return upgraded }
        if let upgraded = upgradedArtworkURL(item.artworkUrl60, targetSize: 600) { return upgraded }
        return nil
    }

    private static func upgradedArtworkURL(_ raw: String?, targetSize: Int) -> URL? {
        guard let raw, !raw.isEmpty else { return nil }

        let pattern = #"(\d{2,4})x(\d{2,4})(bb)?"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let range = NSRange(location: 0, length: (raw as NSString).length)
            let replaced = regex.stringByReplacingMatches(
                in: raw,
                options: [],
                range: range,
                withTemplate: "\(targetSize)x\(targetSize)$3"
            )
            return URL(string: replaced)
        }

        return URL(string: raw)
    }

    private static func parseISO8601Date(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: raw) {
            return date
        }
        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime]
        return fallback.date(from: raw)
    }

    private static func normalizeDescription(_ raw: String?) -> String? {
        guard var raw, !raw.isEmpty else { return nil }

        raw = raw.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
        raw = raw.replacingOccurrences(of: "</p>", with: "\n", options: .caseInsensitive)
        raw = raw.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)

        raw = raw
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")

        raw = raw.replacingOccurrences(of: "\r\n", with: "\n")
        raw = raw.replacingOccurrences(of: "\r", with: "\n")
        raw = raw.replacingOccurrences(of: "[\\t ]+", with: " ", options: .regularExpression)
        raw = raw.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let maxLen = 800
        if trimmed.count > maxLen {
            return String(trimmed.prefix(maxLen))
        }
        return trimmed
    }
}
