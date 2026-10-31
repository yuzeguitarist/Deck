// Copyright © 2024–2026 Yuze Pan. 保留一切权利。

//
//  AppDelegate.swift
//  Deck
//
//  Deck Clipboard Manager
//

import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject {
    static var shared: AppDelegate?

    // Debug: set true to always show the welcome guide on launch.
    private let forceWelcomeGuideOnLaunch = false

    private var menuBarItem: NSStatusItem?
    private let statusBarIconState = StatusBarIconState()
    private var pauseMenuItem: NSMenuItem?
    private var pauseSubmenu: NSMenu?
    private var pauseStateObserver: NSObjectProtocol?
    private var databaseErrorObserver: NSObjectProtocol?
    private var orbitBridgeObserver: NSObjectProtocol?
    private var hasShownAccessibilityPermissionAlert = false

    private lazy var statusMenu: NSMenu = {
        let menu = NSMenu(title: "Deck")

        let showItem = NSMenuItem(
            title: NSLocalizedString("显示 Deck", comment: "Menu bar: Show Deck"),
            action: #selector(showMainWindow),
            keyEquivalent: "p"
        )
        showItem.keyEquivalentModifierMask = .command
        menu.addItem(showItem)

        menu.addItem(NSMenuItem.separator())

        // 暂停记录菜单项
        pauseMenuItem = NSMenuItem(
            title: NSLocalizedString("暂停记录", comment: "Menu bar: Pause recording"),
            action: nil,
            keyEquivalent: ""
        )
        pauseMenuItem?.image = NSImage(systemSymbolName: "pause.circle", accessibilityDescription: nil)
        pauseSubmenu = buildPauseSubmenu()
        pauseMenuItem?.submenu = pauseSubmenu
        if let pauseMenuItem { menu.addItem(pauseMenuItem) }

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(
            title: NSLocalizedString("偏好设置...", comment: "Menu bar: Preferences"),
            action: #selector(showSettings),
            keyEquivalent: ","
        )
        settingsItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        menu.addItem(settingsItem)

        let feedbackItem = NSMenuItem(
            title: NSLocalizedString("反馈意见", comment: "Menu bar: Feedback"),
            action: #selector(sendFeedback),
            keyEquivalent: ""
        )
        feedbackItem.image = NSImage(systemSymbolName: "paperplane", accessibilityDescription: nil)
        menu.addItem(feedbackItem)

        menu.addItem(NSMenuItem.separator())

        let versionItem = NSMenuItem(
            title: currentVersionMenuTitle(),
            action: nil,
            keyEquivalent: ""
        )
        versionItem.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)
        versionItem.isEnabled = false
        menu.addItem(versionItem)

        let checkUpdateItem = NSMenuItem(
            title: NSLocalizedString("检查更新", comment: "Menu bar: Check for updates"),
            action: #selector(checkForUpdatesFromMenu),
            keyEquivalent: ""
        )
        checkUpdateItem.image = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: nil)
        menu.addItem(checkUpdateItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: NSLocalizedString("退出 Deck", comment: "Menu bar: Quit Deck"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)

        return menu
    }()

    private lazy var mainWindowController = MainWindowController.shared
    private lazy var settingsWindowController = SettingsWindowController.shared

    private func buildPauseSubmenu() -> NSMenu {
        let submenu = NSMenu()

        let resumeItem = NSMenuItem(
            title: NSLocalizedString("恢复记录", comment: "Pause menu: Resume recording"),
            action: #selector(resumeRecording),
            keyEquivalent: ""
        )
        resumeItem.image = NSImage(systemSymbolName: "play.circle", accessibilityDescription: nil)
        submenu.addItem(resumeItem)

        submenu.addItem(NSMenuItem.separator())

        let pause5min = NSMenuItem(
            title: NSLocalizedString("暂停 5 分钟", comment: "Pause menu: Pause 5 minutes"),
            action: #selector(pause5Minutes),
            keyEquivalent: ""
        )
        submenu.addItem(pause5min)

        let pause15min = NSMenuItem(
            title: NSLocalizedString("暂停 15 分钟", comment: "Pause menu: Pause 15 minutes"),
            action: #selector(pause15Minutes),
            keyEquivalent: ""
        )
        submenu.addItem(pause15min)

        let pause30min = NSMenuItem(
            title: NSLocalizedString("暂停 30 分钟", comment: "Pause menu: Pause 30 minutes"),
            action: #selector(pause30Minutes),
            keyEquivalent: ""
        )
        submenu.addItem(pause30min)

        let pause1hour = NSMenuItem(
            title: NSLocalizedString("暂停 1 小时", comment: "Pause menu: Pause 1 hour"),
            action: #selector(pause1Hour),
            keyEquivalent: ""
        )
        submenu.addItem(pause1hour)

        submenu.addItem(NSMenuItem.separator())

        let pauseIndefinite = NSMenuItem(
            title: NSLocalizedString("暂停直到手动恢复", comment: "Pause menu: Pause indefinitely"),
            action: #selector(pauseIndefinitely),
            keyEquivalent: ""
        )
        submenu.addItem(pauseIndefinite)

        return submenu
    }
}

