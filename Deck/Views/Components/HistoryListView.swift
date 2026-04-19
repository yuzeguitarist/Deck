// Copyright © 2024–2026 Yuze Pan. 保留一切权利。

//
//  HistoryListView.swift
//  Deck
//
//  Deck Clipboard Manager
//

import SwiftUI
import Foundation
import AppKit
import Carbon

private nonisolated struct IndexedCollection<Base: RandomAccessCollection>: RandomAccessCollection {
    typealias Index = Base.Index
    typealias Element = (index: Base.Index, element: Base.Element)

    let base: Base

    init(_ base: Base) {
        self.base = base
    }

    var startIndex: Base.Index { base.startIndex }
    var endIndex: Base.Index { base.endIndex }

    func index(after i: Base.Index) -> Base.Index { base.index(after: i) }
    func index(before i: Base.Index) -> Base.Index { base.index(before: i) }
    func index(_ i: Base.Index, offsetBy distance: Int) -> Base.Index { base.index(i, offsetBy: distance) }
    func distance(from start: Base.Index, to end: Base.Index) -> Int { base.distance(from: start, to: end) }

    subscript(position: Base.Index) -> Element {
        (index: position, element: base[position])
    }
}

/// 用于承载「不影响 UI 渲染」但需要在 View 生命周期内保持的交互状态。
/// 这些字段如果用 @State 存在 View 里，会在滚轮/按键高频触发时导致 body 反复重算，造成掉帧。
private final class HistoryListInteractionState {
    var previewUpdateTask: Task<Void, Never>?
    var deferredPreviewSelectionId: ClipboardItem.ID?
    var lastSelectionWasRepeating: Bool = false
    var lastTapId: ClipboardItem.ID?
    var lastTapTime: TimeInterval = 0
    var scrollMonitor: Any?
    weak var historyScrollView: NSScrollView?
    var accumulatedScrollDelta: CGFloat = 0
    var lastScrollTime: Date = .distantPast
    var scrollTask: Task<Void, Never>?
    var lastVimKeyCode: UInt16 = 0
    var lastVimKeyTime: Date = .distantPast
}

struct HistoryListView: View {
    @State private var vm = DeckViewModel.shared
    @State private var dataStore = DeckDataStore.shared
    @State private var selectedId: ClipboardItem.ID?
    @State private var showPreviewId: ClipboardItem.ID?
    @State private var isPreviewOpen: Bool = false  // Track if preview was manually opened
    @State private var itemToDelete: ClipboardItem?
    /// Context-aware reordered snapshot.
    ///
    /// IMPORTANT: Do not keep this as a mirror of `dataStore.items` when reordering is disabled.
    /// If `orderedItems` shares the same storage with `dataStore.items`, every pagination append
    /// can trigger an expensive Copy-on-Write full-buffer copy, spiking CPU and peak memory.
    @State private var orderedItems: [ClipboardItem] = []
    @State private var preferredTypes: [String]?
    @State private var workspaceObserver: NSObjectProtocol?
    @State private var interaction = HistoryListInteractionState()
    @State private var scrollRequestToken: Int = 0
    @State private var keyboardHandlerKey = "historyNavigation-\(UUID().uuidString)"
    
    private let doubleTapInterval: TimeInterval = 0.25
    private let previewUpdateInterval: TimeInterval = 0.12
    @State private var pasteQueue = PasteQueueService.shared
    @State private var isQuickPasteModifierHeld = false
    
    // MARK: - Scroll Wheel Navigation
    /// Non-precise wheel devices (most mice) send deltas in line-based steps.
    /// Map those steps to a reasonable pixel distance for a horizontal card list.
    private let wheelLineToPointMultiplier: CGFloat = 28

    /// Trackpads / Magic Mouse send precise deltas already in points.
    /// A slight boost feels more consistent with the card density.
    private let preciseScrollMultiplier: CGFloat = 1.15
    
    // MARK: - Enhanced Vim Mode (dd delete)
    private let vimDoubleKeyInterval: TimeInterval = 0.5  // Time window for dd command
    private let bottomBarHeight: CGFloat = 50
    private let verticalBottomPreFadeHeight: CGFloat = 56
    private let verticalTopSpacerID = "history-list-vertical-top-spacer"

    private var verticalBottomOverlayHeight: CGFloat {
        bottomBarHeight + verticalBottomPreFadeHeight
    }

    private var verticalBottomToolbarStartLocation: CGFloat {
        verticalBottomPreFadeHeight / verticalBottomOverlayHeight
    }

    private var verticalListTopInset: CGFloat {
        Const.verticalFloatingTopBarReservedHeight
    }

    private var verticalListBottomInset: CGFloat {
        bottomBarHeight
    }

    private var quickPasteNumberShortcutText: String {
        "\(DeckUserDefaults.quickPasteNumberModifier.symbol)1-9"
    }

    private var queueQuickSelectBarHintText: String {
        switch DeckUserDefaults.queueQuickSelectAnchor {
        case .leftmost:
            return String.localizedStringWithFormat(
                NSLocalizedString("%@ 从最左侧开始", comment: "Queue quick select hint: leftmost"),
                quickPasteNumberShortcutText
            )
        case .focused:
            return String.localizedStringWithFormat(
                NSLocalizedString("%@ 从聚焦卡片开始", comment: "Queue quick select hint: focused"),
                quickPasteNumberShortcutText
            )
        }
    }

    private var queueSelectedCountText: String {
        String.localizedStringWithFormat(
            NSLocalizedString("%lld 项已选", comment: "Queue selected count"),
            Int64(pasteQueue.queue.count)
        )
    }
    
    /// Items with context-aware reordering applied
    private var displayItems: [ClipboardItem] {
        // 队列模式下保持时间顺序，避免切换 App 影响快捷数字/队列选择
        if pasteQueue.isQueueMode {
            return dataStore.items
        }
        if DeckUserDefaults.contextAwareEnabled {
            // 兜底：若异步刷新尚未完成，回退到原始列表避免出现空白
            return orderedItems.isEmpty ? dataStore.items : orderedItems
        }
        return dataStore.items
    }

    private var quickPasteOverlayMap: [ClipboardItem.ID: Int] {
        guard isQuickPasteModifierHeld else { return [:] }
        return DeckQuickPasteResolver.quickPasteNumbers(in: displayItems, selectedItemId: selectedId)
    }

    private var shouldShowInitialLoadingState: Bool {
        dataStore.items.isEmpty && dataStore.isPreparingInitialPresentation
    }
    
