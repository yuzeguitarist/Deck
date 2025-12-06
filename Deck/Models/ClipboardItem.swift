//
//  ClipboardItem.swift
//  Deck
//
//  Deck Clipboard Manager
//

import AppKit
import Observation
import UniformTypeIdentifiers
import QuickLookThumbnailing
import PDFKit

typealias PasteboardType = NSPasteboard.PasteboardType

extension PasteboardType {
    // Image types first to prioritize image detection over fileURL
    static var supportedTypes: [PasteboardType] = [
        .png, .tiff, .rtf, .rtfd, .fileURL, .string
    ]
    
    func isImage() -> Bool {
        self == .png || self == .tiff
    }
    
    func isText() -> Bool {
        !isImage() && !isFile()
    }
    
    func isFile() -> Bool {
        self == .fileURL
    }
}

enum ClipItemType: String, Codable, Sendable {
    case text
    case richText
    case image
    case file
    case url
    case color
    case code
    
    var displayName: String {
        switch self {
        case .text: return "文本"
        case .richText: return "富文本"
        case .image: return "图片"
        case .file: return "文件"
        case .url: return "链接"
        case .color: return "颜色"
        case .code: return "代码"
        }
    }
    
    var icon: String {
        switch self {
        case .text: return "doc.text"
        case .richText: return "doc.richtext"
        case .image: return "photo"
        case .file: return "doc"
        case .url: return "link"
        case .color: return "paintpalette"
        case .code: return "chevron.left.forwardslash.chevron.right"
        }
    }
}

@Observable
final class ClipboardItem: Identifiable, Equatable {
    var id: Int64?
    let uniqueId: String
    let pasteboardType: PasteboardType
    let data: Data
    let previewData: Data?
    let blobPath: String?
    private(set) var timestamp: Int64
    let appPath: String
    let appName: String
    var searchText: String
    let contentLength: Int
    var tagId: Int
    
    @ObservationIgnored
    private(set) lazy var itemType: ClipItemType = detectItemType()
    
    @ObservationIgnored
    private var cachedThumbnail: NSImage?
    
    @ObservationIgnored
    private var cachedImageSize: CGSize?
    
    @ObservationIgnored
    private var cachedFilePaths: [String]?
    
    @ObservationIgnored
    private var cachedColorValue: NSColor?
    
    @ObservationIgnored
    private lazy var analysisSample: String = {
        if searchText.count > Const.maxSmartAnalysisLength {
            return String(searchText.prefix(Const.maxSmartAnalysisLength))
        }
        return searchText
    }()
    
    @ObservationIgnored
    private var cachedSmartAnalysis: SmartTextService.DetectionResult?
    
    @ObservationIgnored
    private var cachedIsMarkdown: Bool?

    @ObservationIgnored
    private var cachedCalculationResult: SmartTextService.CalculationResult?

    @ObservationIgnored
    private var calculationResultChecked: Bool = false
    
    var url: URL? {
        if pasteboardType == .string {
            let urlString = String(data: data, encoding: .utf8) ?? ""
            return urlString.asCompleteURL()
        }
        return nil
    }
    
    var colorValue: NSColor? {
        if cachedColorValue != nil { return cachedColorValue }
        guard itemType == .color else { return nil }
        let text = String(data: data, encoding: .utf8) ?? ""
        cachedColorValue = text.hexColor
        return cachedColorValue
    }
    
    var filePaths: [String]? {
        if cachedFilePaths != nil { return cachedFilePaths }
        guard pasteboardType == .fileURL,
              let urlString = String(data: data, encoding: .utf8) else { return nil }
        cachedFilePaths = urlString.components(separatedBy: "\n").filter { !$0.isEmpty }
        return cachedFilePaths
    }
    
