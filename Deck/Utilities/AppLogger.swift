// Copyright © 2024–2026 Yuze Pan. 保留一切权利。

//
//  AppLogger.swift
//  Deck
//
//  Deck Clipboard Manager - Logging System
//

import Foundation
import os
import os.lock

enum LogLevel: String, CaseIterable, Comparable, Sendable {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARNING"
    case error = "ERROR"

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

/// App-wide logger.
///
/// Design goals:
/// - Minimal overhead when a log is filtered out.
/// - Swift 6 friendly (no `nonisolated(unsafe)` globals, no `@unchecked Sendable`).
/// - Minimal invasive: keep existing call sites working.
final class AppLogger: Sendable {
    static let shared = AppLogger()

    private struct State: Sendable {
        var minimumLogLevel: LogLevel
        var logsDirectory: URL?
        var currentLogDay: String?
        var logFileURL: URL?
    }

    private let osLogger: Logger
    private let logQueue = DispatchQueue(label: "com.deck.logger", qos: .utility)
    private let state: OSAllocatedUnfairLock<State>

    private init() {
        self.osLogger = Logger(subsystem: "com.deck.clipboard", category: "AppLogger")

        let initialLevel: LogLevel = {
            #if DEBUG
            return .debug
            #else
            return .info
            #endif
        }()

        self.state = OSAllocatedUnfairLock(initialState: State(
            minimumLogLevel: initialLevel,
            logsDirectory: Self.resolveLogsDirectory(),
            currentLogDay: nil,
            logFileURL: nil
        ))

        #if !DEBUG
        setupLogFileIfNeeded(now: Date())
        #endif
    }

    /// Cheap check to avoid expensive work for logs that will be dropped.
    func isEnabled(_ level: LogLevel) -> Bool {
        let min = state.withLock { $0.minimumLogLevel }
        return level >= min
    }

    // MARK: - Public Logging Methods (Sync)

    func debug(
        _ message: @autoclosure () -> String,
        file: StaticString = #fileID,
        function: StaticString = #function,
        line: UInt = #line
    ) {
        log(message, level: .debug, file: file, function: function, line: line)
    }

    func info(
        _ message: @autoclosure () -> String,
        file: StaticString = #fileID,
        function: StaticString = #function,
        line: UInt = #line
    ) {
        log(message, level: .info, file: file, function: function, line: line)
    }

    func warn(
        _ message: @autoclosure () -> String,
        file: StaticString = #fileID,
        function: StaticString = #function,
        line: UInt = #line
    ) {
        log(message, level: .warning, file: file, function: function, line: line)
    }

    func error(
        _ message: @autoclosure () -> String,
        file: StaticString = #fileID,
        function: StaticString = #function,
        line: UInt = #line
    ) {
        log(message, level: .error, file: file, function: function, line: line)
    }

    // MARK: - Public Logging Methods (Async overloads)
    // These exist because the codebase already uses `await log.info(...)` in a few places.
    // Overloading by `async` keeps those call sites warning-free without changing existing sync calls.

    func debug(
        _ message: @autoclosure () -> String,
        file: StaticString = #fileID,
        function: StaticString = #function,
        line: UInt = #line
    ) async {
        log(message, level: .debug, file: file, function: function, line: line)
    }

    func info(
        _ message: @autoclosure () -> String,
        file: StaticString = #fileID,
        function: StaticString = #function,
        line: UInt = #line
    ) async {
        log(message, level: .info, file: file, function: function, line: line)
    }

    func warn(
        _ message: @autoclosure () -> String,
        file: StaticString = #fileID,
        function: StaticString = #function,
        line: UInt = #line
    ) async {
        log(message, level: .warning, file: file, function: function, line: line)
    }

    func error(
        _ message: @autoclosure () -> String,
        file: StaticString = #fileID,
        function: StaticString = #function,
        line: UInt = #line
    ) async {
        log(message, level: .error, file: file, function: function, line: line)
    }

    // MARK: - Private Implementation