    var body: some View {
        Group {
            // Bottom bar:
            // - Vertical mode: queue bar and action bar are mutually exclusive (same slot)
            // - Horizontal mode: queue bar has priority, otherwise ambient bar
            if vm.layoutMode == .vertical {
                contentSection
                    .overlay(alignment: .bottom) {
                        verticalBottomOverlay
                    }
            } else {
                VStack(spacing: 0) {
                    contentSection

                    if pasteQueue.isQueueMode {
                        queueStatusBar
                    } else if !dataStore.items.isEmpty && DeckUserDefaults.showAmbientBar {
                        ASCIIArtBarView()
                    }
                }
            }
        }
        .onAppear {
            setupKeyboardHandlers()
            setupScrollWheelHandler()
            // Reset preview state when panel appears
            resetPreviewState()
            interaction.lastSelectionWasRepeating = false

            // Refresh context-aware ordering based on the app before Deck was activated
            refreshDisplayItems(usePreAppContext: true)
            observeFrontmostAppChanges()

            // Always select first item when panel appears to ensure focus ring is visible
            resetInitialSelection()
        }
        .onChange(of: dataStore.isPanelActive) { _, isActive in
            if isActive {
                // Force refresh using the app before Deck was activated.
                refreshDisplayItems(usePreAppContext: true)
                resetInitialSelection(force: true)
                resetPreviewState()
            } else {
                preferredTypes = nil
                clearQuickPasteModifierState()
                resetPreviewState()
            }
        }
        .onChange(of: vm.selectedTagId) { _, _ in
            refreshDisplayItems()
        }
        .onDisappear {
            cleanupKeyboardHandlers()
            cleanupScrollWheelHandler()
            interaction.scrollTask?.cancel()
            interaction.scrollTask = nil
            clearQuickPasteModifierState()
            if let observer = workspaceObserver {
                NSWorkspace.shared.notificationCenter.removeObserver(observer)
                workspaceObserver = nil
            }
            // Close preview when panel disappears
            resetPreviewState()
        }
    }

    @ViewBuilder
    private var contentSection: some View {
        if shouldShowInitialLoadingState {
            initialLoadingView
        } else if dataStore.items.isEmpty {
            emptyStateView
        } else {
            scrollContent
        }
    }
    
