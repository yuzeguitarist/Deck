// Copyright © 2024–2026 Yuze Pan. 保留一切权利。

//
//  ScriptPluginService.swift
//  Deck
//
//  Scriptable Transformers using JavaScriptCore
//  Scripts are loaded from ~/.deck/scripts/
//

import AppKit
import Dispatch
import Foundation
import JavaScriptCore
import CryptoKit
import Darwin

private typealias JSGlobalContextGetGroupFunc = @convention(c) (JSGlobalContextRef?) -> JSContextGroupRef?
private typealias JSContextGroupSetExecutionTimeLimitCallback = @convention(c) (JSContextRef?, JSValueRef?) -> Bool
private typealias JSContextGroupSetExecutionTimeLimitFunc = @convention(c) (JSContextGroupRef?, Double, JSContextGroupSetExecutionTimeLimitCallback?, UnsafeMutableRawPointer?) -> Void

private enum JSExecutionTimeLimiter {
    static let handle: UnsafeMutableRawPointer? = dlopen(
        "/System/Library/Frameworks/JavaScriptCore.framework/JavaScriptCore",
        RTLD_NOW
    )

    static let getGroup: JSGlobalContextGetGroupFunc? = {
        guard let handle, let symbol = dlsym(handle, "JSGlobalContextGetGroup") else { return nil }
        return unsafeBitCast(symbol, to: JSGlobalContextGetGroupFunc.self)
    }()

    static let setLimit: JSContextGroupSetExecutionTimeLimitFunc? = {
        guard let handle, let symbol = dlsym(handle, "JSContextGroupSetExecutionTimeLimit") else { return nil }
        return unsafeBitCast(symbol, to: JSContextGroupSetExecutionTimeLimitFunc.self)
    }()

    static let callback: JSContextGroupSetExecutionTimeLimitCallback = { _, _ in
        true
    }
}

// MARK: - Script Plugin Model

struct ScriptPlugin: Identifiable, Codable {
    let id: String
    let name: String
    let description: String?
    let author: String?
    let version: String?
    let scriptPath: String
    let scriptHash: String?
    let icon: String?
    let requiresNetwork: Bool  // 是否需要网络权限

    init(
        id: String,
        name: String,
        description: String?,
        author: String?,
        version: String?,
        scriptPath: String,
        scriptHash: String? = nil,
        icon: String?,
        requiresNetwork: Bool
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.author = author
        self.version = version
        self.scriptPath = scriptPath
        self.scriptHash = scriptHash
        self.icon = icon
        self.requiresNetwork = requiresNetwork
    }

    var displayName: String {
        name
    }

    var displayIcon: String {
        icon ?? "scroll"
    }

    /// 是否已获得网络权限授权
    var isNetworkAuthorized: Bool {
        guard requiresNetwork else { return false }
        return DeckUserDefaults.isNetworkPluginAuthorized(pluginId: id, scriptHash: scriptHash)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case author
        case version
        case scriptPath
        case scriptHash
        case icon
        case requiresNetwork
    }
}

// MARK: - Script Manifest

/// 脚本清单文件格式 (manifest.json)
struct ScriptManifest: Codable {
    let name: String
    let description: String?
    let author: String?
    let version: String?
    let main: String  // 主脚本文件名
    let icon: String?
    let permissions: ScriptPermissions?  // 权限声明

    struct ScriptPermissions: Codable {
        let network: Bool?  // 是否需要网络权限
    }
}

// MARK: - Script Execution Result

struct ScriptResult {
    let success: Bool
    let output: String?
    let error: String?
}

// MARK: - Script Plugin Service

@Observable
final class ScriptPluginService {
    static let shared = ScriptPluginService()

    private(set) var plugins: [ScriptPlugin] = []
    private let pluginsLock = NSLock()
    private let maxManifestBytes = 64 * 1024
    private let maxScriptBytes = 1 * 1024 * 1024
    private let reloadQueue = DispatchQueue(label: "deck.script.reload", qos: .utility)
    private let reloadLock = NSLock()
    private var pendingReloadWorkItem: DispatchWorkItem?
    private var lastReloadTime = Date.distantPast
    private let minReloadInterval: TimeInterval = 0.3
    private let watchQueue = DispatchQueue(label: "deck.script.watch", qos: .utility)
    private let watchLock = NSLock()
    private var scriptsDirectoryWatcher: FileSystemWatcher?
    private var pluginPathWatchers: [String: FileSystemWatcher] = [:]
    private let watchEventMask: DispatchSource.FileSystemEvent = [
        .write, .delete, .rename, .attrib, .extend, .link, .revoke
    ]
    private let stateLock = NSLock()
    private var executionStates: [String: ExecutionState] = [:]
    private let scriptExecutionQueue = DispatchQueue(
        label: "deck.script.execution",
        qos: .utility,
        attributes: .concurrent
    )
    private let defaultPluginAuthor = "Deck"
    private let legacyDefaultPluginDirectoryNames: Set<String> = [
        "base64-encode",
        "base64-decode",
        "url-encode",
        "url-decode",
        "json-format"
    ]

    // Network sandbox for scripts: avoid leaking cookies/cache from the main app and limit response size.
    private static let maxFetchResponseBytes = 2 * 1024 * 1024  // 2 MB

