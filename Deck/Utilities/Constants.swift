//
//  Constants.swift
//  Deck
//
//  Deck Clipboard Manager
//

import SwiftUI

enum Const {
    // Card dimensions
    static let cardSize: CGFloat = 200.0
    static let cardContentSize: CGFloat = 150.0
    static let cardHeaderSize: CGFloat = 40.0
    static let cardSpace: CGFloat = 16.0
    static let cardBottomPadding: CGFloat = 12.0
    
    // Window dimensions
    static let windowHeight: CGFloat = 300.0
    static let topBarHeight: CGFloat = 44.0
    static let settingWidth: CGFloat = {
        // Use wider window for English/German due to longer text
        let languageCode = Locale.current.language.languageCode?.identifier ?? "zh"
        return (languageCode == "en" || languageCode == "de") ? 720.0 : 600.0
    }()
    static let settingHeight: CGFloat = 500.0
    
    // Spacing
    static let space4: CGFloat = 4.0
    static let space6: CGFloat = 6.0
    static let space8: CGFloat = 8.0
    static let space12: CGFloat = 12.0
    static let space16: CGFloat = 16.0
    static let space24: CGFloat = 24.0
    static let space32: CGFloat = 32.0
    
    // Radius
    static let radius: CGFloat = {
        if #available(macOS 26.0, *) {
            return 16.0
        } else {
            return 12.0
        }
    }()
    
    static let smallRadius: CGFloat = 8.0
    
    // Icon sizes
    static let iconSize: CGFloat = 16.0
    static let iconSizeLarge: CGFloat = 24.0
    static let appIconSize: CGFloat = 20.0
    
    // Colors - Adaptive for light/dark mode
    static let primaryBackground: Color = Color(nsColor: .windowBackgroundColor)
    static let secondaryBackground: Color = Color(nsColor: .controlBackgroundColor)
    static let cardBackground: Color = Color.white.opacity(0.1)
    static let selectionColor: Color = Color.white.opacity(0.2)
    static let borderColor: Color = Color.white.opacity(0.1)

    /// 浅色模式下更深的灰色，深色模式下保持原样
    static func adaptiveGray(_ lightOpacity: Double = 0.5, darkOpacity: Double = 0.3) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor.white.withAlphaComponent(darkOpacity)
            } else {
                return NSColor.black.withAlphaComponent(lightOpacity)
            }
        })
    }

    /// 卡片选中边框颜色 - 浅色模式使用深色边框
    static let selectionBorderColor: Color = Color(nsColor: NSColor(name: nil) { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor.white.withAlphaComponent(0.5)
        } else {
            return NSColor.black.withAlphaComponent(0.4)
        }
    })

    /// 卡片头部背景色 - 浅色模式使用更深的灰色
    static let cardHeaderBackground: Color = Color(nsColor: NSColor(name: nil) { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor.gray.withAlphaComponent(0.3)
        } else {
            return NSColor.gray.withAlphaComponent(0.15)
        }
    })

    /// 按钮/元素背景色 - 浅色模式使用更明显的背景
    static let elementBackground: Color = Color(nsColor: NSColor(name: nil) { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor.white.withAlphaComponent(0.1)
        } else {
            return NSColor.black.withAlphaComponent(0.08)
        }
    })
    
    // Content limits
    static let maxPreviewTextLength: Int = 500
    static let maxSearchTextLength: Int = 5000
    static let maxSmartAnalysisLength: Int = 8000
    static let maxPreviewBodyLength: Int = 10000
    static let maxSemanticTextLength: Int = 512
    static let semanticCandidateLimit: Int = 800
    static let maxRichTextSanitizeBytes: Int = 512 * 1024
    static let largeBlobThreshold: Int = 512 * 1024 // 512KB threshold for offloading binary payloads
    static let maxBase64ImageBytes: Int = 2 * 1024 * 1024 // 2MB cap for base64 image preview
    static let pageSize: Int = 50

    // Script safety
    static let scriptExecutionTimeout: TimeInterval = 5.0  // 5 seconds timeout
    static let scriptMaxInputLength: Int = 100_000         // 100KB max input
    static let scriptMaxOutputLength: Int = 100_000        // 100KB max output

    // Animation
    static let showDuration: Double = 0.2
    static let hideDuration: Double = 0.25
    
    // Card shape
    static let contentShape = UnevenRoundedRectangle(
        topLeadingRadius: 0,
        bottomLeadingRadius: Const.radius,
        bottomTrailingRadius: Const.radius,
        topTrailingRadius: 0,
        style: .continuous
    )
    
    static let headerShape = UnevenRoundedRectangle(
        topLeadingRadius: Const.radius,
        bottomLeadingRadius: 0,
        bottomTrailingRadius: 0,
        topTrailingRadius: Const.radius,
        style: .continuous
    )
}