    private var emptyStateView: some View {
        let trimmedQuery = vm.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let isSearching = !trimmedQuery.isEmpty
        let selectedTag = vm.selectedTag
        let isTagEmptyHint = !isSearching && (selectedTag?.isSystem == false || selectedTag?.isImportant == true)
        let titleKey: String
        let subtitleKey: String

        if isSearching {
            titleKey = "未找到结果"
            subtitleKey = "请尝试其他关键词"
        } else if isTagEmptyHint {
            titleKey = "该标签还没有记录"
            subtitleKey = "右键历史记录可将其添加到这个标签"
        } else {
            titleKey = "剪贴板为空"
            subtitleKey = "复制内容后将显示在这里"
        }

        return VStack(spacing: Const.space12) {
            Image(systemName: "doc.on.clipboard")
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text(LocalizedStringKey(titleKey))
                .font(.headline)
                .foregroundStyle(.secondary)

            Text(LocalizedStringKey(subtitleKey))
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var initialLoadingView: some View {
        VStack(spacing: 6) {
            Text(NSLocalizedString("正在载入最近记录", comment: "History loading title"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, Const.space12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var verticalBottomOverlay: some View {
        ZStack(alignment: .bottom) {
            verticalBottomToolbarBackground
                .allowsHitTesting(false)

            if pasteQueue.isQueueMode {
                verticalQueueStatusBar
            } else {
                verticalActionBar
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: verticalBottomOverlayHeight)
    }

    private var verticalBottomToolbarBackground: some View {
        let toolbarTop = verticalBottomToolbarStartLocation

        return ZStack {
            Rectangle()
                .fill(.regularMaterial)
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.0),
                            .init(color: .black.opacity(0.012), location: toolbarTop * 0.22),
                            .init(color: .black.opacity(0.06), location: toolbarTop * 0.58),
                            .init(color: .black.opacity(0.22), location: toolbarTop),
                            .init(color: .black.opacity(0.58), location: min(0.86, toolbarTop + 0.22)),
                            .init(color: .black.opacity(0.82), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }

            Rectangle()
                .fill(.thickMaterial)
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.0),
                            .init(color: .clear, location: toolbarTop * 0.34),
                            .init(color: .black.opacity(0.05), location: toolbarTop * 0.72),
                            .init(color: .black.opacity(0.22), location: toolbarTop + 0.02),
                            .init(color: .black.opacity(0.64), location: min(0.88, toolbarTop + 0.24)),
                            .init(color: .black.opacity(0.96), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }

            Rectangle()
                .fill(.ultraThickMaterial)
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.0),
                            .init(color: .clear, location: toolbarTop * 0.68),
                            .init(color: .black.opacity(0.06), location: toolbarTop * 0.92),
                            .init(color: .black.opacity(0.22), location: toolbarTop + 0.08),
                            .init(color: .black.opacity(0.62), location: min(0.9, toolbarTop + 0.26)),
                            .init(color: .black, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }

            Rectangle()
                .fill(Const.panelOverlay.opacity(0.9))
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.0),
                            .init(color: .clear, location: toolbarTop * 0.76),
                            .init(color: .black.opacity(0.08), location: toolbarTop + 0.04),
                            .init(color: .black.opacity(0.3), location: toolbarTop + 0.16),
                            .init(color: .black.opacity(0.66), location: min(0.9, toolbarTop + 0.3)),
                            .init(color: .black, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
        }
        .frame(maxWidth: .infinity)
        .frame(height: verticalBottomOverlayHeight)
    }

    private var verticalQueueStatusBar: some View {
        HStack(spacing: Const.space8) {
            HStack(spacing: 6) {
                Image(systemName: "list.number")
                Text(NSLocalizedString("队列模式", comment: "Queue mode"))
                    .fontWeight(.medium)
            }
            .foregroundStyle(.orange)
            .padding(.leading, Const.space12)

            Spacer(minLength: 0)

            HStack(spacing: Const.space4) {
                OverlayToolbarTextButton(title: NSLocalizedString("清空", comment: "Clear")) {
                    pasteQueue.clearQueue()
                }

                OverlayToolbarTextButton(title: NSLocalizedString("退出", comment: "Exit")) {
                    pasteQueue.toggleQueueMode()
                }
            }
            .padding(.trailing, Const.space12)
        }
        .font(.system(size: 12))
        .padding(.horizontal, Const.space8)
        .frame(height: bottomBarHeight)
    }

    private var queueStatusBar: some View {
        HStack(spacing: Const.space12) {
            HStack(spacing: Const.space12) {
                HStack(spacing: 6) {
                    Image(systemName: "list.number")
                    Text(NSLocalizedString("队列模式", comment: "Queue mode"))
                        .fontWeight(.medium)
                }
                .foregroundStyle(.orange)

                Divider()
                    .frame(height: 14)

                Text(queueSelectedCountText)
                    .foregroundStyle(.secondary)
            }
            .offset(x: 8)
            
            Spacer()
            
            HStack(spacing: Const.space12) {
                Text(queueQuickSelectBarHintText)
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Text(NSLocalizedString("⌘⇧V 依次粘贴", comment: "Sequential paste hotkey hint"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Button {
                    pasteQueue.clearQueue()
                } label: {
                    Text(NSLocalizedString("清空", comment: "Clear"))
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Button {
                    pasteQueue.toggleQueueMode()
                } label: {
                    Text(NSLocalizedString("退出", comment: "Exit"))
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .offset(x: -8)
        }
        .font(.system(size: 12))
        .padding(.horizontal, Const.space12)
        .frame(height: 33)
    }

    private var verticalActionBar: some View {
        HStack {
            Spacer(minLength: 0)
            PanelActionStripView()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Const.space12)
        .frame(height: bottomBarHeight)
    }
    
    private var scrollContent: some View {
        ScrollViewReader { proxy in
            if vm.layoutMode == .vertical {
                verticalScrollContent(proxy: proxy)
            } else {
                horizontalScrollContent(proxy: proxy)
            }
        }
        .onChange(of: showPreviewId) { _, newId in
            if let id = newId,
               let item = dataStore.items.first(where: { $0.id == id }) {
                PreviewWindowController.shared.show(
                    item: item,
                    relativeTo: MainWindowController.shared.window
                )
            } else {
                PreviewWindowController.shared.hide()
            }
        }
    }
    
    // MARK: - Horizontal Scroll Content (横版模式)

    private func horizontalScrollContent(proxy: ScrollViewProxy) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: Const.cardSpace) {
                ForEach(IndexedCollection(displayItems), id: \.element.id) { index, item in
                    horizontalCard(for: item, at: index)
                }
            }
            .padding(.horizontal, Const.cardSpace)
            .padding(.vertical, Const.space4)
            .background(
                EnclosingScrollViewFinder { scrollView in
                    interaction.historyScrollView = scrollView
                    scrollView.drawsBackground = false
                    scrollView.backgroundColor = .clear
                    scrollView.verticalScrollElasticity = .none
                    scrollView.horizontalScrollElasticity = .allowed
                }
            )
        }
        .scrollContentBackground(.hidden)
        .onChange(of: selectedId) { _, newId in
            handleSelectionChange(to: newId, proxy: proxy)
        }
        .onChange(of: scrollRequestToken) { _, _ in
            scrollToItem(id: selectedId, proxy: proxy)
        }
        .onChange(of: dataStore.items) { _, _ in
            handleItemsChanged()
        }
        .alert("确认删除", isPresented: $vm.isShowingDeleteConfirm) {
            Button("取消", role: .cancel) {
                itemToDelete = nil
                restoreWindowFocus()
            }
            Button("删除", role: .destructive) {
                if let item = itemToDelete { performDelete(item) }
                itemToDelete = nil
                restoreWindowFocus()
            }
        } message: {
            Text("确定要删除这条记录吗？")
        }
        .onChange(of: pasteQueue.isQueueMode) { _, _ in
            refreshDisplayItems()
        }
    }

    // MARK: - Vertical Scroll Content (竖版模式)

    private func verticalScrollContent(proxy: ScrollViewProxy) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: Const.verticalRowSpace) {
                Color.clear
                    .frame(height: verticalListTopInset)
                    .id(verticalTopSpacerID)
                    .allowsHitTesting(false)

                ForEach(IndexedCollection(displayItems), id: \.element.id) { index, item in
                    verticalRow(for: item, at: index)
                }

                Color.clear
                    .frame(height: verticalListBottomInset)
                    .allowsHitTesting(false)
            }
            .padding(.horizontal, Const.space8)
            .padding(.vertical, Const.space4)
            .background(
                EnclosingScrollViewFinder { scrollView in
                    interaction.historyScrollView = scrollView
                    scrollView.drawsBackground = false
                    scrollView.backgroundColor = .clear
                    scrollView.hasVerticalScroller = false
                    scrollView.horizontalScrollElasticity = .none
                    scrollView.verticalScrollElasticity = .allowed
                }
            )
        }
        .scrollContentBackground(.hidden)
        .onChange(of: selectedId) { _, newId in
            handleSelectionChange(to: newId, proxy: proxy)
        }
        .onChange(of: scrollRequestToken) { _, _ in
            scrollToItem(id: selectedId, proxy: proxy)
        }
        .onChange(of: dataStore.items) { _, _ in
            handleItemsChanged()
        }
        .alert("确认删除", isPresented: $vm.isShowingDeleteConfirm) {
            Button("取消", role: .cancel) {
                itemToDelete = nil
                restoreWindowFocus()
            }
            Button("删除", role: .destructive) {
                if let item = itemToDelete { performDelete(item) }
                itemToDelete = nil
                restoreWindowFocus()
            }
        } message: {
            Text("确定要删除这条记录吗？")
        }
        .onChange(of: pasteQueue.isQueueMode) { _, _ in
            refreshDisplayItems()
        }
    }

    @ViewBuilder
    private func horizontalCard(for item: ClipboardItem, at index: Int) -> some View {
        let isItemSelected = selectedId == item.id
        let quickPasteNumber = quickPasteOverlayMap[item.id]

        ClipItemCardView(
            item: item,
            isSelected: isItemSelected,
            showPreview: makePreviewBinding(for: item.id),
            quickPasteNumber: quickPasteNumber,
            onDelete: { deleteItem(item) }
        )
        .onTapGesture {
            handleTap(on: item)
        }
        .onAppear {
            if shouldLoadMore(at: index) {
                dataStore.loadNextPage()
            }
        }
    }

    @ViewBuilder
    private func verticalRow(for item: ClipboardItem, at index: Int) -> some View {
        let isItemSelected = selectedId == item.id
        let quickPasteNumber = quickPasteOverlayMap[item.id]

        ClipItemRowView(
            item: item,
            isSelected: isItemSelected,
            showPreview: makePreviewBinding(for: item.id),
            quickPasteNumber: quickPasteNumber,
            onDelete: { deleteItem(item) }
        )
        .onTapGesture {
            handleTap(on: item)
        }
        .onAppear {
            if shouldLoadMore(at: index) {
                dataStore.loadNextPage()
            }
        }
    }

    /// 提取的 items 变更处理，横版/竖版共享
    private func handleItemsChanged() {
        let trimmedQuery = vm.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let isListTail = dataStore.lastChangeType == .listTail
        let isListHead = dataStore.lastChangeType == .listHead
        let shouldReorder = DeckUserDefaults.contextAwareEnabled &&
            trimmedQuery.isEmpty &&
            !pasteQueue.isQueueMode
        if shouldReorder {
            refreshDisplayItems()
        } else if !orderedItems.isEmpty || preferredTypes != nil {
            orderedItems = []
            preferredTypes = nil
        }
        if dataStore.lastChangeType == .search || dataStore.lastChangeType == .reset {
            let firstId = displayItems.first?.id
            if selectedId == firstId {
                requestScrollToSelection()
            } else {
                selectedId = firstId
            }
        } else if isListTail {
            if dataStore.items.isEmpty {
                NSSound.beep()
            } else {
                interaction.lastSelectionWasRepeating = false
                let id = displayItems.last?.id ?? dataStore.items.last?.id
                if selectedId == id {
                    requestScrollToSelection()
                } else {
                    selectedId = id
                }
                if isPreviewOpen, let id {
                    schedulePreviewUpdate(for: id, isRepeating: false)
                }
            }
        } else if isListHead {
            if dataStore.items.isEmpty {
                NSSound.beep()
            } else {
                interaction.lastSelectionWasRepeating = false
                let id = displayItems.first?.id ?? dataStore.items.first?.id
                if selectedId == id {
                    requestScrollToSelection()
                } else {
                    selectedId = id
                }
                if isPreviewOpen, let id {
                    schedulePreviewUpdate(for: id, isRepeating: false)
                }
            }
        }
    }

    // MARK: - Keyboard Navigation
    
    private func setupKeyboardHandlers() {
        EventDispatcher.shared.registerHandler(
            matching: [.keyDown, .flagsChanged],
            key: keyboardHandlerKey,
            priority: 100
        ) { event in
            return handleKeyEvent(event)
        }
    }
    
    private func cleanupKeyboardHandlers() {
        EventDispatcher.shared.unregisterHandler(keyboardHandlerKey)
    }
    
    // MARK: - Scroll Wheel Navigation
    
    private func setupScrollWheelHandler() {
        guard interaction.scrollMonitor == nil else { return }
        
        interaction.scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [self] event in
            return handleScrollWheel(event)
        }
    }
    
    private func cleanupScrollWheelHandler() {
        if let monitor = interaction.scrollMonitor {
            NSEvent.removeMonitor(monitor)
            interaction.scrollMonitor = nil
        }
        interaction.accumulatedScrollDelta = 0
        interaction.historyScrollView = nil
    }
    
    private func handleScrollWheel(_ event: NSEvent) -> NSEvent? {
        // 1) Only handle events for our own panel window.
        guard event.window === MainWindowController.shared.window else { return event }

        // 2) Only handle when the pointer is actually hovering the history scroll view.
        guard let scrollView = interaction.historyScrollView,
              scrollView.window === event.window else {
            return event
        }

        let pointInScrollView = scrollView.convert(event.locationInWindow, from: nil)
        guard scrollView.bounds.contains(pointInScrollView) else {
            return event
        }

        // 竖版模式：让 ScrollView 自然处理垂直滚动，不做拦截
        if vm.layoutMode == .vertical {
            return event
        }

        // 3) 横版模式：Convert vertical wheel deltas to horizontal movement for a horizontal card list.
        let deltaX = event.scrollingDeltaX
        let deltaY = event.scrollingDeltaY

        // Ignore tiny jitter.
        guard abs(deltaX) > 0.01 || abs(deltaY) > 0.01 else { return event }

        let multiplier: CGFloat = event.hasPreciseScrollingDeltas ? preciseScrollMultiplier : wheelLineToPointMultiplier

        let useVerticalAsHorizontal = abs(deltaY) >= (abs(deltaX) * 0.8)
        let horizontalDelta = useVerticalAsHorizontal ? (deltaX + deltaY * multiplier) : (-deltaX)

        guard abs(horizontalDelta) > 0.01 else { return event }

        scrollHistoryList(by: horizontalDelta)
        return nil
    }

    private func scrollHistoryList(by delta: CGFloat) {
        guard let scrollView = interaction.historyScrollView else { return }
        guard let documentView = scrollView.documentView else { return }

        let clipView = scrollView.contentView
        var origin = clipView.bounds.origin

        // Positive delta scrolls towards older items (to the right).
        origin.x += delta

        // Clamp to the scrollable range.
        let maxX = max(0, documentView.bounds.width - clipView.bounds.width)
        origin.x = min(max(origin.x, 0), maxX)

        // Apply.
        clipView.setBoundsOrigin(origin)
        scrollView.reflectScrolledClipView(clipView)
    }

    private func relevantModifiers(for event: NSEvent) -> NSEvent.ModifierFlags {
        event.modifierFlags.intersection([.command, .control, .option, .shift])
    }

    private func hasOnlyControlModifier(_ event: NSEvent) -> Bool {
        relevantModifiers(for: event) == .control
    }

    private func updateQuickPasteModifierState(for event: NSEvent) {
        let shouldShow = relevantModifiers(for: event) == quickPasteModifierFlags()
        if isQuickPasteModifierHeld != shouldShow {
            isQuickPasteModifierHeld = shouldShow
        }
    }

    private func clearQuickPasteModifierState() {
        if isQuickPasteModifierHeld {
            isQuickPasteModifierHeld = false
        }
    }
    
    private func handleKeyEvent(_ event: NSEvent) -> NSEvent? {
        guard event.window === MainWindowController.shared.window else {
            return event
        }

        updateQuickPasteModifierState(for: event)

        if event.type == .flagsChanged {
            return event
        }

        if vm.isEditingItemTitle {
            return event
        }

        // Debug: log key events
        #if DEBUG
        log.debug("handleKeyEvent: keyCode=\(event.keyCode), focusArea=\(vm.focusArea)")
        #endif

        if event.modifierFlags.contains(.command), event.keyCode == KeyCode.comma {
            SettingsWindowController.shared.toggleWindow()
            return nil
        }

        if event.modifierFlags.contains(.command), event.keyCode == KeyCode.v {
            if vm.focusArea == .search || vm.isEditingTag {
                NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
                return nil
            }
        }

        if event.modifierFlags.contains(.command), event.keyCode == KeyCode.a, vm.isEditingTag {
            NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
            return nil
        }
        
        // ESC to close window
        if event.keyCode == KeyCode.escape {
            // Don't close if delete confirmation is showing
            if vm.isShowingDeleteConfirm {
                return event
            }
            if vm.isCreatingTag {
                vm.cancelNewTag()
                return nil
            }
            if vm.isEditingTag {
                vm.cancelEditingTag()
                return nil
            }
            if vm.focusArea == .search {
                if DeckUserDefaults.vimNavigationEnabled && DeckUserDefaults.vimStartInInsertMode {
                    vm.notePendingRestore(focusArea: .search, vimInsertMode: vm.isVimInsertModeActive)
                    vm.isVimInsertModeActive = false
                    vm.focusArea = .history
                    return nil
                }
                // First ESC: clear search query if not empty
                if !vm.query.isEmpty {
                    vm.clearQuery()
                    return nil
                }
                // Second ESC: exit search mode if in search
                vm.notePendingRestore(focusArea: .search, vimInsertMode: nil)
                vm.focusArea = .history
                return nil
            }
            // Third ESC: close window
            MainWindowController.shared.dismissPanelAndRestoreFocus()
            return nil
        }
        
        // Skip if editing tag or in search field
        if vm.isCreatingTag || vm.isEditingTag {
            return event
        }

        if event.modifierFlags.contains(.command), event.keyCode == KeyCode.a {
            let trimmedQuery = vm.query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedQuery.isEmpty else { return event }
            if vm.isSearchFocusSuppressed { return event }
            vm.focusArea = .search
            vm.refreshSearchFocus()
            vm.requestSearchSelectAll()
            return nil
        }

        if event.modifierFlags.intersection([.command, .control, .option]) == .command,
           event.keyCode == KeyCode.f {
            vm.suppressSearchFocusUntil = nil
            if vm.isRulePickerPresented, vm.rulePickerMode == .list {
                vm.dismissRulePicker()
            }
            if DeckUserDefaults.vimNavigationEnabled {
                vm.isVimInsertModeActive = true
            }
            vm.focusArea = .search
            vm.refreshSearchFocus()
            return nil
        }

        // 上/下方向键焦点切换 — 竖版模式中 ↑/↓ 用于列表导航，不切换焦点
        if event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
            if vm.layoutMode == .horizontal {
                // 横版模式：↓ 从搜索切到列表，↑ 从列表切到搜索
                if vm.focusArea == .search, event.keyCode == KeyCode.downArrow {
                    vm.focusArea = .history
                    return nil
                }
                if vm.focusArea == .history, event.keyCode == KeyCode.upArrow {
                    vm.focusArea = .search
                    vm.refreshSearchFocus()
                    return nil
                }
            } else {
                // 竖版模式：Tab/Shift+Tab 或 / 切换焦点 — ↑/↓ 全部用于列表导航
                // 如果在搜索框中按 ↓，先切到列表再导航
                if vm.focusArea == .search, event.keyCode == KeyCode.downArrow {
                    vm.focusArea = .history
                    return nil
                }
                // 竖版模式不用 ↑ 切回搜索 — ↑ 在列表中用于导航
            }
        }
        
        // Allow delete key in search field
        if vm.focusArea == .search {
            return event
        }

        if event.keyCode == KeyCode.tab {
            let modifiers = event.modifierFlags.intersection([.command, .control, .option])
            guard modifiers.isEmpty else { return event }
            let forward = !event.modifierFlags.contains(.shift)
            return cycleTags(forward: forward)
        }
        
        // Cmd+C to copy selected item and close window
        if event.modifierFlags.contains(.command), event.keyCode == KeyCode.c {
            if let id = selectedId, let item = dataStore.items.first(where: { $0.id == id }) {
                vm.copyItem(item)
                MainWindowController.shared.dismissPanelAndRestoreFocus()
                return nil
            }
        }
        
        let keyModifiers = event.modifierFlags.intersection([.command, .control, .option])

        // Option+Q to toggle queue mode
        if keyModifiers == .option, event.keyCode == KeyCode.q {
            PasteQueueService.shared.toggleQueueMode()
            return nil
        }

        // Cmd+Q shows quit confirmation while the panel is open
        if keyModifiers == .command, event.keyCode == KeyCode.q {
            showQuitConfirmAlert()
            return nil
        }
        
        // 可配置修饰键 + 1-9 快速粘贴（使用 context-aware 排序）
        if keyModifiers == quickPasteModifierFlags() {
            let items = displayItems
            if let item = quickPasteItem(for: event.keyCode, in: items) {
                if PasteQueueService.shared.isQueueMode {
                    // 队列模式：修饰键 + 1-9 选择/取消队列项
                    if PasteQueueService.shared.isInQueue(item) {
                        PasteQueueService.shared.removeFromQueue(item)
                    } else {
                        PasteQueueService.shared.addToQueue(item)
                    }
                } else {
                    // Normal mode, paste directly
                    vm.pasteItem(item)
                }
                return nil
            }
        }

        let autoSearchEnabled = !DeckUserDefaults.vimNavigationEnabled ||
            (DeckUserDefaults.vimStartInInsertMode && vm.isVimInsertModeActive)
        if autoSearchEnabled, vm.focusArea == .history, !vm.isSearchFocusSuppressed {
            // Only handle if no modifier keys (except shift) are pressed
            let modifiers = event.modifierFlags.intersection([.command, .control, .option])
            if modifiers.isEmpty,
               KeyCode.specialKeyMap[event.keyCode] == nil,
               let chars = event.characters,
               !chars.isEmpty {
                // Check if it's a printable character (letter, number, symbol)
                guard let char = chars.first else { return nil }
                if char.isLetter || char.isNumber || char.isPunctuation || char.isSymbol {
                    // Switch to search mode
                    vm.focusArea = .search
                    // Repost the event after focus is set, so IME works correctly
                    if let cgEvent = event.cgEvent?.copy() {
                        let safeEvent = UncheckedSendable(cgEvent)
                        DispatchQueue.main.async {
                            safeEvent.value.post(tap: .cghidEventTap)
                        }
                    }
                    return nil
                }
            }
        }
        
        // Vim navigation mode (only when enabled in settings)
        if DeckUserDefaults.vimNavigationEnabled {
            let isVertical = vm.layoutMode == .vertical
            let isReversedVerticalDirection = DeckUserDefaults.vimVerticalDirection == .jUpKDown
            switch event.keyCode {
            case KeyCode.h:
                guard !isVertical else { break }
                if vm.focusArea != .history {
                    vm.focusArea = .history
                }
                return moveSelection(offset: -1, isRepeating: event.isARepeat)
            case KeyCode.l:
                guard !isVertical else { break }
                if vm.focusArea != .history {
                    vm.focusArea = .history
                }
                return moveSelection(offset: 1, isRepeating: event.isARepeat)
            case KeyCode.j:
                if vm.focusArea != .history {
                    vm.focusArea = .history
                }
                // 竖版模式：按设置切换上下；横版模式保持应用默认行为 j = 向右
                let offset: Int
                if isVertical {
                    offset = isReversedVerticalDirection ? -1 : 1
                } else {
                    offset = 1
                }
                return moveSelection(offset: offset, isRepeating: event.isARepeat)
            case KeyCode.k:
                if vm.focusArea != .history {
                    vm.focusArea = .history
                }
                // 竖版模式：按设置切换上下；横版模式保持应用默认行为 k = 向左
                let offset: Int
                if isVertical {
                    offset = isReversedVerticalDirection ? 1 : -1
                } else {
                    offset = -1
                }
                return moveSelection(offset: offset, isRepeating: event.isARepeat)
            case KeyCode.slash:  // Focus search field
                if !vm.isSearchFocusSuppressed {
                    vm.focusArea = .search
                }
                return nil
            case KeyCode.d:  // 'd' key for dd command
                return handleVimDKey()
            default:
                break
            }

            // These Vim commands only work when focus is on history
            if vm.focusArea == .history {
                switch event.keyCode {
                case KeyCode.x:  // Delete selected item(s)
                    return deleteSelectedItems()
                case KeyCode.y:  // Copy and move to top (yank)
                    return copyAndMoveToTop()
                default:
                    break
                }
            }
        }

        // Arrow keys for navigation (only when focus is on history)
        guard vm.focusArea == .history else {
            log.debug("focusArea is not .history (\(vm.focusArea)), passing event through")
            return event
        }

        if hasOnlyControlModifier(event) {
            switch event.keyCode {
            case KeyCode.a:
                // Emacs：行首 → 数据库真·最新一页（与 ⌃E 对称；⌃E 后必须用 DB 头页恢复，否则会困在尾页切片里）
                Task { @MainActor in
                    let ok = await dataStore.jumpToTrueListHead()
                    if ok {
                        handleItemsChanged()
                    }
                }
                return nil
            case KeyCode.e:
                // Emacs：行尾 → 数据库真·末尾一页（单次查询，不扫中间分页）
                Task { @MainActor in
                    let ok = await dataStore.jumpToTrueListTail()
                    if ok {
                        // 内容与上次相同时 `onChange(items)` 可能不触发，需主动跑一遍以刷新 orderedItems 并把选中移到末尾
                        handleItemsChanged()
                    }
                }
                return nil
            case KeyCode.p:
                return moveSelection(offset: -1, isRepeating: event.isARepeat)
            case KeyCode.n:
                return moveSelection(offset: 1, isRepeating: event.isARepeat)
            case KeyCode.b:
                if vm.layoutMode == .horizontal {
                    return moveSelection(offset: -1, isRepeating: event.isARepeat)
                }
                return event
            case KeyCode.f:
                if vm.layoutMode == .horizontal {
                    return moveSelection(offset: 1, isRepeating: event.isARepeat)
                }
                return event
            default:
                break
            }
        }

        switch event.keyCode {
        case KeyCode.leftArrow:
            if vm.layoutMode == .horizontal {
                return moveSelection(offset: -1, isRepeating: event.isARepeat)
            }
            return event  // 竖版模式不响应左右箭头
        case KeyCode.rightArrow:
            if vm.layoutMode == .horizontal {
                return moveSelection(offset: 1, isRepeating: event.isARepeat)
            }
            return event  // 竖版模式不响应左右箭头
        case KeyCode.upArrow:
            if vm.layoutMode == .vertical {
                return moveSelection(offset: -1, isRepeating: event.isARepeat)
            }
            return event  // 横版模式上箭头已在上方处理
        case KeyCode.downArrow:
            if vm.layoutMode == .vertical {
                return moveSelection(offset: 1, isRepeating: event.isARepeat)
            }
            return event  // 横版模式下箭头已在上方处理
        case KeyCode.space:
            return togglePreview()
        case KeyCode.return:
            return pasteSelectedItem(asPlainText: event.modifierFlags.contains(.shift))
        case KeyCode.delete, KeyCode.forwardDelete:
            log.info("Delete key pressed, calling deleteSelectedItem")
            return deleteSelectedItem()
        default:
            break
        }

        return event
    }

    private func showQuitConfirmAlert() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = NSLocalizedString("是否要关闭本 APP", comment: "Panel Cmd+Q quit confirm title")
        alert.informativeText = NSLocalizedString("如果您想使用光标助手功能，请使用快捷键 Option + Q", comment: "Panel Cmd+Q quit confirm guidance")
        alert.addButton(withTitle: NSLocalizedString("取消", comment: "Panel Cmd+Q quit confirm: cancel"))
        alert.addButton(withTitle: NSLocalizedString("确认关闭", comment: "Panel Cmd+Q quit confirm: confirm"))

        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            NSApp.terminate(nil)
        }
    }
    
    private func quickPasteIndex(for keyCode: UInt16) -> Int? {
        // Key codes for 1-9
        let keyCodes: [UInt16: Int] = [
            0x12: 0, // 1
            0x13: 1, // 2
            0x14: 2, // 3
            0x15: 3, // 4
            0x17: 4, // 5
            0x16: 5, // 6
            0x1A: 6, // 7
            0x1C: 7, // 8
            0x19: 8, // 9
        ]
        return keyCodes[keyCode]
    }

    private func quickPasteItem(for keyCode: UInt16, in items: [ClipboardItem]) -> ClipboardItem? {
        guard let offset = quickPasteIndex(for: keyCode) else {
            return nil
        }
        let number = offset + 1
        return DeckQuickPasteResolver.itemForQuickPasteNumber(number, displayItems: items, selectedItemId: selectedId)
    }

    private func quickPasteModifierFlags() -> NSEvent.ModifierFlags {
        switch DeckUserDefaults.quickPasteNumberModifier {
        case .command:
            return .command
        case .option:
            return .option
        case .control:
            return .control
        }
    }
    
    private func moveSelection(offset: Int, isRepeating: Bool = false) -> NSEvent? {
        let items = displayItems
        let count = items.count
        guard count > 0 else {
            selectedId = nil
            showPreviewId = nil
            cancelPreviewUpdateTask()
            NSSound.beep()
            return nil
        }
        
        let currentIndex = selectedId.flatMap { id in
            items.firstIndex { $0.id == id }
        } ?? 0
        
        let newIndex = max(0, min(currentIndex + offset, count - 1))
        
        guard newIndex != currentIndex else {
            NSSound.beep()
            return nil
        }
        
        let newId = items[newIndex].id
        interaction.lastSelectionWasRepeating = isRepeating
        selectedId = newId

        // Update preview to follow selection ONLY if preview was manually opened
        if isPreviewOpen {
            schedulePreviewUpdate(for: newId, isRepeating: isRepeating)
        }
        
        // Load more if needed
        if offset > 0, shouldLoadMore(at: newIndex) {
            dataStore.loadNextPage()
        }
        
        return nil
    }

    private func cycleTags(forward: Bool) -> NSEvent? {
        let tagOrder = vm.tags.map(\.id)
        guard !tagOrder.isEmpty else { return nil }

        let nextIndex: Int
        if let currentIndex = tagOrder.firstIndex(of: vm.selectedTagId) {
            let delta = forward ? 1 : -1
            nextIndex = (currentIndex + delta + tagOrder.count) % tagOrder.count
        } else {
            nextIndex = forward ? 0 : tagOrder.count - 1
        }

        let nextId = tagOrder[nextIndex]
        if let nextTag = vm.tags.first(where: { $0.id == nextId }) {
            vm.selectTag(nextTag)
        }

        return nil
    }
    
    private func togglePreview() -> NSEvent? {
        if let id = selectedId {
            if isPreviewOpen {
                // Close preview
                isPreviewOpen = false
                cancelPreviewUpdateTask()
                showPreviewId = nil
            } else {
                // Open preview
                isPreviewOpen = true
                updatePreviewNow(for: id)
            }
        }
        return nil
    }
    
    private func pasteSelectedItem(asPlainText: Bool) -> NSEvent? {
        guard let id = selectedId,
              let item = dataStore.items.first(where: { $0.id == id }) else {
            return nil
        }
        vm.pasteItem(item, asPlainText: asPlainText)
        return nil
    }
    
    private func deleteSelectedItem() -> NSEvent? {
        log.info("deleteSelectedItem: selectedId=\(String(describing: selectedId))")
        guard let id = selectedId,
              let item = dataStore.items.first(where: { $0.id == id }) else {
            log.warn("deleteSelectedItem: no item found for selectedId")
            NSSound.beep()
            return nil
        }
        deleteItem(item)
        return nil
    }
    
    // MARK: - Enhanced Vim Mode Functions
    
    /// Handle 'd' key for dd command (Vim-style delete)
    private func handleVimDKey() -> NSEvent? {
        guard vm.focusArea == .history else { return nil }
        
        let now = Date()
        
        // Check if this is a second 'd' within the time window
        if interaction.lastVimKeyCode == KeyCode.d,
           now.timeIntervalSince(interaction.lastVimKeyTime) < vimDoubleKeyInterval {
            // dd command: delete selected item(s)
            interaction.lastVimKeyCode = 0
            interaction.lastVimKeyTime = .distantPast
            return deleteSelectedItems()
        }
        
        // First 'd' press, record it
        interaction.lastVimKeyCode = KeyCode.d
        interaction.lastVimKeyTime = now
        return nil
    }
    
    /// Delete selected item via dd command
    private func deleteSelectedItems() -> NSEvent? {
        return deleteSelectedItem()
    }

    /// Vim 'y' - Copy item to clipboard and move to top (like yank)
    private func copyAndMoveToTop() -> NSEvent? {
        guard let id = selectedId,
              let item = dataStore.items.first(where: { $0.id == id }) else {
            NSSound.beep()
            return nil
        }
        vm.copyItem(item)
        dataStore.moveItemToFirst(item)
        selectedId = item.id
        return nil
    }

    private func scrollToItem(id: ClipboardItem.ID?, proxy: ScrollViewProxy) {
        guard let id = id else {
            interaction.lastSelectionWasRepeating = false
            return
        }
        let items = displayItems
        guard let first = items.first?.id,
              let last = items.last?.id,
              items.contains(where: { $0.id == id }) else {
            interaction.lastSelectionWasRepeating = false
            return
        }

        let anchor: UnitPoint
        let performScroll: () -> Void
        if vm.layoutMode == .vertical {
            if id == first {
                anchor = .top
                performScroll = {
                    proxy.scrollTo(verticalTopSpacerID, anchor: .top)
                }
            } else if id == last {
                anchor = UnitPoint(x: 0.5, y: 0.74)
                performScroll = {
                    proxy.scrollTo(id, anchor: anchor)
                }
            } else {
                anchor = .center
                performScroll = {
                    proxy.scrollTo(id, anchor: anchor)
                }
            }
        } else {
            if id == first {
                anchor = .trailing
            } else if id == last {
                anchor = .leading
            } else {
                anchor = .center
            }
            performScroll = {
                proxy.scrollTo(id, anchor: anchor)
            }
        }

        let shouldAnimate = !interaction.lastSelectionWasRepeating
        interaction.lastSelectionWasRepeating = false

        interaction.scrollTask?.cancel()
        interaction.scrollTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled, selectedId == id else { return }
            if shouldAnimate {
                withAnimation(.easeOut(duration: 0.2)) {
                    performScroll()
                }
            } else {
                performScroll()
            }
        }
    }

    private func handleSelectionChange(to id: ClipboardItem.ID?, proxy: ScrollViewProxy) {
        scrollToItem(id: id, proxy: proxy)
        syncPreviewWithSelection(id)
    }

    private func requestScrollToSelection() {
        scrollRequestToken += 1
    }

    private func syncPreviewWithSelection(_ id: ClipboardItem.ID?) {
        guard isPreviewOpen else { return }
        guard interaction.deferredPreviewSelectionId != id else { return }

        cancelPreviewUpdateTask()

        guard showPreviewId != id else { return }
        updatePreviewNow(for: id)
    }
    
    // MARK: - Helpers

    private func hasSameItemOrder(_ lhs: [ClipboardItem], _ rhs: [ClipboardItem]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        for idx in lhs.indices where lhs[idx].id != rhs[idx].id {
            return false
        }
        return true
    }
    
    private func refreshDisplayItems(usePreAppContext: Bool = false, preferredTypesOverride: [String]? = nil) {
        let trimmedQuery = vm.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let shouldLogSearch = log.isEnabled(.debug) && dataStore.lastChangeType == .search && !trimmedQuery.isEmpty
        if shouldLogSearch {
            let preview = dataStore.items.prefix(10).compactMap { $0.id }.map(String.init).joined(separator: ", ")
            if !preview.isEmpty {
                log.debug("UI input items (top10 ids): [\(preview)]")
            }
        }

        guard DeckUserDefaults.contextAwareEnabled else {
            // No reordering needed. Keep `orderedItems` empty to avoid sharing storage with
            // `dataStore.items` (prevents COW full-array copies during pagination appends).
            orderedItems = []
            preferredTypes = nil
            if shouldLogSearch {
                let preview = dataStore.items.prefix(10).compactMap { $0.id }.map(String.init).joined(separator: ", ")
                if !preview.isEmpty {
                    log.debug("UI display items (top10 ids): [\(preview)]")
                }
            }
            return
        }

        if !trimmedQuery.isEmpty {
            // Searching: use DB order directly; avoid mirroring `dataStore.items`.
            orderedItems = []
            preferredTypes = nil
            if shouldLogSearch {
                let preview = dataStore.items.prefix(10).compactMap { $0.id }.map(String.init).joined(separator: ", ")
                if !preview.isEmpty {
                    log.debug("UI display items (top10 ids): [\(preview)]")
                }
            }
            return
        }
        
        if pasteQueue.isQueueMode {
            // 队列模式下禁用上下文重排，维持时间顺序
            // Avoid mirroring `dataStore.items` to prevent COW full-array copies.
            orderedItems = []
            preferredTypes = nil
            if shouldLogSearch {
                let preview = dataStore.items.prefix(10).compactMap { $0.id }.map(String.init).joined(separator: ", ")
                if !preview.isEmpty {
                    log.debug("UI display items (top10 ids): [\(preview)]")
                }
            }
            return
        }
        
        let previousCachedTypes = preferredTypes?.joined(separator: ",") ?? "nil"
        let contextTypes: [String]?
        if let override = preferredTypesOverride {
            contextTypes = override
        } else if usePreAppContext,
                  let preApp = MainWindowController.shared.preApp,
                  preApp.bundleIdentifier != Bundle.main.bundleIdentifier {
            contextTypes = ContextAwareService.shared.getPreferredTypes(for: preApp)
        } else {
            let resolved = ContextAwareService.shared.getPreferredTypes()
            if let resolved {
                contextTypes = resolved
            } else if let cached = preferredTypes {
                contextTypes = cached
            } else {
                contextTypes = nil
            }
        }
        preferredTypes = contextTypes

        if log.isEnabled(.debug) {
            let preAppBundle = MainWindowController.shared.preApp?.bundleIdentifier ?? "nil"
            let frontmostBundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "nil"
            let cachedTypes = previousCachedTypes
            let contextTypesText = contextTypes?.joined(separator: ",") ?? "nil"
            let topTypes = dataStore.items.prefix(9).map { $0.itemType.rawValue }.joined(separator: ",")
            log.debug("ContextAware refresh: preApp=\(preAppBundle) frontmost=\(frontmostBundle) cachedTypes=\(cachedTypes) contextTypes=\(contextTypesText) top9Types=\(topTypes)")
            #if DEBUG
            NSLog("ContextAware refresh: preApp=\(preAppBundle) frontmost=\(frontmostBundle) cachedTypes=\(cachedTypes) contextTypes=\(contextTypesText) top9Types=\(topTypes)")
            #endif
        }

        guard let contextTypes else {
            // No mapping for current context: keep DB order.
            // IMPORTANT: Do not mirror dataStore.items here; it would share storage and trigger
            // expensive full-buffer Copy-on-Write when pagination appends new items.
            orderedItems = []

            if let current = selectedId,
               !dataStore.items.contains(where: { $0.id == current }) {
                selectedId = dataStore.items.first?.id
            }
            return
        }
        
        let reordered = ContextAwareService.shared.reorderItems(
            dataStore.items,
            preferredTypes: contextTypes
        )
        
        if !hasSameItemOrder(orderedItems, reordered) {
            orderedItems = reordered
        }
        if log.isEnabled(.debug) {
            let topReordered = orderedItems.prefix(9).map { $0.itemType.rawValue }.joined(separator: ",")
            log.debug("ContextAware reordered top9 types: \(topReordered)")
            #if DEBUG
            NSLog("ContextAware reordered top9 types: \(topReordered)")
            #endif
        }
        if shouldLogSearch {
            let preview = orderedItems.prefix(10).compactMap { $0.id }.map(String.init).joined(separator: ", ")
            if !preview.isEmpty {
                log.debug("UI display items (top10 ids): [\(preview)]")
            }
        }
        
        if let current = selectedId,
           !reordered.contains(where: { $0.id == current }) {
            selectedId = reordered.first?.id
        }

    }

    private func observeFrontmostAppChanges() {
        guard workspaceObserver == nil else { return }
        let deckBundleIdentifier = Bundle.main.bundleIdentifier

        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            let appBundleIdentifier = app.bundleIdentifier
            if appBundleIdentifier == deckBundleIdentifier {
                return
            }
            MainActor.assumeIsolated {
                guard DeckUserDefaults.contextAwareEnabled else { return }
                let types = ContextAwareService.shared.getPreferredTypes(forBundleIdentifier: appBundleIdentifier)
                refreshDisplayItems(preferredTypesOverride: types)
                resetInitialSelection(force: true)
            }
        }
    }

    private func makePreviewBinding(for id: ClipboardItem.ID?) -> Binding<Bool> {
        Binding(
            get: { isPreviewOpen && showPreviewId == id },
            set: { newValue in
                if newValue {
                    isPreviewOpen = true
                    updatePreviewNow(for: id)
                } else {
                    isPreviewOpen = false
                    cancelPreviewUpdateTask()
                    showPreviewId = nil
                }
            }
        )
    }
    
    private func handleTap(on item: ClipboardItem) {
        if vm.focusArea != .history {
            vm.focusArea = .history
        }
        
        if selectedId != item.id {
            selectedId = item.id
        } else {
            requestScrollToSelection()
        }

        if isPreviewOpen, selectedId == item.id {
            updatePreviewNow(for: item.id)
        }
        
        let now = ProcessInfo.processInfo.systemUptime
        
        if let lastId = interaction.lastTapId, lastId == item.id,
           now - interaction.lastTapTime <= doubleTapInterval {
            // Double tap - paste
            vm.pasteItem(item)
            interaction.lastTapId = nil
            interaction.lastTapTime = 0
        } else {
            interaction.lastTapId = item.id
            interaction.lastTapTime = now
        }
    }
    
    private func shouldLoadMore(at index: Int) -> Bool {
        guard dataStore.hasMoreData else { return false }
        let triggerIndex = dataStore.items.count - 5
        return index >= triggerIndex
    }
    
    private func deleteItem(_ item: ClipboardItem) {
        log.info("deleteItem called: id=\(String(describing: item.id)), focusArea=\(vm.focusArea)")
        if DeckUserDefaults.deleteConfirmation {
            itemToDelete = item
            vm.isShowingDeleteConfirm = true
            log.info("Showing delete confirmation")
        } else {
            performDelete(item)
        }
    }

    /// 恢复主窗口焦点（用于 alert 对话框关闭后）
    private func restoreWindowFocus() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            MainWindowController.shared.window?.makeKeyAndOrderFront(nil)
            vm.focusArea = .history
        }
    }
    
    private func performDelete(_ item: ClipboardItem) {
        log.info("performDelete: item.id=\(String(describing: item.id))")

        withAnimation(.easeOut(duration: 0.2)) {
            let index = dataStore.items.firstIndex(where: { $0.id == item.id })
            log.info("performDelete: found at index=\(String(describing: index)), calling vm.deleteItem")
            vm.deleteItem(item)
            
            // Update selection
            if let index = index {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if dataStore.items.isEmpty {
                        selectedId = nil
                    } else {
                        let newIndex = min(index, dataStore.items.count - 1)
                        selectedId = dataStore.items[safe: newIndex]?.id
                    }
                    // 重新应用上下文排序，确保 UI 立即反映删除结果
                    refreshDisplayItems()
                    // 删除后如果预览处于开启状态，需同步到新的选中项（或关闭预览）
                    if isPreviewOpen {
                        updatePreviewNow(for: selectedId)
                    }
                }
            } else {
                refreshDisplayItems()
            }
        }
    }

    private func resetInitialSelection(force: Bool = false) {
        if !force, selectedId != nil {
            return
        }

        if let firstId = displayItems.first?.id {
            if selectedId != firstId {
                selectedId = firstId
            } else if force {
                requestScrollToSelection()
            }
            return
        }

        if force {
            selectedId = nil
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard let firstId = displayItems.first?.id else { return }
            if force || selectedId == nil {
                if selectedId != firstId {
                    selectedId = firstId
                } else if force {
                    requestScrollToSelection()
                }
            }
        }
    }

    private func resetPreviewState() {
        isPreviewOpen = false
        showPreviewId = nil
        cancelPreviewUpdateTask()
        PreviewWindowController.shared.hide()
    }

    private func cancelPreviewUpdateTask() {
        interaction.previewUpdateTask?.cancel()
        interaction.previewUpdateTask = nil
        interaction.deferredPreviewSelectionId = nil
    }

    private func updatePreviewNow(for id: ClipboardItem.ID?) {
        interaction.deferredPreviewSelectionId = nil
        showPreviewId = id
    }

    private func schedulePreviewUpdate(for id: ClipboardItem.ID?, isRepeating: Bool) {
        guard isPreviewOpen else { return }

        if !isRepeating {
            cancelPreviewUpdateTask()
            updatePreviewNow(for: id)
            return
        }

        cancelPreviewUpdateTask()
        interaction.deferredPreviewSelectionId = id
        interaction.previewUpdateTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(previewUpdateInterval * 1_000_000_000))
            guard !Task.isCancelled, isPreviewOpen else { return }
            updatePreviewNow(for: id)
        }
    }
}

