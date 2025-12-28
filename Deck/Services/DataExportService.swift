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
    
    private init() {
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
    
    struct ExportData: Codable {
        let version: Int
        let exportDate: Date
        let items: [ExportItem]
    }
    
    struct ExportItem: Codable {
        let uniqueId: String
        let type: String
        let itemType: String
        let data: Data
        let previewData: Data?
        let timestamp: Int64
        let appPath: String
        let appName: String
        let searchText: String
        let contentLength: Int
        let tagId: Int
        // 标记是否为大图（用于导入时重建 blob）
        let isLargeBlob: Bool?
    }
    
    // MARK: - Export
    
    func exportData(completion: @escaping (Result<URL, Error>) -> Void) {
        Task {
            // Check if security mode is enabled - require authentication
            let isSecurityMode = DeckUserDefaults.securityModeEnabled
            if isSecurityMode {
                let authenticated = await SecurityService.shared.authenticate(reason: "验证身份以导出数据")
                guard authenticated else {
                    await MainActor.run {
                        completion(.failure(ExportError.authenticationFailed))
                    }
                    return
                }
            }
            
            // 清理之前可能残留的临时文件
            cleanupTempFile()
            
            do {
                // 使用安全的临时目录（应用私有目录）
                let tempDir = getSecureTempDirectory()
                let fileName = "Deck_Export_\(formatDate(Date())).json"
                let tempURL = tempDir.appendingPathComponent(fileName)
                
                // 记录当前临时文件以便清理
                currentExportTempURL = tempURL
                
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                
                let dateString = ISO8601DateFormatter().string(from: Date())
                let header = #"{"version":1,"exportDate":""# + dateString + #""# + #","items":["#
                try header.data(using: .utf8)?.write(to: tempURL)
                
                // 设置文件保护属性（仅限 macOS 具有此功能时）
                try? FileManager.default.setAttributes(
                    [.protectionKey: FileProtectionType.complete],
                    ofItemAtPath: tempURL.path
                )
                
                let handle = try FileHandle(forWritingTo: tempURL)
                try handle.seekToEnd()
                
                var offset = 0
                let batchSize = 500
                var isFirst = true
                
                while true {
                    let batch = DeckSQLManager.shared.fetchAll(limit: batchSize, offset: offset, loadFullData: true)
                    if batch.isEmpty { break }

                    for item in batch {
                        // 使用 resolvedData() 获取完整数据（包括 offload 到文件的大图）
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
                            searchText: item.searchText,
                            contentLength: item.contentLength,
                            tagId: item.tagId,
                            isLargeBlob: isLargeBlob
                        )
                        let data = try encoder.encode(exportItem)
                        if !isFirst {
                            handle.write(Data([UInt8(ascii: ",")]))
                        }
                        handle.write(data)
                        isFirst = false
                    }

                    offset += batch.count
                    if batch.count < batchSize { break }
                }
                
                handle.write(Data([UInt8(ascii: "]"), UInt8(ascii: "}")]))
                try handle.close()
                
                await MainActor.run {
                    completion(.success(tempURL))
                }
            } catch {
                // 出错时清理临时文件
                cleanupTempFile()
                await MainActor.run {
                    completion(.failure(error))
                }
            }
        }
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
                // 检查文件大小，对于大文件使用内存映射减少复制
                let fileSize = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64 ?? 0
                let isLargeFile = fileSize > 50 * 1024 * 1024  // > 50MB

                let data: Data
                if isLargeFile {
                    // 使用内存映射读取大文件
                    data = try Data(contentsOf: url, options: .mappedIfSafe)
                    log.info("Importing large file (\(fileSize / 1024 / 1024) MB) using memory-mapped IO")
                } else {
                    data = try Data(contentsOf: url)
                }

                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let exportData = try decoder.decode(ExportData.self, from: data)

                // 批量导入并显示进度
                var importedCount = 0
                let totalCount = exportData.items.count
                let batchSize = 50

                for (index, exportItem) in exportData.items.enumerated() {
                    // 对于大图，insert 方法会自动处理 blob offload
                    let item = ClipboardItem(
                        pasteboardType: PasteboardType(exportItem.type),
                        data: exportItem.data,
                        previewData: exportItem.previewData,
                        timestamp: exportItem.timestamp,
                        appPath: exportItem.appPath,
                        appName: exportItem.appName,
                        searchText: exportItem.searchText,
                        contentLength: exportItem.contentLength,
                        tagId: exportItem.tagId,
                        uniqueId: exportItem.uniqueId
                    )

                    _ = await DeckSQLManager.shared.insert(item: item)
                    importedCount += 1

                    // 每批次后让出执行，避免长时间阻塞
                    if (index + 1) % batchSize == 0 {
                        await Task.yield()
                        log.debug("Import progress: \(importedCount)/\(totalCount)")
                    }
                }

                // Reload data
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
        // Export to temp first, then let user choose location
        exportData { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let tempURL):
                    self?.showSavePanel(tempURL: tempURL)
                    
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
    
    private func showSavePanel(tempURL: URL) {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.json]
        savePanel.nameFieldStringValue = "Deck_Export_\(formatDate(Date())).json"
        savePanel.canCreateDirectories = true
        savePanel.title = "导出剪贴板历史"
        savePanel.message = "选择保存位置"
        
        savePanel.begin { [weak self] response in
            defer {
                // 无论成功或取消，都清理临时文件
                self?.cleanupTempFile()
            }
            
            guard response == .OK, let targetURL = savePanel.url else {
                return
            }
            
            do {
                if FileManager.default.fileExists(atPath: targetURL.path) {
                    try FileManager.default.removeItem(at: targetURL)
                }
                try FileManager.default.moveItem(at: tempURL, to: targetURL)
                
                // 移动成功后清空记录（文件已不在临时位置）
                self?.currentExportTempURL = nil
                
                NSWorkspace.shared.selectFile(targetURL.path, inFileViewerRootedAtPath: targetURL.deletingLastPathComponent().path)
                
                let alert = NSAlert()
                alert.messageText = "导出成功"
                alert.informativeText = "已导出 \(DeckDataStore.shared.items.count) 条记录"
                alert.alertStyle = .informational
                alert.runModal()
            } catch {
                let alert = NSAlert()
                alert.messageText = "导出失败"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning
                alert.runModal()
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
