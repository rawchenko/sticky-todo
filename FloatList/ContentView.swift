import SwiftUI
import AppKit

private let escapeKeyCode: UInt16 = 53
private let undoKeyCode: UInt16 = 6   // kVK_ANSI_Z

private struct TaskListViewportPreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

private final class TaskListScrollController: ObservableObject {
    weak var scrollView: NSScrollView?

    func attach(_ scrollView: NSScrollView?) {
        self.scrollView = scrollView
    }

    @discardableResult
    func scrollBy(_ deltaY: CGFloat) -> CGFloat {
        guard let scrollView, let documentView = scrollView.documentView else { return 0 }

        let clipView = scrollView.contentView
        var bounds = clipView.bounds
        let minY: CGFloat = 0
        let maxY = max(0, documentView.bounds.height - bounds.height)
        let previousY = bounds.origin.y
        let nextY = min(max(previousY + deltaY, minY), maxY)
        guard abs(nextY - previousY) > 0.01 else { return 0 }

        bounds.origin.y = nextY
        clipView.scroll(to: bounds.origin)
        scrollView.reflectScrolledClipView(clipView)
        return nextY - previousY
    }
}

private struct TaskListScrollAccessor: NSViewRepresentable {
    typealias NSViewType = ResolverView

    var onResolve: (NSScrollView?) -> Void

    func makeNSView(context: Context) -> ResolverView {
        let view = ResolverView()
        view.onResolve = onResolve
        return view
    }

    func updateNSView(_ nsView: ResolverView, context: Context) {
        nsView.onResolve = onResolve
        nsView.resolveEnclosingScrollView()
    }

    final class ResolverView: NSView {
        var onResolve: ((NSScrollView?) -> Void)?

        override var isFlipped: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            resolveEnclosingScrollView()
        }

        override func layout() {
            super.layout()
            resolveEnclosingScrollView()
        }

        func resolveEnclosingScrollView() {
            DispatchQueue.main.async { [weak self] in
                self?.onResolve?(self?.enclosingScrollView)
            }
        }
    }
}

private struct AddListButton: View {
    var action: () -> Void

    @State private var isHovering = false
    @State private var isPressed = false
    @ObservedObject private var tweaks = LayoutTweaks.shared

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: tweaks.addListIconSize, weight: .medium))
                .foregroundStyle(FloatListTheme.textSecondary)
                .frame(width: 22, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerCursor(.pointingHand)
        .background(WindowDragBlocker())
        .scaleEffect(isPressed ? 0.9 : 1.0)
        .opacity(isHovering ? 1 : 0.72)
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .animation(.spring(response: 0.22, dampingFraction: 0.7), value: isPressed)
        .onHover { hovering in
            isHovering = hovering
            if !hovering { isPressed = false }
        }
        .onLongPressGesture(minimumDuration: .infinity, maximumDistance: 6, perform: {}) { pressing in
            isPressed = pressing
        }
    }
}

private struct PillIconButton<Icon: View>: View {
    var help: String
    var action: () -> Void
    var onHoverStart: () -> Void = {}
    @ViewBuilder var icon: () -> Icon

    @State private var isHovering = false
    @State private var isPressed = false
    @ObservedObject private var tweaks = LayoutTweaks.shared

    private var pillContentHeight: CGFloat {
        let textLineHeight = NSFont.systemFont(ofSize: tweaks.bodyTextSize, weight: .medium)
            .boundingRectForFont
            .height
            .rounded(.up)
        let chevronSize = max(tweaks.secondaryTextSize - 2, 8)
        return max(textLineHeight, tweaks.listIconSize, chevronSize)
    }

    var body: some View {
        Button(action: action) {
            icon()
                .frame(width: pillContentHeight, height: pillContentHeight)
                .padding(.horizontal, tweaks.pillHorizontalPadding)
                .padding(.vertical, tweaks.pillVerticalPadding)
                .background(
                    RoundedRectangle(cornerRadius: tweaks.pillCornerRadius, style: .continuous)
                        .fill(isHovering ? FloatListTheme.rowHover : Color.clear)
                        .animation(.easeOut(duration: 0.12), value: isHovering)
                )
                .contentShape(RoundedRectangle(cornerRadius: tweaks.pillCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .pointerCursor(.pointingHand)
        .background(WindowDragBlocker())
        .help(help)
        .scaleEffect(isPressed ? 0.9 : 1.0)
        .opacity(isHovering ? 1 : 0.72)
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .animation(.spring(response: 0.22, dampingFraction: 0.7), value: isPressed)
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                onHoverStart()
            } else {
                isPressed = false
            }
        }
        .onLongPressGesture(minimumDuration: .infinity, maximumDistance: 6, perform: {}) { pressing in
            isPressed = pressing
        }
    }
}

private struct UndoButton: View {
    var undoTick: Int
    var action: () -> Void

    var body: some View {
        PillIconButton(help: "Undo (\u{2318}Z)", action: action) {
            Image(systemName: "arrow.uturn.backward")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(FloatListTheme.textPrimary)
                .symbolRenderingMode(.monochrome)
                .symbolEffect(.bounce, value: undoTick)
        }
    }
}

private struct SettingsButton: View {
    @State private var spinCount = 0

