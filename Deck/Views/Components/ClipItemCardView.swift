// Copyright © 2024–2026 Yuze Pan. 保留一切权利。

//
//  ClipItemCardView.swift
//  Deck
//
//  Deck Clipboard Manager
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ImageIO

struct QuickPasteBadgeView: View {
    let number: Int
    @Environment(\.colorScheme) private var colorScheme

    private var foregroundColor: Color {
        if colorScheme == .dark {
            return Color.white.opacity(0.72)
        }
        return Color.black.opacity(0.42)
    }

    private var backgroundColor: Color {
        if colorScheme == .dark {
            return Color.black.opacity(0.88)
        }
        return Color.white.opacity(0.96)
    }

    var body: some View {
        HStack(spacing: 1.5) {
            Image(systemName: "list.number")
                .font(.system(size: 11, weight: .regular))

            Text("\(number)")
                .font(.system(size: 12, weight: .regular))
        }
        .foregroundStyle(foregroundColor)
        .padding(.horizontal, 3)
        .padding(.vertical, 1.5)
        .background(
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(backgroundColor)
        )
        .fixedSize()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private enum ClipItemCardCache {
    static let thumbnailCache: NSCache<NSString, CGImage> = {
        let cache = NSCache<NSString, CGImage>()
        cache.countLimit = 256
        // Rough memory cap (bytes) for thumbnails to avoid unbounded growth.
        cache.totalCostLimit = 64 * 1024 * 1024
        return cache
    }()

    static let iconCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 512
        return cache
    }()

    static let imageFileSizeCache: NSCache<NSString, NSNumber> = {
        let cache = NSCache<NSString, NSNumber>()
        cache.countLimit = 1024
        return cache
    }()
}

private struct ImageDecodeResult: @unchecked Sendable {
    let image: CGImage
    let pixelSize: CGSize?
}

private actor ClipItemThumbnailDecodeGate {
    static let shared = ClipItemThumbnailDecodeGate()

    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Bool, Never>
    }

    private let limit: Int
    private var available: Int
    private var waiters: [Waiter] = []

    private init() {
        let cores = ProcessInfo.processInfo.activeProcessorCount
        let computedLimit = max(1, min(2, max(1, cores / 2)))
        limit = computedLimit
        available = computedLimit
    }

    func acquire() async -> Bool {
        if Task.isCancelled { return false }
        if available > 0 {
            available -= 1
            return true
        }

        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                waiters.append(Waiter(id: id, continuation: continuation))
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
    }

    func release() {
        if !waiters.isEmpty {
            let waiter = waiters.removeFirst()
            waiter.continuation.resume(returning: true)
            return
        }
        available = min(available + 1, limit)
    }

    private func cancelWaiter(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        let waiter = waiters.remove(at: index)
        waiter.continuation.resume(returning: false)
    }
}

final class TitleEditorTextField: NoSelectTextField {
    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        guard result, shouldMoveCursorToEnd else { return result }

        let existingLength = (stringValue as NSString).length
        guard existingLength > 0 else { return result }

        DispatchQueue.main.async { [weak self] in
            guard let self,
                  let editor = self.currentEditor() as? NSTextView,
                  !editor.hasMarkedText() else { return }
            editor.setSelectedRange(NSRange(location: existingLength, length: 0))
            editor.scrollRangeToVisible(NSRange(location: existingLength, length: 0))
        }

        return result
    }
}

struct InlineTitleEditorField: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let placeholder: String
    let fontSize: CGFloat
    let alignment: NSTextAlignment
    let onSubmit: () -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> TitleEditorTextField {
        let textField = TitleEditorTextField()
        textField.delegate = context.coordinator
        textField.isBordered = false
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.backgroundColor = .clear
        textField.focusRingType = .none
        textField.font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        textField.textColor = .labelColor
        textField.alignment = alignment
        textField.placeholderString = placeholder
        textField.cell?.usesSingleLineMode = true
        textField.cell?.lineBreakMode = .byTruncatingTail
        textField.cell?.isScrollable = true
        return textField
    }

    func updateNSView(_ nsView: TitleEditorTextField, context: Context) {
        context.coordinator.parent = self
        nsView.font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        nsView.alignment = alignment
        nsView.placeholderString = placeholder

        if nsView.stringValue != text {
            context.coordinator.isProgrammaticUpdate = true
            nsView.discardMarkedTextIfNeeded()
            nsView.stringValue = text
            if let editor = nsView.currentEditor() {
                let length = (text as NSString).length
                editor.selectedRange = NSRange(location: length, length: 0)
                context.coordinator.ensureEditorSelectionVisible(in: editor)
            }
            context.coordinator.isProgrammaticUpdate = false
        }

        if isFocused {
            nsView.shouldMoveCursorToEnd = !text.isEmpty
            if !context.coordinator.isEditing {
                DispatchQueue.main.async { [weak nsView] in
                    guard let nsView else { return }
                    nsView.window?.makeFirstResponder(nsView)
                }
            }
        } else {
            nsView.shouldMoveCursorToEnd = false
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: InlineTitleEditorField
        var isProgrammaticUpdate = false
        var isEditing = false

        init(_ parent: InlineTitleEditorField) {
            self.parent = parent
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            isEditing = true
            if let textField = obj.object as? NSTextField,
               let editor = textField.currentEditor() as? NSTextView {
                let caretLocation = (parent.text as NSString).length
                if !editor.hasMarkedText() {
                    editor.setSelectedRange(NSRange(location: caretLocation, length: 0))
                }
                ensureEditorSelectionVisible(in: editor)
            }
            if !parent.isFocused {
                parent.isFocused = true
            }
        }

        func controlTextDidChange(_ obj: Notification) {
            guard !isProgrammaticUpdate, let textField = obj.object as? NSTextField else { return }
            let newValue = textField.stringValue
            if let editor = textField.currentEditor() {
                ensureEditorSelectionVisible(in: editor)
            }
            if parent.text != newValue {
                parent.text = newValue
            }
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            isEditing = false
            if parent.isFocused {
                parent.isFocused = false
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                if textView.hasMarkedText() {
                    return false
                }
                parent.onSubmit()
                return true
            }

            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onCancel()
                return true
            }

            return false
        }

        func ensureEditorSelectionVisible(in editor: NSText) {
            guard let textView = editor as? NSTextView else { return }
            let markedRange = textView.markedRange()
            if markedRange.location != NSNotFound, markedRange.length > 0 {
                textView.scrollRangeToVisible(markedRange)
            } else {
                textView.scrollRangeToVisible(textView.selectedRange())
            }
        }
    }
}

struct ClipItemCardView: View {
    @Bindable var item: ClipboardItem
    let isSelected: Bool
    @Binding var showPreview: Bool
    let quickPasteNumber: Int?
    var onDelete: (() -> Void)?
    @AppStorage(PrefKey.instantCalculation.rawValue) private var instantCalculationEnabled = DeckUserDefaults.instantCalculation

    @State private var vm = DeckViewModel.shared
    @State private var pasteQueue = PasteQueueService.shared
    @State private var multipeerService = MultipeerService.shared
    @State private var directConnectService = DirectConnectService.shared
    @State private var isHovered = false
    @State private var contextMenuID = UUID()
    @State private var isEditingTitle = false
    @State private var titleDraft = ""
    @State private var titleFieldFocused = false
    @Environment(\.colorScheme) private var colorScheme

    // 缩略图（后台解码/降采样，避免滚动时主线程卡顿）
    @State private var imageThumbnail: CGImage?
    @State private var isImageThumbnailLoading: Bool = false
    @State private var imageDimensionText: String?
    @State private var imageStateItemID: String?

