//
//  AppLogger.swift
//  Deck
//
//  Deck Clipboard Manager - Logging System
//

import Foundation
import os.log

extension DateFormatter {
    static let logFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()
    
    static let fileFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

enum LogLevel: String, CaseIterable, Comparable {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARNING"
    case error = "ERROR"
    
    var osLogType: OSLogType {
        switch self {
        case .debug: return .debug
        case .info: return .info
        case .warning: return .default
        case .error: return .error
        }
    }
    
    var priority: Int {
        switch self {
        case .debug: return 0
        case .info: return 1
        case .warning: return 2
        case .error: return 3
        }
    }
    
    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.priority < rhs.priority
    }
}

final class AppLogger {
    static let shared = AppLogger()
    
    private let osLogger: os.Logger
    private let logQueue = DispatchQueue(label: "com.deck.logger", qos: .utility)
    private nonisolated(unsafe) var logFileURL: URL?
    
    #if DEBUG
    var minimumLogLevel: LogLevel = .debug
    #else
    var minimumLogLevel: LogLevel = .info
    #endif
    
    private init() {
        osLogger = os.Logger(subsystem: "com.deck.clipboard", category: "AppLogger")
        setupLogFile()
    }
    
    // MARK: - Public Logging Methods
    
    func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .debug, file: file, function: function, line: line)
    }
    
    func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .info, file: file, function: function, line: line)
    }
    
    func warn(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .warning, file: file, function: function, line: line)
    }
    
    func error(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .error, file: file, function: function, line: line)
    }
    
    // MARK: - Private Implementation
    
    private func log(_ message: String, level: LogLevel, file: String, function: String, line: Int) {
        guard level >= minimumLogLevel else { return }
        
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        let timestamp = DateFormatter.logFormatter.string(from: Date())
        
        #if DEBUG
        let consoleMessage = "[\(level.rawValue)] [\(fileName):\(line)] \(message)"
        print("\(timestamp) \(consoleMessage)")
        #else
        let logMessage = "[\(fileName):\(line)] \(function) - \(message)"
        writeToFile(logMessage, level: level)
        if level == .error {
            osLogger.error("\(logMessage)")
        }
        #endif
    }
    
    // MARK: - File Management
    
    private func setupLogFile() {
        #if !DEBUG
        createLogFileURL()
        #endif
    }
    
    private func createLogFileURL() {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { return }
        
        let appDir = appSupport.appendingPathComponent("Deck")
        let logsDir = appDir.appendingPathComponent("Logs")
        
        do {
            try FileManager.default.createDirectory(
                at: logsDir,
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            osLogger.error("Failed to create logs directory: \(error.localizedDescription)")
            return
        }
        
        let logFileName = "Deck-\(DateFormatter.fileFormatter.string(from: Date())).log"
        logFileURL = logsDir.appendingPathComponent(logFileName)
        
        cleanOldLogFiles(in: logsDir)
    }
    
    private func writeToFile(_ message: String, level: LogLevel) {
        logQueue.async { [weak self] in
            guard let self = self, let logURL = self.logFileURL else { return }
            
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let logEntry = "[\(timestamp)] [\(level.rawValue)] \(message)\n"
            
            guard let data = logEntry.data(using: .utf8) else { return }
            
            if FileManager.default.fileExists(atPath: logURL.path) {
                do {
                    let fileHandle = try FileHandle(forWritingTo: logURL)
                    defer { fileHandle.closeFile() }
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                } catch {
                    self.osLogger.error("Failed to write to log file: \(error.localizedDescription)")
                }
            } else {
                do {
                    try data.write(to: logURL)
                } catch {
                    self.osLogger.error("Failed to create log file: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func cleanOldLogFiles(in directory: URL) {
        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.creationDateKey],
                options: []
            )
            let logFiles = files.filter { $0.pathExtension == "log" }
            
            let calendar = Calendar.current
            let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()
            
            for file in logFiles {
                if let creationDate = try file.resourceValues(forKeys: [.creationDateKey]).creationDate,
                   creationDate < sevenDaysAgo {
                    try FileManager.default.removeItem(at: file)
                    osLogger.info("Removed old log file: \(file.lastPathComponent)")
                }
            }
        } catch {
            osLogger.error("Failed to clean old log files: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Static Helpers
    
    static func setMinimumLogLevel(_ level: LogLevel) {
        shared.minimumLogLevel = level
    }
    
    static func getMinimumLogLevel() -> LogLevel {
        shared.minimumLogLevel
    }
    
    static func getLogFileURL() -> URL? {
        shared.logFileURL
    }
    
    static func getAllLogFiles() -> [URL] {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { return [] }
        
        let logsDir = appSupport.appendingPathComponent("Deck/Logs")
        
        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: logsDir,
                includingPropertiesForKeys: nil,
                options: []
            )
            return files.filter { $0.pathExtension == "log" }.sorted {
                $0.lastPathComponent > $1.lastPathComponent
            }
        } catch {
            return []
        }
    }
}

let log = AppLogger.shared