    init(
        pasteboardType: PasteboardType,
        data: Data,
        previewData: Data?,
        timestamp: Int64,
        appPath: String,
        appName: String,
        searchText: String,
        contentLength: Int,
        tagId: Int = -1,
        id: Int64? = nil,
        uniqueId: String? = nil,
        blobPath: String? = nil
    ) {
        self.pasteboardType = pasteboardType
        self.data = data
        self.previewData = previewData
        self.uniqueId = uniqueId ?? data.sha256Hex
        self.timestamp = timestamp
        self.appPath = appPath
        self.appName = appName
        self.searchText = searchText
        self.contentLength = contentLength
        self.tagId = tagId
        self.id = id
        self.blobPath = blobPath
        
        if pasteboardType == .fileURL {
            if let urlString = String(data: data, encoding: .utf8) {
                cachedFilePaths = urlString.components(separatedBy: "\n").filter { !$0.isEmpty }
            }
        }
    }
    
    convenience init?(with pasteboard: NSPasteboard) {
        guard let item = pasteboard.pasteboardItems?.first else { return nil }
        
        let app = NSWorkspace.shared.frontmostApplication
        guard let type = item.availableType(from: PasteboardType.supportedTypes) else { return nil }
        
        log.debug("Creating item with type: \(type.rawValue)")
        
        var content: Data?
        if type.isFile() {
            // 使用 propertyList 替代 readObjects 以避免 NSSecureCoding 问题
            // readObjects(forClasses:) 会触发 NSXPCDecoder 警告
            var filePaths: [String] = []

            // 方法 1: 从 propertyList 读取 (避免 NSSecureCoding)
            if let urlStrings = pasteboard.propertyList(forType: .fileURL) as? [String] {
                filePaths = urlStrings.compactMap { URL(string: $0)?.path }
            } else if let urlString = pasteboard.propertyList(forType: .fileURL) as? String,
                      let url = URL(string: urlString) {
                filePaths = [url.path]
            } else if let data = item.data(forType: .fileURL),
                      let urlString = String(data: data, encoding: .utf8) {
                // 方法 2: 从 data 解析
                filePaths = urlString.components(separatedBy: "\n")
                    .compactMap { URL(string: $0)?.path }
                    .filter { !$0.isEmpty }
            }

            guard !filePaths.isEmpty else { return nil }

            log.debug("File paths: \(filePaths)")
            let filePathsString = filePaths.joined(separator: "\n")
            content = filePathsString.data(using: .utf8) ?? Data()
        } else {
            content = item.data(forType: type)
        }
        
        guard let content = content else { return nil }
        
        var previewData: Data?
        var attributedString = NSAttributedString()
        
        if type.isText() {
            attributedString = NSAttributedString(with: content, type: type) ?? NSAttributedString()
            guard !attributedString.string.allSatisfy(\.isWhitespace) else { return nil }
            
            let previewAttr = attributedString.length > 250
                ? attributedString.attributedSubstring(from: NSMakeRange(0, 250))
                : attributedString
            previewData = previewAttr.toData(with: type)
        }
        
        // 对于文本类型，使用字符长度；对于图片/文件，使用数据字节大小
        let length = type.isText() ? attributedString.length : content.count

        self.init(
            pasteboardType: type,
            data: content,
            previewData: previewData,
            timestamp: Int64(Date().timeIntervalSince1970),
            appPath: app?.bundleURL?.path ?? "",
            appName: app?.localizedName ?? "",
            searchText: attributedString.string,
            contentLength: length,
            tagId: -1
        )
    }
    
    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "bmp", "tiff", "tif", "heic", "heif", "webp", "ico", "icns", "raw", "cr2", "nef", "arw"
    ]

    private static let pdfExtensions: Set<String> = ["pdf"]
    private static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd"]

    /// 检查文件是否为 PDF
    var isPDF: Bool {
        guard itemType == .file, let paths = filePaths, let firstPath = paths.first else { return false }
        let ext = (firstPath as NSString).pathExtension.lowercased()
        return Self.pdfExtensions.contains(ext)
    }

    /// 获取第一个 PDF 文件路径
    var firstPDFPath: String? {
        guard isPDF, let paths = filePaths else { return nil }
        return paths.first
    }

    /// 检查文件是否为 Markdown
    var isMarkdownFile: Bool {
        guard itemType == .file, let paths = filePaths, let firstPath = paths.first else { return false }
        let ext = (firstPath as NSString).pathExtension.lowercased()
        return Self.markdownExtensions.contains(ext)
    }

    /// 获取第一个 Markdown 文件路径
    var firstMarkdownPath: String? {
        guard isMarkdownFile, let paths = filePaths else { return nil }
        return paths.first
    }
    
    private func detectItemType() -> ClipItemType {
        log.debug("detectItemType for pasteboardType: \(pasteboardType.rawValue)")
        
        switch pasteboardType {
        case .png, .tiff:
            log.debug("Detected as image (png/tiff)")
            return .image
        case .fileURL:
            // Ensure cachedFilePaths is initialized
            if cachedFilePaths == nil {
                if let urlString = String(data: data, encoding: .utf8) {
                    cachedFilePaths = urlString.components(separatedBy: "\n").filter { !$0.isEmpty }
                }
            }
            // Check if files are images
            if let paths = cachedFilePaths, !paths.isEmpty {
                log.debug("Checking file paths for image extensions: \(paths)")
                let allImages = paths.allSatisfy { path in
                    let ext = (path as NSString).pathExtension.lowercased()
                    let isImage = Self.imageExtensions.contains(ext)
                    return isImage
                }
                if allImages {
                    log.debug("All files are images, returning .image")
                    return .image
                }
            }
            log.debug("Returning .file")
            return .file
        case .rtf, .rtfd:
            return .richText
        case .string:
            let text = String(data: data, encoding: .utf8) ?? ""
            if text.isHexColor { return .color }
            if text.asCompleteURL() != nil { return .url }
            if text.isCodeSnippet { return .code }
            return .text
        default:
            return .text
        }
    }
    
    private static let maxThumbnailSize: CGFloat = 400
    private static let maxImageDataSize: Int = 100 * 1024 * 1024 // 100MB limit for direct loading

    @ObservationIgnored
    private var cachedPDFThumbnail: NSImage?

    /// 使用 QLThumbnailGenerator 生成 PDF 首页缩略图 (卡片界面使用)
    func pdfThumbnail(size: CGSize = CGSize(width: 400, height: 400), completion: @escaping (NSImage?) -> Void) {
        // 返回缓存
        if let cached = cachedPDFThumbnail {
            completion(cached)
            return
        }

        guard let pdfPath = firstPDFPath else {
            completion(nil)
            return
        }

        let url = URL(fileURLWithPath: pdfPath)
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: size,
            scale: NSScreen.main?.backingScaleFactor ?? 2.0,
            representationTypes: .thumbnail
        )

        QLThumbnailGenerator.shared.generateRepresentations(for: request) { [weak self] thumbnail, _, error in
            DispatchQueue.main.async {
                if let thumbnail = thumbnail {
                    let image = thumbnail.nsImage
                    self?.cachedPDFThumbnail = image
                    completion(image)
                } else {
                    log.debug("PDF thumbnail generation failed: \(error?.localizedDescription ?? "unknown")")
                    // Fallback: 使用系统文件图标
                    let icon = NSWorkspace.shared.icon(forFile: pdfPath)
                    icon.size = NSSize(width: size.width, height: size.height)
                    self?.cachedPDFThumbnail = icon
                    completion(icon)
                }
            }
        }
    }

    /// 同步获取 PDF 缩略图（如果已缓存）
    func cachedPDFThumbnailImage() -> NSImage? {
        return cachedPDFThumbnail
    }
    
    func thumbnail() -> NSImage? {
        if let cached = cachedThumbnail { return cached }
        guard itemType == .image else { return nil }
        
        // For file-based images
        if pasteboardType == .fileURL, let paths = cachedFilePaths, let path = paths.first {
            cachedThumbnail = generateThumbnailFromFile(path: path)
            return cachedThumbnail
        }
        
        // For pasteboard images (png, tiff)
        guard pasteboardType.isImage() else { return nil }
        
        if let previewData, let image = NSImage(data: previewData) {
            cachedThumbnail = image
            return cachedThumbnail
        }
        
        // Safety check for large data
        guard let payload = resolvedData() else { return nil }
        if payload.count > Self.maxImageDataSize {
            cachedThumbnail = generateSafeThumbnailFromData()
            return cachedThumbnail
        }
        
        cachedThumbnail = NSImage(data: payload)
        return cachedThumbnail
    }
    
    private func generateThumbnailFromFile(path: String) -> NSImage? {
        let url = URL(fileURLWithPath: path)
        
        // First try: Use QuickLook thumbnail generator
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Self.maxThumbnailSize
        ]
        
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        }
        
        // Fallback 1: Try NSImage directly
        if let image = NSImage(contentsOf: url)?.resizedSafely(maxSize: Self.maxThumbnailSize) {
            return image
        }
        
        // Fallback 2: Use system file icon (always works in sandbox)
        let icon = NSWorkspace.shared.icon(forFile: path)
        icon.size = NSSize(width: Self.maxThumbnailSize, height: Self.maxThumbnailSize)
        return icon
    }
    
    private func generateSafeThumbnailFromData() -> NSImage? {
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Self.maxThumbnailSize
        ]

        guard let payload = resolvedData(),
              let source = CGImageSourceCreateWithData(payload as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    /// 为大图预生成缩略图数据（用于存入数据库的 previewData）
    /// 在数据写入时调用，避免读取时解码大图
    static func generatePreviewThumbnailData(from imageData: Data, maxSize: CGFloat = 200) -> Data? {
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSize
        ]

        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        // Convert CGImage to PNG data
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        return bitmapRep.representation(using: .png, properties: [:])
    }

    /// 异步生成预览缩略图数据
    static func generatePreviewThumbnailDataAsync(from imageData: Data, maxSize: CGFloat = 200) async -> Data? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let result = generatePreviewThumbnailData(from: imageData, maxSize: maxSize)
                continuation.resume(returning: result)
            }
        }
    }
    
    func imageSize() -> CGSize? {
        if let cached = cachedImageSize { return cached }
        guard itemType == .image else { return nil }
        
        var source: CGImageSource?
        if pasteboardType == .fileURL, let paths = cachedFilePaths, let path = paths.first {
            let url = URL(fileURLWithPath: path)
            source = CGImageSourceCreateWithURL(url as CFURL, nil)
        } else if pasteboardType.isImage(), let payload = resolvedData() {
            source = CGImageSourceCreateWithData(payload as CFData, nil)
        }
        
        guard let source = source,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return nil
        }
        
        guard let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight] as? CGFloat else {
            return nil
        }
        
        let dpi = properties[kCGImagePropertyDPIWidth] as? CGFloat ?? 72.0
        let scale = dpi / 72.0
        let size = CGSize(width: width / scale, height: height / scale)
        cachedImageSize = size
        return size
    }
    
    func updateTag(_ newTagId: Int) {
        tagId = newTagId
    }
    
    func updateTimestamp() {
        timestamp = Int64(Date().timeIntervalSince1970)
    }
    
    func displayDescription() -> String {
        switch itemType {
        case .image:
            if let size = imageSize() {
                return "\(Int(size.width)) × \(Int(size.height))"
            }
            return "图片"
        case .text, .richText, .code:
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            return "\(formatter.string(from: NSNumber(value: contentLength)) ?? "\(contentLength)") 个字符"
        case .file:
            guard let paths = filePaths else { return "文件" }
            return paths.count > 1 ? "\(paths.count) 个文件" : (URL(fileURLWithPath: paths.first ?? "").lastPathComponent)
        case .url:
            return String(data: data, encoding: .utf8) ?? "链接"
        case .color:
            return String(data: data, encoding: .utf8) ?? "颜色"
        }
    }
    
    func previewText(maxCharacters: Int = Const.maxPreviewBodyLength) -> (text: String, isTruncated: Bool) {
        guard searchText.count > maxCharacters else {
            return (searchText, false)
        }
        return (String(searchText.prefix(maxCharacters)) + "\n...", true)
    }
    
    /// 获取完整数据：若存在外部文件则优先读文件（自动解密），否则返回内存数据
    func resolvedData() -> Data? {
        if let blobPath, FileManager.default.fileExists(atPath: blobPath) {
            // 使用 BlobStorage.load() 自动处理解密
            return BlobStorage.shared.load(path: blobPath)
        }
        return data
    }
    
    var smartAnalysis: SmartTextService.DetectionResult {
        if let cachedSmartAnalysis {
            return cachedSmartAnalysis
        }
        let result = SmartTextService.shared.analyze(analysisSample)
        cachedSmartAnalysis = result
        return result
    }
    
    var detectedCodeLanguage: SmartTextService.CodeLanguage? {
        smartAnalysis.codeLanguage
    }
    
    var isMarkdown: Bool {
        if let cachedIsMarkdown {
            return cachedIsMarkdown
        }
        let detected = SmartTextService.shared.isMarkdown(analysisSample)
        cachedIsMarkdown = detected
        return detected
    }

    /// 即时计算结果（如果文本是数学表达式）
    var calculationResult: SmartTextService.CalculationResult? {
        // 检查设置是否开启
        guard DeckUserDefaults.instantCalculation else {
            return nil
        }
        if calculationResultChecked {
            return cachedCalculationResult
        }
        // 只对文本类型且长度合适的内容进行计算
        guard itemType == .text || itemType == .code else {
            calculationResultChecked = true
            return nil
        }
        cachedCalculationResult = SmartTextService.shared.detectAndCalculate(searchText)
        calculationResultChecked = true
        return cachedCalculationResult
    }

    var hasSmartContent: Bool {
        let analysis = smartAnalysis
        return !analysis.emails.isEmpty ||
               !analysis.phones.isEmpty ||
               analysis.codeLanguage != nil ||
               isMarkdown ||
               calculationResult != nil
    }
    
    static func == (lhs: ClipboardItem, rhs: ClipboardItem) -> Bool {
        lhs.uniqueId == rhs.uniqueId && lhs.id == rhs.id
    }
}

