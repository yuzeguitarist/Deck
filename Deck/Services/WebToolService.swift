// Copyright © 2024–2026 Yuze Pan. 保留一切权利。

//
//  WebToolService.swift
//  Deck
//
//  Web search (Exa AI MCP) and web fetch (URLSession + HTML→Markdown)
//

import Darwin
import Foundation

enum WebToolError: LocalizedError {
    case invalidURL(String)
    case requestFailed(statusCode: Int)
    case responseTooLarge
    case timeout
    case noSearchResults
    case blockedPrivateNetwork(String)
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return "无效 URL：\(url)"
        case .requestFailed(let code):
            return "请求失败（HTTP \(code)）"
        case .responseTooLarge:
            return "响应内容过大（超过 5 MB）"
        case .timeout:
            return "请求超时"
        case .noSearchResults:
            return "未找到搜索结果"
        case .blockedPrivateNetwork(let reason):
            return String(
                format: NSLocalizedString("已阻止访问本机或内网地址：%@", comment: "AI web fetch error: blocked private network"),
                reason
            )
        case .networkError(let message):
            return "网络错误：\(message)"
        }
    }
}

struct WebSearchResult: Sendable {
    let query: String
    let content: String
}

struct WebFetchResult: Sendable {
    let url: String
    let contentType: String
    let content: String
}

final class WebToolService: Sendable {
    static let shared = WebToolService()

