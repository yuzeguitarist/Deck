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
/// - Reduce log spam and disk IO in hot paths.
final class AppLogger: Sendable {
    static let shared = AppLogger()

    private struct State: Sendable {
        var minimumLogLevel: LogLevel
        var logsDirectory: URL?
        var currentLogDay: String?
        var logFileURL: URL?
    }

    // MARK: - Throttling

    /// Identify a log call-site without allocating Strings (no message evaluation needed).
    private struct ThrottleKey: Hashable, Sendable {
        let fileKey: Int
        let line: UInt32
        let level: UInt8
    }

    private struct ThrottleEntry: Sendable {
        var lastEmittedAt: TimeInterval
        var suppressedCount: Int
    }

    private struct ThrottleState: Sendable {
        var enabled: Bool
        var debugInterval: TimeInterval
        var infoInterval: TimeInterval
        var maxEntries: Int
        var entries: [ThrottleKey: ThrottleEntry]
    }

    private enum ThrottleOutcome: Sendable {
        case emit(suppressed: Int)
        case drop
    }

    private let throttleState: OSAllocatedUnfairLock<ThrottleState>

    // MARK: - Buffered file output (Release)

    private struct FileBufferState: Sendable {
        var pendingURL: URL?
        var pendingData: Data
        var flushScheduled: Bool
    }

    private let fileBufferState: OSAllocatedUnfairLock<FileBufferState>
    private let fileFlushInterval: TimeInterval = 0.5
    private let maxBufferedBytes: Int = 64 * 1024

    // MARK: - Core

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

        self.throttleState = OSAllocatedUnfairLock(initialState: ThrottleState(
            enabled: true,
            // Debug builds can be extremely chatty (search typing, polling, etc.).
            // Throttle per call-site to keep logs useful while preventing log spam.
            debugInterval: 0.5,
            infoInterval: 1.0,
            maxEntries: 4096,
            entries: [:]
        ))