// MARK: - NSItemProvider support

extension ClipboardItem {
    func itemProvider() -> NSItemProvider {
        let provider = NSItemProvider()
        
        switch itemType {
        case .text, .code, .url, .color:
            if let str = String(data: data, encoding: .utf8) {
                return NSItemProvider(object: str as NSString)
            }
        case .richText:
            provider.registerDataRepresentation(forTypeIdentifier: pasteboardType.rawValue, visibility: .all) { [weak self] completion in
                guard let data = self?.resolvedData() else {
                    completion(nil, nil)
                    return nil
                }
                DispatchQueue.global(qos: .userInitiated).async {
                    completion(data, nil)
                }
                return nil
            }
        case .image:
            provider.registerDataRepresentation(forTypeIdentifier: pasteboardType.rawValue, visibility: .all) { [weak self] completion in
                guard let data = self?.resolvedData() else {
                    completion(nil, nil)
                    return nil
                }
                DispatchQueue.global(qos: .userInitiated).async {
                    completion(data, nil)
                }
                return nil
            }
            provider.suggestedName = appName + "-" + timestamp.formattedDate()
        case .file:
            if let paths = filePaths {
                for path in paths {
                    let fileURL = URL(fileURLWithPath: path)
                    let typeId = UTType(filenameExtension: fileURL.pathExtension)?.identifier ?? UTType.data.identifier
                    provider.registerFileRepresentation(forTypeIdentifier: typeId, fileOptions: [], visibility: .all) { completion in
                        DispatchQueue.global(qos: .userInitiated).async {
                            if FileManager.default.fileExists(atPath: path) {
                                completion(fileURL, true, nil)
                            } else {
                                let error = NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError)
                                completion(nil, false, error)
                            }
                        }
                        return nil
                    }
                }
                if paths.count == 1 {
                    provider.suggestedName = URL(fileURLWithPath: paths[0]).lastPathComponent
                }
            }
        }
        
        return provider
    }
}