// MARK: - NSApplicationDelegate

extension AppDelegate: NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        
        // Hide from Dock, show only in menu bar
        NSApp.setActivationPolicy(.accessory)

        // Memory-benchmark host: open an isolated database and do not start
        // clipboard monitoring, CLI install, sync, or the welcome window.
        if MemOptIsolation.isActive {
            setvbuf(stdout, nil, _IONBF, 0)
            setvbuf(stderr, nil, _IONBF, 0)
            DeckSQLManager.shared.configureSensitiveCacheObservation()
            DeckDataStore.shared.setup()
            Task { @MainActor in
                do {
                    try await MemOptBenchmark.run()
                    fputs("MEMOPT_OK\n", stdout)
                    fflush(stdout)
                    Darwin.exit(EXIT_SUCCESS)
                } catch {
                    fputs("MEMOPT_FAIL \(error)\n", stderr)
                    fflush(stderr)
                    Darwin.exit(EXIT_FAILURE)
                }
            }
            return
        }
        
        initializeApp()
        applyAppearanceSettings()
        
        // Show welcome guide on first launch or when forced for debugging.
        let shouldForceWelcome = forceWelcomeGuideOnLaunch
        if shouldForceWelcome || !DeckUserDefaults.hasLaunchedBefore {
            if !DeckUserDefaults.hasLaunchedBefore {
                DeckUserDefaults.hasLaunchedBefore = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                WelcomeWindowController.shared.show()
            }
        }
    }
    
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        ClipboardService.shared.shutdown()
        CLIBridgeService.shared.stop()
        DeckClipSocketService.shared.stop()
        IOSSyncService.shared.stop()
        if let pauseStateObserver {
            NotificationCenter.default.removeObserver(pauseStateObserver)
        }
        if let databaseErrorObserver {
            NotificationCenter.default.removeObserver(databaseErrorObserver)
        }
        if let orbitBridgeObserver {
            DistributedNotificationCenter.default().removeObserver(orbitBridgeObserver)
        }
    }

    /// Handle deck:// URL scheme
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            handleOpenURL(url)
        }
    }

    private func handleOpenURL(_ url: URL) {
        // Handle deck:// URLs
        if url.scheme == "deck" {
            handleDeckURL(url)
            return
        }

        // Handle .deckrule file URLs
        if url.pathExtension == "deckrule" {
            handleDeckRuleFile(url)
        }
    }

    private func handleDeckURL(_ url: URL) {
        if PluginStoreDeepLinkInstaller.shared.handleIfNeeded(url) {
            return
        }

        if handleDeckBridgeDeepLink(url) {
            return
        }

        guard url.host == "install-rule" else {
            log.warn("Unknown deck:// URL: \(url)")
            return
        }

        // Parse rule from URL
        guard let rules = SmartRuleService.shared.parseShareURL(url) else {
            showAlert(
                title: "无法导入规则",
                message: "链接格式无效或已损坏。",
                style: .warning
            )
            return
        }

        // Show confirmation
        let ruleNames = rules.map { $0.name }.joined(separator: ", ")
        let message = "是否导入以下规则？\n\n\(ruleNames)"

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "导入智能规则"
        alert.informativeText = message
        alert.addButton(withTitle: "导入")
        alert.addButton(withTitle: "取消")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            SmartRuleService.shared.addImportedRules(rules)
            showAlert(
                title: "导入成功",
                message: "已成功导入 \(rules.count) 条规则。",
                style: .informational
            )
        }
    }

    /// `deck://panel/toggle` · `deck://paste?index=1`（与 CLI Bridge HTTP 行为一致，见 `Resources/CLI_BRIDGE.md`）
    private func handleDeckBridgeDeepLink(_ url: URL) -> Bool {
        guard url.scheme == "deck" else { return false }

        let host = url.host?.lowercased() ?? ""
        let path = url.path.trimmingCharacters(in: .whitespaces)

        if host == "panel" {
            let isToggle = path == "/toggle" || path == "/toggle/"
            guard isToggle else { return false }
            DeckCLIBridgeActions.togglePanel()
            return true
        }

        if host == "paste" {
            let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let queryItems = comps?.queryItems ?? []
            var queryValues: [String: String?] = [:]
            var seenQueryNames = Set<String>()
            queryValues.reserveCapacity(queryItems.count)
            seenQueryNames.reserveCapacity(queryItems.count)
            for item in queryItems {
                let key = item.name.lowercased()
                guard seenQueryNames.insert(key).inserted else { continue }
                queryValues.updateValue(item.value, forKey: key)
            }
            func first(_ name: String) -> String? {
                guard let value = queryValues[name.lowercased()] else { return nil }
                return value
            }
            guard let indexStr = first("index") ?? first("n"), let index = Int(indexStr), (1...9).contains(index) else {
                log.warn("deck://paste missing index=1...9: \(url)")
                return true
            }

            let asPlainText = (first("asPlainText")).flatMap { parseDeckBridgeBool($0) } ?? false
            let pasteboardOnly = (first("pasteboardOnly")).flatMap { parseDeckBridgeBool($0) } ?? false
            let targetBundleId: String? = {
                guard let t = first("targetBundleId")?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
                return t
            }()
            let selectedItemId: Int64? = (first("selectedItemId")).flatMap { Int64($0) }
            // A deck:// URL does not reliably identify the app that invoked it. Without an
            // explicit targetBundleId, keep the action safe and deterministic: authenticate,
            // copy the resolved item to the pasteboard, and never jump to a stale preApp.
            let shouldPasteboardOnly = pasteboardOnly || targetBundleId == nil

            Task { @MainActor in
                _ = await DeckCLIBridgeActions.quickPaste(
                    index: index,
                    selectedItemId: selectedItemId,
                    asPlainText: asPlainText,
                    pasteboardOnly: shouldPasteboardOnly,
                    targetBundleId: targetBundleId,
                    requiresAuthentication: true,
                    authenticationReason: NSLocalizedString(
                        "验证身份以允许 deck:// 链接粘贴剪贴板内容",
                        comment: "deck deep link paste authentication reason"
                    )
                )
            }
            return true
        }

        return false
    }

    private func parseDeckBridgeBool(_ raw: String) -> Bool? {
        switch raw.lowercased() {
        case "1", "true", "yes", "on": return true
        case "0", "false", "no", "off": return false
        default: return nil
        }
    }

    private func handleDeckRuleFile(_ url: URL) {
        do {
            let rules = try SmartRuleService.shared.importRules(from: url)

            let ruleNames = rules.map { $0.name }.joined(separator: ", ")
            let message = "是否导入以下规则？\n\n\(ruleNames)"

            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = "导入智能规则"
            alert.informativeText = message
            alert.addButton(withTitle: "导入")
            alert.addButton(withTitle: "取消")

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                SmartRuleService.shared.addImportedRules(rules)
                showAlert(
                    title: "导入成功",
                    message: "已成功导入 \(rules.count) 条规则。",
                    style: .informational
                )
            }
        } catch {
            showAlert(
                title: "导入失败",
                message: "无法读取规则文件: \(error.localizedDescription)",
                style: .warning
            )
        }
    }

    private func showAlert(title: String, message: String, style: NSAlert.Style) {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "确定")
        alert.runModal()
    }
    
    private func initializeApp() {
        logInputMonitoringStartupState()

        // Setup menu bar
        setupMenuBar()

        // Initialize context-aware service early to capture last non-Deck app
        _ = ContextAwareService.shared

        // Start clipboard monitoring
        ClipboardService.shared.startListening()

        // Initialize data store
        DeckSQLManager.shared.configureSensitiveCacheObservation()
        DeckDataStore.shared.setup()

        // Pre-generate Orbit bridge token to avoid first-request races.
        OrbitBridgeAuth.ensureTokenReady()

        // [Legacy] HTTP CLI Bridge — disabled by default, preserved for backward compatibility.
        // Users who have explicitly enabled it in Settings will still get it.
        // New integrations should use DeckClip UDS protocol instead.
        // CLIBridgeService.shared.start()

        // Start Orbit CLI bridge (always on)
        OrbitCLIBridgeService.shared.start()

        // ─── DeckClip UDS ───
        DeckClipAuth.ensureTokenReady()
        DeckClipAuth.writeLocaleFile()
        DeckClipPeerValidator.shared.initialize()
        if DeckUserDefaults.cliBridgeEnabled {
            DeckClipSocketService.shared.start()
        }
        DeckCLIInstaller.installIfNeeded()

        IOSSyncService.shared.applyUserDefaultsState()

        // Setup LAN sharing callbacks
        setupMultipeerCallbacks()
        setupDirectConnectCallbacks()

        // Initialize hotkey manager
        HotKeyManager.shared.initialize()

        // Initialize paste queue service to register the queue paste handler
        _ = PasteQueueService.shared

        // Check accessibility permission
        checkAccessibilityPermission()

        // Initialize cursor assistant (if enabled)
        initializeCursorAssistant()

        // Schedule update checks (daily at Beijing 8pm)
        UpdateNotificationManager.shared.start()
        UpdateCoordinator.shared.start()
        UpdateService.shared.restoreAvailableUpdateFromPersistedRecord()
        UpdateService.shared.autoCheckIfNeeded()
        let didRemoveCurrentUpdate = UpdateService.shared.cleanupUpdateArtifactsForCurrentVersion()
        let removedBackups = UpdateService.shared.cleanupOldAppBackupsInApplications()
        let didRemovePostUpdateArtifacts = didRemoveCurrentUpdate || removedBackups > 0
        schedulePostUpdateCongratsIfNeeded(didRemoveCurrentUpdate: didRemovePostUpdateArtifacts)

        // Schedule diagnostics uploads (daily at local 3pm)
        DiagnosticsUploadService.shared.start()

        scheduleDeferredPerformanceWarmups()

        // 监听暂停状态变化
        pauseStateObserver = NotificationCenter.default.addObserver(
            forName: .clipboardPauseStateChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updatePauseState()
            }
        }
        updatePauseState()

        // 监听数据库错误
        databaseErrorObserver = NotificationCenter.default.addObserver(
            forName: .databaseError,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let message = userInfo["message"] as? String,
                  let isCritical = userInfo["isCritical"] as? Bool else { return }
            MainActor.assumeIsolated {
                self?.handleDatabaseError(message: message, isCritical: isCritical)
            }
        }

        orbitBridgeObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("DeckOrbitBridgeAction"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let action = userInfo["action"] as? String else { return }
            let uniqueIds = userInfo["uniqueIds"] as? [String] ?? []
            MainActor.assumeIsolated {
                self?.handleOrbitBridgeNotification(action: action, uniqueIds: uniqueIds)
            }
        }
    }

    private func logInputMonitoringStartupState() {
        log.info(
            "InputMonitoringStartup: inputMonitoring=energyOptimizedDefault; copyMonitor=flagsChanged -> temporary keyDown while Command is held; deckShortcuts=flagsChanged -> temporary keyDown for Deck shortcut chords"
        )
    }

    private func scheduleDeferredPerformanceWarmups() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            SystemSharingService.prewarmCachedServices()
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1.2) {
            _ = ScriptPluginService.shared
        }
    }

    private func handleOrbitBridgeNotification(action: String, uniqueIds: [String]) {
        switch action {
        case "delete":
            guard !uniqueIds.isEmpty else { return }
            Task { @MainActor in
                for id in uniqueIds {
                    _ = await DeckDataStore.shared.deleteItemByUniqueId(id)
                }
            }
        default:
            break
        }
    }

    private func handleDatabaseError(message: String, isCritical: Bool) {
        let alert = NSAlert()
        alert.alertStyle = isCritical ? .critical : .warning
        alert.messageText = isCritical ? "数据库错误" : "数据库警告"
        alert.informativeText = """
            \(message)

            这可能导致剪贴板历史无法正常保存。
            建议检查磁盘空间或重启应用。
            """
        alert.addButton(withTitle: "知道了")
        alert.addButton(withTitle: "打开设置")

        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            // 打开设置页面
            SettingsWindowController.shared.toggleWindow()
        }

        // 重置错误状态，允许再次通知
        DeckSQLManager.shared.resetErrorState()
    }

    private func schedulePostUpdateCongratsIfNeeded(didRemoveCurrentUpdate: Bool) {
        guard UpdateService.shared.shouldShowPostUpdateCongrats(didRemoveCurrentUpdate: didRemoveCurrentUpdate) else {
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            SettingsWindowController.shared.showWindow()
            self.showPostUpdateCongratsAlert()
        }
    }

    private func showPostUpdateCongratsAlert() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = NSLocalizedString("更新完成", comment: "Post update: title")
        alert.informativeText = NSLocalizedString("Deck 已更新到最新版本，感谢支持！", comment: "Post update: message")
        alert.addButton(withTitle: NSLocalizedString("好的", comment: "Post update: OK"))

        if let window = SettingsWindowController.shared.window {
            alert.beginSheetModal(for: window, completionHandler: nil)
        } else {
            alert.runModal()
        }
    }

    private func updatePauseState() {
        let isPaused = ClipboardService.shared.isPaused

        // 更新菜单栏图标
        updateMenuBarIcon(paused: isPaused)

        // 更新菜单标题
        if isPaused {
            if let endTime = ClipboardService.shared.pauseEndTime {
                let formatter = DateFormatter()
                formatter.timeStyle = .short
                pauseMenuItem?.title = String(format: NSLocalizedString("已暂停 (至 %@)", comment: "Pause state: Paused until time"), formatter.string(from: endTime))
            } else {
                pauseMenuItem?.title = NSLocalizedString("已暂停记录", comment: "Pause state: Recording paused")
            }
            pauseMenuItem?.image = NSImage(systemSymbolName: "pause.circle.fill", accessibilityDescription: nil)
        } else {
            pauseMenuItem?.title = NSLocalizedString("暂停记录", comment: "Menu bar: Pause recording")
            pauseMenuItem?.image = NSImage(systemSymbolName: "pause.circle", accessibilityDescription: nil)
        }
    }

    private func updateMenuBarIcon(paused: Bool) {
        statusBarIconState.isPaused = paused
    }
    
    private func checkAccessibilityPermission() {
        guard !AXIsProcessTrusted(), !hasShownAccessibilityPermissionAlert else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self, !AXIsProcessTrusted(), !self.hasShownAccessibilityPermissionAlert else {
                return
            }

            // After replacing the app bundle or refreshing a signed build,
            // tccd/LaunchServices can lag behind for a short moment. Confirm
            // the state one more time before telling the user the permission
            // is missing.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                guard let self, !AXIsProcessTrusted(), !self.hasShownAccessibilityPermissionAlert else {
                    return
                }

                self.hasShownAccessibilityPermissionAlert = true

                let alert = NSAlert()
                alert.messageText = NSLocalizedString("需要辅助功能权限", comment: "Accessibility permission required")
                alert.informativeText = NSLocalizedString(
                    "Deck 需要辅助功能权限才能自动粘贴内容到其它应用。\n\n请在系统设置中授权 Deck 访问辅助功能。如果列表里已经有 Deck 且开关是打开的（更新后签名变化会出现这种情况），请先选中它点「−」删除，再重新添加。",
                    comment: "Accessibility permission alert message"
                )
                alert.alertStyle = .informational
                alert.addButton(withTitle: NSLocalizedString("打开系统设置", comment: "Open System Settings"))
                alert.addButton(withTitle: NSLocalizedString("稍后设置", comment: "Set later"))

                let response = alert.runModal()
                if response == .alertFirstButtonReturn {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }
    
    private func applyAppearanceSettings() {
        let appearanceMode = AppearanceMode(rawValue: DeckUserDefaults.appearance) ?? .system

        DispatchQueue.main.async {
            switch appearanceMode {
            case .system:
                NSApp.appearance = nil
            case .light:
                NSApp.appearance = NSAppearance(named: .aqua)
            case .dark:
                NSApp.appearance = NSAppearance(named: .darkAqua)
            }
        }
    }

    private func initializeCursorAssistant() {
        // 初始化控制器（设置回调）
        _ = CursorAssistantController.shared

        // 根据设置启用/禁用
        CursorAssistantService.shared.isEnabled = DeckUserDefaults.cursorAssistantEnabled
    }
    
    private func setupMenuBar() {
        guard DeckUserDefaults.showInMenuBar else {
            removeMenuBarItem()
            return
        }

        guard menuBarItem == nil else {
            updateMenuBarIcon(paused: ClipboardService.shared.isPaused)
            return
        }

        menuBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        guard let menuBarItem = menuBarItem else { return }

        menuBarItem.isVisible = true

        let hostingView = NSHostingView(rootView: StatusBarIconSwiftUIView(state: statusBarIconState))
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        if let button = menuBarItem.button {
            button.image = nil
            button.addSubview(hostingView)
            NSLayoutConstraint.activate([
                hostingView.centerXAnchor.constraint(equalTo: button.centerXAnchor),
                hostingView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
                hostingView.widthAnchor.constraint(equalToConstant: 22),
                hostingView.heightAnchor.constraint(equalToConstant: 22),
            ])
        }
        menuBarItem.button?.target = self
        menuBarItem.button?.action = #selector(statusBarClick)
        menuBarItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        updateMenuBarIcon(paused: ClipboardService.shared.isPaused)
    }

    private func removeMenuBarItem() {
        guard let menuBarItem else { return }
        NSStatusBar.system.removeStatusItem(menuBarItem)
        self.menuBarItem = nil
    }
}