    var body: some View {
        PillIconButton(
            help: "Settings",
            action: openSettings,
            onHoverStart: { spinCount += 1 }
        ) {
            Image(systemName: "gear")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(FloatListTheme.textPrimary)
                .symbolRenderingMode(.monochrome)
                .rotationEffect(.degrees(Double(spinCount) * 60))
                .animation(.spring(response: 0.55, dampingFraction: 0.62), value: spinCount)
        }
    }

    private func openSettings() {
        AppDelegate.shared?.openSettings()
    }
}

struct ContentView: View {
    @ObservedObject var store: TodoStore
    @ObservedObject var panelManager: PanelManager
    @ObservedObject private var tweaks = LayoutTweaks.shared
    @StateObject private var taskListScrollController = TaskListScrollController()
    @State private var pendingToggleAnimations: [UUID: PendingToggleAnimation] = [:]
    @State private var newTaskTitle = ""
    @State private var dismissedRecoveryNoticeID: UUID?
    @State private var dragSession: DragSession?
    @State private var rowHeights: [UUID: CGFloat] = [:]
    @State private var rowFrames: [UUID: CGRect] = [:]
    @State private var taskListViewport: CGRect = .zero
    @State private var autoScrollTask: Task<Void, Never>?
    @State private var settleTask: Task<Void, Never>?
    @State private var escapeMonitor: Any?
    @State private var undoMonitor: Any?
    @State private var undoTick: Int = 0
    @State private var pendingAutoFocusListID: UUID?
    @State private var listPendingDeletion: TodoList?
    @State private var isShowingEmptyTrashAlert = false
    @State private var isHoldingForDeletePrompt = false
    @State private var expandedCompletedListIDs: Set<UUID> = []
    @State private var hoveredCompletedToggleListID: UUID?
    @State private var isHoldingForInput = false

    private var hasInputDraft: Bool {
        newTaskTitle.contains { !$0.isWhitespace && !$0.isNewline }
    }

    private static let reorderAnimation = Animation.spring(response: 0.28, dampingFraction: 0.86)
    private static let reorderStepAnimation = Animation.interactiveSpring(response: 0.22, dampingFraction: 0.9)
    private static let reorderSettleDelayNanoseconds: UInt64 = 170_000_000
    private static let autoScrollFrameNanoseconds: UInt64 = 16_666_667
    private static let autoScrollFrameDuration: CGFloat = 1.0 / 60.0
    private static let rowToggleExitAnimation = Animation.easeOut(duration: 0.18)
    private static let rowToggleCommitDelayNanoseconds: UInt64 = 2_000_000_000

    private struct PendingToggleAnimation: Equatable {
        let targetCompleted: Bool
    }

    private struct DragSession {
        let item: TodoItem
        let originalIndex: Int
        let initialFrame: CGRect
        let frozenRowHeight: CGFloat
        var gestureTranslation: CGFloat
        var lastCompositeTranslation: CGFloat
        var dragDirection: ReorderDragDirection
        var autoScrollVelocity: CGFloat
        var targetIndex: Int

        var overlayMidY: CGFloat {
            initialFrame.midY + gestureTranslation
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let shape = MorphingDockedShape(
                expansion: expansionProgress,
                handleRadius: tweaks.handleCornerRadius,
                panelRadius: tweaks.panelCornerRadius
            )

            ZStack(alignment: panelManager.currentAnchor.edge.alignment) {
                PanelGlassBackground(shape: shape)
                    .allowsHitTesting(false)

                WindowDragZone()
                    .clipShape(shape)

                expandedLayer

                collapsedGlyph
            }
            .frame(
                width: proxy.size.width,
                height: proxy.size.height,
                alignment: panelManager.currentAnchor.edge.alignment
            )
            .clipShape(shape)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
        .environmentObject(panelManager)
        .animation(PanelMotion.stateAnimation, value: panelManager.isCollapsed)
        .animation(PanelMotion.stateAnimation, value: panelManager.currentAnchor)
        .animation(PanelMotion.stateAnimation, value: panelManager.isDragging)
        .onAppear {
            installUndoMonitor()
        }
        .onDisappear {
            removeEscapeMonitor()
            removeUndoMonitor()
            stopAutoScrollLoop()
            settleTask?.cancel()
            settleTask = nil
            releaseDeletePromptHoldIfNeeded()
            setInputHoverHold(false)
        }
        .onChange(of: hasInputDraft) { _, hold in
            setInputHoverHold(hold)
        }
        .alert(
            deleteAlertTitle,
            isPresented: Binding(
                get: { listPendingDeletion != nil },
                set: { presented in
                    if !presented { listPendingDeletion = nil }
                }
            ),
            presenting: listPendingDeletion
        ) { list in
            Button("Delete", role: .destructive) {
                performDeleteList(list)
            }
            Button("Cancel", role: .cancel) { }
        } message: { list in
            Text(deleteAlertMessage(for: list))
        }
        .alert(
            "Empty Trash?",
            isPresented: $isShowingEmptyTrashAlert
        ) {
            Button("Empty Trash", role: .destructive) {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.84)) {
                    store.emptyTrash()
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("All trashed items will be permanently deleted.")
        }
        .onChange(of: listPendingDeletion != nil || isShowingEmptyTrashAlert) { _, shouldHold in
            setDeletePromptHold(shouldHold)
        }
    }

