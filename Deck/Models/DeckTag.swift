//
//  DeckTag.swift
//  Deck
//
//  Deck Clipboard Manager
//

import SwiftUI

struct DeckTag: Identifiable, Equatable, Codable {
    let id: Int
    var name: String
    var colorIndex: Int
    var isSystem: Bool
    
    static let colorPalette: [Color] = [
        .gray.opacity(0.8),
        .blue,
        .green,
        .purple,
        .red,
        .orange,
        .yellow,
        .pink,
        .cyan,
        .brown,
        .indigo
    ]
    
    var color: Color {
        get {
            guard colorIndex >= 0, colorIndex < DeckTag.colorPalette.count else {
                return .gray
            }
            return DeckTag.colorPalette[colorIndex]
        }
        set {
            if let index = DeckTag.colorPalette.firstIndex(of: newValue) {
                colorIndex = index
            } else {
                colorIndex = 0
            }
        }
    }

    /// 颜色的十六进制字符串表示（用于共享）
    var colorHex: String {
        // 使用 colorIndex 作为简单的标识
        return String(colorIndex)
    }

    /// 从十六进制字符串创建标签时的颜色索引
    static func colorIndex(from hex: String) -> Int {
        return Int(hex) ?? 0
    }
    
    var typeFilter: [String]? {
        guard isSystem else { return nil }
        
        // Filter by itemType (ClipItemType.rawValue), not pasteboardType
        // Use internal tag IDs for system tags
        switch id {
        case 2: // 文本
            return ["text", "richText", "url", "color", "code"]
        case 3: // 图片
            return ["image"]
        case 4: // 文件
            return ["file"]
        default:
            return nil
        }
    }
    
    init(id: Int, name: String, color: Color, isSystem: Bool) {
        self.id = id
        self.name = name
        self.isSystem = isSystem

        if let index = DeckTag.colorPalette.firstIndex(of: color) {
            colorIndex = index
        } else {
            colorIndex = 0
        }
    }

    /// 使用 colorIndex 直接创建标签（用于接收共享分组）
    init(id: Int, name: String, colorIndex: Int, isSystem: Bool) {
        self.id = id
        self.name = name
        self.colorIndex = min(max(colorIndex, 0), DeckTag.colorPalette.count - 1)
        self.isSystem = isSystem
    }
    
    /// 获取本地化的系统标签
    static var systemTags: [DeckTag] {
        [
            DeckTag(id: 1, name: String(localized: "全部"), color: .gray.opacity(0.8), isSystem: true),
            DeckTag(id: 2, name: String(localized: "文本"), color: .blue, isSystem: true),
            DeckTag(id: 3, name: String(localized: "图片"), color: .green, isSystem: true),
            DeckTag(id: 4, name: String(localized: "文件"), color: .purple, isSystem: true)
        ]
    }
}