// MARK: - Actions

extension AppDelegate {
    func setMenuBarIconVisible(_ isVisible: Bool) {
        if isVisible {
            setupMenuBar()
        } else {
            removeMenuBarItem()
        }
    }

    @objc private func statusBarClick(sender: NSStatusBarButton) {
        guard let event = NSApplication.shared.currentEvent else { return }

        if event.type == .leftMouseUp {
            mainWindowController.toggleWindow()
        } else if event.type == .rightMouseUp {
            menuBarItem?.menu = statusMenu
            sender.performClick(nil)
            menuBarItem?.menu = nil
        }
    }

    @objc private func showMainWindow() {
        mainWindowController.toggleWindow()
    }

    @objc private func showSettings() {
        settingsWindowController.toggleWindow()
    }

    @objc private func sendFeedback() {
        FeedbackEmailService.shared.composeFeedbackEmail(source: .clipboardPanel)
    }

    @objc private func checkForUpdatesFromMenu() {
        Task { @MainActor in
            if let update = await UpdateService.shared.checkForUpdates(trigger: .settings) {
                UpdatePromptWindowController.shared.show(update: update)
                return
            }

            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = NSLocalizedString("已是最新版本", comment: "Menu bar: up to date title")
            alert.informativeText = NSLocalizedString("当前已是最新版本。", comment: "Menu bar: up to date message")
            alert.addButton(withTitle: NSLocalizedString("确定", comment: "Common: OK"))
            alert.runModal()
        }
    }

