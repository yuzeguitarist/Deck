// Copyright © 2024–2026 Yuze Pan. 保留一切权利。

//
//  TextTransformer.swift
//  Deck
//
//  Text transformation utilities
//

import Foundation
import CryptoKit

enum TransformType: String, CaseIterable, Identifiable, Codable {
    case jsonFormat = "JSON 格式化"
    case jsonMinify = "JSON 压缩"
    case urlEncode = "URL 编码"
    case urlDecode = "URL 解码"
    case base64Encode = "Base64 编码"
    case base64Decode = "Base64 解码"
    case camelToSnake = "驼峰转下划线"
    case snakeToCamel = "下划线转驼峰"
    case timestampToDate = "时间戳转日期"
    case uppercase = "转大写"
    case lowercase = "转小写"
    case trim = "去除空白"
    case escapeHtml = "HTML 转义"
    case unescapeHtml = "HTML 反转义"
    case md5Hash = "MD5 哈希"
    case lineSort = "行排序"
    case lineDedupe = "行去重"
    case reverseText = "反转文本"
    
    var id: String { rawValue }

    var stableCode: String {
        switch self {
        case .jsonFormat: return "json_format"
        case .jsonMinify: return "json_minify"
        case .urlEncode: return "url_encode"
        case .urlDecode: return "url_decode"
        case .base64Encode: return "base64_encode"
        case .base64Decode: return "base64_decode"
        case .camelToSnake: return "camel_to_snake"
        case .snakeToCamel: return "snake_to_camel"
        case .timestampToDate: return "timestamp_to_date"
        case .uppercase: return "uppercase"
        case .lowercase: return "lowercase"
        case .trim: return "trim"
        case .escapeHtml: return "escape_html"
        case .unescapeHtml: return "unescape_html"
        case .md5Hash: return "md5"
        case .lineSort: return "line_sort"
        case .lineDedupe: return "line_dedupe"
        case .reverseText: return "reverse_text"
        }
    }

    static func fromStableCode(_ code: String) -> TransformType? {
        switch code {
        case "json_format": return .jsonFormat
        case "json_minify": return .jsonMinify
        case "url_encode": return .urlEncode
        case "url_decode": return .urlDecode
        case "base64_encode": return .base64Encode
        case "base64_decode": return .base64Decode
        case "camel_to_snake": return .camelToSnake
        case "snake_to_camel": return .snakeToCamel
        case "timestamp_to_date": return .timestampToDate
        case "uppercase": return .uppercase
        case "lowercase": return .lowercase
        case "trim": return .trim
        case "escape_html": return .escapeHtml
        case "unescape_html": return .unescapeHtml
        case "md5": return .md5Hash
        case "line_sort": return .lineSort
        case "line_dedupe": return .lineDedupe
        case "reverse_text": return .reverseText
        default: return nil
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)

        if let mapped = Self.fromStableCode(value) {
            self = mapped
            return
        }

        if let legacy = TransformType(rawValue: value) {
            self = legacy
            return
        }

        if let mapped = Self.fromStableCode(value.lowercased()) {
            self = mapped
            return
        }

        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown TransformType: \(value)")
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(stableCode)
    }
    
    var icon: String {
        switch self {
        case .jsonFormat, .jsonMinify: return "curlybraces"
        case .urlEncode, .urlDecode: return "link"
        case .base64Encode, .base64Decode: return "lock"
        case .camelToSnake, .snakeToCamel: return "textformat"
        case .timestampToDate: return "calendar"
        case .uppercase, .lowercase: return "textformat.size"
        case .trim: return "scissors"
        case .escapeHtml, .unescapeHtml: return "chevron.left.forwardslash.chevron.right"
        case .md5Hash: return "number"
        case .lineSort, .lineDedupe: return "list.number"
        case .reverseText: return "arrow.left.arrow.right"
        }
    }
}

final class TextTransformer {
    static let shared = TextTransformer()
    private init() {}
    