    private var deleteAlertTitle: String {
        guard let list = listPendingDeletion else { return "Delete list?" }
        return "Delete \u{201C}\(list.name)\u{201D}?"
    }

    private func deleteAlertMessage(for list: TodoList) -> String {
        let count = store.items(in: list.id).count
        if count == 0 {
            return "This list will be deleted."
        }
        let taskWord = count == 1 ? "task" : "tasks"
        return "This list will be deleted and its \(count) \(taskWord) will move to Trash."
    }

    private func setDeletePromptHold(_ hold: Bool) {
        guard hold != isHoldingForDeletePrompt else { return }
        isHoldingForDeletePrompt = hold
        if hold {
            panelManager.pushHoverHold()
        } else {
            panelManager.popHoverHold()
        }
    }

    private func releaseDeletePromptHoldIfNeeded() {
        if isHoldingForDeletePrompt {
            isHoldingForDeletePrompt = false
            panelManager.popHoverHold()
        }
    }

    private func setInputHoverHold(_ hold: Bool) {
        guard hold != isHoldingForInput else { return }
        isHoldingForInput = hold
        if hold {
            panelManager.pushHoverHold()
        } else {
            panelManager.popHoverHold()
        }
    }

    private var expandedLayer: some View {
        expandedContent
            .compositingGroup()
            .blur(radius: expandedBlur)
            .opacity(expandedOpacity)
            .scaleEffect(expandedScale, anchor: panelManager.currentAnchor.edge.unitPoint)
            .allowsHitTesting(expansionProgress > 0.72)
            .accessibilityHidden(expansionProgress < 0.3)
    }

    private var expandedContent: some View {
        VStack(spacing: 0) {
            header

            if let notice = activeRecoveryNotice {
                recoveryBanner(notice)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
            }

            if shouldShowNoListsEmptyState {
                noListsEmptyState
            } else {
                if shouldShowTaskList {
                    taskList
                } else {
                    currentEmptyState
                }
            }

            if store.selectedListID != nil && !store.isSpecialListSelected {
                inputBar
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .liquidGlassContainer(spacing: 0)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 2) {
            Group {
                if shouldShowNoListsEmptyState {
                    HStack(alignment: .top, spacing: 6) {
                        Text("No lists yet")
                            .font(.system(size: tweaks.secondaryTextSize))
                            .foregroundStyle(FloatListTheme.textSecondary)
                            .padding(.horizontal, 4)
                        Spacer(minLength: 0)
                        AddListButton(action: createList)
                    }
                } else {
                    ListsDropdownView(
                        lists: store.lists,
                        completedList: TodoList.completedList,
                        trashList: TodoList.trashList,
                        selectedID: store.selectedListID,
                        autoFocusRenameID: pendingAutoFocusListID,
                        onSelect: { selectList($0) },
                        onCreate: createList,
                        onRename: { list, name in store.renameList(list, to: name) },
                        onDelete: { deleteList($0) },
                        onEmptyTrash: { emptyTrash() },
                        onSetIcon: { list, symbol in store.setListIcon(list, to: symbol) },
                        onReorder: { from, to in store.moveList(from: from, to: to) },
                        onAutoFocusConsumed: { pendingAutoFocusListID = nil }
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(alignment: .top, spacing: 2) {
                if store.canUndo {
                    UndoButton(undoTick: undoTick, action: performUndo)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.85).combined(with: .opacity),
                            removal: .scale(scale: 0.85).combined(with: .opacity)
                        ))
                }
                SettingsButton()
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: store.canUndo)
        .padding(.horizontal, tweaks.contentHorizontalPadding)
        .padding(.top, tweaks.contentTopPadding)
        .padding(.bottom, tweaks.contentBottomPadding)
        .onChange(of: store.lists.map(\.id)) { _, ids in
            let live = Set(ids)
            expandedCompletedListIDs = Set(expandedCompletedListIDs.filter { live.contains($0) })
        }
    }

    private func performUndo() {
        guard store.canUndo else { return }
        undoTick &+= 1
        withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
            store.undo()
        }
    }

    private func createList() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
            let newList = store.addList(name: TodoList.defaultName)
            pendingAutoFocusListID = newList.id
        }
    }

    private func deleteList(_ list: TodoList) {
        listPendingDeletion = list
    }

    private func performDeleteList(_ list: TodoList) {
        listPendingDeletion = nil
        withAnimation(.spring(response: 0.38, dampingFraction: 0.84)) {
            store.deleteList(list)
        }
    }

    private func emptyTrash() {
        isShowingEmptyTrashAlert = true
    }

    private func selectList(_ id: UUID) {
        withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
            store.selectList(id)
        }
    }