    private func currentVersionMenuTitle() -> String {
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        return String(format: NSLocalizedString("版本 %@", comment: "Menu bar: Version info"), appVersion)
    }

    // MARK: - Pause Actions

    @objc private func resumeRecording() {
        ClipboardService.shared.resumeRecording()
    }

    @objc private func pause5Minutes() {
        ClipboardService.shared.pauseRecording(for: 5 * 60)
    }

    @objc private func pause15Minutes() {
        ClipboardService.shared.pauseRecording(for: 15 * 60)
    }

    @objc private func pause30Minutes() {
        ClipboardService.shared.pauseRecording(for: 30 * 60)
    }

    @objc private func pause1Hour() {
        ClipboardService.shared.pauseRecording(for: 60 * 60)
    }

    @objc private func pauseIndefinitely() {
        ClipboardService.shared.pauseRecording()
    }

    // MARK: - LAN Sharing

    private func setupMultipeerCallbacks() {
        let multipeerService = MultipeerService.shared

        // 接收单个项目
        multipeerService.onDataReceived = { item, peer in
            log.info("Received item from \(peer.displayName)")
            DeckDataStore.shared.insertItem(item)
        }

        // 接收分组
        multipeerService.onGroupReceived = { groupName, colorHex, items, peer in
            log.info("Received group '\(groupName)' with \(items.count) items from \(peer.displayName)")
            Task { @MainActor in
                await DeckDataStore.shared.receiveGroup(name: groupName, colorHex: colorHex, items: items)
            }
        }

        // TOTP 验证码显示（作为接收方）
        multipeerService.onCodeRequired = { code in
            log.info("TOTP code generated: \(code)")
            LANSharingAlertController.shared.showTOTPDisplay()
        }

        // TOTP 验证码输入（作为发送方）
        multipeerService.onTOTPInputRequired = { peer in
            log.info("TOTP input required for peer: \(peer.displayName)")
            LANSharingAlertController.shared.showTOTPInput(
                peerName: peer.displayName,
                onSubmit: { code in
                    multipeerService.submitVerificationCode(code)
                },
                onCancel: {
                    multipeerService.cancelVerification()
                }
            )
        }

        // TOTP 验证成功
        multipeerService.onVerificationSuccess = {
            log.info("TOTP verification succeeded")
            LANSharingAlertController.shared.dismiss()
        }

        // TOTP 验证失败
        multipeerService.onVerificationFailed = {
            log.warn("TOTP verification failed")
            LANSharingAlertController.shared.dismiss()
        }

        // 入站连接邀请
        multipeerService.onInvitationReceived = { invitation in
            log.info("Received invitation from \(invitation.peerName)")
            LANSharingAlertController.shared.showInvitationConfirmation(
                peerName: invitation.peerName,
                onAccept: {
                    multipeerService.acceptInvitation()
                },
                onReject: {
                    multipeerService.rejectInvitation()
                }
            )
        }

        // 启动服务（如果已启用）
        if DeckUserDefaults.lanSharingEnabled {
            multipeerService.start()
        }
    }

