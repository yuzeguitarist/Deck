//
//  Extensions.swift
//  Deck
//
//  Deck Clipboard Manager
//

import AppKit
import SwiftUI
import CryptoKit

// MARK: - Data Extensions

extension Data {
    var sha256Hex: String {
        let hash = SHA256.hash(data: self)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - String Extensions

extension String {
    func asCompleteURL() -> URL? {
        let trimmed = self.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        
        // Check if it's already a valid URL with scheme
        if let url = URL(string: trimmed), let scheme = url.scheme,
           ["http", "https", "ftp"].contains(scheme.lowercased()) {
            return url
        }
        
        // Try adding https:// prefix for domain-like strings
        let pattern = #"^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z]{2,})+.*$"#
        if trimmed.range(of: pattern, options: .regularExpression) != nil {
            if let url = URL(string: "https://\(trimmed)") {
                return url
            }
        }
        
        return nil
    }
    
    var isHexColor: Bool {
        let pattern = "^#([A-Fa-f0-9]{6}|[A-Fa-f0-9]{8}|[A-Fa-f0-9]{3})$"
        return self.range(of: pattern, options: .regularExpression) != nil
    }
    
    var hexColor: NSColor? {
        guard isHexColor else { return nil }
        var hex = self.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        
        var rgb: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&rgb)
        
        switch hex.count {
        case 3:
            let r = CGFloat((rgb >> 8) & 0xF) / 15.0
            let g = CGFloat((rgb >> 4) & 0xF) / 15.0
            let b = CGFloat(rgb & 0xF) / 15.0
            return NSColor(red: r, green: g, blue: b, alpha: 1.0)
        case 6:
            let r = CGFloat((rgb >> 16) & 0xFF) / 255.0
            let g = CGFloat((rgb >> 8) & 0xFF) / 255.0
            let b = CGFloat(rgb & 0xFF) / 255.0
            return NSColor(red: r, green: g, blue: b, alpha: 1.0)
        case 8:
            let r = CGFloat((rgb >> 24) & 0xFF) / 255.0
            let g = CGFloat((rgb >> 16) & 0xFF) / 255.0
            let b = CGFloat((rgb >> 8) & 0xFF) / 255.0
            let a = CGFloat(rgb & 0xFF) / 255.0
            return NSColor(red: r, green: g, blue: b, alpha: a)
        default:
            return nil
        }
    }
    
    var isCodeSnippet: Bool {
        let codePatterns = [
            "^\\s*(func|class|struct|enum|protocol|extension|import|var|let|if|else|for|while|switch|case|return|guard|defer|do|try|catch|throw|async|await)\\s",
            "^\\s*(def|class|import|from|if|elif|else|for|while|try|except|return|yield|async|await|lambda)\\s",
            "^\\s*(function|const|let|var|if|else|for|while|switch|case|return|async|await|import|export|class)\\s",
            "\\{[\\s\\S]*\\}",
            "\\[[\\s\\S]*\\]",
            "=>|->|::|&&|\\|\\|",
            "^\\s*[#@]\\w+",
            "\\w+\\(.*\\)\\s*[{;]?$"
        ]
        
        for pattern in codePatterns {
            if self.range(of: pattern, options: .regularExpression) != nil {
                return true
            }
        }
        return false
    }
}

// MARK: - NSColor Extensions

extension NSColor {
    convenience init(hex: String) {
        var hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if hexString.hasPrefix("#") { hexString.removeFirst() }
        
        var rgb: UInt64 = 0
        Scanner(string: hexString).scanHexInt64(&rgb)
        
        let r = CGFloat((rgb >> 16) & 0xFF) / 255.0
        let g = CGFloat((rgb >> 8) & 0xFF) / 255.0
        let b = CGFloat(rgb & 0xFF) / 255.0
        
        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
    
    var hexString: String {
        guard let color = usingColorSpace(.sRGB) else { return "#000000" }
        let r = Int(color.redComponent * 255)
        let g = Int(color.greenComponent * 255)
        let b = Int(color.blueComponent * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

// MARK: - Int64 Extensions

extension Int64 {
    func formattedDate() -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(self))
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    func relativeDate() -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(self))
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - NSImage Extensions

extension NSImage {
    func resized(to size: CGSize) -> NSImage {
        let newImage = NSImage(size: size)
        newImage.lockFocus()
        self.draw(in: NSRect(origin: .zero, size: size),
                  from: NSRect(origin: .zero, size: self.size),
                  operation: .copy,
                  fraction: 1.0)
        newImage.unlockFocus()
        return newImage
    }
    
    func resizedSafely(maxSize: CGFloat) -> NSImage? {
        let originalSize = self.size
        guard originalSize.width > 0, originalSize.height > 0 else { return nil }
        
        let scale = min(maxSize / originalSize.width, maxSize / originalSize.height, 1.0)
        let newSize = CGSize(width: originalSize.width * scale, height: originalSize.height * scale)
        
        return autoreleasepool {
            let newImage = NSImage(size: newSize)
            newImage.lockFocus()
            NSGraphicsContext.current?.imageInterpolation = .high
            self.draw(in: NSRect(origin: .zero, size: newSize),
                      from: NSRect(origin: .zero, size: originalSize),
                      operation: .copy,
                      fraction: 1.0)
            newImage.unlockFocus()
            return newImage
        }
    }
    
    var dominantColor: NSColor {
        guard let tiffData = self.tiffRepresentation,
              let _ = NSBitmapImageRep(data: tiffData) else {
            return .gray
        }
        
        let resized = self.resized(to: CGSize(width: 20, height: 20))
        guard let resizedTiff = resized.tiffRepresentation,
              let resizedBitmap = NSBitmapImageRep(data: resizedTiff) else {
            return .gray
        }
        
        var colorCounts: [UInt32: Int] = [:]
        
        for y in 0..<Int(resizedBitmap.pixelsHigh) {
            for x in 0..<Int(resizedBitmap.pixelsWide) {
                guard let color = resizedBitmap.colorAt(x: x, y: y) else { continue }
                let rgb = color.usingColorSpace(.sRGB)
                guard let c = rgb else { continue }
                
                let r = UInt32(c.redComponent * 255) / 32 * 32
                let g = UInt32(c.greenComponent * 255) / 32 * 32
                let b = UInt32(c.blueComponent * 255) / 32 * 32
                let key = (r << 16) | (g << 8) | b
                
                colorCounts[key, default: 0] += 1
            }
        }
        
        guard let mostCommon = colorCounts.max(by: { $0.value < $1.value }) else {
            return .gray
        }
        
        let r = CGFloat((mostCommon.key >> 16) & 0xFF) / 255.0
        let g = CGFloat((mostCommon.key >> 8) & 0xFF) / 255.0
        let b = CGFloat(mostCommon.key & 0xFF) / 255.0
        
        return NSColor(red: r, green: g, blue: b, alpha: 1.0)
    }
}

// MARK: - View Extensions

extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

// MARK: - Character Extensions

extension Character {
    /// 检测是否为中文字符 (CJK Unified Ideographs)
    nonisolated var isChineseCharacter: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        // CJK Unified Ideographs: U+4E00 - U+9FFF
        // CJK Unified Ideographs Extension A: U+3400 - U+4DBF
        return (0x4E00...0x9FFF).contains(scalar.value) ||
               (0x3400...0x4DBF).contains(scalar.value)
    }
}

// MARK: - Array Extensions

extension Array {
    /// Safe array subscript - returns nil if index is out of bounds
    subscript(safe index: Int) -> Element? {
        guard index >= 0 && index < count else { return nil }
        return self[index]
    }
}

// MARK: - Notification.Name Extensions

extension Notification.Name {
    static let clipboardPauseStateChanged = Notification.Name("clipboardPauseStateChanged")
    static let databaseError = Notification.Name("databaseError")
}

// MARK: - NSAttributedString Extensions

extension NSAttributedString {
    convenience init?(with data: Data?, type: NSPasteboard.PasteboardType) {
        guard let data = data else { return nil }
        
        switch type {
        case .rtf:
            try? self.init(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
        case .rtfd, .flatRTFD:
            try? self.init(data: data, options: [.documentType: NSAttributedString.DocumentType.rtfd], documentAttributes: nil)
        case .string:
            if let str = String(data: data, encoding: .utf8) {
                self.init(string: str)
            } else {
                return nil
            }
        default:
            return nil
        }
    }
    
    func toData(with type: NSPasteboard.PasteboardType) -> Data? {
        switch type {
        case .rtf:
            return try? data(from: NSRange(location: 0, length: length),
                            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        case .rtfd, .flatRTFD:
            return try? data(from: NSRange(location: 0, length: length),
                            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd])
        default:
            return string.data(using: .utf8)
        }
    }
}
