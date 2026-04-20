import SwiftUI
import AppKit

private let escapeKeyCode: UInt16 = 53
private let undoKeyCode: UInt16 = 6   // kVK_ANSI_Z

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
                .symbolRenderingMode(.hierarchical)
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
            Image(systemName: "gearshape")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(FloatListTheme.textPrimary)
                .symbolRenderingMode(.hierarchical)
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
    @State private var pendingToggleAnimations: [UUID: PendingToggleAnimation] = [:]
    @State private var newTaskTitle = ""
    @State private var dismissedRecoveryNoticeID: UUID?
    @State private var draggingID: UUID?
    @State private var dragOffset: CGFloat = 0
    @State private var rowHeights: [UUID: CGFloat] = [:]
    @State private var lastTargetIndex: Int?
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

    private static let reorderAnimation = Animation.spring(response: 0.35, dampingFraction: 0.78)
    private static let rowToggleExitAnimation = Animation.easeOut(duration: 0.18)
    private static let rowToggleCommitDelayNanoseconds: UInt64 = 260_000_000

    private struct PendingToggleAnimation: Equatable {
        let targetCompleted: Bool
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
        ScrollView {
            LazyVStack(spacing: tweaks.rowSpacing) {
                if let listID = selectedRegularListID {
                    if sortedItems.isEmpty && !currentCompletedItems.isEmpty {
                        inlineEmptyState
                    }

                    ForEach(sortedItems) { item in
                        taskRow(item)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

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
            .coordinateSpace(name: "list")
            .onPreferenceChange(RowHeightPreferenceKey.self) { heights in
                rowHeights.merge(heights) { _, new in new }
            }
            .onChange(of: store.items.map(\.id)) { _, ids in
                let live = Set(ids)
                rowHeights = rowHeights.filter { live.contains($0.key) }
                pendingToggleAnimations = pendingToggleAnimations.filter { live.contains($0.key) }
            }
            .onChange(of: store.selectedListID) {
                cancelDrag()
            }
        }
        .frame(maxHeight: .infinity)
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
            isDragging: draggingID == item.id,
            isDragActive: draggingID != nil,
            yOffset: offset(for: item.id),
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
            isToggleEnabled: !isTrashItem && pendingToggleAnimation == nil,
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
        Image("PanelGlyph")
            .renderingMode(.template)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 18, height: 18)
            .foregroundStyle(FloatListTheme.textPrimary)
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
        let isHovering = hoveredCompletedToggleListID == listID

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
        .pointerCursor(.pointingHand)
        .onHover { hovering in
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
        let order = sortedItems.map(\.id)
        if draggingID == nil {
            draggingID = id
            lastTargetIndex = order.firstIndex(of: id)
            fireHaptic(.levelChange)
            installEscapeMonitor()
        }
        dragOffset = translation
        guard let original = order.firstIndex(of: id) else { return }
        let target = targetIndex(from: original, offset: translation, in: order)
        if target != lastTargetIndex {
            lastTargetIndex = target
            fireHaptic(.alignment)
        }
    }

    private func commitDrag(for id: UUID, translation: CGFloat) {
        guard draggingID == id else {
            removeEscapeMonitor()
            lastTargetIndex = nil
            return
        }
        let order = sortedItems.map(\.id)
        let original = order.firstIndex(of: id) ?? 0
        let target = targetIndex(from: original, offset: translation, in: order)
        withAnimation(Self.reorderAnimation) {
            if target != original {
                store.move(from: original, to: target)
            }
            dragOffset = 0
            draggingID = nil
        }
        lastTargetIndex = nil
        removeEscapeMonitor()
    }

    private func cancelDrag() {
        withAnimation(Self.reorderAnimation) {
            dragOffset = 0
            draggingID = nil
        }
        lastTargetIndex = nil
        removeEscapeMonitor()
    }

    // MARK: - Drag math helpers

    private func targetIndex(from original: Int, offset: CGFloat, in order: [UUID]) -> Int {
        guard !order.isEmpty else { return 0 }
        var idx = original
        var accumulated: CGFloat = 0
        if offset > 0 {
            for i in (original + 1)..<order.count {
                let h = rowHeights[order[i]] ?? RowMetrics.estimatedHeight
                accumulated += h
                if offset > accumulated - h / 2 {
                    idx = i
                } else {
                    break
                }
            }
        } else if offset < 0 {
            for i in stride(from: original - 1, through: 0, by: -1) {
                let h = rowHeights[order[i]] ?? RowMetrics.estimatedHeight
                accumulated += h
                if -offset > accumulated - h / 2 {
                    idx = i
                } else {
                    break
                }
            }
        }
        return idx
    }

    private func yPosition(for index: Int, in order: [UUID]) -> CGFloat {
        var y: CGFloat = 0
        for i in 0..<index {
            y += rowHeights[order[i]] ?? RowMetrics.estimatedHeight
        }
        return y
    }

    private func offset(for id: UUID) -> CGFloat {
        guard let draggingID else { return 0 }
        if id == draggingID { return dragOffset }
        let order = sortedItems.map(\.id)
        guard let originalIdx = order.firstIndex(of: draggingID),
              let myIdx = order.firstIndex(of: id) else { return 0 }
        let target = targetIndex(from: originalIdx, offset: dragOffset, in: order)
        if target == originalIdx { return 0 }

        var newOrder = order
        newOrder.remove(at: originalIdx)
        newOrder.insert(draggingID, at: target)
        guard let newIdx = newOrder.firstIndex(of: id) else { return 0 }
        return yPosition(for: newIdx, in: newOrder) - yPosition(for: myIdx, in: order)
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
