//
//  DataExportService.swift
//  Deck
//
//  Deck Clipboard Manager
//

import Foundation
import AppKit
import UniformTypeIdentifiers

final class DataExportService {
    static let shared = DataExportService()
    
    /// 当前正在导出的临时文件 URL（用于清理）
    private var currentExportTempURL: URL?
    /// 最近一次导出的记录数量（用于提示）
    private var lastExportedCount: Int = 0
    
    private init() {
        cleanupExportTempDirectory()
        // 注册应用终止通知，确保清理临时文件
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.cleanupTempFile()
        }
    }
    
    deinit {
        cleanupTempFile()
    }
    
    /// 清理临时文件
    private func cleanupTempFile() {
        guard let url = currentExportTempURL else { return }
        try? FileManager.default.removeItem(at: url)
        currentExportTempURL = nil
        log.debug("Cleaned up export temp file")
    }

    /// 启动时清理可能残留的导出临时目录
    private func cleanupExportTempDirectory() {
        guard let containerURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }
        let privateTempDir = containerURL.appendingPathComponent("Deck/ExportTemp", isDirectory: true)
        guard FileManager.default.fileExists(atPath: privateTempDir.path) else { return }
        let contents = (try? FileManager.default.contentsOfDirectory(at: privateTempDir, includingPropertiesForKeys: nil)) ?? []
        for url in contents {
            try? FileManager.default.removeItem(at: url)
        }
    }
    
    /// 获取安全的临时目录（优先使用应用私有目录）
    private func getSecureTempDirectory() -> URL {
        // 优先使用应用私有的临时目录
        if let containerURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let privateTempDir = containerURL.appendingPathComponent("Deck/ExportTemp", isDirectory: true)
            try? FileManager.default.createDirectory(at: privateTempDir, withIntermediateDirectories: true)
            return privateTempDir
        }
        // 回退到系统临时目录
        return FileManager.default.temporaryDirectory
    }
    
    // MARK: - Export Format
    
    nonisolated struct ExportData: Codable, Sendable {
        let version: Int
        let exportDate: Date
        let items: [ExportItem]
    }
    
    nonisolated struct ExportItem: Codable, Sendable {
        let uniqueId: String
        let type: String
        let itemType: String
        let data: Data
        let previewData: Data?
        let timestamp: Int64
        let appPath: String
        let appName: String
        let sourceAnchor: SourceAnchor?
        let searchText: String
        let contentLength: Int
        let tagId: Int
        let isTemporary: Bool?
        // 标记是否为大图（用于导入时重建 blob）
        let isLargeBlob: Bool?
    }
    
    // MARK: - Export
    
    func exportData(completion: @escaping (Result<URL, Error>) -> Void) {
        exportDataInternal(targetURL: nil, completion: completion)
    }

    func exportData(to targetURL: URL, completion: @escaping (Result<URL, Error>) -> Void) {
        exportDataInternal(targetURL: targetURL, completion: completion)
    }

    private func exportDataInternal(targetURL: URL?, completion: @escaping (Result<URL, Error>) -> Void) {
        Task { @MainActor in
            let isSecurityMode = DeckUserDefaults.securityModeEnabled
            if isSecurityMode {
                let authenticated = await SecurityService.shared.authenticate(reason: "验证身份以导出数据")
                guard authenticated else {
                    completion(.failure(ExportError.authenticationFailed))
                    return
                }
            }

            // 清理之前可能残留的临时文件
            cleanupTempFile()

            do {
                let outputURL: URL
                if let targetURL {
                    outputURL = targetURL
                    if FileManager.default.fileExists(atPath: targetURL.path) {
                        try FileManager.default.removeItem(at: targetURL)
                    }
                } else {
                    let tempDir = getSecureTempDirectory()
                    let fileName = "Deck_Export_\(formatDate(Date())).json"
                    let tempURL = tempDir.appendingPathComponent(fileName)
                    outputURL = tempURL
                    currentExportTempURL = tempURL
                }

                let exportedCount = try await Task.detached(priority: .utility) {
                    try await Self.exportLargeDataset(to: outputURL)
                }.value

                lastExportedCount = exportedCount
                completion(.success(outputURL))
            } catch {
                if targetURL == nil, let tempURL = currentExportTempURL {
                    try? FileManager.default.removeItem(at: tempURL)
                    currentExportTempURL = nil
                } else if let targetURL {
                    try? FileManager.default.removeItem(at: targetURL)
                }
                lastExportedCount = 0
                completion(.failure(error))
            }
        }
    }

    private static func exportLargeDataset(to outputURL: URL) async throws -> Int {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let dateString = ISO8601DateFormatter().string(from: Date())
        let header = #"{"version":1,"exportDate":""# + dateString + #""# + #","items":["#
        guard let headerData = header.data(using: .utf8) else {
            throw ExportError.invalidFormat
        }
        try headerData.write(to: outputURL)

        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: outputURL.path
        )

        let handle = try FileHandle(forWritingTo: outputURL)
        defer { try? handle.close() }
        try handle.seekToEnd()

        let batchSize = 500
        var isFirst = true
        var exportedCount = 0
        var cursorTimestamp: Int64?
        var cursorId: Int64?

        while true {
            let batch = await DeckSQLManager.shared.fetchAllBeforeCursor(
                limit: batchSize,
                beforeTimestamp: cursorTimestamp,
                beforeId: cursorId,
                loadFullData: true
            )
            if batch.isEmpty { break }

            for item in batch {
                let fullData = item.resolvedData() ?? item.data
                let isLargeBlob = item.blobPath != nil

                let exportItem = ExportItem(
                    uniqueId: item.uniqueId,
                    type: item.pasteboardType.rawValue,
                    itemType: item.itemType.rawValue,
                    data: fullData,
                    previewData: item.previewData,
                    timestamp: item.timestamp,
                    appPath: item.appPath,
                    appName: item.appName,
                    sourceAnchor: item.sourceAnchor,
                    searchText: item.searchText,
                    contentLength: item.contentLength,
                    tagId: item.tagId,
                    isTemporary: item.isTemporary,
                    isLargeBlob: isLargeBlob
                )
                let data = try encoder.encode(exportItem)
                if !isFirst {
                    try handle.write(contentsOf: Data([UInt8(ascii: ",")]))
                }
                try handle.write(contentsOf: data)
                isFirst = false
                exportedCount += 1
            }

            if batch.count < batchSize { break }

            guard let last = batch.last, let lastId = last.id else { break }
            cursorTimestamp = last.timestamp
            cursorId = lastId
        }

        try handle.write(contentsOf: Data([UInt8(ascii: "]"), UInt8(ascii: "}")]))
        return exportedCount
    }
    
    // MARK: - Import
    
    func importData(from url: URL, completion: @escaping (Result<Int, Error>) -> Void) {
        Task {
            // Check if security mode is enabled - require authentication
            if DeckUserDefaults.securityModeEnabled {
                let authenticated = await SecurityService.shared.authenticate(reason: "验证身份以导入数据")
                guard authenticated else {
                    await MainActor.run {
                        completion(.failure(ExportError.authenticationFailed))
                    }
                    return
                }
            }

            do {
                let importedCount = try await Task.detached(priority: .utility) {
                    // 检查文件大小，对于大文件使用内存映射减少复制
                    let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
                    let fileSize = (attrs[.size] as? NSNumber)?.int64Value ?? (attrs[.size] as? Int64) ?? 0
                    let isLargeFile = fileSize > 50 * 1024 * 1024  // > 50MB

                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .iso8601
                    
                    if isLargeFile {
                        await log.info("Importing large file (\(fileSize / 1024 / 1024) MB) using streaming parser")
                        return try await Self.importLargeExport(from: url, decoder: decoder)
                    }

                    let data = try Data(contentsOf: url)
                    let exportData = try decoder.decode(ExportData.self, from: data)

                    // 批量导入并显示进度
                    var importedCount = 0
                    let totalCount = exportData.items.count
                    let batchSize = 50

                    for (index, exportItem) in exportData.items.enumerated() {
                        await Self.insertExportItem(exportItem)
                        importedCount += 1

                        // 每批次后让出执行，避免长时间阻塞
                        if (index + 1) % batchSize == 0 {
                            await Task.yield()
                            await log.debug("Import progress: \(importedCount)/\(totalCount)")
                        }
                    }

                    return importedCount
                }.value

                await DeckDataStore.shared.loadInitialData()

                await MainActor.run {
                    completion(.success(importedCount))
                }
            } catch {
                await MainActor.run {
                    completion(.failure(error))
                }
            }
        }
    }

    nonisolated private static func importLargeExport(from url: URL, decoder: JSONDecoder) async throws -> Int {
        enum ParseState {
            case seekingItemsKey
            case seekingArrayStart
            case readingItems
            case done
        }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let itemsKey = Data(#""items""#.utf8)
        let openBrace = UInt8(ascii: "{")
        let closeBrace = UInt8(ascii: "}")
        let openBracket = UInt8(ascii: "[")
        let closeBracket = UInt8(ascii: "]")
        let quote = UInt8(ascii: "\"")
        let backslash = UInt8(ascii: "\\")

        let chunkSize = 64 * 1024
        let maxObjectBytes = 200 * 1024 * 1024
        let batchSize = 50

        var buffer = Data()
        var state: ParseState = .seekingItemsKey
        var objectBuffer = Data()
        var inString = false
        var isEscaped = false
        var depth = 0
        var importedCount = 0
        var reachedEOF = false

        while !reachedEOF || !buffer.isEmpty {
            if !reachedEOF && buffer.count < chunkSize {
                let chunk = try handle.read(upToCount: chunkSize) ?? Data()
                if chunk.isEmpty {
                    reachedEOF = true
                } else {
                    buffer.append(chunk)
                }
            }

            var madeProgress = false

            switch state {
            case .seekingItemsKey:
                if let range = buffer.range(of: itemsKey) {
                    let removeCount = buffer.distance(from: buffer.startIndex, to: range.upperBound)
                    buffer.removeFirst(removeCount)
                    state = .seekingArrayStart
                    madeProgress = true
                } else if buffer.count > itemsKey.count {
                    buffer = buffer.suffix(itemsKey.count - 1)
                    madeProgress = true
                }

            case .seekingArrayStart:
                if let idx = buffer.firstIndex(of: openBracket) {
                    let removeCount = buffer.distance(from: buffer.startIndex, to: idx) + 1
                    buffer.removeFirst(removeCount)
                    state = .readingItems
                    madeProgress = true
                } else if buffer.count > 1 {
                    buffer = buffer.suffix(1)
                    madeProgress = true
                }

            case .readingItems:
                var cursor = 0
                while cursor < buffer.count {
                    let byte = buffer[cursor]
                    if depth == 0 {
                        if byte == openBrace {
                            depth = 1
                            inString = false
                            isEscaped = false
                            objectBuffer.removeAll(keepingCapacity: true)
                            objectBuffer.append(byte)
                            if objectBuffer.count > maxObjectBytes { throw ExportError.invalidFormat }
                        } else if byte == closeBracket {
                            state = .done
                            cursor += 1
                            break
                        }
                    } else {
                        objectBuffer.append(byte)
                        if objectBuffer.count > maxObjectBytes { throw ExportError.invalidFormat }
                        if inString {
                            if isEscaped {
                                isEscaped = false
                            } else if byte == backslash {
                                isEscaped = true
                            } else if byte == quote {
                                inString = false
                            }
                        } else {
                            if byte == quote {
                                inString = true
                            } else if byte == openBrace {
                                depth += 1
                            } else if byte == closeBrace {
                                depth -= 1
                                if depth == 0 {
                                    let exportItem = try decoder.decode(ExportItem.self, from: objectBuffer)
                                    await Self.insertExportItem(exportItem)
                                    importedCount += 1

                                    if importedCount % batchSize == 0 {
                                        await Task.yield()
                                        await log.debug("Import progress: \(importedCount)")
                                    }

                                    objectBuffer.removeAll(keepingCapacity: true)
                                }
                            }
                        }
                    }
                    cursor += 1
                }

                if cursor > 0 {
                    buffer.removeFirst(cursor)
                    madeProgress = true
                }

            case .done:
                break
            }

            if state == .done {
                break
            }

            if reachedEOF && !madeProgress {
                break
            }
        }

        if state != .done || depth != 0 {
            throw ExportError.invalidFormat
        }

        return importedCount
    }

    private static func insertExportItem(_ exportItem: ExportItem) async {
        // 对于大图，insert 方法会自动处理 blob offload
        let item = ClipboardItem(
            pasteboardType: PasteboardType(exportItem.type),
            data: exportItem.data,
            previewData: exportItem.previewData,
            timestamp: exportItem.timestamp,
            appPath: exportItem.appPath,
            appName: exportItem.appName,
            sourceAnchor: exportItem.sourceAnchor,
            searchText: exportItem.searchText,
            contentLength: exportItem.contentLength,
            tagId: exportItem.tagId,
            isTemporary: exportItem.isTemporary ?? false,
            uniqueId: exportItem.uniqueId
        )

        _ = await DeckSQLManager.shared.insert(item: item)
    }
    
    // MARK: - Helpers
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        return formatter.string(from: date)
    }
    
    // MARK: - Errors
    
    enum ExportError: LocalizedError {
        case authenticationFailed
        case noData
        case invalidFormat
        
        var errorDescription: String? {
            switch self {
            case .authenticationFailed:
                return "身份验证失败"
            case .noData:
                return "没有可导出的数据"
            case .invalidFormat:
                return "文件格式无效"
            }
        }
    }
}

