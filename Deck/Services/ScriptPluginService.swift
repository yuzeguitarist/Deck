//
//  ScriptPluginService.swift
//  Deck
//
//  Scriptable Transformers using JavaScriptCore
//  Scripts are loaded from ~/.deck/scripts/
//

import AppKit
import Foundation
import JavaScriptCore

// MARK: - Script Plugin Model

struct ScriptPlugin: Identifiable, Codable {
    let id: String
    let name: String
    let description: String?
    let author: String?
    let version: String?
    let scriptPath: String
    let icon: String?
    let requiresNetwork: Bool  // 是否需要网络权限

    var displayName: String {
        name
    }

    var displayIcon: String {
        icon ?? "scroll"
    }

    /// 是否已获得网络权限授权
    var isNetworkAuthorized: Bool {
        guard requiresNetwork else { return false }
        return DeckUserDefaults.authorizedNetworkPlugins.contains(id)
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
    private var contexts: [String: JSContext] = [:]

    /// 脚本目录路径
    private var scriptsDirectoryURL: URL {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        return homeDir.appendingPathComponent(".deck/scripts", isDirectory: true)
    }

    private init() {
        ensureScriptsDirectory()
        loadPlugins()
    }

    // MARK: - Directory Setup

    /// 确保脚本目录存在
    private func ensureScriptsDirectory() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: scriptsDirectoryURL.path) {
            do {
                try fm.createDirectory(at: scriptsDirectoryURL, withIntermediateDirectories: true)
                log.info("Created scripts directory: \(scriptsDirectoryURL.path)")

                // 创建示例脚本
                createExampleScripts()
            } catch {
                log.error("Failed to create scripts directory: \(error)")
            }
        }
    }

    /// 创建示例脚本
    private func createExampleScripts() {
        // 创建 base64-encode 示例
        let base64Dir = scriptsDirectoryURL.appendingPathComponent("base64-encode", isDirectory: true)
        createExampleScript(
            at: base64Dir,
            manifest: ScriptManifest(
                name: "Base64 编码",
                description: "将文本转换为 Base64 编码",
                author: "Deck",
                version: "1.0.0",
                main: "index.js",
                icon: "lock",
                permissions: nil
            ),
            script: """
            function transform(input) {
                return btoa(unescape(encodeURIComponent(input)));
            }
            """
        )

        // 创建 base64-decode 示例
        let base64DecodeDir = scriptsDirectoryURL.appendingPathComponent("base64-decode", isDirectory: true)
        createExampleScript(
            at: base64DecodeDir,
            manifest: ScriptManifest(
                name: "Base64 解码",
                description: "将 Base64 编码转换回文本",
                author: "Deck",
                version: "1.0.0",
                main: "index.js",
                icon: "lock.open",
                permissions: nil
            ),
            script: """
            function transform(input) {
                try {
                    return decodeURIComponent(escape(atob(input)));
                } catch (e) {
                    return "解码失败: " + e.message;
                }
            }
            """
        )

        // 创建 word-count 示例
        let wordCountDir = scriptsDirectoryURL.appendingPathComponent("word-count", isDirectory: true)
        createExampleScript(
            at: wordCountDir,
            manifest: ScriptManifest(
                name: "字数统计",
                description: "统计文本的字符数、单词数和行数",
                author: "Deck",
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

                return "字符数: " + chars + "\\n" +
                       "字符数(不含空格): " + charsNoSpace + "\\n" +
                       "单词数: " + words + "\\n" +
                       "行数: " + lines;
            }
            """
        )

        // 创建 url-encode 示例
        let urlEncodeDir = scriptsDirectoryURL.appendingPathComponent("url-encode", isDirectory: true)
        createExampleScript(
            at: urlEncodeDir,
            manifest: ScriptManifest(
                name: "URL 编码",
                description: "对文本进行 URL 编码",
                author: "Deck",
                version: "1.0.0",
                main: "index.js",
                icon: "link",
                permissions: nil
            ),
            script: """
            function transform(input) {
                return encodeURIComponent(input);
            }
            """
        )

        // 创建 url-decode 示例
        let urlDecodeDir = scriptsDirectoryURL.appendingPathComponent("url-decode", isDirectory: true)
        createExampleScript(
            at: urlDecodeDir,
            manifest: ScriptManifest(
                name: "URL 解码",
                description: "对 URL 编码的文本进行解码",
                author: "Deck",
                version: "1.0.0",
                main: "index.js",
                icon: "link",
                permissions: nil
            ),
            script: """
            function transform(input) {
                try {
                    return decodeURIComponent(input);
                } catch (e) {
                    return "解码失败: " + e.message;
                }
            }
            """
        )

        log.info("Created example scripts")
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

    /// 重新加载所有插件
    func reloadPlugins() {
        contexts.removeAll()
        loadPlugins()
    }

    /// 加载所有插件
    private func loadPlugins() {
        plugins.removeAll()

        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: scriptsDirectoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) else {
            log.warn("Cannot read scripts directory")
            return
        }

        for url in contents {
            guard let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey]),
                  resourceValues.isDirectory == true else {
                continue
            }

            if let plugin = loadPlugin(from: url) {
                plugins.append(plugin)
            }
        }

        log.info("Loaded \(plugins.count) script plugins")
    }

    /// 从目录加载单个插件
    private func loadPlugin(from directory: URL) -> ScriptPlugin? {
        let manifestURL = directory.appendingPathComponent("manifest.json")

        guard let manifestData = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(ScriptManifest.self, from: manifestData) else {
            log.warn("Invalid or missing manifest.json in \(directory.lastPathComponent)")
            return nil
        }

        let scriptPath = directory.appendingPathComponent(manifest.main).path

        guard FileManager.default.fileExists(atPath: scriptPath) else {
            log.warn("Script file not found: \(scriptPath)")
            return nil
        }

        return ScriptPlugin(
            id: directory.lastPathComponent,
            name: manifest.name,
            description: manifest.description,
            author: manifest.author,
            version: manifest.version,
            scriptPath: scriptPath,
            icon: manifest.icon,
            requiresNetwork: manifest.permissions?.network ?? false
        )
    }

    // MARK: - Script Execution
    
    /// 用于追踪正在执行的脚本任务
    private var runningTasks: [String: Bool] = [:]

    /// 执行脚本转换（带安全检查）
    func executeTransform(pluginId: String, input: String) -> ScriptResult {
        guard let plugin = plugins.first(where: { $0.id == pluginId }) else {
            return ScriptResult(success: false, output: nil, error: "插件不存在")
        }

        // 输入长度检查
        let maxInput = DeckUserDefaults.scriptMaxInputLength
        guard input.count <= maxInput else {
            return ScriptResult(
                success: false,
                output: nil,
                error: "输入超过最大长度限制 (\(maxInput) 字符)"
            )
        }

        // 执行脚本（带超时）
        let result = executeScriptWithTimeout(plugin: plugin, input: input)

        // 输出长度检查
        if let output = result.output, output.count > Const.scriptMaxOutputLength {
            return ScriptResult(
                success: false,
                output: nil,
                error: "输出超过最大长度限制 (\(Const.scriptMaxOutputLength) 字符)"
            )
        }

        return result
    }

    /// 带超时的脚本执行
    /// 注意：JavaScriptCore 没有真正的中断机制，死循环脚本会继续在后台运行直到完成
    /// 但超时后会立即返回错误，不会阻塞调用者
    private func executeScriptWithTimeout(plugin: ScriptPlugin, input: String) -> ScriptResult {
        let timeout = TimeInterval(DeckUserDefaults.scriptTimeout)
        let executionId = UUID().uuidString
        
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
        
        // 标记任务开始
        runningTasks[executionId] = true
        
        // 在独立线程执行脚本（使用较低优先级避免影响 UI）
        let scriptQueue = DispatchQueue(label: "deck.script.\(executionId)", qos: .utility)
        scriptQueue.async { [weak self] in
            guard let self else {
                semaphore.signal()
                return
            }
            
            // 检查是否已被标记为超时
            guard self.runningTasks[executionId] == true else {
                semaphore.signal()
                return
            }
            
            let result = self.executeScript(plugin: plugin, input: input)
            resultBox.setResult(result)
            semaphore.signal()
        }

        // 等待执行完成或超时
        let waitResult = semaphore.wait(timeout: .now() + timeout)
        
        resultBox.markCompleted()
        
        // 清理任务追踪
        runningTasks.removeValue(forKey: executionId)

        if waitResult == .timedOut {
            // 标记上下文为已中断（用于 fetch 等检查）
            if let context = contexts[plugin.id] {
                context.setObject(true, forKeyedSubscript: "__deckInterrupted" as NSString)
            }
            
            // 移除上下文缓存，强制下次创建新的
            // 注意：正在执行的脚本可能仍在后台运行，但不会影响后续执行
            contexts.removeValue(forKey: plugin.id)
            
            log.warn("Script \(plugin.id) execution timed out after \(Int(timeout)) seconds. " +
                     "Note: The script may continue running in background until completion.")
            
            return ScriptResult(
                success: false,
                output: nil,
                error: "脚本执行超时（超过 \(Int(timeout)) 秒）\n注意：包含死循环的脚本可能仍在后台运行"
            )
        }

        return resultBox.result ?? ScriptResult(success: false, output: nil, error: "执行失败")
    }

    /// 执行脚本（内部方法，不带安全检查）
    private func executeScript(plugin: ScriptPlugin, input: String) -> ScriptResult {
        // 每次执行都创建新的 JSContext，确保干净的执行环境
        // 这样超时后旧的 context 会被丢弃，不影响后续执行
        guard let context = createContext(for: plugin) else {
            return ScriptResult(success: false, output: nil, error: "无法创建 JavaScript 环境")
        }
        
        // 更新缓存（用于中断检查）
        contexts[plugin.id] = context

        // 调用 transform 函数
        guard let transformFunc = context.objectForKeyedSubscript("transform"),
              !transformFunc.isUndefined else {
            return ScriptResult(success: false, output: nil, error: "脚本中未定义 transform 函数")
        }
        
        // 检查是否已被中断
        if let interrupted = context.objectForKeyedSubscript("__deckInterrupted"), interrupted.toBool() {
            return ScriptResult(success: false, output: nil, error: "脚本已被中断")
        }

        // 执行转换
        let result = transformFunc.call(withArguments: [input])
        
        // 再次检查中断状态
        if let interrupted = context.objectForKeyedSubscript("__deckInterrupted"), interrupted.toBool() {
            return ScriptResult(success: false, output: nil, error: "脚本已被中断")
        }

        // 检查异常
        if let exception = context.exception {
            let errorMessage = exception.toString() ?? "未知错误"
            context.exception = nil  // 清除异常
            return ScriptResult(success: false, output: nil, error: errorMessage)
        }

        // 获取结果
        guard let outputString = result?.toString() else {
            return ScriptResult(success: false, output: nil, error: "转换结果无效")
        }

        return ScriptResult(success: true, output: outputString, error: nil)
    }

    /// 创建 JSContext
    private func createContext(for plugin: ScriptPlugin) -> JSContext? {
        guard let context = JSContext() else { return nil }

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
            guard let ctx = context,
                  let interrupted = ctx.objectForKeyedSubscript("__deckInterrupted") else {
                return false
            }
            return interrupted.toBool()
        }
        context.setObject(checkInterrupt, forKeyedSubscript: "__deckCheckInterrupt" as NSString)

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
                }
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
            setupNetworkAPI(context: context, pluginId: plugin.id)
        }

        // 加载脚本
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
    private func setupNetworkAPI(context: JSContext, pluginId: String) {
        // 同步 fetch 实现（因为 JSContext 不支持原生 Promise）
        // 使用 __deckFetch 作为底层实现
        // 支持中断检查
        let fetchSync: @convention(block) (String, JSValue?) -> JSValue = { [weak context] urlString, options in
            guard let context = context else {
                return JSValue(nullIn: context)
            }
            
            // 检查是否已被中断
            if let interrupted = context.objectForKeyedSubscript("__deckInterrupted"), interrupted.toBool() {
                return Self.createFetchError(context: context, message: "Script interrupted")
            }

            guard let url = URL(string: urlString) else {
                log.error("[JS \(pluginId)] Invalid URL: \(urlString)")
                return Self.createFetchError(context: context, message: "Invalid URL")
            }

            // 解析 options
            var request = URLRequest(url: url)
            request.timeoutInterval = 10  // 10秒超时

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

            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                responseData = data
                httpResponse = response as? HTTPURLResponse
                requestError = error
                semaphore.signal()
            }
            task.resume()

            // 等待请求完成，但定期检查中断状态
            let checkInterval: TimeInterval = 0.5
            let maxWaitTime: TimeInterval = 10
            var elapsedTime: TimeInterval = 0
            
            while elapsedTime < maxWaitTime {
                let result = semaphore.wait(timeout: .now() + checkInterval)
                
                if result == .success {
                    // 请求完成
                    break
                }
                
                elapsedTime += checkInterval
                
                // 检查是否已被中断
                if let interrupted = context.objectForKeyedSubscript("__deckInterrupted"), interrupted.toBool() {
                    task.cancel()
                    log.info("[JS \(pluginId)] Fetch cancelled due to script interruption")
                    return Self.createFetchError(context: context, message: "Request cancelled")
                }
            }
            
            if elapsedTime >= maxWaitTime {
                task.cancel()
                log.error("[JS \(pluginId)] Fetch timeout: \(urlString)")
                return Self.createFetchError(context: context, message: "Request timeout")
            }

            if let error = requestError {
                log.error("[JS \(pluginId)] Fetch error: \(error.localizedDescription)")
                return Self.createFetchError(context: context, message: error.localizedDescription)
            }

            // 创建响应对象
            return Self.createFetchResponse(
                context: context,
                data: responseData,
                status: httpResponse?.statusCode ?? 0,
                statusText: HTTPURLResponse.localizedString(forStatusCode: httpResponse?.statusCode ?? 0)
            )
        }

        context.setObject(fetchSync, forKeyedSubscript: "__deckFetchSync" as NSString)

        // 创建兼容 fetch API 的包装器
        context.evaluateScript("""
            var fetch = function(url, options) {
                return new Promise(function(resolve, reject) {
                    try {
                        var response = __deckFetchSync(url, options);
                        if (response.error) {
                            reject(new Error(response.error));
                        } else {
                            resolve(response);
                        }
                    } catch (e) {
                        reject(e);
                    }
                });
            };

            // 简单的 Promise polyfill（如果不存在）
            if (typeof Promise === 'undefined') {
                var Promise = function(executor) {
                    var self = this;
                    self._state = 'pending';
                    self._value = undefined;
                    self._handlers = [];

                    function resolve(value) {
                        if (self._state !== 'pending') return;
                        self._state = 'fulfilled';
                        self._value = value;
                        self._handlers.forEach(function(h) { h.onFulfilled(value); });
                    }

                    function reject(reason) {
                        if (self._state !== 'pending') return;
                        self._state = 'rejected';
                        self._value = reason;
                        self._handlers.forEach(function(h) { h.onRejected(reason); });
                    }

                    try { executor(resolve, reject); } catch (e) { reject(e); }
                };

                Promise.prototype.then = function(onFulfilled, onRejected) {
                    var self = this;
                    return new Promise(function(resolve, reject) {
                        function handle(value) {
                            try {
                                var result = onFulfilled ? onFulfilled(value) : value;
                                resolve(result);
                            } catch (e) { reject(e); }
                        }
                        function handleReject(reason) {
                            try {
                                if (onRejected) {
                                    resolve(onRejected(reason));
                                } else {
                                    reject(reason);
                                }
                            } catch (e) { reject(e); }
                        }
                        if (self._state === 'fulfilled') handle(self._value);
                        else if (self._state === 'rejected') handleReject(self._value);
                        else self._handlers.push({ onFulfilled: handle, onRejected: handleReject });
                    });
                };

                Promise.prototype.catch = function(onRejected) {
                    return this.then(null, onRejected);
                };
            }
        """)

        log.info("Network API enabled for plugin: \(pluginId)")
    }

    /// 创建 fetch 错误响应
    private static func createFetchError(context: JSContext, message: String) -> JSValue {
        let errorObj = JSValue(newObjectIn: context)!
        errorObj.setValue(message, forProperty: "error")
        return errorObj
    }

    /// 创建 fetch 成功响应
    private static func createFetchResponse(context: JSContext, data: Data?, status: Int, statusText: String) -> JSValue {
        let response = JSValue(newObjectIn: context)!
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
        var authorized = DeckUserDefaults.authorizedNetworkPlugins
        if !authorized.contains(pluginId) {
            authorized.append(pluginId)
            DeckUserDefaults.authorizedNetworkPlugins = authorized
        }
        // 清除缓存的 context 以便重新创建
        contexts.removeValue(forKey: pluginId)
        log.info("Authorized network permission for plugin: \(pluginId)")
    }

    /// 撤销插件网络权限
    func revokeNetworkPermission(for pluginId: String) {
        var authorized = DeckUserDefaults.authorizedNetworkPlugins
        authorized.removeAll { $0 == pluginId }
        DeckUserDefaults.authorizedNetworkPlugins = authorized
        // 清除缓存的 context
        contexts.removeValue(forKey: pluginId)
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