// MARK: - NSScrollView Introspection

/// A tiny AppKit bridge used to capture the underlying `NSScrollView` created by SwiftUI's
/// `ScrollView`.
///
/// We use this to implement a predictable mouse-wheel behavior for a horizontal card list:
///   - Hover anywhere over the list and scroll: it scrolls the list (no "focus" requirement).
///   - Vertical wheel deltas are converted into horizontal scrolling deltas.
private struct EnclosingScrollViewFinder: NSViewRepresentable {
    let onResolve: (NSScrollView) -> Void

    func makeNSView(context: Context) -> FinderView {
        FinderView(onResolve: onResolve)
    }

    func updateNSView(_ nsView: FinderView, context: Context) {
        nsView.onResolve = onResolve
        nsView.resolveIfNeeded()
    }

    final class FinderView: NSView {
        var onResolve: (NSScrollView) -> Void
        private weak var lastResolved: NSScrollView?

        init(onResolve: @escaping (NSScrollView) -> Void) {
            self.onResolve = onResolve
            super.init(frame: .zero)
            wantsLayer = false
            isHidden = true
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            resolveIfNeeded()
        }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            resolveIfNeeded()
        }

        func resolveIfNeeded() {
            guard let scrollView = enclosingScrollView else { return }
            guard scrollView !== lastResolved else { return }
            lastResolved = scrollView
            onResolve(scrollView)
        }
    }
}

private struct OverlayToolbarTextButton: View {
    let title: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background {
                    Capsule()
                        .fill(isHovered ? Const.adaptiveGray(0.08, darkOpacity: 0.15) : Color.clear)
                }
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

#Preview {
    HistoryListView()
        .frame(width: 800, height: 250)
        .background(Color.black.opacity(0.3))
}