// MARK: - Save Panel Helper

extension DataExportService {
    func showExportPanel() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.json]
        savePanel.nameFieldStringValue = "Deck_Export_\(formatDate(Date())).json"
        savePanel.canCreateDirectories = true
        savePanel.title = "导出剪贴板历史"
        savePanel.message = "选择保存位置"
        
        savePanel.begin { [weak self] response in
            guard response == .OK, let targetURL = savePanel.url else { return }
            
            self?.exportData(to: targetURL) { [weak self] result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let url):
                        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
                        
                        let alert = NSAlert()
                        alert.messageText = "导出成功"
                        alert.informativeText = "已导出 \(self?.lastExportedCount ?? 0) 条记录"
                        alert.alertStyle = .informational
                        alert.runModal()
                        
                    case .failure(let error):
                        let alert = NSAlert()
                        alert.messageText = "导出失败"
                        alert.informativeText = error.localizedDescription
                        alert.alertStyle = .warning
                        alert.runModal()
                    }
                }
            }
        }
    }
    
    func showImportPanel() {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.json]
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.title = "导入剪贴板历史"
        openPanel.message = "选择要导入的 JSON 文件"
        
        openPanel.begin { [weak self] response in
            guard response == .OK, let url = openPanel.url else { return }
            
            self?.importData(from: url) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let count):
                        let alert = NSAlert()
                        alert.messageText = "导入成功"
                        alert.informativeText = "已导入 \(count) 条剪贴板记录"
                        alert.alertStyle = .informational
                        alert.runModal()
                        
                    case .failure(let error):
                        let alert = NSAlert()
                        alert.messageText = "导入失败"
                        alert.informativeText = error.localizedDescription
                        alert.alertStyle = .warning
                        alert.runModal()
                    }
                }
            }
        }
    }
}