    private func log(
        _ message: () -> String,
        level: LogLevel,
        file: StaticString,
        function: StaticString,
        line: UInt
    ) {
        let min = state.withLock { $0.minimumLogLevel }
        guard level >= min else { return }

        let resolvedMessage = message()
        let fileName = Self.shortFileName(file)
        let functionName = String(describing: function)

        #if DEBUG
        let timestamp = Self.timestampString(Date())
        let consoleMessage = "[\(level.rawValue)] [\(fileName):\(line)] \(resolvedMessage)"
        print("\(timestamp) \(consoleMessage)")
        #else
        let logMessage = "[\(fileName):\(line)] \(functionName) - \(resolvedMessage)"
        writeToFile(logMessage, level: level)
        if level == .error {
            osLogger.error("\(logMessage, privacy: .public)")
        }
        #endif
    }

    // MARK: - Static Helpers

    static func setMinimumLogLevel(_ level: LogLevel) {
        shared.state.withLock { $0.minimumLogLevel = level }
    }

    static func getMinimumLogLevel() -> LogLevel {
        shared.state.withLock { $0.minimumLogLevel }
    }

    static func getLogFileURL() -> URL? {
        shared.state.withLock { $0.logFileURL }
    }

    static func getAllLogFiles() -> [URL] {
        guard let logsDir = resolveLogsDirectory() else { return [] }
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

    // MARK: - File Management

    private static func resolveLogsDirectory() -> URL? {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { return nil }

        return appSupport.appendingPathComponent("Deck/Logs", isDirectory: true)
    }

    private func setupLogFileIfNeeded(now: Date) {
        #if DEBUG
        return
        #else
        let today = Self.dayString(now)
        let needsRotate = state.withLock { s in
            s.logFileURL == nil || s.currentLogDay != today
        }
        guard needsRotate else { return }

        guard let logsDir = state.withLock({ $0.logsDirectory }) else { return }
        do {
            try FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        } catch {
            osLogger.error("Failed to create logs directory: \(error.localizedDescription, privacy: .public)")
            return
        }

        let logFileName = "Deck-\(today).log"
        let logURL = logsDir.appendingPathComponent(logFileName)

        state.withLock { s in
            s.currentLogDay = today
            s.logFileURL = logURL
        }

        cleanOldLogFiles(in: logsDir)
        #endif
    }

    private func writeToFile(_ message: String, level: LogLevel) {
        #if DEBUG
        return
        #else
        setupLogFileIfNeeded(now: Date())

        guard let logURL = state.withLock({ $0.logFileURL }) else { return }

        let timestamp = Date().ISO8601Format()
        let logEntry = "[\(timestamp)] [\(level.rawValue)] \(message)\n"
        guard let data = logEntry.data(using: .utf8) else { return }

        let osLogger = self.osLogger

        // Avoid capturing `self` in the `@Sendable` Dispatch closure.
        logQueue.async {
            do {
                try Self.append(data, to: logURL)
            } catch {
                osLogger.error("Failed to write to log file: \(error.localizedDescription, privacy: .public)")
            }
        }
        #endif
    }

    private static func append(_ data: Data, to url: URL) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            fm.createFile(atPath: url.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    private func cleanOldLogFiles(in directory: URL) {
        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey],
                options: []
            )
            let logFiles = files.filter { $0.pathExtension == "log" }

            let calendar = Calendar.current
            let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()

            for file in logFiles {
                let values = try file.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
                let date = values.contentModificationDate ?? values.creationDate
                if let date, date < sevenDaysAgo {
                    try FileManager.default.removeItem(at: file)
                    osLogger.info("Removed old log file: \(file.lastPathComponent, privacy: .public)")
                }
            }
        } catch {
            osLogger.error("Failed to clean old log files: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Formatting

    private static func shortFileName(_ file: StaticString) -> String {
        let full = String(describing: file)
        return full.split(separator: "/").last.map(String.init) ?? full
    }

    /// Local timestamp for debug console printing.
    /// Uses Calendar+components to avoid `DateFormatter`'s thread-safety footguns.
    private static func timestampString(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .nanosecond], from: date)
        let ms = (comps.nanosecond ?? 0) / 1_000_000
        return String(
            format: "%04d-%02d-%02d %02d:%02d:%02d.%03d",
            comps.year ?? 0,
            comps.month ?? 0,
            comps.day ?? 0,
            comps.hour ?? 0,
            comps.minute ?? 0,
            comps.second ?? 0,
            ms
        )
    }

    private static func dayString(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            comps.year ?? 0,
            comps.month ?? 0,
            comps.day ?? 0
        )
    }
}

let log = AppLogger.shared