    func transform(_ text: String, type: TransformType) -> String? {
        switch type {
        case .jsonFormat:
            return formatJSON(text)
        case .jsonMinify:
            return minifyJSON(text)
        case .urlEncode:
            var allowed = CharacterSet.urlQueryAllowed
            allowed.remove(charactersIn: "&=?+")
            return text.addingPercentEncoding(withAllowedCharacters: allowed)
        case .urlDecode:
            return text.removingPercentEncoding
        case .base64Encode:
            return text.data(using: .utf8)?.base64EncodedString()
        case .base64Decode:
            guard let data = Data(base64Encoded: text),
                  let decoded = String(data: data, encoding: .utf8) else { return nil }
            return decoded
        case .camelToSnake:
            return camelToSnake(text)
        case .snakeToCamel:
            return snakeToCamel(text)
        case .timestampToDate:
            return timestampToDate(text)
        case .uppercase:
            return text.uppercased()
        case .lowercase:
            return text.lowercased()
        case .trim:
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        case .escapeHtml:
            return escapeHTML(text)
        case .unescapeHtml:
            return unescapeHTML(text)
        case .md5Hash:
            return md5(text)
        case .lineSort:
            return text.components(separatedBy: "\n").sorted().joined(separator: "\n")
        case .lineDedupe:
            let lines = text.components(separatedBy: "\n")
            var seen = Set<String>()
            return lines.filter { seen.insert($0).inserted }.joined(separator: "\n")
        case .reverseText:
            return String(text.reversed())
        }
    }
    
    // MARK: - JSON
    
    private func formatJSON(_ text: String) -> String? {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return nil
        }
        if JSONSerialization.isValidJSONObject(json),
           let formatted = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
           let result = String(data: formatted, encoding: .utf8) {
            return result
        }
        return serializeJSONFragment(json, prettyPrinted: true)
    }
    
    private func minifyJSON(_ text: String) -> String? {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return nil
        }
        if JSONSerialization.isValidJSONObject(json),
           let minified = try? JSONSerialization.data(withJSONObject: json),
           let result = String(data: minified, encoding: .utf8) {
            return result
        }
        return serializeJSONFragment(json, prettyPrinted: false)
    }

    private func serializeJSONFragment(_ json: Any, prettyPrinted: Bool) -> String? {
        let options: JSONSerialization.WritingOptions = prettyPrinted ? [.prettyPrinted, .sortedKeys] : []
        guard let data = try? JSONSerialization.data(withJSONObject: [json], options: options),
              var result = String(data: data, encoding: .utf8) else {
            return nil
        }
        guard result.first == "[", result.last == "]" else {
            return nil
        }
        result.removeFirst()
        result.removeLast()
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Case Conversion
    
    private func camelToSnake(_ text: String) -> String {
        var result = ""
        for (index, char) in text.enumerated() {
            if char.isUppercase {
                if index > 0 {
                    result += "_"
                }
                result += char.lowercased()
            } else {
                result += String(char)
            }
        }
        return result
    }
    
    private func snakeToCamel(_ text: String) -> String {
        let parts = text.components(separatedBy: "_")
        guard let first = parts.first else { return text }
        return first + parts.dropFirst().map { $0.capitalized }.joined()
    }
    
    // MARK: - Timestamp
    
    private func timestampToDate(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let timestamp = Double(trimmed) else { return nil }
        
        // Detect milliseconds vs seconds
        let date: Date
        if timestamp > 1_000_000_000_000 {
            date = Date(timeIntervalSince1970: timestamp / 1000)
        } else {
            date = Date(timeIntervalSince1970: timestamp)
        }

        return Self.threadLocalTimestampFormatter.string(from: date)
    }

    // MARK: - Cached formatters (thread-local)

    private static var threadLocalTimestampFormatter: DateFormatter {
        let key = "com.deck.textTransformer.timestampFormatter"
        if let cached = Thread.current.threadDictionary[key] as? DateFormatter {
            return cached
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        Thread.current.threadDictionary[key] = formatter
        return formatter
    }

    // MARK: - HTML
    
    private func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
    
    private func unescapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }
    
    // MARK: - Hash
    
    private func md5(_ text: String) -> String? {
        guard let data = text.data(using: .utf8) else { return nil }
        let digest = Insecure.MD5.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