    private func setupDirectConnectCallbacks() {
        let directConnectService = DirectConnectService.shared

        // 接收手动直连的项目（安全模式下直接接收，已通过 PSK 认证）
        directConnectService.onDataReceived = { item, peer in
            log.info("DirectConnect: Received item from \(peer.displayName)")
            DeckDataStore.shared.insertItem(item)
        }

        // 非安全模式下收到数据，显示确认弹窗
        directConnectService.onReceiveConfirmationNeeded = { pending, completion in
            log.info("DirectConnect: Showing receive confirmation for item from \(pending.fromName)")
            LANSharingAlertController.shared.showReceiveConfirmation(
                pending: pending,
                onAccept: {
                    completion(true)
                },
                onReject: {
                    completion(false)
                }
            )
        }

        // 记录连接状态变化
        directConnectService.onConnectionStateChanged = { peer, isConnected in
            let status = isConnected ? "connected" : "disconnected"
            log.info("DirectConnect: \(peer.displayName) \(status)")
        }

        // 启动服务（如果已启用）
        if DeckUserDefaults.lanSharingEnabled && !directConnectService.isListening {
            directConnectService.start()
        }
    }

    func triggerStatusBarPulse() {
        guard !ClipboardService.shared.isPaused else { return }
        statusBarIconState.triggerCopyAnimation()
    }

    func toggleWindow(_ completionHandler: (() -> Void)? = nil) {
        mainWindowController.toggleWindow(completionHandler)
    }
}