    // 图片文件大小（异步计算）
    @State private var imageFileSizeText: String?
    @State private var isImageFileSizeLoading: Bool = false

    // Base64 图片缩略图（仅在文本/代码检测到 base64 图片时加载）
    @State private var base64Thumbnail: CGImage?
    @State private var didAttemptBase64Decode: Bool = false
    @State private var isBase64ThumbnailLoading: Bool = false

    // 异步智能分析状态
    @State private var smartState = SmartContentState()

    private var smartTaskID: SmartAnalysisTaskKey {
        item.smartAnalysisTaskKey(instantCalculationEnabled: instantCalculationEnabled)
    }

    /// Whether the "Ask AI" context menu item should be shown.
    private var canAskAI: Bool {
        switch item.itemType {
        case .text, .url, .code, .color:
            return true
        case .image:
            if let ocr = item.ocrTextForImage, !ocr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return true
            }
            return false
        default:
            return false
        }
    }

    private var effectiveCardSize: CGFloat {
        vm.layoutMode == .horizontal ? vm.horizontalCardSize : Const.cardSize
    }

    /// Scale factor relative to the default card size (1.0 at default, >1.0 when enlarged).
    private var cardScale: CGFloat {
        effectiveCardSize / Const.cardSize
    }

    private var effectiveHeaderHeight: CGFloat {
        Const.cardHeaderSize * cardScale
    }

    private var headerAppIconSize: CGFloat {
        min(Const.cardAppIconSize, max(Const.appIconSize, effectiveHeaderHeight - 12))
    }

    private var dragPreviewSelectionOutset: CGFloat {
        isSelected ? 2 : 0
    }

    private var textPrefixLength: Int {
        Int(400 * cardScale)
    }

    private var markdownCardPrefixLength: Int {
        Int(1_400 * cardScale)
    }

    private var codePrefixLength: Int {
        Int(600 * cardScale)
    }

    private var textLineLimit: Int {
        Int(6 * cardScale * 1.5)
    }

    private var codeLineLimit: Int {
        Int(8 * cardScale * 1.5)
    }

    init(
        item: ClipboardItem,
        isSelected: Bool,
        showPreview: Binding<Bool>,
        quickPasteNumber: Int? = nil,
        onDelete: (() -> Void)? = nil
    ) {
        self.item = item
        self.isSelected = isSelected
        self._showPreview = showPreview
        self.quickPasteNumber = quickPasteNumber
        self.onDelete = onDelete
    }

    var body: some View {
        let ocrText = (item.itemType == .image || item.isFileURLImage) ? item.ocrTextForImage : nil
        cardBody
            .onHover { isHovered = $0 }
            .contextMenu { contextMenuContent(ocrText: ocrText) }
            .id(contextMenuID)
            .onDrag {
                createDragItemProvider()
            } preview: {
                dragPreview
            }
            .onChange(of: item.searchText) { _, _ in
                contextMenuID = UUID()
            }
            .onChange(of: vm.titleEditingResetToken) { _, _ in
                if isEditingTitle {
                    titleDraft = item.displayTitle ?? ""
                    isEditingTitle = false
                    titleFieldFocused = false
                }
                vm.isEditingItemTitle = false
            }
            .onDisappear {
                if isEditingTitle {
                    titleDraft = item.displayTitle ?? ""
                    isEditingTitle = false
                    titleFieldFocused = false
                    vm.isEditingItemTitle = false
                }
            }
    }

    private var cardBody: some View {
        VStack(spacing: 0) {
            // Header
            cardHeader
            
            // Content
            cardContent
        }
        .frame(width: effectiveCardSize, height: effectiveCardSize)
        .clipShape(RoundedRectangle(cornerRadius: Const.radius, style: .continuous))
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: Const.radius + 2, style: .continuous)
                    .strokeBorder(
                        Const.selectionBorderColor,
                        lineWidth: 2
                    )
                    .padding(-2)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if let quickPasteNumber {
                QuickPasteBadgeView(number: quickPasteNumber)
                    .padding(.trailing, 4)
                    .padding(.bottom, 7)
            }
        }
        .zIndex(quickPasteNumber == nil ? 0 : 1)
    }

    private var dragPreview: some View {
        cardBody
            .padding(dragPreviewSelectionOutset)
            .fixedSize()
            .compositingGroup()
    }

    // MARK: - Virtual File Drag

    /// 创建拖拽时的 NSItemProvider
    private func createDragItemProvider() -> NSItemProvider {
        MainWindowController.shared.beginClipItemDragWindowLevelRelaxation()

        switch item.itemType {
        case .image:
            // 图片：直接拖拽为图片文件
            return createImageProvider()
        case .file:
            // 文件：拖拽原文件路径
            return createFileProvider()
        case .color:
            // 颜色：拖拽为颜色代码文本文件
            return createTextFileProvider(content: item.searchText, suggestedName: "color", extension: "txt")
        default:
            // 文本/代码/URL：根据内容智能生成文件
            return createSmartTextFileProvider()
        }
    }

    /// 创建图片拖拽 Provider
    private func createImageProvider() -> NSItemProvider {
        let imageData = item.resolvedData() ?? item.data
        let imageType: UTType = detectImageType(from: imageData) ?? .png
        let ext = imageType.preferredFilenameExtension ?? "png"
        let filename = "image_\(item.timestamp).\(ext)"
        do {
            let tempURL = try TemporaryFileManager.shared.writeData(imageData, filename: filename)
            let provider = NSItemProvider(contentsOf: tempURL) ?? NSItemProvider()
            provider.suggestedName = filename
            return provider
        } catch {
            log.error("Failed to write temp image: \(error)")
            return NSItemProvider()
        }
    }

    /// 检测图片类型
    private func detectImageType(from data: Data) -> UTType? {
        guard data.count >= 8 else { return nil }

        return data.withUnsafeBytes { rawBuffer -> UTType? in
            let bytes = rawBuffer.bindMemory(to: UInt8.self)
            guard bytes.count >= 8 else { return nil }

            // PNG: 89 50 4E 47 0D 0A 1A 0A
            if bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47 {
                return .png
            }
            // JPEG: FF D8 FF
            if bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF {
                return .jpeg
            }
            // GIF: 47 49 46 38
            if bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x38 {
                return .gif
            }
            // WebP: "RIFF" .... "WEBP"
            if bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46,
               bytes.count >= 12,
               bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50 {
                return .webP
            }
            // TIFF: 49 49 2A 00 or 4D 4D 00 2A
            if (bytes[0] == 0x49 && bytes[1] == 0x49) || (bytes[0] == 0x4D && bytes[1] == 0x4D) {
                return .tiff
            }

            return .png // 默认 PNG
        }
    }

    /// 创建文件拖拽 Provider
    private func createFileProvider() -> NSItemProvider {
        guard let paths = item.filePaths, let firstPath = paths.first else {
            return NSItemProvider()
        }

        let fileURL = URL(fileURLWithPath: firstPath)

        // 检查文件是否存在
        guard FileManager.default.fileExists(atPath: firstPath) else {
            return NSItemProvider()
        }

        let provider = NSItemProvider(contentsOf: fileURL) ?? NSItemProvider()
        provider.suggestedName = fileURL.lastPathComponent
        return provider
    }

    /// 创建智能文本文件 Provider（根据内容自动检测类型）
    private func createSmartTextFileProvider() -> NSItemProvider {
        let text = item.searchText
        let (baseName, ext) = SmartTextService.shared.generateSmartFilename(for: text)
        return createTextFileProvider(content: text, suggestedName: baseName, extension: ext)
    }

    /// 创建文本文件 Provider
    private func createTextFileProvider(content: String, suggestedName: String, extension ext: String) -> NSItemProvider {
        // 清理文件名中的非法字符
        let cleanName = suggestedName
            .components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|\n\r\t"))
            .joined(separator: "_")
            .trimmingCharacters(in: .whitespaces)
        let safeName = cleanName.isEmpty ? "text" : String(cleanName.prefix(50))
        let filename = "\(safeName).\(ext)"
        do {
            let tempURL = try TemporaryFileManager.shared.writeText(content, filename: filename)
            let provider = NSItemProvider(contentsOf: tempURL) ?? NSItemProvider()
            provider.suggestedName = filename
            return provider
        } catch {
            log.error("Failed to write temp file: \(error)")
            return NSItemProvider()
        }
    }

    // MARK: - Title Editing

    private func startTitleEditing() {
        titleDraft = item.displayTitle ?? ""
        isEditingTitle = true
        vm.isEditingItemTitle = true
        DispatchQueue.main.async {
            titleFieldFocused = true
        }
    }

    private func commitTitleEdit() {
        let normalized = ClipboardItem.normalizedCustomTitle(titleDraft)
        titleDraft = normalized ?? ""
        isEditingTitle = false
        vm.isEditingItemTitle = false

        item.customTitle = normalized
        if let itemId = item.id {
            DeckDataStore.shared.updateItemCustomTitle(itemId: itemId, customTitle: normalized)
        }
    }

    private func cancelTitleEdit() {
        titleDraft = item.displayTitle ?? ""
        isEditingTitle = false
        vm.isEditingItemTitle = false
    }

    private func sanitizeTitleDraft(_ value: String) {
        let cleaned = value
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        if cleaned != value {
            titleDraft = cleaned
        }
    }
    
    // MARK: - Header

    private var headerTypeSymbolName: String {
        guard item.itemType == .url, let url = item.url else {
            return item.itemType.icon
        }

        switch AppleStreamingMetadataResolver.classifyForCardIcon(url: url) {
        case .podcast:
            if #available(macOS 26.0, *) {
                return "apple.podcasts.pages"
            }
            return "dot.radiowaves.left.and.right"
        case .appleMusicSong:
            return "music.note"
        case .appleMusicAlbum:
            return "music.note.list"
        case .none:
            return item.itemType.icon
        }
    }
    
    private var cardHeader: some View {
        ZStack {
            if isEditingTitle {
                titleEditorHeader
            } else if let title = item.displayTitle {
                titleDisplayHeader(title)
            } else {
                defaultHeaderContent
            }
        }
        .padding(.horizontal, Const.space12)
        .padding(.vertical, Const.space8)
        .frame(height: Const.cardHeaderSize)
        .background {
            if #available(macOS 26.0, *) {
                Const.headerShape
                    .fill(Const.cardHeaderBackground)
            } else {
                Const.headerShape
                    .fill(Const.cardHeaderBackground)
            }
        }
    }

    private var defaultHeaderContent: some View {
        HStack(spacing: Const.space8) {
            // App icon
            if !item.appPath.isEmpty {
                Image(nsImage: cachedIcon(for: item.appPath))
                    .resizable()
                    .frame(width: headerAppIconSize, height: headerAppIconSize)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(item.appName.isEmpty ? "未知" : item.appName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(item.timestamp.relativeDate())
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Queue position or Type icon
            if let queuePos = pasteQueue.queuePosition(of: item) {
                Text("\(queuePos + 1)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Color.orange))
            } else {
                VStack(spacing: 1) {
                    HStack(spacing: 4) {
                        Image(systemName: headerTypeSymbolName)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)

                        if item.isTemporary {
                            Image(systemName: "timer")
                                .font(.system(size: 10))
                                .foregroundStyle(.orange)
                        }
                    }

                    if hasMultipleImages {
                        Text(multiImageTotalText)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    private func titleDisplayHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private var titleEditorHeader: some View {
        InlineTitleEditorField(
            text: $titleDraft,
            isFocused: $titleFieldFocused,
            placeholder: String(localized: "输入标题"),
            fontSize: 15,
            alignment: .left,
            onSubmit: commitTitleEdit,
            onCancel: cancelTitleEdit
        )
        .onChange(of: titleDraft) { _, newValue in
            sanitizeTitleDraft(newValue)
        }
        .padding(.horizontal, Const.space8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Const.elementBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Const.adaptiveGray(0.35, darkOpacity: 0.5), lineWidth: 0.6)
        )
        .frame(maxWidth: .infinity, alignment: .center)
    }
    
    // MARK: - Content
    
    @ViewBuilder
    private var cardContent: some View {
        Group {
            if item.isMissingFile {
                missingFileContent
            } else if item.isUnsupported {
                unsupportedContent
            } else {
                switch item.itemType {
                case .image:
                    imageContent
                case .file:
                    fileContent
                case .color:
                    colorContent
                case .url:
                    if DeckUserDefaults.enableLinkPreview {
                        LinkPreviewCard(item: item, contentHeight: effectiveCardSize - Const.cardHeaderSize)
                    } else {
                        urlContent
                    }
                case .text:
                    if let cgImage = base64Thumbnail {
                        base64ImageContent(cgImage)
                    } else if DeckUserDefaults.enableLinkPreview, item.url != nil {
                        // Check if text contains a URL for link preview
                        LinkPreviewCard(item: item, contentHeight: effectiveCardSize - Const.cardHeaderSize)
                    } else {
                        textContent
                    }
                case .code:
                    if let cgImage = base64Thumbnail {
                        base64ImageContent(cgImage)
                    } else {
                        codeContent
                    }
                default:
                    textContent
                }
            }
        }
        .task(id: item.uniqueId) {
            resetImageFileSizeState()
            await prefetchHeavyAssetsIfNeeded()
        }
        .frame(maxWidth: .infinity, maxHeight: effectiveCardSize - Const.cardHeaderSize)
        .background {
            if item.itemType == .image || item.isFileURLImage {
                Const.contentShape
                    .fill(.clear)
                    .background(CheckerboardBackground())
                    .clipShape(Const.contentShape)
            } else {
                Const.contentShape
                    .fill(Const.cardContentBackground)
            }
        }
        .clipped()
    }

    private var missingFileMessage: String {
        if item.itemType == .image || item.isFileURLImage {
            return String(localized: "图片已被移动或删除", comment: "Missing image file message")
        }
        return String(localized: "文件已被移动或删除", comment: "Missing file message")
    }

    private var missingFileContent: some View {
        VStack(spacing: Const.space8) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 22))
                .foregroundStyle(.orange)
            Text(missingFileMessage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Const.space12)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var unsupportedContent: some View {
        VStack(spacing: Const.space8) {
            Spacer()
            if item.isFigmaClipboard {
                let logo = Image("figma-logo")
                    .renderingMode(colorScheme == .dark ? .template : .original)
                logo
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                    .opacity(0.9)
                    .foregroundStyle(colorScheme == .dark ? Color.white : Color.primary)
            } else {
                Text(NSLocalizedString("Deck 无法解析本剪贴板内容", comment: "Clipboard: unsupported content"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, Const.space12)
            }
            Spacer()
        }
    }

    private var textContent: some View {
        Group {
            if vm.layoutMode == .horizontal, smartState.isMarkdown {
                MarkdownCardPreview(
                    item: item,
                    sourceText: String(item.searchText.prefix(markdownCardPrefixLength)),
                    showsFileHeader: false,
                    lineLimit: textLineLimit,
                    maxLength: markdownCardPrefixLength
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                plainCardTextContent
            }
        }
        .task(id: smartTaskID) {
            // 异步加载智能分析
            smartState.isLoading = true
            let cached = await SmartContentCache.shared.analysis(for: item)
            smartState.analysis = cached.analysis
            smartState.isMarkdown = cached.isMarkdown
            smartState.calculationResult = cached.calculationResult
            smartState.isLoading = false
        }
    }

    private var plainCardTextContent: some View {
        VStack(alignment: .leading, spacing: Const.space4) {
            // Smart content badges (不包含计算结果)
            if smartState.hasOtherSmartContent, let analysis = smartState.analysis {
                SmartContentBadge(
                    analysis: analysis,
                    isMarkdown: smartState.isMarkdown,
                    calculationResult: nil  // 计算结果单独显示在下方
                )
            }

            // 原文本
            Text(item.searchText.prefix(textPrefixLength))
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .lineLimit(smartState.calculationResult != nil ? max(4, textLineLimit - 2) : (smartState.hasOtherSmartContent ? max(5, textLineLimit - 1) : textLineLimit))
                .multilineTextAlignment(.leading)

            // 计算结果显示在文本下方
            if let calc = smartState.calculationResult {
                HStack(spacing: 3) {
                    Text("=")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                    Text(calc.formattedResult)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.cyan.opacity(0.15))
                .foregroundStyle(.cyan)
                .clipShape(Capsule())
            }

            Spacer()

            Text(item.displayDescription())
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(Const.space12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    
    private var imageContent: some View {
        VStack(spacing: Const.space4) {
            Group {
                if let cgImage = imageThumbnail {
                    Image(decorative: cgImage, scale: 1.0)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: Const.smallRadius))
                } else {
                    RoundedRectangle(cornerRadius: Const.smallRadius)
                        .fill(.gray.opacity(0.15))
                        .overlay {
                            if isImageThumbnailLoading {
                                ProgressView()
                                    .controlSize(.mini)
                            } else {
                                Image(systemName: "photo")
                                    .font(.system(size: 20))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            
            HStack(spacing: Const.space4) {
                Text(imageDimensionDisplayText)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(imageFileSizeDisplayText)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.bottom, Const.space4)
        }
        .padding(.horizontal, Const.space8)
        .padding(.bottom, Const.space4)
    }

    private var imageDimensionDisplayText: String {
        imageDimensionText ?? NSLocalizedString("图片", comment: "Clipboard item description: image")
    }

    private var imageFileSizeDisplayText: String {
        if let text = imageFileSizeText { return text }
        if isImageFileSizeLoading {
            return String(localized: "Calculating...")
        }
        return "—"
    }

    private var imagePathCount: Int {
        guard item.pasteboardType == .fileURL else { return 0 }
        return item.normalizedFilePaths.count
    }

    private var hasMultipleImages: Bool {
        imagePathCount > 1
    }

    private var additionalImageCount: Int {
        max(0, imagePathCount - 1)
    }

    private var multiImageTotalText: String {
        String.localizedStringWithFormat(String(localized: "共 %lld 张"), Int64(imagePathCount))
    }

    private var multiImageMoreText: String {
        String.localizedStringWithFormat(String(localized: "还有 %lld 张图片"), Int64(additionalImageCount))
    }

    private func base64ImageContent(_ cgImage: CGImage) -> some View {
        VStack(spacing: Const.space4) {
            Image(decorative: cgImage, scale: 1.0)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Text("Base64 图片")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .padding(.bottom, Const.space8)
        }
        .padding(Const.space8)
    }
    
    private var fileContent: some View {
        Group {
            // PDF 文件使用缩略图预览
            if item.isPDF {
                PDFThumbnailView(item: item)
            } else if item.isMarkdownFile, vm.layoutMode == .horizontal {
                // Markdown 文件预览
                MarkdownCardPreview(item: item)
            } else {
                VStack(spacing: Const.space8) {
                    if let paths = item.filePaths {
                        ForEach(paths.prefix(3), id: \.self) { path in
                            HStack(spacing: Const.space8) {
                                Image(nsImage: cachedIcon(for: path))
                                    .resizable()
                                    .frame(width: 24, height: 24)

                                Text(URL(fileURLWithPath: path).lastPathComponent)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)

                                Spacer()
                            }
                        }

                        Spacer(minLength: 0)

                        if paths.count > 3 {
                            Text("还有 \(paths.count - 3) 个文件")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(Const.space12)
            }
        }
    }
    
    private var colorContent: some View {
        VStack(spacing: Const.space12) {
            if let color = item.colorValue {
                RoundedRectangle(cornerRadius: Const.smallRadius)
                    .fill(Color(nsColor: color))
                    .frame(width: 80, height: 80)
                    .overlay {
                        RoundedRectangle(cornerRadius: Const.smallRadius)
                            .strokeBorder(.white.opacity(0.2), lineWidth: 1)
                    }
            }
            
            Text(item.searchText)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var urlContent: some View {
        VStack(alignment: .leading, spacing: Const.space8) {
            Image(systemName: "globe")
                .font(.system(size: 24))
                .foregroundStyle(.secondary)
            
            Text(item.searchText)
                .font(.system(size: 11))
                .foregroundStyle(.blue)
                .lineLimit(max(4, textLineLimit))
                .multilineTextAlignment(.leading)
            
            Spacer()
        }
        .padding(Const.space12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    
    private var codeContent: some View {
        VStack(alignment: .leading, spacing: Const.space4) {
            Text(item.searchText.prefix(codePrefixLength))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(codeLineLimit)
                .multilineTextAlignment(.leading)
            
            Spacer()
            
            HStack {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 10))
                Text(item.displayDescription())
                    .font(.system(size: 10))
            }
            .foregroundStyle(.secondary)
        }
        .padding(Const.space12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Thumbnail Prefetching

    private var thumbnailMaxPixelSize: Int {
        // Keep this cheap; use main screen scale if available.
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let maxPoint = max(effectiveCardSize, Const.cardContentSize)
        return max(64, Int(maxPoint * scale))
    }

    @MainActor
    private func prefetchHeavyAssetsIfNeeded() async {
        checkMissingFileIfNeeded()
        if item.isMissingFile {
            return
        }
        switch item.itemType {
        case .image:
            await loadImageFileSizeIfNeeded()
            await loadImageThumbnailIfNeeded()
        case .text, .code:
            await loadBase64ThumbnailIfNeeded()
        default:
            break
        }
    }

    private static let imageFileSizeUnavailableSentinel = -1

    @MainActor
    private func resetImageFileSizeState() {
        if imageStateItemID != item.uniqueId {
            imageStateItemID = item.uniqueId
            imageThumbnail = nil
            imageDimensionText = nil
            isImageThumbnailLoading = false
        }
        imageFileSizeText = nil
        isImageFileSizeLoading = false
    }

    @MainActor
    private func loadImageFileSizeIfNeeded() async {
        guard item.itemType == .image else { return }

        let cacheKey = ("img-size:" + item.uniqueId) as NSString
        if let cached = ClipItemCardCache.imageFileSizeCache.object(forKey: cacheKey) {
            let value = cached.intValue
            imageFileSizeText = value >= 0 ? Self.formatFileSize(value) : "—"
            return
        }

        guard !isImageFileSizeLoading else { return }
        isImageFileSizeLoading = true

        let targetId = item.uniqueId
        let isFileURL = item.pasteboardType == .fileURL
        let filePaths = item.normalizedFilePaths
        let blobPath = item.blobPath
        let inlineDataSize = item.data.count
        let isMissingFile = item.isMissingFile

        let bytes = await Task.detached(priority: .utility) { () -> Int? in
            if isMissingFile { return nil }
            if isFileURL { return Self.totalFileSize(for: filePaths) }
            if let blobPath { return Self.fileSize(at: blobPath) }
            if inlineDataSize > 0 { return inlineDataSize }
            return nil
        }.value

        guard targetId == item.uniqueId else { return }
        isImageFileSizeLoading = false

        if let bytes = bytes, bytes > 0 {
            ClipItemCardCache.imageFileSizeCache.setObject(NSNumber(value: bytes), forKey: cacheKey)
            imageFileSizeText = Self.formatFileSize(bytes)
        } else {
            ClipItemCardCache.imageFileSizeCache.setObject(
                NSNumber(value: Self.imageFileSizeUnavailableSentinel),
                forKey: cacheKey
            )
            imageFileSizeText = "—"
        }
    }

    nonisolated private static func fileSize(at path: String) -> Int? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? NSNumber else { return nil }
        return size.intValue
    }

    nonisolated private static func totalFileSize(for paths: [String]) -> Int? {
        guard !paths.isEmpty else { return nil }
        var total = 0
        var found = false
        for path in paths {
            if let size = fileSize(at: path) {
                total += size
                found = true
            }
        }
        return found ? total : nil
    }

    private static func formatFileSize(_ bytes: Int) -> String {
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024)
        } else if bytes < 1024 * 1024 * 1024 {
            return String(format: "%.1f MB", Double(bytes) / 1024 / 1024)
        } else {
            return String(format: "%.1f GB", Double(bytes) / 1024 / 1024 / 1024)
        }
    }

    @MainActor
    private func checkMissingFileIfNeeded() {
        guard item.pasteboardType == .fileURL else { return }
        guard !item.isMissingFile else { return }
        if item.isFileMissingOnDisk() {
            DeckDataStore.shared.markMissingFileItem(item)
        }
    }

    @MainActor
    private func loadImageThumbnailIfNeeded() async {
        guard imageThumbnail == nil else { return }

        let cacheKey = ("img:" + item.uniqueId) as NSString
        if let cached = ClipItemCardCache.thumbnailCache.object(forKey: cacheKey) {
            imageThumbnail = cached
            return
        }

        isImageThumbnailLoading = true
        let maxPixel = thumbnailMaxPixelSize

        if item.pasteboardType == .fileURL, let fileURL = primaryImageFileURL() {
            if fileURL.isFileURL, !FileManager.default.fileExists(atPath: fileURL.path) {
                checkMissingFileIfNeeded()
                isImageThumbnailLoading = false
                return
            }
            let fileResult = await decodeThumbnail {
                Self.downsampledImage(from: fileURL, maxPixelSize: maxPixel)
            }

            if let fileResult {
                let fileThumb = fileResult.image
                ClipItemCardCache.thumbnailCache.setObject(
                    fileThumb,
                    forKey: cacheKey,
                    cost: fileThumb.bytesPerRow * fileThumb.height
                )
                imageThumbnail = fileThumb
                imageDimensionText = Self.formatPixelSize(fileResult.pixelSize)
                isImageThumbnailLoading = false
                return
            }
        }

        // Prefer in-memory data first (no I/O on main thread).
        let previewData = item.previewData
        let inlineData = item.data

        let dataToDecode: (data: Data, isOriginal: Bool)? = {
            if let previewData, !previewData.isEmpty { return (previewData, false) }
            if item.pasteboardType == .fileURL { return nil }
            if !inlineData.isEmpty { return (inlineData, item.hasFullData) }
            return nil
        }()

        // Fallback: resolvedData() is ClipboardItem-isolated; keep the actor boundary explicit.
        let finalData: (data: Data, isOriginal: Bool)? = dataToDecode ?? item.resolvedData().map { ($0, true) }

        guard let finalData, !finalData.data.isEmpty else {
            isImageThumbnailLoading = false
            return
        }

        let decodeResult = await decodeThumbnail {
            Self.downsampledImage(from: finalData.data, maxPixelSize: maxPixel)
        }

        isImageThumbnailLoading = false

        if let decodeResult {
            let cgImage = decodeResult.image
            ClipItemCardCache.thumbnailCache.setObject(
                cgImage,
                forKey: cacheKey,
                cost: cgImage.bytesPerRow * cgImage.height
            )
            imageThumbnail = cgImage
            if finalData.isOriginal {
                imageDimensionText = Self.formatPixelSize(decodeResult.pixelSize)
            }
        }
    }

    @MainActor
    private func decodeThumbnail(_ operation: @escaping @Sendable () -> ImageDecodeResult?) async -> ImageDecodeResult? {
        let acquired = await ClipItemThumbnailDecodeGate.shared.acquire()
        guard acquired else { return nil }
        defer { Task { await ClipItemThumbnailDecodeGate.shared.release() } }

        let task = Task.detached(priority: .utility, operation: operation)
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    @MainActor
    private func loadBase64ThumbnailIfNeeded() async {
        // Base64 detection is relatively expensive; never run it repeatedly for the same item.
        guard !didAttemptBase64Decode else { return }

        let cacheKey = ("b64:" + item.uniqueId) as NSString
        if let cached = ClipItemCardCache.thumbnailCache.object(forKey: cacheKey) {
            base64Thumbnail = cached
            return
        }

        // IMPORTANT: do NOT do any heavy string work on the main actor.
        // Large clipboard text (e.g. 1M+ chars) can otherwise freeze panel open/close.
        let text = item.searchText
        let length = item.contentLength
        let maxBytes = Const.maxBase64ImageBytes

        guard Self.shouldAttemptBase64ImageDecode(text, contentLength: length, maxBytes: maxBytes) else {
            return
        }

        didAttemptBase64Decode = true

        isBase64ThumbnailLoading = true
        let maxPixel = thumbnailMaxPixelSize

        let dataTask = Task.detached(priority: .userInitiated) {
            Self.extractBase64ImageData(from: text, contentLength: length, maxBytes: maxBytes)
        }
        let data = await withTaskCancellationHandler(operation: {
            await dataTask.value
        }, onCancel: {
            dataTask.cancel()
        })

        if Task.isCancelled {
            isBase64ThumbnailLoading = false
            return
        }

        guard let data else {
            isBase64ThumbnailLoading = false
            return
        }

        let cgImageTask = Task.detached(priority: .userInitiated) {
            Self.downsampledCGImage(from: data, maxPixelSize: maxPixel)
        }
        let cgImage = await withTaskCancellationHandler(operation: {
            await cgImageTask.value
        }, onCancel: {
            cgImageTask.cancel()
        })

        if Task.isCancelled {
            isBase64ThumbnailLoading = false
            return
        }

        isBase64ThumbnailLoading = false

        if let cgImage {
            ClipItemCardCache.thumbnailCache.setObject(
                cgImage,
                forKey: cacheKey,
                cost: cgImage.bytesPerRow * cgImage.height
            )
        }
        base64Thumbnail = cgImage
    }

    /// Extremely cheap, conservative pre-check to avoid spawning a detached task
    /// for the ~99.9% of text items that are obviously not a base64 image.
    ///
    /// We intentionally keep this logic in sync with `extractBase64ImageData` but without
    /// allocating or decoding anything.
    nonisolated private static func shouldAttemptBase64ImageDecode(_ text: String, contentLength: Int, maxBytes: Int) -> Bool {
        // Too small to be a meaningful image payload.
        guard contentLength >= 256 else { return false }

        // Hard cap: we never attempt to decode payloads that couldn't possibly fit within the configured limit.
        let maxBase64Chars = (maxBytes * 4) / 3 + 1024
        guard contentLength <= maxBase64Chars else { return false }

        // Fast path: data URL prefix.
        if quickLooksLikeDataImagePrefix(text) {
            return true
        }

        // Heuristic path: long, base64-like payload (avoid trying on normal short text).
        guard contentLength > 4096 else { return false }

        let start = firstNonWhitespaceIndex(in: text, maxScan: 256) ?? text.startIndex
        let head = text[start...]
        guard sampleLooksLikeBase64(head, sampleLimit: 512) else { return false }

        let estimatedBytes = (contentLength * 3) / 4
        return estimatedBytes <= maxBytes
    }

    /// 只做“非常保守”的 base64 图片探测：
    /// - 必须快速失败（尤其是超长文本）
    /// - 必须在后台线程完成（避免卡住面板打开/关闭）
    /// - 必须有上限（decoded data <= maxBase64ImageBytes）
    nonisolated private static func extractBase64ImageData(from text: String, contentLength: Int, maxBytes: Int) -> Data? {
        // Too small to be a meaningful image payload.
        guard contentLength >= 256 else { return nil }

        // We never attempt to decode payloads that couldn't possibly fit within the configured limit.
        // base64 decoded bytes ~= chars * 3/4 (ignoring whitespace).
        let maxBase64Chars = (maxBytes * 4) / 3 + 1024
        guard contentLength <= maxBase64Chars else {
            // Still allow a quick "data:image" prefix check (cheap), but we will reject by size anyway.
            // Returning nil early avoids scanning huge normal text (e.g. SQL dumps).
            if !quickLooksLikeDataImagePrefix(text) {
                return nil
            }
            // Even if it looks like a data URL, it exceeds our size cap.
            return nil
        }

        // 1) Common data URL pattern: data:image/png;base64,XXXX
        if let data = decodeDataURLIfPresent(text, contentLength: contentLength, maxBytes: maxBytes) {
            return data
        }

        // 2) Heuristic: long, base64-like payload (avoid trying on normal text).
        //    NOTE: Conservative by design.
        guard contentLength > 4096 else { return nil }

        // Quick sample check on the first chunk only.
        let start = firstNonWhitespaceIndex(in: text, maxScan: 256) ?? text.startIndex
        let head = text[start...]
        guard sampleLooksLikeBase64(head, sampleLimit: 2048) else { return nil }

        // Estimate decoded bytes before doing any real decode.
        let estimatedBytes = (contentLength * 3) / 4
        guard estimatedBytes <= maxBytes else { return nil }

        guard let data = Data(base64Encoded: text, options: [.ignoreUnknownCharacters]) else { return nil }
        return data.count <= maxBytes ? data : nil
    }

    nonisolated private static func quickLooksLikeDataImagePrefix(_ text: String) -> Bool {
        let start = firstNonWhitespaceIndex(in: text, maxScan: 128) ?? text.startIndex
        return text[start...].hasPrefix("data:image")
    }

    nonisolated private static func decodeDataURLIfPresent(_ text: String, contentLength: Int, maxBytes: Int) -> Data? {
        let start = firstNonWhitespaceIndex(in: text, maxScan: 128) ?? text.startIndex
        let head = text[start...]
        guard head.hasPrefix("data:image") else { return nil }

        // The comma separating metadata and payload should appear very early.
        let headerSlice = head.prefix(1024)
        guard let comma = headerSlice.firstIndex(of: ",") else { return nil }
        let base64Start = head.index(after: comma)

        // Approximate size check using the known total length (avoid O(n) count traversal).
        let prefixLen = text.distance(from: text.startIndex, to: base64Start)
        let approxB64Chars = max(0, contentLength - prefixLen)
        let estimatedBytes = (approxB64Chars * 3) / 4
        guard estimatedBytes <= maxBytes else { return nil }

        let b64 = String(text[base64Start...])
        guard let data = Data(base64Encoded: b64, options: [.ignoreUnknownCharacters]) else { return nil }
        return data.count <= maxBytes ? data : nil
    }

    nonisolated private static func firstNonWhitespaceIndex(in text: String, maxScan: Int) -> String.Index? {
        var idx = text.startIndex
        var remaining = maxScan
        while idx < text.endIndex, remaining > 0 {
            if !text[idx].isWhitespace {
                return idx
            }
            idx = text.index(after: idx)
            remaining -= 1
        }
        return nil
    }

    nonisolated private static func sampleLooksLikeBase64(_ text: Substring, sampleLimit: Int) -> Bool {
        var checked = 0
        for scalar in text.unicodeScalars {
            if checked >= sampleLimit { break }
            let v = scalar.value
            switch v {
            case 65...90, 97...122, 48...57, 43, 47, 61, 45, 95, 9, 10, 13, 32:
                break
            default:
                return false
            }
            checked += 1
        }
        return checked >= 128
    }

    nonisolated private static func formatPixelSize(_ size: CGSize?) -> String? {
        guard let size, size.width > 0, size.height > 0 else { return nil }
        return "\(Int(size.width.rounded())) × \(Int(size.height.rounded()))"
    }

    nonisolated private static func imagePixelSize(from source: CGImageSource) -> CGSize? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else {
            return nil
        }
        return CGSize(width: CGFloat(truncating: width), height: CGFloat(truncating: height))
    }

    nonisolated private static func downsampledImage(from data: Data, maxPixelSize: Int) -> ImageDecodeResult? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let pixelSize = imagePixelSize(from: source)

        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixelSize)
        ] as CFDictionary

        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else { return nil }
        return ImageDecodeResult(image: image, pixelSize: pixelSize)
    }

    nonisolated private static func downsampledImage(from url: URL, maxPixelSize: Int) -> ImageDecodeResult? {
        if url.isFileURL, !FileManager.default.fileExists(atPath: url.path) {
            return nil
        }
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
        let pixelSize = imagePixelSize(from: source)

        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixelSize)
        ] as CFDictionary

        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else { return nil }
        return ImageDecodeResult(image: image, pixelSize: pixelSize)
    }

    nonisolated fileprivate static func downsampledCGImage(from data: Data, maxPixelSize: Int) -> CGImage? {
        downsampledImage(from: data, maxPixelSize: maxPixelSize)?.image
    }

    nonisolated fileprivate static func downsampledCGImage(from url: URL, maxPixelSize: Int) -> CGImage? {
        downsampledImage(from: url, maxPixelSize: maxPixelSize)?.image
    }

    private func primaryImageFileURL() -> URL? {
        guard let path = item.filePaths?.first else { return nil }
        if path.hasPrefix("file://"), let url = URL(string: path) {
            return url
        }
        return URL(fileURLWithPath: path)
    }

    private func cachedIcon(for path: String) -> NSImage {
        let key = path as NSString
        if let cached = ClipItemCardCache.iconCache.object(forKey: key) {
            return cached
        }
        let icon = IconCache.shared.icon(forFile: path)
        ClipItemCardCache.iconCache.setObject(icon, forKey: key)
        return icon
    }

    // MARK: - Context Menu
    
    @ViewBuilder
    private func contextMenuContent(ocrText: String?) -> some View {
        Button {
            vm.pasteItem(item)
        } label: {
            Label("粘贴", systemImage: "doc.on.clipboard")
        }
        
        if item.pasteboardType.isText() {
            Button {
                vm.pasteItem(item, asPlainText: true)
            } label: {
                Label("以纯文本粘贴", systemImage: "text.alignleft")
            }
        }
        
        Button {
            vm.copyItem(item)
        } label: {
            Label("复制", systemImage: "doc.on.doc")
        }

        Button {
            startTitleEditing()
        } label: {
            Label(String(localized: "重命名"), systemImage: "pencil")
        }

        if let ocrText {
            Button {
                copyOCRTextToClipboard(ocrText)
            } label: {
                Label(String(localized: "复制图片OCR文本"), systemImage: "text.viewfinder")
            }
        }

        if let url = item.url {
            Button {
                openURLFromPanel(url)
            } label: {
                Label(String(localized: "在默认浏览器中打开"), systemImage: "safari")
            }

            if QRCodeViewModel.shouldOfferQRCode(for: url) {
                Button {
                    QRCodeWindowController.shared.show(url: url, relativeTo: MainWindowController.shared.window)
                } label: {
                    Label(String(localized: "显示二维码"), systemImage: "qrcode")
                }
            }
        }

        let isImportant = item.tagId == DeckTag.importantTagId
        Button {
            if let itemId = item.id {
                let targetTagId = isImportant ? -1 : DeckTag.importantTagId
                DeckDataStore.shared.updateItemTag(itemId: itemId, tagId: targetTagId)
            }
        } label: {
            Label(
                isImportant ? String(localized: "取消重要") : String(localized: "标记为重要"),
                systemImage: isImportant ? "pin.slash" : "pin.fill"
            )
        }

        let isTemporary = item.isTemporary
        Button {
            if let itemId = item.id {
                DeckDataStore.shared.updateItemTemporary(itemId: itemId, isTemporary: !isTemporary)
            }
        } label: {
            Label(
                isTemporary ? String(localized: "取消临时") : String(localized: "标记为临时"),
                systemImage: isTemporary ? "timer" : "timer"
            )
        }
        
        Divider()
        
        // Add to group menu
        let userTags = vm.tags.filter { !$0.isSystem }
        if !userTags.isEmpty {
            Menu {
                ForEach(userTags) { tag in
                    Button {
                        if let itemId = item.id {
                            DeckDataStore.shared.updateItemTag(itemId: itemId, tagId: tag.id)
                        }
                    } label: {
                        HStack {
                            Circle()
                                .fill(tag.color)
                                .frame(width: 8, height: 8)
                            Text(tag.name)
                        }
                    }
                }
                
                Divider()
                
                Button {
                    if let itemId = item.id {
                        DeckDataStore.shared.updateItemTag(itemId: itemId, tagId: -1)
                    }
                } label: {
                    Label("移出分组", systemImage: "xmark")
                }
            } label: {
                Label("添加到分组", systemImage: "folder.badge.plus")
            }
        }

        // Add to Template Library menu
        let templateLibraries = TemplateLibraryService.shared.libraries
        if !templateLibraries.isEmpty {
            Menu {
                ForEach(templateLibraries) { library in
                    Button {
                        TemplateLibraryService.shared.addItem(item, to: library)
                    } label: {
                        HStack {
                            Circle()
                                .fill(library.color)
                                .frame(width: 8, height: 8)
                            Text(library.name)
                        }
                    }
                }

            } label: {
                Label(NSLocalizedString("添加到模版库", comment: "Add to Template Library"), systemImage: "tray.and.arrow.down")
            }
        }

        Divider()

        // Transform menu (only for text content)
        if item.pasteboardType.isText() {
            Menu {
                ForEach(TransformType.allCases) { transform in
                    Button {
                        pasteWithTransform(transform)
                    } label: {
                        Label(NSLocalizedString(transform.rawValue, comment: "Transform type display name"), systemImage: transform.icon)
                    }
                }

                // Script Plugins section
                let plugins = ScriptPluginService.shared.plugins
                if !plugins.isEmpty {
                    Divider()

                    ForEach(plugins) { plugin in
                        Button {
                            pasteWithScriptPlugin(plugin)
                        } label: {
                            Label(plugin.displayName, systemImage: plugin.displayIcon)
                        }
                    }
                }
            } label: {
                Label("转换后粘贴", systemImage: "wand.and.stars")
            }
        }

        if item.itemType == .text || item.itemType == .code || item.itemType == .richText {
            Menu {
                Button {
                    stegoEncodeToImage()
                } label: {
                    Label(String(localized: "隐写到图片..."), systemImage: "photo")
                }

                Button {
                    stegoEncodeToText()
                } label: {
                    Label(String(localized: "隐写为文本"), systemImage: "text.badge.plus")
                }
            } label: {
                Label(String(localized: "隐写"), systemImage: "lock.doc")
            }
        }

        if item.itemType == .image || item.itemType == .text || item.itemType == .code || item.itemType == .richText {
            Button {
                stegoDecodeFromItem()
            } label: {
                Label(String(localized: "解密隐写"), systemImage: "lock.open")
            }
        }
        
        // LAN Sharing menu
        if DeckUserDefaults.lanSharingEnabled {
            let hasMultipeerPeers = !multipeerService.connectedPeers.isEmpty
            let hasDirectPeers = !directConnectService.manualPeers.filter(\.isConnected).isEmpty

            Divider()

            Menu {
                // Multipeer connected peers
                if hasMultipeerPeers {
                    ForEach(multipeerService.connectedPeers) { peer in
                        Button {
                            Task {
                                await multipeerService.sendItem(item, to: peer)
                            }
                        } label: {
                            Label(
                                peer.displayName,
                                systemImage: peer.isSecurityModeEnabled ? "lock.desktopcomputer" : "desktopcomputer"
                            )
                        }
                    }
                }

                // DirectConnect manual peers
                if hasDirectPeers {
                    if hasMultipeerPeers {
                        Divider()
                    }
                    ForEach(directConnectService.manualPeers.filter(\.isConnected)) { peer in
                        Button {
                            Task {
                                _ = await directConnectService.sendItem(item, to: peer)
                            }
                        } label: {
                            Label(peer.displayName, systemImage: "network")
                        }
                    }
                }

                // No peers available
                if !hasMultipeerPeers && !hasDirectPeers {
                    Text("暂无可用设备")
                        .foregroundStyle(.secondary)
                    Divider()
                    Button {
                        SettingsWindowController.shared.showWindow(selecting: .lanSharing)
                    } label: {
                        Label("前往设置添加设备", systemImage: "gear")
                    }
                }
            } label: {
                Label("发送给", systemImage: "paperplane")
            }
        }

        // System Share submenu
        Menu {
            ForEach(Array(SystemSharingService.cachedServices.enumerated()), id: \.offset) { _, service in
                Button {
                    SystemSharingService.performShare(for: item, service: service)
                    MainWindowController.shared.dismissPanelAndRestoreFocus()
                } label: {
                    Label {
                        Text(service.title)
                    } icon: {
                        Image(nsImage: service.image)
                    }
                }
            }
        } label: {
            Label(String(localized: "系统分享"), systemImage: "square.and.arrow.up")
        }

        // Ask AI
        if canAskAI {
            Divider()
            Button {
                AIChatWindowController.shared.showForClipboardItem(item)
            } label: {
                Label("询问 AI", systemImage: "sparkles")
            }
        }

        Divider()

        Button(role: .destructive) {
            onDelete?()
        } label: {
            Label("删除", systemImage: "trash")
        }

        Divider()

        Button {
            showPreview.toggle()
        } label: {
            Label("预览", systemImage: "eye")
        }
    }
    
    private func pasteWithTransform(_ type: TransformType) {
        guard let transformed = TextTransformer.shared.transform(item.searchText, type: type) else {
            // If transform fails, paste original
            vm.pasteItem(item)
            return
        }

        // Copy transformed text to clipboard
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transformed, forType: .string)

        // Close panel and paste
        MainWindowController.shared.toggleWindow()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            ClipboardService.shared.simulatePaste()
            vm.consumeTemporaryItemIfNeeded(item)
        }
    }

    private func openURLFromPanel(_ url: URL) {
        MainWindowController.shared.setPresented(false, animated: true) {
            NSWorkspace.shared.open(url)
        }
    }

    private func copyOCRTextToClipboard(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(trimmed, forType: .string)
    }

    private func pasteWithScriptPlugin(_ plugin: ScriptPlugin) {
        let pluginId = plugin.id
        let input = item.searchText

        Task { @MainActor in
            let result = await ScriptPluginService.shared.executeTransformAsync(
                pluginId: pluginId,
                input: input
            )

            guard result.success, let output = result.output else {
                if let error = result.error {
                    await log.error("Script plugin error: \(error)")
                }
                vm.pasteItem(item)
                return
            }

            // Copy transformed text to clipboard
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(output, forType: .string)

            // Close panel and paste
            MainWindowController.shared.toggleWindow()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                ClipboardService.shared.simulatePaste()
                vm.consumeTemporaryItemIfNeeded(item)
            }
        }
    }

    // MARK: - Steganography

    private func stegoEncodeToImage() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]

        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let imageData = try? Data(contentsOf: url) else {
            showStegoAlert(
                title: String(localized: "无法读取图片"),
                message: String(localized: "请选择可用的图片文件。")
            )
            return
        }

        guard let stegoData = SteganographyService.shared.encode(text: item.searchText, into: imageData) else {
            showStegoAlert(
                title: String(localized: "隐写失败"),
                message: String(localized: "图片容量不足或加密失败。")
            )
            return
        }

        let timestamp = Int64(Date().timeIntervalSince1970)
        let newItem = ClipboardItem(
            pasteboardType: .png,
            data: stegoData,
            previewData: nil,
            timestamp: timestamp,
            appPath: Bundle.main.bundlePath,
            appName: "Deck",
            searchText: "",
            contentLength: stegoData.count,
            tagId: -1
        )
        vm.storeAndCopy(newItem)
    }

    private func stegoEncodeToText() {
        guard let encoded = SteganographyService.shared.encode(text: item.searchText, asZeroWidthWithCover: nil) else {
            showStegoAlert(
                title: String(localized: "隐写失败"),
                message: String(localized: "加密失败或内容为空。")
            )
            return
        }
        let newItem = makeTextItem(from: encoded)
        vm.storeAndCopy(newItem)
    }

    private func stegoDecodeFromItem() {
        guard let decoded = SteganographyService.shared.decodeIfPossible(from: item) else {
            showStegoAlert(
                title: String(localized: "未检测到隐写内容"),
                message: String(localized: "请确认载体未被压缩或密钥一致。")
            )
            return
        }
        let newItem = makeTextItem(from: decoded)
        vm.storeAndCopy(newItem)
    }

    private func makeTextItem(from text: String) -> ClipboardItem {
        let attributed = NSAttributedString(string: text)
        let previewAttr = attributed.length > 250
            ? attributed.attributedSubstring(from: NSMakeRange(0, 250))
            : attributed
        let previewData = previewAttr.toData(with: .string)

        return ClipboardItem(
            pasteboardType: .string,
            data: text.data(using: .utf8) ?? Data(),
            previewData: previewData,
            timestamp: Int64(Date().timeIntervalSince1970),
            appPath: Bundle.main.bundlePath,
            appName: "Deck",
            searchText: text,
            contentLength: attributed.length,
            tagId: -1
        )
    }

    private func showStegoAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: String(localized: "好"))
        alert.runModal()
    }
}

// MARK: - Preview Popover

struct PreviewPopoverView: View {
    let item: ClipboardItem
    @State private var calculationResult: SmartTextService.CalculationResult?
    @AppStorage(PrefKey.instantCalculation.rawValue) private var instantCalculationEnabled = DeckUserDefaults.instantCalculation

    private var calcTaskID: SmartAnalysisTaskKey {
        item.smartAnalysisTaskKey(instantCalculationEnabled: instantCalculationEnabled)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Const.space12) {
                switch item.itemType {
                case .image:
                    AsyncPreviewImageView(item: item)
                case .color:
                    if let color = item.colorValue {
                        VStack(spacing: Const.space16) {
                            RoundedRectangle(cornerRadius: Const.radius)
                                .fill(Color(nsColor: color))
                                .frame(width: 150, height: 150)

                            Text(item.searchText)
                                .font(.system(size: 18, weight: .medium, design: .monospaced))
                        }
                        .padding()
                    }
                default:
                    VStack(alignment: .leading, spacing: Const.space8) {
                        // 原文本
                        Text(item.searchText)
                            .font(.system(size: 13))
                            .textSelection(.enabled)
                            .frame(maxWidth: 500, alignment: .leading)

                        // 计算结果（如果有）
                        if let calcResult = calculationResult {
                            HStack(spacing: 4) {
                                Text("=")
                                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.cyan)
                                Text(calcResult.formattedResult)
                                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(.cyan)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.cyan.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
            }
            .padding()
        }
        .frame(minWidth: 300, maxWidth: 600, minHeight: 200, maxHeight: 500)
        .task(id: calcTaskID) {
            await loadCalculationIfNeeded()
        }
        .onChange(of: item.uniqueId) { _, _ in
            calculationResult = nil
        }
    }

    private func loadCalculationIfNeeded() async {
        guard item.itemType == .text || item.itemType == .code else {
            calculationResult = nil
            return
        }
        let cached = await SmartContentCache.shared.analysis(for: item)
        if Task.isCancelled { return }
        calculationResult = cached.calculationResult
    }
}

// MARK: - Async Preview Image

private struct AsyncPreviewImageView: View {
    let item: ClipboardItem

    @State private var cgImage: CGImage?
    @State private var isLoading = false

    private var maxPixelSize: Int {
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        // Preview is up to ~600pt wide; decode at ~2x for retina.
        return max(256, Int(600 * scale))
    }

    var body: some View {
        Group {
            if let cgImage {
                Image(decorative: cgImage, scale: 1.0)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 600, maxHeight: 400)
            } else {
                RoundedRectangle(cornerRadius: Const.radius)
                    .fill(.gray.opacity(0.15))
                    .overlay {
                        if isLoading {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "photo")
                                .font(.system(size: 24))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .frame(maxWidth: 600, maxHeight: 400)
            }
        }
        .task(id: item.uniqueId) {
            await loadIfNeeded()
        }
    }

    @MainActor
    private func loadIfNeeded() async {
        guard cgImage == nil else { return }

        let cacheKey = ("preview:" + item.uniqueId) as NSString
        if let cached = ClipItemCardCache.thumbnailCache.object(forKey: cacheKey) {
            cgImage = cached
            return
        }

        let data = (item.previewData?.isEmpty == false ? item.previewData : nil) ?? item.resolvedData() ?? item.data
        guard !data.isEmpty else { return }

        isLoading = true
        let maxPixel = maxPixelSize
        let decoded = await Task.detached(priority: .userInitiated) {
            ClipItemCardView.downsampledCGImage(from: data, maxPixelSize: maxPixel)
        }.value
        isLoading = false

        if let decoded {
            ClipItemCardCache.thumbnailCache.setObject(decoded, forKey: cacheKey, cost: decoded.bytesPerRow * decoded.height)
        }
        cgImage = decoded
    }
}

#Preview {
    HStack(spacing: 20) {
        ClipItemCardView(
            item: ClipboardItem(
                pasteboardType: .string,
                data: "Hello World".data(using: .utf8)!,
                previewData: nil,
                timestamp: Int64(Date().timeIntervalSince1970),
                appPath: "/Applications/Safari.app",
                appName: "Safari",
                searchText: "Hello World",
                contentLength: 11,
                tagId: -1
            ),
            isSelected: true,
            showPreview: .constant(false)
        )
        
        ClipItemCardView(
            item: ClipboardItem(
                pasteboardType: .string,
                data: "#FF5733".data(using: .utf8)!,
                previewData: nil,
                timestamp: Int64(Date().timeIntervalSince1970),
                appPath: "",
                appName: "Xcode",
                searchText: "#FF5733",
                contentLength: 7,
                tagId: -1
            ),
            isSelected: false,
            showPreview: .constant(false)
        )
    }
    .padding()
    .background(Color.black.opacity(0.5))
}
