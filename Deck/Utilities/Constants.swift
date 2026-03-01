// Copyright © 2024–2026 Yuze Pan. 保留一切权利。

//
//  Constants.swift
//  Deck
//
//  Deck Clipboard Manager
//

import Foundation
import SwiftUI

/// 面板布局模式
enum LayoutMode: Int, CaseIterable, Identifiable {
    case horizontal = 0   // 底部横向弹出（默认）
    case vertical  = 1    // 侧边竖向弹出

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .horizontal: return NSLocalizedString("横版模式", comment: "Layout mode: Horizontal")
        case .vertical:   return NSLocalizedString("竖版模式", comment: "Layout mode: Vertical")
        }
    }
}

enum Const {
    // Card dimensions (horizontal mode)
    static let cardSize: CGFloat = 200.0
    static let cardContentSize: CGFloat = 150.0
    static let cardHeaderSize: CGFloat = 40.0
    static let cardSpace: CGFloat = 16.0
    static let cardBottomPadding: CGFloat = 12.0
    static let linkCardImageSize: CGSize = CGSize(width: 640.0, height: 360.0)

    // Vertical mode card/row dimensions
    static let verticalWindowWidth: CGFloat = 380.0
    static let verticalWindowInset: CGFloat = 7.0
    static let verticalRowHeight: CGFloat = 72.0
    static let verticalRowSpace: CGFloat = 4.0
    static let verticalRowIconSize: CGFloat = 40.0
    static let verticalRowTrailingWidth: CGFloat = 60.0
    
    // Window dimensions
    static let windowHeight: CGFloat = 305.0
    static let topBarHeight: CGFloat = 44.0
    static let settingWidth: CGFloat = {
        // Use wider window for English/German due to longer text
        let languageCode = Locale.preferredLanguages.first?.lowercased() ?? ""
        return (languageCode.hasPrefix("en") || languageCode.hasPrefix("de")) ? 720.0 : 600.0
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
    static let panelCornerRadius: CGFloat = 28.0
    static let panelTopPadding: CGFloat = 10.0
    static let searchFieldRadius: CGFloat = 12.0
    
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

    /// 卡片头部背景色 - 使用更高对比度的颜色
    static let cardHeaderBackground: Color = Color(nsColor: NSColor(name: nil) { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            // 深色模式：较亮的深灰色背景（避免太黑）
            return NSColor(red: 0.22, green: 0.22, blue: 0.24, alpha: 0.95)
        } else {
            // 浅色模式：淡灰色背景
            return NSColor(red: 0.92, green: 0.92, blue: 0.94, alpha: 0.98)
        }
    })

    /// 卡片内容背景色 - Material Design 风格的 surface 颜色
    static let cardContentBackground: Color = Color(nsColor: NSColor(name: nil) { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            // 深色模式：#2C2C2E 较亮的深灰（类似系统控件背景）
            return NSColor(red: 0.17, green: 0.17, blue: 0.18, alpha: 0.98)
        } else {
            // 浅色模式：纯白色
            return NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.98)
        }
    })

    /// 按钮/元素背景色 - 更高对比度
    static let elementBackground: Color = Color(nsColor: NSColor(name: nil) { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor(red: 0.28, green: 0.28, blue: 0.30, alpha: 0.9)
        } else {
            return NSColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.06)
        }
    })

    /// 弹出窗口毛玻璃叠加层 - 增加背景不透明度
    static let panelOverlay: Color = Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if #available(macOS 26.0, *) {
            return isDark
                ? NSColor.black.withAlphaComponent(0.10)
                : NSColor.white.withAlphaComponent(0.06)
        }
        if isDark {
            // 深色模式：较浅的叠加层（避免太黑）
            return NSColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 0.55)
        }
        // 浅色模式：淡色半透明叠加
        return NSColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 0.5)
    })

    /// 卡片阴影 - 浅色模式更明显的阴影
    static let cardShadowColor: Color = Color(nsColor: NSColor(name: nil) { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor.black.withAlphaComponent(0.3)
        } else {
            // 浅色模式需要更明显的阴影
            return NSColor.black.withAlphaComponent(0.15)
        }
    })

    static let cardShadowRadius: CGFloat = {
        if NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return 6.0
        } else {
            return 10.0
        }
    }()
    
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
    static let customTitleMaxLength: Int = 12

    // Script safety
    static let scriptExecutionTimeout: TimeInterval = 5.0  // 5 seconds timeout
    static let scriptMaxInputLength: Int = 100_000         // 100KB max input
    static let scriptMaxOutputLength: Int = 100_000        // 100KB max output

    // Animation
    static let showDuration: Double = 0.16
    static let hideDuration: Double = 0.18
    
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