        self.fileBufferState = OSAllocatedUnfairLock(initialState: FileBufferState(
            pendingURL: nil,
            pendingData: Data(),
            flushScheduled: false
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

        // Throttle debug/info before evaluating the message closure to keep hot paths cheap.
        var suppressedCount = 0
        if level == .debug || level == .info {
            let now = CFAbsoluteTimeGetCurrent()
            switch throttleDecision(level: level, file: file, line: line, now: now) {
            case .drop:
                return
            case .emit(let suppressed):
                suppressedCount = suppressed
            }
        }

        var resolvedMessage = message()
        if suppressedCount > 0 {
            resolvedMessage += " (+\(suppressedCount) suppressed)"
        }

        let fileName = Self.shortFileName(file)

        #if DEBUG
        let timestamp = Self.timestampString(Date())
        let consoleMessage = "[\(level.rawValue)] [\(fileName):\(line)] \(resolvedMessage)"
        print("\(timestamp) \(consoleMessage)")
        #else
        let functionName = String(describing: function)
        let logMessage = "[\(fileName):\(line)] \(functionName) - \(resolvedMessage)"
        writeToFile(logMessage, level: level)
        if level == .error {
            osLogger.error("\(logMessage, privacy: .public)")
        }
        #endif
    }

    // MARK: - Throttling internals

    private func throttleDecision(level: LogLevel, file: StaticString, line: UInt, now: TimeInterval) -> ThrottleOutcome {
        throttleState.withLock { state in
            guard state.enabled else { return .emit(suppressed: 0) }

            let interval: TimeInterval
            switch level {
            case .debug:
                interval = state.debugInterval
            case .info:
                interval = state.infoInterval
            default:
                return .emit(suppressed: 0)
            }

            guard interval > 0 else { return .emit(suppressed: 0) }

            // Prevent unbounded growth if many unique call-sites are hit (e.g. feature flags / plugins).
            if state.entries.count > state.maxEntries {
                state.entries.removeAll(keepingCapacity: true)
            }

            let key = ThrottleKey(
                fileKey: Self.staticStringKey(file),
                line: UInt32(line),
                level: UInt8(level.priority)
            )

            if var entry = state.entries[key] {
                if now - entry.lastEmittedAt < interval {
                    entry.suppressedCount += 1
                    state.entries[key] = entry
                    return .drop
                } else {
                    let suppressed = entry.suppressedCount
                    entry.lastEmittedAt = now
                    entry.suppressedCount = 0
                    state.entries[key] = entry
                    return .emit(suppressed: suppressed)
                }
            } else {
                state.entries[key] = ThrottleEntry(lastEmittedAt: now, suppressedCount: 0)
                return .emit(suppressed: 0)
            }
        }
    }

    private static func staticStringKey(_ value: StaticString) -> Int {
        if value.hasPointerRepresentation {
            return Int(bitPattern: UnsafeRawPointer(value.utf8Start))
        }
        if let scalar = value.unicodeScalarValue {
            return Int(scalar.value)
        }
        return 0
    }

    // MARK: - Static Helpers / Configuration

    static func setMinimumLogLevel(_ level: LogLevel) {
        shared.state.withLock { $0.minimumLogLevel = level }
    }

    static func getMinimumLogLevel() -> LogLevel {
        shared.state.withLock { $0.minimumLogLevel }
    }

    static func setThrottlingEnabled(_ enabled: Bool) {
        shared.throttleState.withLock { $0.enabled = enabled }
    }

    static func configureThrottling(debugInterval: TimeInterval, infoInterval: TimeInterval) {
        shared.throttleState.withLock { state in
            state.debugInterval = max(0, debugInterval)
            state.infoInterval = max(0, infoInterval)
        }
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

        enqueueBufferedWrite(data, to: logURL)
        #endif
    }

    private func enqueueBufferedWrite(_ data: Data, to url: URL) {
        var batchesToFlush: [(URL, Data)] = []
        var shouldScheduleFlush = false

        fileBufferState.withLock { buffer in
            // If the log file rotated, flush pending data to the old file first.
            if let pendingURL = buffer.pendingURL,
               pendingURL != url,
               !buffer.pendingData.isEmpty {
                batchesToFlush.append((pendingURL, buffer.pendingData))
                buffer.pendingData = Data()
                buffer.flushScheduled = false
            }

            buffer.pendingURL = url
            buffer.pendingData.append(data)

            if buffer.pendingData.count >= maxBufferedBytes {
                // Flush immediately when the buffer is large to reduce peak memory.
                batchesToFlush.append((url, buffer.pendingData))
                buffer.pendingData = Data()
                buffer.flushScheduled = false
            } else if !buffer.flushScheduled {
                buffer.flushScheduled = true
                shouldScheduleFlush = true
            }
        }

        if !batchesToFlush.isEmpty {
            let osLogger = self.osLogger
            logQueue.async {
                for (u, d) in batchesToFlush {
                    do {
                        try Self.append(d, to: u)
                    } catch {
                        osLogger.error("Failed to write to log file: \(error.localizedDescription, privacy: .public)")
                    }
                }
            }
        }

        if shouldScheduleFlush {
            logQueue.asyncAfter(deadline: .now() + fileFlushInterval) { [weak self] in
                self?.flushBufferedLogs()
            }
        }
    }

    private func flushBufferedLogs() {
        var batch: (URL, Data)?
        fileBufferState.withLock { buffer in
            buffer.flushScheduled = false
            guard let url = buffer.pendingURL, !buffer.pendingData.isEmpty else { return }
            batch = (url, buffer.pendingData)
            buffer.pendingData = Data()
        }
        guard let batch else { return }

        do {
            try Self.append(batch.1, to: batch.0)
        } catch {
            osLogger.error("Failed to write to log file: \(error.localizedDescription, privacy: .public)")
        }
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