    private static let exaBaseURL = "https://mcp.exa.ai/mcp"
    private static let defaultNumResults = 8
    private static let searchTimeout: TimeInterval = 25
    private static let fetchTimeout: TimeInterval = 30
    private static let maxResponseSize = 5 * 1024 * 1024 // 5 MB
    /// `AsyncBytes` 只能按元素迭代；把字节先攒到该缓冲再 `append(contentsOf:)`，避免百万次单字节 `Data.append`。
    private static let asyncBytesBufferSize = 256 * 1024
    private static let networkSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.waitsForConnectivity = false
        return URLSession(configuration: config, delegate: DeckOutboundHTTPRedirectDelegate(), delegateQueue: nil)
    }()

    private init() {}

    // MARK: - Web Search (Exa AI MCP)

    func search(query: String, numResults: Int = 8) async throws -> WebSearchResult {
        let clampedResults = max(1, min(20, numResults))

        let requestBody: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "tools/call",
            "params": [
                "name": "web_search_exa",
                "arguments": [
                    "query": query,
                    "type": "auto",
                    "numResults": clampedResults,
                    "livecrawl": "fallback"
                ] as [String: Any]
            ] as [String: Any]
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            throw WebToolError.networkError("Failed to serialize search request")
        }

        var request = URLRequest(url: URL(string: Self.exaBaseURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData
        request.timeoutInterval = Self.searchTimeout

        let (data, response) = try await performRequest(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw WebToolError.networkError("Invalid response")
        }
        guard httpResponse.statusCode == 200 else {
            throw WebToolError.requestFailed(statusCode: httpResponse.statusCode)
        }

        guard let responseText = String(data: data, encoding: .utf8) else {
            throw WebToolError.noSearchResults
        }

        let lines = responseText.components(separatedBy: "\n")
        for line in lines {
            if line.hasPrefix("data: ") {
                let jsonString = String(line.dropFirst(6))
                guard let jsonData = jsonString.data(using: .utf8),
                      let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                      let result = parsed["result"] as? [String: Any],
                      let content = result["content"] as? [[String: Any]],
                      let firstText = content.first?["text"] as? String,
                      !firstText.isEmpty else {
                    continue
                }
                return WebSearchResult(query: query, content: firstText)
            }
        }

        // Fallback: try parsing the whole response as plain JSON (non-SSE)
        if let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let result = parsed["result"] as? [String: Any],
           let content = result["content"] as? [[String: Any]],
           let firstText = content.first?["text"] as? String,
           !firstText.isEmpty {
            return WebSearchResult(query: query, content: firstText)
        }

        throw WebToolError.noSearchResults
    }

    // MARK: - Web Fetch

    func fetch(url urlString: String, format: String = "markdown") async throws -> WebFetchResult {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            throw WebToolError.invalidURL(urlString)
        }
        if let rejection = DeckOutboundNetworkPolicy.rejectionReason(for: url) {
            throw WebToolError.blockedPrivateNetwork(rejection)
        }

        let headers: [String: String] = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
            "Accept": acceptHeader(for: format),
            "Accept-Language": "en-US,en;q=0.9"
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = Self.fetchTimeout
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await performRequest(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw WebToolError.networkError("Invalid response")
        }

        // Cloudflare bot-detection retry
        if httpResponse.statusCode == 403,
           httpResponse.value(forHTTPHeaderField: "cf-mitigated") == "challenge" {
            var retryRequest = request
            retryRequest.setValue("Deck", forHTTPHeaderField: "User-Agent")
            let (retryData, retryResponse) = try await performRequest(retryRequest)
            guard let retryHTTP = retryResponse as? HTTPURLResponse, retryHTTP.statusCode == 200 else {
                throw WebToolError.requestFailed(statusCode: (retryResponse as? HTTPURLResponse)?.statusCode ?? 403)
            }
            return try processResponse(data: retryData, httpResponse: retryHTTP, url: trimmed, format: format)
        }

        guard httpResponse.statusCode == 200 else {
            throw WebToolError.requestFailed(statusCode: httpResponse.statusCode)
        }

        return try processResponse(data: data, httpResponse: httpResponse, url: trimmed, format: format)
    }

    // MARK: - Private Helpers

    /// 将 `byteBuffer` 合并进 `data`，总长度不超过 `maxTotal`；若缓冲超出剩余空间则视为响应过大。
    private static func flushByteBuffer(
        _ byteBuffer: inout [UInt8],
        into data: inout Data,
        maxTotal: Int
    ) throws {
        guard !byteBuffer.isEmpty else { return }
        let room = maxTotal - data.count
        guard room > 0 else {
            throw WebToolError.responseTooLarge
        }
        if byteBuffer.count <= room {
            data.append(contentsOf: byteBuffer)
            byteBuffer.removeAll(keepingCapacity: true)
        } else {
            data.append(contentsOf: byteBuffer[..<room])
            byteBuffer.removeAll(keepingCapacity: true)
            throw WebToolError.responseTooLarge
        }
    }

    private func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            if let url = request.url,
               let rejection = DeckOutboundNetworkPolicy.rejectionReason(for: url) {
                throw WebToolError.blockedPrivateNetwork(rejection)
            }

            let (asyncBytes, response) = try await Self.networkSession.bytes(for: request)

            if let http = response as? HTTPURLResponse,
               http.expectedContentLength > 0,
               http.expectedContentLength > Self.maxResponseSize {
                throw WebToolError.responseTooLarge
            }

            var data = Data()
            let expectedLen = (response as? HTTPURLResponse)?.expectedContentLength ?? -1
            if expectedLen > 0, expectedLen <= Self.maxResponseSize {
                data.reserveCapacity(Int(expectedLen))
            }

            var byteBuffer: [UInt8] = []
            byteBuffer.reserveCapacity(min(Self.asyncBytesBufferSize, Self.maxResponseSize))

            for try await byte in asyncBytes {
                if data.count >= Self.maxResponseSize {
                    throw WebToolError.responseTooLarge
                }
                byteBuffer.append(byte)
                if byteBuffer.count >= Self.asyncBytesBufferSize {
                    try Self.flushByteBuffer(&byteBuffer, into: &data, maxTotal: Self.maxResponseSize)
                }
            }
            if !byteBuffer.isEmpty {
                try Self.flushByteBuffer(&byteBuffer, into: &data, maxTotal: Self.maxResponseSize)
            }

            return (data, response)
        } catch let error as WebToolError {
            throw error
        } catch let error as URLError where error.code == .timedOut {
            throw WebToolError.timeout
        } catch {
            throw WebToolError.networkError(error.localizedDescription)
        }
    }

    private func processResponse(
        data: Data,
        httpResponse: HTTPURLResponse,
        url: String,
        format: String
    ) throws -> WebFetchResult {
        let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? ""
        let isHTML = contentType.lowercased().contains("text/html")

        guard let rawContent = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) else {
            throw WebToolError.networkError("Unable to decode response body")
        }

        let content: String
        switch format.lowercased() {
        case "markdown":
            content = isHTML ? Self.htmlToMarkdown(rawContent) : rawContent
        case "text":
            content = isHTML ? Self.htmlToPlainText(rawContent) : rawContent
        default:
            content = isHTML ? Self.htmlToMarkdown(rawContent) : rawContent
        }

        return WebFetchResult(url: url, contentType: contentType, content: content)
    }

    private func acceptHeader(for format: String) -> String {
        switch format.lowercased() {
        case "text":
            return "text/plain;q=1.0, text/markdown;q=0.9, text/html;q=0.8, */*;q=0.1"
        case "html":
            return "text/html;q=1.0, application/xhtml+xml;q=0.9, text/plain;q=0.8, */*;q=0.1"
        default:
            return "text/markdown;q=1.0, text/x-markdown;q=0.9, text/plain;q=0.8, text/html;q=0.7, */*;q=0.1"
        }
    }

    // MARK: - HTML → Markdown

    static func htmlToMarkdown(_ html: String) -> String {
        var text = html

        // Remove content inside script, style, noscript, meta, link tags
        let removeTags = ["script", "style", "noscript", "meta", "link", "svg"]
        for tag in removeTags {
            text = text.replacingOccurrences(
                of: "<\(tag)[^>]*>[\\s\\S]*?</\(tag)>",
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
            text = text.replacingOccurrences(
                of: "<\(tag)[^>]*/?>",
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }

        // Headings: <h1>…</h1> → # …
        for level in 1...6 {
            let prefix = String(repeating: "#", count: level)
            text = text.replacingOccurrences(
                of: "<h\(level)[^>]*>(.*?)</h\(level)>",
                with: "\n\n\(prefix) $1\n\n",
                options: [.regularExpression, .caseInsensitive]
            )
        }

        // Horizontal rules
        text = text.replacingOccurrences(
            of: "<hr[^>]*/?>",
            with: "\n\n---\n\n",
            options: [.regularExpression, .caseInsensitive]
        )

        // Block quotes
        text = text.replacingOccurrences(
            of: "<blockquote[^>]*>(.*?)</blockquote>",
            with: "\n\n> $1\n\n",
            options: [.regularExpression, .caseInsensitive]
        )

        // Pre/code blocks: <pre><code>…</code></pre>
        text = text.replacingOccurrences(
            of: "<pre[^>]*>\\s*<code[^>]*>(.*?)</code>\\s*</pre>",
            with: "\n\n```\n$1\n```\n\n",
            options: [.regularExpression, .caseInsensitive]
        )
        text = text.replacingOccurrences(
            of: "<pre[^>]*>(.*?)</pre>",
            with: "\n\n```\n$1\n```\n\n",
            options: [.regularExpression, .caseInsensitive]
        )

        // Inline code
        text = text.replacingOccurrences(
            of: "<code[^>]*>(.*?)</code>",
            with: "`$1`",
            options: [.regularExpression, .caseInsensitive]
        )

        // Bold
        text = text.replacingOccurrences(
            of: "<(strong|b)[^>]*>(.*?)</\\1>",
            with: "**$2**",
            options: [.regularExpression, .caseInsensitive]
        )

        // Italic
        text = text.replacingOccurrences(
            of: "<(em|i)[^>]*>(.*?)</\\1>",
            with: "*$2*",
            options: [.regularExpression, .caseInsensitive]
        )

        // Links: <a href="…">text</a> → [text](href)
        text = text.replacingOccurrences(
            of: "<a[^>]*href=\"([^\"]*)\"[^>]*>(.*?)</a>",
            with: "[$2]($1)",
            options: [.regularExpression, .caseInsensitive]
        )
        text = text.replacingOccurrences(
            of: "<a[^>]*href='([^']*)'[^>]*>(.*?)</a>",
            with: "[$2]($1)",
            options: [.regularExpression, .caseInsensitive]
        )

        // Images: <img src="…" alt="…"> → ![alt](src)
        text = text.replacingOccurrences(
            of: "<img[^>]*src=\"([^\"]*)\"[^>]*alt=\"([^\"]*)\"[^>]*/?>",
            with: "![$2]($1)",
            options: [.regularExpression, .caseInsensitive]
        )
        text = text.replacingOccurrences(
            of: "<img[^>]*alt=\"([^\"]*)\"[^>]*src=\"([^\"]*)\"[^>]*/?>",
            with: "![$1]($2)",
            options: [.regularExpression, .caseInsensitive]
        )

        // List items
        text = text.replacingOccurrences(
            of: "<li[^>]*>(.*?)</li>",
            with: "\n- $1",
            options: [.regularExpression, .caseInsensitive]
        )
        text = text.replacingOccurrences(
            of: "</?[uo]l[^>]*>",
            with: "\n",
            options: [.regularExpression, .caseInsensitive]
        )

        // Paragraphs and line breaks
        text = text.replacingOccurrences(
            of: "<br[^>]*/?>",
            with: "\n",
            options: [.regularExpression, .caseInsensitive]
        )
        text = text.replacingOccurrences(
            of: "</p>",
            with: "\n\n",
            options: [.regularExpression, .caseInsensitive]
        )
        text = text.replacingOccurrences(
            of: "<p[^>]*>",
            with: "\n\n",
            options: [.regularExpression, .caseInsensitive]
        )
        text = text.replacingOccurrences(
            of: "</div>",
            with: "\n",
            options: [.regularExpression, .caseInsensitive]
        )

        // Strip remaining HTML tags
        text = text.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )

        // Decode common HTML entities
        text = decodeHTMLEntities(text)

        // Collapse excessive blank lines
        text = text.replacingOccurrences(
            of: "\\n{3,}",
            with: "\n\n",
            options: .regularExpression
        )

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - HTML → Plain Text

    static func htmlToPlainText(_ html: String) -> String {
        var text = html

        let removeTags = ["script", "style", "noscript", "svg"]
        for tag in removeTags {
            text = text.replacingOccurrences(
                of: "<\(tag)[^>]*>[\\s\\S]*?</\(tag)>",
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }

        text = text.replacingOccurrences(
            of: "<br[^>]*/?>",
            with: "\n",
            options: [.regularExpression, .caseInsensitive]
        )
        text = text.replacingOccurrences(
            of: "</p>",
            with: "\n\n",
            options: [.regularExpression, .caseInsensitive]
        )
        text = text.replacingOccurrences(
            of: "</div>",
            with: "\n",
            options: [.regularExpression, .caseInsensitive]
        )
        text = text.replacingOccurrences(
            of: "<li[^>]*>",
            with: "\n• ",
            options: [.regularExpression, .caseInsensitive]
        )

        text = text.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )

        text = decodeHTMLEntities(text)

        text = text.replacingOccurrences(
            of: "\\n{3,}",
            with: "\n\n",
            options: .regularExpression
        )

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - HTML Entity Decoding

    private static func decodeHTMLEntities(_ text: String) -> String {
        var result = text
        let entities: [(String, String)] = [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"),
            ("&nbsp;", " "), ("&mdash;", "—"), ("&ndash;", "–"),
            ("&laquo;", "«"), ("&raquo;", "»"),
            ("&ldquo;", "\u{201C}"), ("&rdquo;", "\u{201D}"),
            ("&lsquo;", "\u{2018}"), ("&rsquo;", "\u{2019}"),
            ("&bull;", "•"), ("&hellip;", "…"),
            ("&copy;", "©"), ("&reg;", "®"), ("&trade;", "™")
        ]
        for (entity, replacement) in entities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }

        // Numeric entities: &#123; and &#x1F;
        if let regex = try? NSRegularExpression(pattern: "&#(x?[0-9a-fA-F]+);", options: []) {
            let range = NSRange(result.startIndex..., in: result)
            let matches = regex.matches(in: result, options: [], range: range).reversed()
            for match in matches {
                guard let codeRange = Range(match.range(at: 1), in: result) else { continue }
                let codeStr = String(result[codeRange])
                let codePoint: UInt32?
                if codeStr.hasPrefix("x") || codeStr.hasPrefix("X") {
                    codePoint = UInt32(codeStr.dropFirst(), radix: 16)
                } else {
                    codePoint = UInt32(codeStr, radix: 10)
                }
                if let cp = codePoint, let scalar = Unicode.Scalar(cp) {
                    let fullRange = Range(match.range, in: result)!
                    result.replaceSubrange(fullRange, with: String(scalar))
                }
            }
        }

        return result
    }
}

nonisolated enum DeckOutboundNetworkPolicy {
    static func rejectionReason(for url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return "Only http/https URLs are allowed"
        }

        guard let host = url.host?.trimmingCharacters(in: .whitespacesAndNewlines),
              !host.isEmpty else {
            return "Missing host"
        }

        let normalizedHost = host
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
        if isBlockedHostname(normalizedHost) {
            return host
        }

        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        hints.ai_flags = AI_ADDRCONFIG

        var results: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(host, nil, &hints, &results)
        guard status == 0, let first = results else {
            return "Unable to resolve host safely: \(host)"
        }
        defer { freeaddrinfo(first) }

        var resolvedAtLeastOneAddress = false
        var pointer: UnsafeMutablePointer<addrinfo>? = first
        while let current = pointer {
            defer { pointer = current.pointee.ai_next }
            guard let address = current.pointee.ai_addr else { continue }
            switch Int32(address.pointee.sa_family) {
            case AF_INET:
                resolvedAtLeastOneAddress = true
                let blocked = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { addr -> Bool in
                    isBlockedIPv4(addr.pointee.sin_addr)
                }
                if blocked { return host }
            case AF_INET6:
                resolvedAtLeastOneAddress = true
                let blocked = address.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { addr -> Bool in
                    isBlockedIPv6(addr.pointee.sin6_addr)
                }
                if blocked { return host }
            default:
                continue
            }
        }

        return resolvedAtLeastOneAddress ? nil : "Unable to resolve host safely: \(host)"
    }

    static func isAllowedPublicHTTPURL(_ url: URL) -> Bool {
        rejectionReason(for: url) == nil
    }

    private static func isBlockedHostname(_ host: String) -> Bool {
        host == "localhost"
            || host.hasSuffix(".localhost")
            || host == "local"
            || host.hasSuffix(".local")
    }

    private static func isBlockedIPv4(_ address: in_addr) -> Bool {
        let value = UInt32(bigEndian: address.s_addr)
        let b0 = UInt8((value >> 24) & 0xff)
        let b1 = UInt8((value >> 16) & 0xff)

        if b0 == 0 { return true }                              // "this" network
        if b0 == 10 { return true }                             // RFC1918
        if b0 == 127 { return true }                            // loopback
        if b0 == 169, b1 == 254 { return true }                 // link-local
        if b0 == 172, (16...31).contains(b1) { return true }    // RFC1918
        if b0 == 192, b1 == 168 { return true }                 // RFC1918
        if b0 == 100, (64...127).contains(b1) { return true }   // carrier-grade NAT
        if b0 == 198, (b1 == 18 || b1 == 19) { return true }     // benchmarking/private test nets
        if b0 >= 224 { return true }                            // multicast/reserved
        return false
    }

    private static func isBlockedIPv6(_ address: in6_addr) -> Bool {
        let bytes = withUnsafeBytes(of: address) { Array($0) }
        guard bytes.count == 16 else { return true }

        let isUnspecified = bytes.allSatisfy { $0 == 0 }
        let isLoopback = bytes[0..<15].allSatisfy { $0 == 0 } && bytes[15] == 1
        if isUnspecified || isLoopback { return true }
        if (bytes[0] & 0xfe) == 0xfc { return true }            // unique local fc00::/7
        if bytes[0] == 0xfe, (bytes[1] & 0xc0) == 0x80 { return true } // link-local fe80::/10
        if bytes[0] == 0xff { return true }                     // multicast

        let isIPv4Mapped = bytes[0..<10].allSatisfy { $0 == 0 }
            && bytes[10] == 0xff
            && bytes[11] == 0xff
        if isIPv4Mapped {
            let value = (UInt32(bytes[12]) << 24)
                | (UInt32(bytes[13]) << 16)
                | (UInt32(bytes[14]) << 8)
                | UInt32(bytes[15])
            let ipv4 = in_addr(s_addr: value.bigEndian)
            return isBlockedIPv4(ipv4)
        }

        return false
    }
}

nonisolated final class DeckOutboundHTTPRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let url = request.url,
              DeckOutboundNetworkPolicy.isAllowedPublicHTTPURL(url) else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}