    private static let pluginNetworkSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    private final class ExecutionState: @unchecked Sendable {
        private let lock = NSLock()
        private var interrupted = false

        func markInterrupted() {
            lock.lock()
            interrupted = true
            lock.unlock()
        }

        func isInterrupted() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return interrupted
        }
    }

    private final class FileSystemWatcher {
        private var source: DispatchSourceFileSystemObject?

        init?(
            path: String,
            eventMask: DispatchSource.FileSystemEvent,
            queue: DispatchQueue,
            onChange: @escaping @Sendable (String) -> Void
        ) {
            let fileDescriptor = open(path, O_EVTONLY)
            guard fileDescriptor >= 0 else { return nil }

            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fileDescriptor,
                eventMask: eventMask,
                queue: queue
            )
            source.setEventHandler { [path] in
                onChange(path)
            }
            source.setCancelHandler {
                close(fileDescriptor)
            }
            source.resume()
            self.source = source
        }

        func cancel() {
            source?.cancel()
            source = nil
        }

        deinit {
            cancel()
        }
    }

    /// 脚本目录路径
    private var scriptsDirectoryURL: URL {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        return homeDir.appendingPathComponent(".deck/scripts", isDirectory: true)
    }

    private init() {
        ensureScriptsDirectory()
        startWatchingScriptsDirectory()
        loadPlugins()
    }

    deinit {
        stopScriptWatchers()
    }

    // MARK: - Directory Setup

    /// 确保脚本目录存在
    private func ensureScriptsDirectory() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: scriptsDirectoryURL.path) {
            do {
                try fm.createDirectory(at: scriptsDirectoryURL, withIntermediateDirectories: true)
                log.info("Created scripts directory: \(scriptsDirectoryURL.path)")
            } catch {
                log.error("Failed to create scripts directory: \(error)")
                return
            }
        }
        migrateDefaultScripts()
    }

    private func isURL(_ candidate: URL, within directory: URL) -> Bool {
        let base = directory.resolvingSymlinksInPath().standardizedFileURL
        let resolved = candidate.resolvingSymlinksInPath().standardizedFileURL
        let basePath = base.path.hasSuffix("/") ? base.path : (base.path + "/")
        return resolved.path.hasPrefix(basePath)
    }

    /// 创建示例脚本
    private func createExampleScripts() {
        let wordCountCharsLabel = NSLocalizedString("字符数", comment: "Default script output label: character count")
        let wordCountCharsNoSpaceLabel = NSLocalizedString("字符数(不含空格)", comment: "Default script output label: character count without spaces")
        let wordCountWordsLabel = NSLocalizedString("单词数", comment: "Default script output label: word count")
        let wordCountLinesLabel = NSLocalizedString("行数", comment: "Default script output label: line count")

        createDefaultScript(
            directoryName: "word-count",
            manifest: ScriptManifest(
                name: NSLocalizedString("字数统计", comment: "Default script name: word count"),
                description: NSLocalizedString("统计文本的字符数、单词数和行数", comment: "Default script description: word count"),
                author: defaultPluginAuthor,
                version: "1.0.0",
                main: "index.js",
                icon: "number",
                permissions: nil
            ),
            script: """
            function transform(input) {
                const chars = input.length;
                const charsNoSpace = input.replace(/\\s/g, '').length;
                const words = input.trim().split(/\\s+/).filter(w => w.length > 0).length;
                const lines = input.split('\\n').length;

                return "\(wordCountCharsLabel): " + chars + "\\n" +
                       "\(wordCountCharsNoSpaceLabel): " + charsNoSpace + "\\n" +
                       "\(wordCountWordsLabel): " + words + "\\n" +
                       "\(wordCountLinesLabel): " + lines;
            }
            """
        )

        createDefaultScript(
            directoryName: "remove-emoji",
            manifest: ScriptManifest(
                name: NSLocalizedString("去除表情符号", comment: "Default script name: remove emoji"),
                description: NSLocalizedString("移除文本中的表情符号", comment: "Default script description: remove emoji"),
                author: defaultPluginAuthor,
                version: "1.0.0",
                main: "index.js",
                icon: "face.smiling",
                permissions: nil
            ),
            script: """
            function buildEmojiRegex() {
                try {
                    return new RegExp(
                        "[\\\\p{Extended_Pictographic}\\\\p{Emoji_Presentation}\\\\p{Emoji}\\\\uFE0F\\\\uFE0E\\\\u200D\\\\u{1F3FB}-\\\\u{1F3FF}]",
                        "gu"
                    );
                } catch (e) {
                    return /[\\u{1F300}-\\u{1FAFF}\\u{2600}-\\u{27BF}\\u{1F1E6}-\\u{1F1FF}\\u{1F3FB}-\\u{1F3FF}\\uFE0F\\uFE0E\\u200D]/gu;
                }
            }

            function transform(input) {
                if (!input) {
                    return "";
                }
                const emojiRegex = buildEmojiRegex();
                let output = input.replace(emojiRegex, "");
                output = output.replace(/[\\uFE0F\\uFE0E\\u200D]/g, "");
                return output;
            }
            """
        )

        createDefaultScript(
            directoryName: "strip-markdown",
            manifest: ScriptManifest(
                name: NSLocalizedString("去除 Markdown 格式", comment: "Default script name: strip markdown"),
                description: NSLocalizedString("删除 Markdown 语法，保留纯文本内容", comment: "Default script description: strip markdown"),
                author: defaultPluginAuthor,
                version: "1.0.0",
                main: "index.js",
                icon: "doc.plaintext",
                permissions: nil
            ),
            script: """
            function transform(input) {
                if (!input) {
                    return "";
                }

                let text = input.replace(/\\r\\n?/g, "\\n");

                text = text.replace(/```([\\s\\S]*?)```/g, function(_, code) {
                    return code;
                });
                text = text.replace(/`([^`]+)`/g, "$1");

                text = text.replace(/!\\[([^\\]]*)\\]\\([^\\)]+\\)/g, "$1");
                text = text.replace(/\\[([^\\]]+)\\]\\([^\\)]+\\)/g, "$1");
                text = text.replace(/<((?:https?:\\/\\/|mailto:)[^>]+)>/g, "$1");

                text = text.replace(/^\\s{0,3}#{1,6}\\s+/gm, "");
                text = text.replace(/^\\s{0,3}>\\s?/gm, "");
                text = text.replace(/^\\s*([-*+]|\\d+\\.)\\s+/gm, "");
                text = text.replace(/^\\s*([-*_])(?:\\s*\\1){2,}\\s*$/gm, "");

                text = text.replace(/~~(.*?)~~/g, "$1");
                text = text.replace(/(\\*\\*|__)(.*?)\\1/g, "$2");
                text = text.replace(/(\\*|_)(.*?)\\1/g, "$2");

                text = text.replace(/^\\s*\\|?(\\s*:?-+:?\\s*\\|)+\\s*$/gm, "");
                text = text.replace(/\\|/g, " ");

                text = text.replace(/<\\/?.*?>/g, "");
                text = text.replace(/\\\\([\\\\`*_{}\\[\\]()#+\\-.!])/g, "$1");

                return text;
            }
            """
        )

        createDefaultScript(
            directoryName: "remove-empty-lines",
            manifest: ScriptManifest(
                name: NSLocalizedString("去空行", comment: "Default script name: remove empty lines"),
                description: NSLocalizedString("删除空白行，仅保留有内容的行", comment: "Default script description: remove empty lines"),
                author: defaultPluginAuthor,
                version: "1.0.0",
                main: "index.js",
                icon: "line.3.horizontal.decrease",
                permissions: nil
            ),
            script: """
            function transform(input) {
                if (!input) {
                    return "";
                }
                return String(input)
                    .replace(/\\r\\n?/g, "\\n")
                    .split("\\n")
                    .filter(function(line) { return line.trim().length > 0; })
                    .join("\\n");
            }
            """
        )

        createDefaultScript(
            directoryName: "extract-urls",
            manifest: ScriptManifest(
                name: NSLocalizedString("提取 URL", comment: "Default script name: extract url"),
                description: NSLocalizedString("提取文本中的 URL（基于 Deck SmartText 逻辑）", comment: "Default script description: extract url"),
                author: defaultPluginAuthor,
                version: "1.0.0",
                main: "index.js",
                icon: "link",
                permissions: nil
            ),
            script: """
            function transform(input) {
                return Deck.detectURLs(String(input || ""));
            }
            """
        )

        createDefaultScript(
            directoryName: "extract-emails",
            manifest: ScriptManifest(
                name: NSLocalizedString("提取邮箱", comment: "Default script name: extract email"),
                description: NSLocalizedString("提取文本中的邮箱地址（基于 Deck SmartText 逻辑）", comment: "Default script description: extract email"),
                author: defaultPluginAuthor,
                version: "1.0.0",
                main: "index.js",
                icon: "envelope",
                permissions: nil
            ),
            script: """
            function transform(input) {
                return Deck.detectEmails(String(input || ""));
            }
            """
        )

        createDefaultScript(
            directoryName: "line-number",
            manifest: ScriptManifest(
                name: NSLocalizedString("行号前缀", comment: "Default script name: line number prefix"),
                description: NSLocalizedString("为每行添加行号前缀", comment: "Default script description: line number prefix"),
                author: defaultPluginAuthor,
                version: "1.0.0",
                main: "index.js",
                icon: "list.number",
                permissions: nil
            ),
            script: """
            function transform(input) {
                if (input === null || input === undefined) {
                    return "";
                }
                var lines = String(input).replace(/\\r\\n?/g, "\\n").split("\\n");
                return lines.map(function(line, index) {
                    return (index + 1) + ". " + line;
                }).join("\\n");
            }
            """
        )

        log.info("Created default scripts")
    }

    private func migrateDefaultScripts() {
        removeLegacyDefaultScripts()
        createExampleScripts()
    }

    private func removeLegacyDefaultScripts() {
        let fm = FileManager.default
        for name in legacyDefaultPluginDirectoryNames {
            let directory = scriptsDirectoryURL.appendingPathComponent(name, isDirectory: true)
            guard let values = try? directory.resourceValues(forKeys: [.isDirectoryKey]),
                  values.isDirectory == true else { continue }
            guard shouldRemoveLegacyDefaultScript(at: directory) else { continue }
            do {
                try fm.removeItem(at: directory)
                log.info("Removed legacy default script: \(name)")
            } catch {
                log.warn("Failed to remove legacy default script \(name): \(error.localizedDescription)")
            }
        }
    }

    private func createDefaultScript(
        directoryName: String,
        manifest: ScriptManifest,
        script: String
    ) {
        let directory = scriptsDirectoryURL.appendingPathComponent(directoryName, isDirectory: true)
        guard shouldOverwriteDefaultScript(at: directory) else { return }
        createExampleScript(at: directory, manifest: manifest, script: script)
    }

    private func shouldOverwriteDefaultScript(at directory: URL) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { return true }
        guard let manifest = loadManifest(at: directory) else { return true }
        if manifest.author == defaultPluginAuthor {
            return true
        }
        log.info("Skipping default script overwrite for user plugin: \(directory.lastPathComponent)")
        return false
    }

    private func shouldRemoveLegacyDefaultScript(at directory: URL) -> Bool {
        guard let manifest = loadManifest(at: directory) else { return true }
        return manifest.author == defaultPluginAuthor
    }

    private func loadManifest(at directory: URL) -> ScriptManifest? {
        let manifestURL = directory.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL, options: [.mappedIfSafe]),
              let manifest = try? JSONDecoder().decode(ScriptManifest.self, from: data) else {
            return nil
        }
        return manifest
    }

    private func createExampleScript(at directory: URL, manifest: ScriptManifest, script: String) {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)

            // 写入 manifest.json
            let manifestURL = directory.appendingPathComponent("manifest.json")
            let manifestData = try JSONEncoder().encode(manifest)
            try manifestData.write(to: manifestURL)

            // 写入脚本文件
            let scriptURL = directory.appendingPathComponent(manifest.main)
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        } catch {
            log.error("Failed to create example script at \(directory): \(error)")
        }
    }

    // MARK: - Plugin Loading

    private func makeWatcher(for path: String) -> FileSystemWatcher? {
        FileSystemWatcher(
            path: path,
            eventMask: watchEventMask,
            queue: watchQueue
        ) { [weak self] changedPath in
            log.debug("Script watcher detected change: \(changedPath)")
            self?.reloadPlugins()
        }
    }

    private func startWatchingScriptsDirectory() {
        watchLock.lock()
        defer { watchLock.unlock() }
        guard scriptsDirectoryWatcher == nil else { return }

        let rootPath = scriptsDirectoryURL.standardizedFileURL.path
        scriptsDirectoryWatcher = makeWatcher(for: rootPath)
        if scriptsDirectoryWatcher == nil {
            log.warn("Failed to watch scripts directory: \(rootPath)")
        } else {
            log.info("Started watching scripts directory: \(rootPath)")
        }
    }

    private func stopScriptWatchers() {
        watchLock.lock()
        let rootWatcher = scriptsDirectoryWatcher
        let watchers = pluginPathWatchers.values
        scriptsDirectoryWatcher = nil
        pluginPathWatchers.removeAll()
        watchLock.unlock()

        rootWatcher?.cancel()
        for watcher in watchers {
            watcher.cancel()
        }
    }

    private func watchedPaths(for plugins: [ScriptPlugin]) -> Set<String> {
        var paths: Set<String> = []
        for plugin in plugins {
            let scriptURL = URL(fileURLWithPath: plugin.scriptPath).standardizedFileURL
            let directoryURL = scriptURL.deletingLastPathComponent().standardizedFileURL
            let manifestURL = directoryURL.appendingPathComponent("manifest.json").standardizedFileURL
            paths.insert(directoryURL.path)
            paths.insert(manifestURL.path)
            paths.insert(scriptURL.path)
        }
        return paths
    }

    private func refreshScriptWatchTargets(with plugins: [ScriptPlugin]) {
        let desiredPaths = watchedPaths(for: plugins)

        watchLock.lock()
        defer { watchLock.unlock() }

        if scriptsDirectoryWatcher == nil {
            scriptsDirectoryWatcher = makeWatcher(for: scriptsDirectoryURL.standardizedFileURL.path)
        }

        // 这里直接全量重建，避免某些编辑器原子替换文件后 watcher 绑定到旧 inode 导致失效。
        for watcher in pluginPathWatchers.values {
            watcher.cancel()
        }
        pluginPathWatchers.removeAll(keepingCapacity: true)

        for path in desiredPaths {
            if let watcher = makeWatcher(for: path) {
                pluginPathWatchers[path] = watcher
            }
        }
    }

    /// 重新加载所有插件
    func reloadPlugins() {
        let now = Date()
        reloadLock.lock()
        let elapsed = now.timeIntervalSince(lastReloadTime)
        let delay = elapsed >= minReloadInterval ? 0 : (minReloadInterval - elapsed)
        pendingReloadWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.reloadLock.lock()
            self.lastReloadTime = Date()
            self.pendingReloadWorkItem = nil
            self.reloadLock.unlock()
            self.clearExecutionStates()
            self.loadPlugins()
        }
        pendingReloadWorkItem = workItem
        reloadLock.unlock()
        reloadQueue.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    /// 加载所有插件
    private func loadPlugins() {
        var loaded: [ScriptPlugin] = []

        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: scriptsDirectoryURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: .skipsHiddenFiles
        ) else {
            log.warn("Cannot read scripts directory")
            return
        }

        for url in contents {
            guard let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  resourceValues.isDirectory == true else {
                continue
            }

            if resourceValues.isSymbolicLink == true {
                log.warn("Skipping symlinked plugin directory: \(url.path)")
                continue
            }

            if let plugin = loadPlugin(from: url) {
                loaded.append(plugin)
            }
        }

        let apply: () -> Void = { [weak self] in
            guard let self else { return }
            self.pluginsLock.lock()
            self.plugins = loaded
            self.pluginsLock.unlock()
        }
        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async(execute: apply)
        }

        refreshScriptWatchTargets(with: loaded)
        log.info("Loaded \(loaded.count) script plugins")
    }

    /// 从目录加载单个插件
    private func loadPlugin(from directory: URL) -> ScriptPlugin? {
        let fm = FileManager.default
        let manifestURL = directory.appendingPathComponent("manifest.json")

        do {
            let attrs = try fm.attributesOfItem(atPath: manifestURL.path)
            if let fileType = attrs[.type] as? FileAttributeType, fileType != .typeRegular {
                log.warn("Invalid manifest type in \(directory.lastPathComponent)")
                return nil
            }
            let size = (attrs[.size] as? NSNumber)?.intValue ?? 0
            if size <= 0 || size > maxManifestBytes {
                log.warn("manifest.json too large (\(size) bytes), skipping plugin: \(directory.lastPathComponent)")
                return nil
            }
        } catch {
            log.warn("Invalid or missing manifest.json in \(directory.lastPathComponent)")
            return nil
        }

        guard let manifestData = try? Data(contentsOf: manifestURL, options: [.mappedIfSafe]),
              let manifest = try? JSONDecoder().decode(ScriptManifest.self, from: manifestData) else {
            log.warn("Invalid or missing manifest.json in \(directory.lastPathComponent)")
            return nil
        }

        let scriptURL = directory.appendingPathComponent(manifest.main)
        guard isURL(scriptURL, within: directory) else {
            log.warn("Script path escapes plugin directory, skipping plugin: \(directory.lastPathComponent)")
            return nil
        }
        let scriptPath = scriptURL.path

        guard fm.fileExists(atPath: scriptPath) else {
            log.warn("Script file not found: \(scriptPath)")
            return nil
        }

        do {
            let attrs = try fm.attributesOfItem(atPath: scriptPath)
            if let fileType = attrs[.type] as? FileAttributeType, fileType != .typeRegular {
                log.warn("Invalid script file type, skipping plugin: \(directory.lastPathComponent)")
                return nil
            }
            let size = (attrs[.size] as? NSNumber)?.intValue ?? 0
            if size <= 0 || size > maxScriptBytes {
                log.warn("Script file too large (\(size) bytes), skipping plugin: \(directory.lastPathComponent)")
                return nil
            }
        } catch {
            log.warn("Failed to read script file attributes, skipping plugin: \(directory.lastPathComponent)")
            return nil
        }

        let scriptHash = computeScriptHash(at: scriptPath)

        return ScriptPlugin(
            id: directory.lastPathComponent,
            name: manifest.name,
            description: manifest.description,
            author: manifest.author,
            version: manifest.version,
            scriptPath: scriptPath,
            scriptHash: scriptHash,
            icon: manifest.icon,
            requiresNetwork: manifest.permissions?.network ?? false
        )
    }

    private func computeScriptHash(at path: String) -> String? {
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: path)
            let size = (attrs[.size] as? NSNumber)?.intValue ?? 0
            if size <= 0 || size > maxScriptBytes {
                log.warn("Script file too large for hashing (\(size) bytes): \(path)")
                return nil
            }
            let data = try Data(contentsOf: URL(fileURLWithPath: path), options: [.mappedIfSafe])
            let hash = SHA256.hash(data: data)
            return hash.compactMap { String(format: "%02x", $0) }.joined()
        } catch {
            log.warn("Failed to hash script file: \(error.localizedDescription)")
            return nil
        }
    }

    func plugin(by pluginId: String) -> ScriptPlugin? {
        pluginsLock.lock()
        defer { pluginsLock.unlock() }
        return plugins.first(where: { $0.id == pluginId })
    }

    func pluginDisplayName(for pluginId: String) -> String? {
        plugin(by: pluginId)?.name
    }

    // MARK: - Script Execution
    
    /// 用于追踪正在执行的脚本任务
    private func markTaskRunning(_ executionId: String) -> ExecutionState {
        let state = ExecutionState()
        stateLock.lock()
        executionStates[executionId] = state
        stateLock.unlock()
        return state
    }

    private func isTaskRunning(_ executionId: String) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return executionStates[executionId] != nil
    }

    private func finishTask(_ executionId: String) {
        stateLock.lock()
        executionStates.removeValue(forKey: executionId)
        stateLock.unlock()
    }

    private func clearExecutionStates() {
        stateLock.lock()
        executionStates.removeAll()
        stateLock.unlock()
    }

    /// 执行脚本转换（带安全检查）
    func executeTransform(pluginId: String, input: String) -> ScriptResult {
        if Thread.isMainThread {
            log.warn("executeTransform called on main thread; use executeTransformAsync instead")
            return ScriptResult(
                success: false,
                output: nil,
                error: NSLocalizedString("脚本执行应使用异步 API", comment: "Script execution should use async API")
            )
        }
        return executeTransformInternal(pluginId: pluginId, input: input)
    }

    /// 异步执行脚本转换（不会阻塞调用方线程）
    func executeTransformAsync(pluginId: String, input: String) async -> ScriptResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async { [weak self] in
                let result = self?.executeTransformInternal(pluginId: pluginId, input: input)
                    ?? ScriptResult(
                        success: false,
                        output: nil,
                        error: NSLocalizedString("执行失败", comment: "Script execution failed")
                    )
                continuation.resume(returning: result)
            }
        }
    }

    private func executeTransformInternal(pluginId: String, input: String) -> ScriptResult {
        let plugin: ScriptPlugin? = {
            pluginsLock.lock()
            defer { pluginsLock.unlock() }
            return plugins.first(where: { $0.id == pluginId })
        }()
        guard let plugin else {
            return ScriptResult(
                success: false,
                output: nil,
                error: NSLocalizedString("插件不存在", comment: "Script plugin does not exist")
            )
        }

        // 输入长度检查
        let maxInput = DeckUserDefaults.scriptMaxInputLength
        guard input.count <= maxInput else {
            return ScriptResult(
                success: false,
                output: nil,
                error: String(
                    format: NSLocalizedString("输入超过最大长度限制 (%d 字符)", comment: "Script input too long"),
                    maxInput
                )
            )
        }

        // 执行脚本（带超时）
        let result = executeScriptWithTimeout(plugin: plugin, input: input)

        // 输出长度检查
        if let output = result.output, output.count > Const.scriptMaxOutputLength {
            return ScriptResult(
                success: false,
                output: nil,
                error: String(
                    format: NSLocalizedString("输出超过最大长度限制 (%d 字符)", comment: "Script output too long"),
                    Const.scriptMaxOutputLength
                )
            )
        }

        return result
    }

    /// 带超时的脚本执行
    /// 注意：执行超时后会中断 JS 运行，避免死循环长期占用执行队列
    private func executeScriptWithTimeout(plugin: ScriptPlugin, input: String) -> ScriptResult {
        let timeout = TimeInterval(DeckUserDefaults.scriptTimeout)
        let executionId = UUID().uuidString
        let executionState = markTaskRunning(executionId)
        
        // 使用线程安全的容器存储结果
        final class ResultBox: @unchecked Sendable {
            private let lock = NSLock()
            private var _result: ScriptResult?
            private var _isCompleted = false
            
            var result: ScriptResult? {
                lock.lock()
                defer { lock.unlock() }
                return _result
            }
            
            func setResult(_ r: ScriptResult) {
                lock.lock()
                defer { lock.unlock() }
                if !_isCompleted {
                    _result = r
                }
            }
            
            func markCompleted() {
                lock.lock()
                defer { lock.unlock() }
                _isCompleted = true
            }
        }
        
        let resultBox = ResultBox()
        let semaphore = DispatchSemaphore(value: 0)

        // 在执行队列中运行脚本（使用较低优先级避免影响 UI）
        scriptExecutionQueue.async { [weak self] in
            guard let self else {
                semaphore.signal()
                return
            }
            
            // 检查是否已被标记为超时
            guard self.isTaskRunning(executionId) else {
                semaphore.signal()
                return
            }
            
            let result = self.executeScript(
                plugin: plugin,
                input: input,
                executionState: executionState,
                timeout: timeout
            )
            resultBox.setResult(result)
            semaphore.signal()
        }

        // 等待执行完成或超时
        let waitResult = semaphore.wait(timeout: .now() + timeout)
        
        resultBox.markCompleted()

        if waitResult == .timedOut {
            // 标记为已中断（用于 fetch 等检查）
            executionState.markInterrupted()
            finishTask(executionId)
            
            log.warn("Script \(plugin.id) execution timed out after \(Int(timeout)) seconds.")
            
            return ScriptResult(
                success: false,
                output: nil,
                error: String(
                    format: NSLocalizedString("脚本执行超时（超过 %d 秒）\n注意：包含死循环的脚本可能仍在后台运行", comment: "Script execution timeout"),
                    Int(timeout)
                )
            )
        }

        // 清理任务追踪
        finishTask(executionId)
        return resultBox.result ?? ScriptResult(
            success: false,
            output: nil,
            error: NSLocalizedString("执行失败", comment: "Script execution failed")
        )
    }

    /// 执行脚本（内部方法，不带安全检查）
    private func executeScript(
        plugin: ScriptPlugin,
        input: String,
        executionState: ExecutionState,
        timeout: TimeInterval
    ) -> ScriptResult {
        // 每次执行都创建新的 JSContext，确保干净的执行环境
        // 这样超时后旧的 context 会被丢弃，不影响后续执行
        guard let context = createContext(for: plugin, executionState: executionState, timeout: timeout) else {
            return ScriptResult(
                success: false,
                output: nil,
                error: NSLocalizedString("无法创建 JavaScript 环境", comment: "Cannot create JavaScript context")
            )
        }

        // 调用 transform 函数
        guard let transformFunc = context.objectForKeyedSubscript("transform"),
              !transformFunc.isUndefined else {
            return ScriptResult(
                success: false,
                output: nil,
                error: NSLocalizedString("脚本中未定义 transform 函数", comment: "transform function not defined in script")
            )
        }
        
        // 检查是否已被中断
        if executionState.isInterrupted() {
            return ScriptResult(
                success: false,
                output: nil,
                error: NSLocalizedString("脚本已被中断", comment: "Script interrupted")
            )
        }

        // 执行转换
        let result = transformFunc.call(withArguments: [input])
        
        // 再次检查中断状态
        if executionState.isInterrupted() {
            return ScriptResult(
                success: false,
                output: nil,
                error: NSLocalizedString("脚本已被中断", comment: "Script interrupted")
            )
        }

        // 检查异常
        if let exception = context.exception {
            let errorMessage = exception.toString() ?? NSLocalizedString("未知错误", comment: "Unknown script error")
            context.exception = nil  // 清除异常
            return ScriptResult(success: false, output: nil, error: errorMessage)
        }

        // 获取结果
        guard let outputString = result?.toString() else {
            return ScriptResult(
                success: false,
                output: nil,
                error: NSLocalizedString("转换结果无效", comment: "Invalid transformed result")
            )
        }

        return ScriptResult(success: true, output: outputString, error: nil)
    }

    /// 创建 JSContext
    private func createContext(
        for plugin: ScriptPlugin,
        executionState: ExecutionState,
        timeout: TimeInterval
    ) -> JSContext? {
        let vm = JSVirtualMachine()
        guard let context = JSContext(virtualMachine: vm) else { return nil }

        if let getGroup = JSExecutionTimeLimiter.getGroup,
           let setLimit = JSExecutionTimeLimiter.setLimit,
           let group = getGroup(context.jsGlobalContextRef) {
            let timeLimit = max(1, timeout)
            setLimit(group, timeLimit, JSExecutionTimeLimiter.callback, nil)
        }

        // 设置异常处理
        context.exceptionHandler = { _, exception in
            if let error = exception?.toString() {
                log.error("JS Exception in \(plugin.id): \(error)")
            }
        }

        // 初始化中断标记
        context.setObject(false, forKeyedSubscript: "__deckInterrupted" as NSString)
        
        // 添加中断检查函数 - 脚本可以在循环中调用此函数检查是否应该中断
        let checkInterrupt: @convention(block) () -> Bool = { [weak context] in
            let interrupted = executionState.isInterrupted()
            if let context {
                context.setObject(interrupted, forKeyedSubscript: "__deckInterrupted" as NSString)
            }
            return interrupted
        }
        context.setObject(checkInterrupt, forKeyedSubscript: "__deckCheckInterrupt" as NSString)

        // SmartText bridge (URL / Email detection)
        let detectURLs: @convention(block) (String) -> String = { text in
            let urls = SmartTextService.shared.detectURLs(in: text).map { $0.absoluteString }
            return urls.joined(separator: "\n")
        }
        context.setObject(detectURLs, forKeyedSubscript: "__deckDetectURLs" as NSString)

        let detectEmails: @convention(block) (String) -> String = { text in
            let emails = SmartTextService.shared.detectEmails(in: text)
            return emails.joined(separator: "\n")
        }
        context.setObject(detectEmails, forKeyedSubscript: "__deckDetectEmails" as NSString)

        // 添加 console.log 支持
        let consoleLog: @convention(block) (String) -> Void = { message in
            log.debug("[JS \(plugin.id)] \(message)")
        }
        context.setObject(consoleLog, forKeyedSubscript: "log" as NSString)

        // 创建 console 对象和中断检查辅助函数
        context.evaluateScript("""
            var console = {
                log: function() { log(Array.prototype.slice.call(arguments).join(' ')); },
                warn: function() { log('WARN: ' + Array.prototype.slice.call(arguments).join(' ')); },
                error: function() { log('ERROR: ' + Array.prototype.slice.call(arguments).join(' ')); }
            };
            
            // 辅助函数：在循环中检查是否应该中断
            // 使用方式: while(condition && !Deck.shouldStop()) { ... }
            var Deck = {
                shouldStop: function() { return __deckCheckInterrupt(); },
                checkInterrupt: function() {
                    if (__deckCheckInterrupt()) {
                        throw new Error('Script interrupted by timeout');
                    }
                },
                detectURLs: function(text) { return __deckDetectURLs(String(text || "")); },
                detectEmails: function(text) { return __deckDetectEmails(String(text || "")); }
            };
        """)

        // 添加 btoa/atob 支持 (Base64)
        let btoa: @convention(block) (String) -> String = { input in
            return Data(input.utf8).base64EncodedString()
        }
        context.setObject(btoa, forKeyedSubscript: "btoa" as NSString)

        let atob: @convention(block) (String) -> String = { input in
            guard let data = Data(base64Encoded: input),
                  let decoded = String(data: data, encoding: .utf8) else {
                return ""
            }
            return decoded
        }
        context.setObject(atob, forKeyedSubscript: "atob" as NSString)

        // 如果插件有网络权限，添加 fetch API
        if plugin.requiresNetwork && plugin.isNetworkAuthorized {
            setupNetworkAPI(context: context, pluginId: plugin.id, executionState: executionState)
        }

        // 加载脚本
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: plugin.scriptPath)
            let size = (attrs[.size] as? NSNumber)?.intValue ?? 0
            guard size > 0, size <= maxScriptBytes else {
                log.warn("Plugin script too large (\(size) bytes): \(plugin.scriptPath)")
                return nil
            }
        } catch {
            log.warn("Failed to stat plugin script: \(error.localizedDescription)")
            return nil
        }
        guard let scriptContent = try? String(contentsOfFile: plugin.scriptPath, encoding: .utf8) else {
            log.error("Failed to read script: \(plugin.scriptPath)")
            return nil
        }

        context.evaluateScript(scriptContent)

        if context.exception != nil {
            log.error("Script evaluation error in \(plugin.id)")
            return nil
        }

        return context
    }

    /// 设置网络 API (fetch)
    private func setupNetworkAPI(context: JSContext, pluginId: String, executionState: ExecutionState) {
        // 同步 fetch 实现（因为 JSContext 不支持原生 Promise）
        // 使用 __deckFetch 作为底层实现
        // 支持中断检查
        let fetchSync: @convention(block) (String, JSValue?) -> JSValue = { urlString, options in
            let jsContext = JSContext.current() ?? context
            
            // 检查是否已被中断
            if executionState.isInterrupted() {
                return Self.createFetchError(context: jsContext, message: "Script interrupted")
            }

            guard let url = URL(string: urlString) else {
                log.error("[JS \(pluginId)] Invalid URL: \(urlString)")
                return Self.createFetchError(context: jsContext, message: "Invalid URL")
            }

            // Restrict to http/https to avoid unintentionally granting local file access via URLSession.
            guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
                log.error("[JS \(pluginId)] Unsupported URL scheme: \(urlString)")
                return Self.createFetchError(context: jsContext, message: "Only http/https URLs are allowed")
            }

            // 解析 options
            var request = URLRequest(url: url)
            let maxWaitTime = max(1, min(10, TimeInterval(DeckUserDefaults.scriptTimeout)))
            request.timeoutInterval = maxWaitTime

            if let opts = options, !opts.isUndefined, !opts.isNull {
                if let method = opts.forProperty("method")?.toString(), !method.isEmpty {
                    request.httpMethod = method.uppercased()
                }

                if let headers = opts.forProperty("headers"), !headers.isUndefined {
                    if let headerDict = headers.toDictionary() as? [String: String] {
                        for (key, value) in headerDict {
                            request.setValue(value, forHTTPHeaderField: key)
                        }
                    }
                }

                if let body = opts.forProperty("body"), !body.isUndefined, !body.isNull {
                    if let bodyString = body.toString() {
                        request.httpBody = bodyString.data(using: .utf8)
                    }
                }
            }

            // 同步执行网络请求（可取消）
            var responseData: Data?
            var httpResponse: HTTPURLResponse?
            var requestError: Error?

            let semaphore = DispatchSemaphore(value: 0)

            let task = Self.pluginNetworkSession.dataTask(with: request) { data, response, error in
                responseData = data
                httpResponse = response as? HTTPURLResponse
                requestError = error
                semaphore.signal()
            }
            task.resume()

            // 等待请求完成，但定期检查中断状态
            let checkInterval: TimeInterval = 0.5
            let deadline = Date().addingTimeInterval(maxWaitTime)

            while true {
                let remaining = max(0, deadline.timeIntervalSinceNow)
                if remaining <= 0 {
                    break
                }
                let waitInterval = min(checkInterval, remaining)
                let result = semaphore.wait(timeout: .now() + waitInterval)

                if result == .success {
                    // 请求完成
                    break
                }

                // 检查是否已被中断
                if executionState.isInterrupted() {
                    task.cancel()
                    log.info("[JS \(pluginId)] Fetch cancelled due to script interruption")
                    return Self.createFetchError(context: jsContext, message: "Request cancelled")
                }
            }

            if Date() >= deadline {
                task.cancel()
                log.error("[JS \(pluginId)] Fetch timeout: \(urlString)")
                return Self.createFetchError(context: jsContext, message: "Request timeout")
            }

            if let error = requestError {
                log.error("[JS \(pluginId)] Fetch error: \(error.localizedDescription)")
                return Self.createFetchError(context: jsContext, message: error.localizedDescription)
            }

            if let data = responseData, data.count > Self.maxFetchResponseBytes {
                log.error("[JS \(pluginId)] Fetch response too large (\(data.count) bytes): \(urlString)")
                return Self.createFetchError(context: jsContext, message: "Response too large")
            }

            // 创建响应对象
            return Self.createFetchResponse(
                context: jsContext,
                data: responseData,
                status: httpResponse?.statusCode ?? 0,
                statusText: HTTPURLResponse.localizedString(forStatusCode: httpResponse?.statusCode ?? 0)
            )
        }

        context.setObject(fetchSync, forKeyedSubscript: "__deckFetchSync" as NSString)

        // 创建同步 thenable 的 fetch 包装器（避免返回原生 Promise）
        context.evaluateScript("""
            var fetch = function(url, options) {
                var response = __deckFetchSync(url, options);

                response.then = function(onFulfilled, onRejected) {
                    if (response && response.error) {
                        if (onRejected) { return onRejected(new Error(response.error)); }
                        throw new Error(response.error);
                    }
                    return onFulfilled ? onFulfilled(response) : response;
                };

                response.catch = function(onRejected) {
                    if (response && response.error) {
                        if (onRejected) { return onRejected(new Error(response.error)); }
                        throw new Error(response.error);
                    }
                    return response;
                };

                return response;
            };
        """)

        log.info("Network API enabled for plugin: \(pluginId)")
    }

    /// 创建 fetch 错误响应
    private static func createFetchError(context: JSContext, message: String) -> JSValue {
        guard let errorObj = JSValue(newObjectIn: context) else {
            return JSValue(nullIn: context)
        }
        errorObj.setValue(message, forProperty: "error")
        return errorObj
    }

    /// 创建 fetch 成功响应
    private static func createFetchResponse(context: JSContext, data: Data?, status: Int, statusText: String) -> JSValue {
        guard let response = JSValue(newObjectIn: context) else {
            return JSValue(nullIn: context)
        }
        response.setValue(status, forProperty: "status")
        response.setValue(statusText, forProperty: "statusText")
        response.setValue(status >= 200 && status < 300, forProperty: "ok")

        // text() 方法
        let textFunc: @convention(block) () -> String = {
            guard let data = data, let text = String(data: data, encoding: .utf8) else {
                return ""
            }
            return text
        }
        response.setValue(JSValue(object: textFunc, in: context), forProperty: "text")

        // json() 方法
        let jsonFunc: @convention(block) () -> JSValue = {
            guard let data = data else {
                return JSValue(nullIn: context)
            }
            do {
                let json = try JSONSerialization.jsonObject(with: data)
                return JSValue(object: json, in: context)
            } catch {
                return JSValue(nullIn: context)
            }
        }
        response.setValue(JSValue(object: jsonFunc, in: context), forProperty: "json")

        return response
    }

    // MARK: - Network Permission Management

    /// 授权插件网络权限
    func authorizeNetworkPermission(for pluginId: String) {
        let scriptHash: String? = {
            pluginsLock.lock()
            defer { pluginsLock.unlock() }
            return plugins.first(where: { $0.id == pluginId })?.scriptHash
        }()
        DeckUserDefaults.authorizeNetworkPlugin(pluginId: pluginId, scriptHash: scriptHash)
        log.info("Authorized network permission for plugin: \(pluginId)")
    }

    /// 撤销插件网络权限
    func revokeNetworkPermission(for pluginId: String) {
        DeckUserDefaults.revokeNetworkPlugin(pluginId: pluginId)
        log.info("Revoked network permission for plugin: \(pluginId)")
    }

    // MARK: - Plugin Directory

    /// 打开脚本目录
    func openScriptsDirectory() {
        NSWorkspace.shared.open(scriptsDirectoryURL)
    }

    /// 获取脚本目录路径
    var scriptsPath: String {
        scriptsDirectoryURL.path
    }
}