    private var noListsEmptyState: some View {
        VStack(spacing: 8) {
            Text("Create a list to get started.")
                .font(.system(size: 22, weight: .regular, design: .serif).italic())
                .tracking(-0.4)
                .foregroundStyle(FloatListTheme.textPrimary.opacity(0.95))
                .multilineTextAlignment(.center)

            Text("Tap + above to add one.")
                .font(.system(size: 13))
                .foregroundStyle(FloatListTheme.textSecondary)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("Start anywhere.")
                .font(.system(size: 28, weight: .regular, design: .serif).italic())
                .tracking(-0.56)
                .foregroundStyle(FloatListTheme.textPrimary.opacity(0.95))

            Text(hasInputDraft ? "Press ⏎ to add" : "Type a task below")
                .font(.system(size: tweaks.bodyTextSize))
                .foregroundStyle(FloatListTheme.textSecondary)
        }
        .opacity(hasInputDraft ? 0.42 : 0.7)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.2), value: hasInputDraft)
    }

    private var trashEmptyState: some View {
        VStack(spacing: 8) {
            Text("Trash is empty.")
                .font(.system(size: 26, weight: .regular, design: .serif).italic())
                .tracking(-0.48)
                .foregroundStyle(FloatListTheme.textPrimary.opacity(0.95))

            Text("Deleted tasks will wait here until you restore them or empty Trash.")
                .font(.system(size: tweaks.bodyTextSize))
                .foregroundStyle(FloatListTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var completedEmptyState: some View {
        VStack(spacing: 8) {
            Text("Completed is clear.")
                .font(.system(size: 26, weight: .regular, design: .serif).italic())
                .tracking(-0.48)
                .foregroundStyle(FloatListTheme.textPrimary.opacity(0.95))

            Text("Finished tasks from every list will collect here.")
                .font(.system(size: tweaks.bodyTextSize))
                .foregroundStyle(FloatListTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var currentEmptyState: some View {
        if store.isTrashSelected {
            trashEmptyState
        } else if store.isCompletedSelected {
            completedEmptyState
        } else {
            emptyState
        }
    }

    private var taskList: some View {
        ZStack(alignment: .topLeading) {
            ScrollView {
                LazyVStack(spacing: tweaks.rowSpacing) {
                    if let listID = selectedRegularListID {
                        regularListSection

                        if !currentCompletedItems.isEmpty {
                            completedToggleButton(for: listID, count: currentCompletedItems.count)

                            if isCompletedExpanded(for: listID) {
                                ForEach(currentCompletedItems) { item in
                                    taskRow(item, isReorderEnabled: false)
                                        .transition(.opacity.combined(with: .move(edge: .top)))
                                }
                            }
                        }
                    } else {
                        ForEach(sortedItems) { item in
                            taskRow(
                                item,
                                subtitle: store.isSpecialListSelected ? store.sourceListName(for: item) : nil,
                                isReorderEnabled: false
                            )
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }
                .padding(.horizontal, tweaks.contentHorizontalPadding)
                .padding(.vertical, 4)
            }
            .background(TaskListScrollAccessor { scrollView in
                taskListScrollController.attach(scrollView)
            })
            .background(
                GeometryReader { geo in
                    Color.clear
                        .preference(
                            key: TaskListViewportPreferenceKey.self,
                            value: geo.frame(in: .named("taskListContent"))
                        )
                }
            )

            if let dragSession {
                dragOverlay(for: dragSession)
            }
        }
        .coordinateSpace(name: "taskListContent")
        .coordinateSpace(name: "list")
        .onPreferenceChange(RowHeightPreferenceKey.self) { heights in
            rowHeights.merge(heights) { _, new in new }
        }
        .onPreferenceChange(RowFramePreferenceKey.self) { frames in
            rowFrames.merge(frames) { _, new in new }
            refreshDragSessionTarget(triggerHaptic: true)
        }
        .onPreferenceChange(TaskListViewportPreferenceKey.self) { viewport in
            taskListViewport = viewport
            refreshDragSessionTarget(triggerHaptic: false)
        }
        .onChange(of: store.items.map(\.id)) { _, ids in
            let live = Set(ids)
            rowHeights = rowHeights.filter { live.contains($0.key) }
            rowFrames = rowFrames.filter { live.contains($0.key) }
            pendingToggleAnimations = pendingToggleAnimations.filter { live.contains($0.key) }
            if let draggingID, !live.contains(draggingID) {
                cancelDrag()
            }
        }
        .onChange(of: store.selectedListID) {
            cancelDrag()
        }
        .frame(maxHeight: .infinity)
        .animation(Self.reorderStepAnimation, value: dragSession?.targetIndex)
    }

    @ViewBuilder
    private var regularListSection: some View {
        let items = projectedRegularItems

        if items.isEmpty && !currentCompletedItems.isEmpty {
            inlineEmptyState
        }

        ForEach(items) { item in
            if draggingID == item.id {
                Color.clear
                    .frame(height: dragSession?.item.id == item.id ? (dragSession?.frozenRowHeight ?? RowMetrics.estimatedHeight) : (rowHeights[item.id] ?? RowMetrics.estimatedHeight))
                    .frame(maxWidth: .infinity)
                    .overlay {
                        dragLandingIndicator()
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                taskRow(item)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func taskRow(
        _ item: TodoItem,
        subtitle: String? = nil,
        isReorderEnabled: Bool? = nil
    ) -> some View {
        let isTrashItem = store.isTrashSelected
        let pendingToggleAnimation = pendingToggleAnimations[item.id]
        return TodoRowView(
            item: item,
            isTrashItem: isTrashItem,
            isDragging: false,
            isDragActive: draggingID != nil,
            subtitle: subtitle,
            completionOverride: pendingToggleAnimation?.targetCompleted,
            isExiting: pendingToggleAnimation != nil,
            onToggle: {
                handleToggle(for: item)
            },
            onDelete: {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                    if store.isTrashSelected {
                        store.permanentlyDelete(item)
                    } else {
                        store.moveToTrash(item)
                    }
                }
            },
            onRestore: store.isTrashSelected ? {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                    store.restore(item)
                }
            } : nil,
            onRename: { newTitle in
                store.rename(item, to: newTitle)
            },
            onDragChanged: { translation in
                handleDragChanged(for: item.id, translation: translation)
            },
            onDragEnded: { translation in
                commitDrag(for: item.id, translation: translation)
            },
            moveDestinations: isTrashItem ? [] : store.lists.filter { $0.id != item.listID },
            onMoveToList: { targetListID in
                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                    store.moveItem(item, to: targetListID)
                }
            },
            isToggleEnabled: !isTrashItem && pendingToggleAnimation == nil && draggingID == nil,
            isReorderEnabled: isReorderEnabled ?? !store.isSpecialListSelected
        )
        .id(RowRenderIdentity(
            itemID: item.id,
            selectedListID: store.selectedListID,
            isCompleted: item.isCompleted,
            isTrashItem: isTrashItem,
            subtitle: subtitle
        ))
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            AutoGrowingInputField(
                text: $newTaskTitle,
                placeholder: sortedItems.isEmpty ? "What's your first task?" : "What's next?",
                font: NSFont.systemFont(ofSize: tweaks.bodyTextSize),
                textColor: NSColor(FloatListTheme.textPrimary),
                placeholderColor: .placeholderTextColor,
                maxLines: 5,
                onSubmit: submitTask
            )
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .topLeading)

            Button(action: submitTask) {
                Image(systemName: "arrow.up")
            }
            .floatListGlassButton(prominent: hasInputDraft)
            .disabled(!hasInputDraft)
            .pointerCursor(hasInputDraft ? .pointingHand : nil)
            .animation(.easeInOut(duration: 0.15), value: hasInputDraft)
        }
        .padding(.leading, tweaks.inputLeadingPadding)
        .padding(.trailing, tweaks.inputTrailingPadding)
        .padding(.vertical, tweaks.inputVerticalPadding)
        .background(
            RoundedRectangle(cornerRadius: tweaks.inputCornerRadius, style: .continuous).fill(FloatListTheme.inputFill)
        )
        .padding(.horizontal, 6)
        .padding(.bottom, 6)
        .animation(.easeOut(duration: 0.18), value: newTaskTitle)
    }

    private func submitTask() {
        let trimmed = newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.add(title: trimmed)
        newTaskTitle = ""
    }

    private var collapsedGlyph: some View {
        Image("CollapsedGlyph")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: tweaks.collapsedWidth, height: tweaks.collapsedHeight)
            .compositingGroup()
            .blur(radius: collapsedBlur)
            .opacity(collapsedOpacity)
            .scaleEffect(collapsedScale, anchor: panelManager.currentAnchor.edge.unitPoint)
            .offset(collapsedOffset)
            .allowsHitTesting(false)
            .accessibilityHidden(expansionProgress > 0.7)
    }

    private var expansionProgress: CGFloat {
        panelManager.isCollapsed ? 0 : 1
    }

    private var expandedOpacity: CGFloat {
        smoothstep((expansionProgress - 0.10) / 0.82)
    }

    private var expandedScale: CGFloat {
        0.94 + (0.06 * expansionProgress)
    }

    private var collapsedOpacity: CGFloat {
        // Fade runs ahead of `expansionProgress` (x1.55) so the glyph clears
        // the frame before the expanded layer reaches full opacity, letting
        // the two cross through the blurred midpoint instead of stacking.
        smoothstep((1 - expansionProgress) * 1.55)
    }

    private var collapsedScale: CGFloat {
        1 - (0.18 * expansionProgress)
    }

    private var collapsedOffset: CGSize {
        CGSize(
            width: transitionOffset.width * expansionProgress * 0.32,
            height: transitionOffset.height * expansionProgress * 0.32
        )
    }

    private var expandedBlur: CGFloat {
        let remaining = 1 - expansionProgress
        return remaining * remaining * PanelMotion.expandedTransitionBlur
    }

    private var collapsedBlur: CGFloat {
        expansionProgress * expansionProgress * PanelMotion.collapsedTransitionBlur
    }

    private var transitionOffset: CGSize {
        panelManager.currentAnchor.edge.transitionOffset
    }

    private var sortedItems: [TodoItem] {
        store.visibleItems
    }

    private var draggingID: UUID? {
        dragSession?.item.id
    }

    private var projectedRegularItems: [TodoItem] {
        guard let session = dragSession else { return sortedItems }
        var items = sortedItems
        guard let currentIndex = items.firstIndex(where: { $0.id == session.item.id }) else {
            return items
        }

        let moving = items.remove(at: currentIndex)
        let target = min(max(session.targetIndex, 0), items.count)
        items.insert(moving, at: target)
        return items
    }

    private var shouldShowNoListsEmptyState: Bool {
        store.lists.isEmpty && !store.isSpecialListSelected && !store.hasCompletedItems && !store.hasTrashedItems
    }

    private var selectedRegularListID: UUID? {
        guard let id = store.selectedListID, !store.isSpecialListSelected else { return nil }
        return id
    }

    private var currentCompletedItems: [TodoItem] {
        guard let listID = selectedRegularListID else { return [] }
        return store.completedItems(in: listID)
    }

    private var shouldShowTaskList: Bool {
        if store.isSpecialListSelected {
            return !sortedItems.isEmpty
        }
        return !sortedItems.isEmpty || !currentCompletedItems.isEmpty
    }

    private var inlineEmptyState: some View {
        VStack(spacing: 8) {
            Text("Start anywhere.")
                .font(.system(size: 24, weight: .regular, design: .serif).italic())
                .tracking(-0.48)
                .foregroundStyle(FloatListTheme.textPrimary.opacity(0.95))

            Text(hasInputDraft ? "Press ⏎ to add" : "Type a task below")
                .font(.system(size: tweaks.bodyTextSize))
                .foregroundStyle(FloatListTheme.textSecondary)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .opacity(hasInputDraft ? 0.42 : 0.7)
        .animation(.easeInOut(duration: 0.2), value: hasInputDraft)
    }

    private func completedToggleButton(for listID: UUID, count: Int) -> some View {
        let expanded = isCompletedExpanded(for: listID)
        let isDraggingTask = draggingID != nil
        let isHovering = !isDraggingTask && hoveredCompletedToggleListID == listID

        return Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                toggleCompletedSection(for: listID)
            }
        } label: {
            HStack(spacing: 6) {
                Text(completedButtonTitle(count: count, expanded: expanded))
                    .font(.system(size: tweaks.secondaryTextSize, weight: .medium))
                    .foregroundStyle(FloatListTheme.textSecondary)

                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: max(tweaks.secondaryTextSize - 3, 8), weight: .semibold))
                    .foregroundStyle(FloatListTheme.textSecondary)
            }
            .padding(.horizontal, tweaks.rowHorizontalPadding)
            .padding(.vertical, max(6, tweaks.rowVerticalPadding))
            .frame(alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: tweaks.rowCornerRadius, style: .continuous)
                    .fill((expanded || isHovering) ? FloatListTheme.controlFill : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .background(WindowDragBlocker())
        .pointerCursor(isDraggingTask ? nil : .pointingHand)
        .allowsHitTesting(!isDraggingTask)
        .onHover { hovering in
            guard !isDraggingTask else {
                hoveredCompletedToggleListID = nil
                return
            }
            hoveredCompletedToggleListID = hovering ? listID : nil
        }
        .padding(.top, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func completedButtonTitle(count: Int, expanded: Bool) -> String {
        let noun = count == 1 ? "completed item" : "completed items"
        return expanded ? "Hide \(count) \(noun)" : "Show \(count) \(noun)"
    }

    private func isCompletedExpanded(for listID: UUID) -> Bool {
        expandedCompletedListIDs.contains(listID)
    }

    private func toggleCompletedSection(for listID: UUID) {
        if expandedCompletedListIDs.contains(listID) {
            expandedCompletedListIDs.remove(listID)
        } else {
            expandedCompletedListIDs.insert(listID)
        }
    }

    private struct RowRenderIdentity: Hashable {
        let itemID: UUID
        let selectedListID: UUID?
        let isCompleted: Bool
        let isTrashItem: Bool
        let subtitle: String?
    }

    private func handleToggle(for item: TodoItem) {
        guard pendingToggleAnimations[item.id] == nil else { return }

        let pendingAnimation = PendingToggleAnimation(targetCompleted: !item.isCompleted)
        withAnimation(Self.rowToggleExitAnimation) {
            pendingToggleAnimations[item.id] = pendingAnimation
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.rowToggleCommitDelayNanoseconds)

            guard pendingToggleAnimations[item.id] == pendingAnimation else { return }

            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                store.toggle(item)
                pendingToggleAnimations.removeValue(forKey: item.id)
            }
        }
    }

    // MARK: - Drag

    private func handleDragChanged(for id: UUID, translation: CGFloat) {
        let items = sortedItems
        let order = items.map(\.id)
        guard beginDragSessionIfNeeded(for: id, translation: translation, items: items, order: order) else { return }

        guard var session = dragSession, session.item.id == id else { return }
        session = updatedDragSession(session, translation: translation, in: order)
        applyDragSessionUpdate(session, triggerHaptic: true)
        syncAutoScrollLoop(with: session)
    }

    private func commitDrag(for id: UUID, translation: CGFloat) {
        guard var session = dragSession, session.item.id == id else {
            removeEscapeMonitor()
            return
        }
        stopAutoScrollLoop()
        settleTask?.cancel()
        settleTask = nil

        let order = sortedItems.map(\.id)
        session = updatedDragSession(
            session,
            translation: translation,
            in: order,
            includeAutoScroll: false
        )

        let target = session.targetIndex
        session.gestureTranslation = dropTranslation(for: session, target: target, in: order)
        session.lastCompositeTranslation = session.gestureTranslation

        let settledSession = session
        withAnimation(Self.reorderAnimation) {
            dragSession = settledSession
        }

        removeEscapeMonitor()

        settleTask = Task { @MainActor in
            defer { settleTask = nil }
            try? await Task.sleep(nanoseconds: Self.reorderSettleDelayNanoseconds)
            guard dragSession?.item.id == id else { return }

            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                if target != settledSession.originalIndex {
                    store.move(from: settledSession.originalIndex, to: target)
                }
                dragSession = nil
            }
        }
    }

    private func cancelDrag() {
        stopAutoScrollLoop()
        settleTask?.cancel()
        settleTask = nil
        hoveredCompletedToggleListID = nil
        withAnimation(Self.reorderAnimation) {
            dragSession = nil
        }
        removeEscapeMonitor()
    }

    private func refreshDragSessionTarget(triggerHaptic: Bool) {
        guard settleTask == nil else { return }
        guard var session = dragSession else { return }

        let order = sortedItems.map(\.id)
        guard order.contains(session.item.id) else {
            cancelDrag()
            return
        }

        session = updatedDragSession(session, in: order)
        applyDragSessionUpdate(session, triggerHaptic: triggerHaptic)
        syncAutoScrollLoop(with: session)
    }

    private func applyDragSessionUpdate(_ session: DragSession, triggerHaptic: Bool) {
        let previousTarget = dragSession?.targetIndex
        if previousTarget != session.targetIndex {
            withAnimation(Self.reorderStepAnimation) {
                dragSession = session
            }
            if triggerHaptic {
                fireHaptic(.alignment)
            }
        } else {
            dragSession = session
        }
    }

    private func syncAutoScrollLoop(with session: DragSession) {
        if abs(session.autoScrollVelocity) > 0.1 {
            startAutoScrollLoop()
        } else {
            stopAutoScrollLoop()
        }
    }

    private func startAutoScrollLoop() {
        guard autoScrollTask == nil else { return }

        autoScrollTask = Task { @MainActor in
            while !Task.isCancelled {
                guard var session = dragSession else { break }

                let velocity = currentAutoScrollVelocity(for: session)
                if abs(velocity) <= 0.1 {
                    session.autoScrollVelocity = 0
                    dragSession = session
                    break
                }

                let deltaY = velocity * Self.autoScrollFrameDuration
                let actualDelta = taskListScrollController.scrollBy(deltaY)
                session.autoScrollVelocity = velocity
                dragSession = session

                if abs(actualDelta) <= 0.01 {
                    session.autoScrollVelocity = 0
                    dragSession = session
                    break
                }

                refreshDragSessionTarget(triggerHaptic: true)

                try? await Task.sleep(nanoseconds: Self.autoScrollFrameNanoseconds)
            }

            if var session = dragSession, abs(session.autoScrollVelocity) > 0.1 {
                session.autoScrollVelocity = 0
                dragSession = session
            }
            autoScrollTask = nil
        }
    }

    private func stopAutoScrollLoop() {
        autoScrollTask?.cancel()
        autoScrollTask = nil
        if var session = dragSession, abs(session.autoScrollVelocity) > 0.1 {
            session.autoScrollVelocity = 0
            dragSession = session
        }
    }

    // MARK: - Drag math helpers

    private func beginDragSessionIfNeeded(
        for id: UUID,
        translation: CGFloat,
        items: [TodoItem],
        order: [UUID]
    ) -> Bool {
        if dragSession != nil {
            return true
        }

        guard let originalIndex = order.firstIndex(of: id),
              let initialFrame = rowFrames[id]
        else {
            return false
        }

        settleTask?.cancel()
        settleTask = nil
        dragSession = DragSession(
            item: items[originalIndex],
            originalIndex: originalIndex,
            initialFrame: initialFrame,
            frozenRowHeight: rowHeights[id] ?? initialFrame.height,
            gestureTranslation: translation,
            lastCompositeTranslation: translation,
            dragDirection: .stationary,
            autoScrollVelocity: 0,
            targetIndex: originalIndex
        )
        hoveredCompletedToggleListID = nil
        fireHaptic(.levelChange)
        installEscapeMonitor()
        return true
    }

    private func updatedDragSession(
        _ session: DragSession,
        translation: CGFloat? = nil,
        in order: [UUID],
        includeAutoScroll: Bool = true
    ) -> DragSession {
        var updated = session
        let nextTranslation = translation ?? session.gestureTranslation
        let delta = nextTranslation - session.lastCompositeTranslation
        updated.dragDirection = ReorderDragDirection(delta: delta, fallback: session.dragDirection)
        updated.gestureTranslation = nextTranslation
        updated.lastCompositeTranslation = nextTranslation
        updated.targetIndex = resolvedTargetIndex(for: updated, in: order)
        updated.autoScrollVelocity = includeAutoScroll ? currentAutoScrollVelocity(for: updated) : 0
        return updated
    }

    private func resolvedTargetIndex(for session: DragSession, in order: [UUID]) -> Int {
        let draggingID = session.item.id
        let overlayMidY = session.overlayMidY
        let remaining = order.filter { $0 != draggingID }
        let frames = remaining.enumerated().map { index, rowID in
            rowFrames[rowID] ?? estimatedFrame(for: rowID, at: index, in: remaining, session: session)
        }
        return min(
            max(
                ReorderInteractionMath.targetIndex(
                    for: overlayMidY,
                    frames: frames,
                    direction: session.dragDirection
                ),
                0
            ),
            remaining.count
        )
    }

    private func currentAutoScrollVelocity(for session: DragSession) -> CGFloat {
        ReorderInteractionMath.autoScrollVelocity(
            pointerY: session.overlayMidY,
            viewport: taskListViewport
        )
    }

    private func estimatedFrame(for id: UUID, at index: Int, in order: [UUID], session: DragSession? = nil) -> CGRect {
        let activeSession = session ?? dragSession
        let y = order.prefix(index).reduce(CGFloat(0)) { partial, rowID in
            if activeSession?.item.id == rowID {
                return partial + (activeSession?.frozenRowHeight ?? RowMetrics.estimatedHeight)
            }
            return partial + (rowHeights[rowID] ?? RowMetrics.estimatedHeight)
        } + (CGFloat(index) * tweaks.rowSpacing)
        let height: CGFloat
        if activeSession?.item.id == id {
            height = activeSession?.frozenRowHeight ?? RowMetrics.estimatedHeight
        } else {
            height = rowHeights[id] ?? RowMetrics.estimatedHeight
        }
        let width = activeSession?.initialFrame.width ?? max(0, tweaks.expandedWidth - (tweaks.contentHorizontalPadding * 2))
        let minX = activeSession?.initialFrame.minX ?? tweaks.contentHorizontalPadding
        return CGRect(x: minX, y: y, width: width, height: height)
    }

    private func dropTranslation(for session: DragSession, target: Int, in order: [UUID]) -> CGFloat {
        var projectedOrder = order.filter { $0 != session.item.id }
        let clampedTarget = min(max(target, 0), projectedOrder.count)
        projectedOrder.insert(session.item.id, at: clampedTarget)
        let destinationFrame = estimatedFrame(for: session.item.id, at: clampedTarget, in: projectedOrder, session: session)
        return destinationFrame.midY - session.initialFrame.midY
    }

    private func dragOverlay(for session: DragSession) -> some View {
        TodoRowDragPreview(item: session.item)
            .frame(width: session.initialFrame.width, height: session.frozenRowHeight, alignment: .topLeading)
            .position(
                x: session.initialFrame.midX,
                y: session.initialFrame.midY + session.gestureTranslation
            )
            .zIndex(1_000)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func dragLandingIndicator() -> some View {
        RoundedRectangle(cornerRadius: tweaks.rowCornerRadius, style: .continuous)
            .fill(FloatListTheme.controlFillStrong.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: tweaks.rowCornerRadius, style: .continuous)
                    .stroke(FloatListTheme.hairline.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: FloatListTheme.panelShadow(opacity: 0.05), radius: 4, y: 1)
            .padding(.vertical, 3)
            .allowsHitTesting(false)
    }

    private func fireHaptic(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .default)
    }

    private func installEscapeMonitor() {
        if escapeMonitor != nil { return }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            if event.keyCode == escapeKeyCode {
                cancelDrag()
                return nil
            }
            return event
        }
    }

    private func installUndoMonitor() {
        if undoMonitor != nil { return }
        undoMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            guard event.keyCode == undoKeyCode,
                  event.modifierFlags.contains(.command),
                  !event.modifierFlags.contains(.shift),
                  !event.modifierFlags.contains(.option),
                  !event.modifierFlags.contains(.control)
            else { return event }
            guard store.canUndo else { return event }
            performUndo()
            return nil
        }
    }

    private func removeUndoMonitor() {
        if let monitor = undoMonitor {
            NSEvent.removeMonitor(monitor)
            undoMonitor = nil
        }
    }

    private func removeEscapeMonitor() {
        if let monitor = escapeMonitor {
            NSEvent.removeMonitor(monitor)
            escapeMonitor = nil
        }
    }

    private var activeRecoveryNotice: TodoStoreRecoveryNotice? {
        guard let notice = store.recoveryNotice else { return nil }
        return dismissedRecoveryNoticeID == notice.id ? nil : notice
    }

    @ViewBuilder
    private func recoveryBanner(_ notice: TodoStoreRecoveryNotice) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.orange)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(notice.message)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(FloatListTheme.warningText)

                if let backupURL = notice.backupURL {
                    Text("Backup: \(backupURL.lastPathComponent)")
                        .font(.system(size: 10))
                        .foregroundStyle(FloatListTheme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 8)

            Button {
                dismissedRecoveryNoticeID = notice.id
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(FloatListTheme.textPrimary)
                    .frame(width: 18, height: 18)
                    .background(
                        Circle()
                            .fill(FloatListTheme.controlFill)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(FloatListTheme.warningBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(FloatListTheme.warningBorder, lineWidth: 1)
        )
    }
}
