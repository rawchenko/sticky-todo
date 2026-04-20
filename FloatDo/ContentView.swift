import SwiftUI
import AppKit

private let escapeKeyCode: UInt16 = 53

private struct AddListButton: View {
    var action: () -> Void

    @State private var isHovering = false
    @State private var isPressed = false
    @ObservedObject private var tweaks = LayoutTweaks.shared

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: tweaks.addListIconSize, weight: .medium))
                .foregroundStyle(FloatDoTheme.textSecondary)
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

private struct SettingsButton: View {
    @State private var isHovering = false
    @State private var isPressed = false
    @State private var spinCount = 0
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
        Button(action: openSettings) {
            Image(systemName: "gearshape")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(FloatDoTheme.textPrimary)
                .symbolRenderingMode(.hierarchical)
                .rotationEffect(.degrees(Double(spinCount) * 60))
                .frame(width: pillContentHeight, height: pillContentHeight)
                .padding(.horizontal, tweaks.pillHorizontalPadding)
                .padding(.vertical, tweaks.pillVerticalPadding)
                .background(
                    RoundedRectangle(cornerRadius: tweaks.pillCornerRadius, style: .continuous)
                        .fill(isHovering ? FloatDoTheme.rowHover : Color.clear)
                        .animation(.easeOut(duration: 0.12), value: isHovering)
                )
                .contentShape(RoundedRectangle(cornerRadius: tweaks.pillCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .pointerCursor(.pointingHand)
        .background(WindowDragBlocker())
        .help("Settings")
        .scaleEffect(isPressed ? 0.9 : 1.0)
        .opacity(isHovering ? 1 : 0.72)
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .animation(.spring(response: 0.55, dampingFraction: 0.62), value: spinCount)
        .animation(.spring(response: 0.22, dampingFraction: 0.7), value: isPressed)
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                spinCount += 1
            } else {
                isPressed = false
            }
        }
        .onLongPressGesture(minimumDuration: .infinity, maximumDistance: 6, perform: {}) { pressing in
            isPressed = pressing
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
    @State private var newTaskTitle = ""
    @State private var dismissedRecoveryNoticeID: UUID?
    @State private var draggingID: UUID?
    @State private var dragOffset: CGFloat = 0
    @State private var rowHeights: [UUID: CGFloat] = [:]
    @State private var lastTargetIndex: Int?
    @State private var escapeMonitor: Any?
    @State private var pendingAutoFocusListID: UUID?
    @State private var listPendingDeletion: TodoList?
    @State private var isHoldingForDeletePrompt = false
    @FocusState private var isInputFocused: Bool

    private static let reorderAnimation = Animation.spring(response: 0.35, dampingFraction: 0.78)

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
        .onDisappear {
            removeEscapeMonitor()
            releaseDeletePromptHoldIfNeeded()
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
        .onChange(of: listPendingDeletion == nil) { _, isNil in
            setDeletePromptHold(!isNil)
        }
    }

    private var deleteAlertTitle: String {
        guard let list = listPendingDeletion else { return "Delete list?" }
        return "Delete \u{201C}\(list.name)\u{201D}?"
    }

    private func deleteAlertMessage(for list: TodoList) -> String {
        let count = store.items(in: list.id).count
        if count == 0 {
            return "This list will be permanently deleted."
        }
        let taskWord = count == 1 ? "task" : "tasks"
        return "This list and its \(count) \(taskWord) will be permanently deleted."
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

    private var expandedLayer: some View {
        expandedContent
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

            if store.lists.isEmpty {
                noListsEmptyState
            } else if sortedItems.isEmpty {
                emptyState
            } else {
                taskList
            }

            if store.selectedListID != nil {
                inputBar
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .liquidGlassContainer(spacing: 0)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 6) {
            if store.lists.isEmpty {
                Text("No lists yet")
                    .font(.system(size: tweaks.secondaryTextSize))
                    .foregroundStyle(FloatDoTheme.textSecondary)
                    .padding(.horizontal, 4)
                Spacer(minLength: 0)
                AddListButton(action: createList)
            } else {
                ListsDropdownView(
                    lists: store.lists,
                    selectedID: store.selectedListID,
                    autoFocusRenameID: pendingAutoFocusListID,
                    onSelect: { selectList($0) },
                    onCreate: createList,
                    onRename: { list, name in store.renameList(list, to: name) },
                    onDelete: { deleteList($0) },
                    onSetIcon: { list, symbol in store.setListIcon(list, to: symbol) },
                    onAutoFocusConsumed: { pendingAutoFocusListID = nil }
                )
                Spacer(minLength: 0)
            }
            SettingsButton()
        }
        .padding(.horizontal, tweaks.contentHorizontalPadding)
        .padding(.top, tweaks.contentTopPadding)
        .padding(.bottom, tweaks.contentBottomPadding)
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
                .foregroundStyle(FloatDoTheme.textPrimary.opacity(0.95))
                .multilineTextAlignment(.center)

            Text("Tap + above to add one.")
                .font(.system(size: 13))
                .foregroundStyle(FloatDoTheme.textSecondary)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("Start anywhere.")
                .font(.system(size: 28, weight: .regular, design: .serif).italic())
                .tracking(-0.56)
                .foregroundStyle(FloatDoTheme.textPrimary.opacity(0.95))

            Text(isInputFocused ? "Press ⏎ to add" : "Type a task below")
                .font(.system(size: tweaks.bodyTextSize))
                .foregroundStyle(FloatDoTheme.textSecondary)
        }
        .opacity(isInputFocused ? 0.42 : 0.7)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.2), value: isInputFocused)
    }

    private var taskList: some View {
        ScrollView {
            LazyVStack(spacing: tweaks.rowSpacing) {
                ForEach(sortedItems) { item in
                    taskRow(item)
                        .transition(.opacity.combined(with: .move(edge: .top)))
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
            }
            .onChange(of: store.selectedListID) {
                cancelDrag()
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func taskRow(_ item: TodoItem) -> some View {
        TodoRowView(
            item: item,
            isDragging: draggingID == item.id,
            isDragActive: draggingID != nil,
            yOffset: offset(for: item.id),
            onToggle: {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                    store.toggle(item)
                }
            },
            onDelete: {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                    store.delete(item)
                }
            },
            onRename: { newTitle in
                store.rename(item, to: newTitle)
            },
            onDragChanged: { translation in
                handleDragChanged(for: item.id, translation: translation)
            },
            onDragEnded: { translation in
                commitDrag(for: item.id, translation: translation)
            }
        )
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField(
                sortedItems.isEmpty ? "What's your first task?" : "What's next?",
                text: $newTaskTitle,
                axis: .vertical
            )
                .textFieldStyle(.plain)
                .font(.system(size: tweaks.bodyTextSize))
                .foregroundStyle(FloatDoTheme.textPrimary)
                .lineLimit(1...5)
                .focused($isInputFocused)
                .onSubmit(submitTask)
                .padding(.vertical, 4)

            Button(action: submitTask) {
                Image(systemName: "arrow.up")
            }
            .floatDoGlassButton(prominent: canSubmit)
            .disabled(!canSubmit)
            .pointerCursor(canSubmit ? .pointingHand : nil)
            .animation(.easeInOut(duration: 0.15), value: canSubmit)
        }
        .padding(.leading, tweaks.inputLeadingPadding)
        .padding(.trailing, tweaks.inputTrailingPadding)
        .padding(.vertical, tweaks.inputVerticalPadding)
        .background(
            RoundedRectangle(cornerRadius: tweaks.inputCornerRadius, style: .continuous).fill(FloatDoTheme.inputFill)
        )
        .padding(.horizontal, 6)
        .padding(.bottom, 6)
        .animation(.easeOut(duration: 0.18), value: newTaskTitle)
    }

    private var canSubmit: Bool {
        !newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
            .foregroundStyle(FloatDoTheme.textPrimary)
            .frame(width: tweaks.collapsedWidth, height: tweaks.collapsedHeight)
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
        let adjusted = max(0, (expansionProgress - 0.18) / 0.82)
        return adjusted * adjusted
    }

    private var expandedScale: CGFloat {
        0.975 + (0.025 * expansionProgress)
    }

    private var collapsedOpacity: CGFloat {
        let inverse = 1 - expansionProgress
        return min(1, inverse * 1.3)
    }

    private var collapsedScale: CGFloat {
        1 - (0.1 * expansionProgress)
    }

    private var collapsedOffset: CGSize {
        CGSize(
            width: transitionOffset.width * expansionProgress * 0.32,
            height: transitionOffset.height * expansionProgress * 0.32
        )
    }

    private var transitionOffset: CGSize {
        panelManager.currentAnchor.edge.transitionOffset
    }

    private var sortedItems: [TodoItem] {
        store.visibleItems
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
                    .foregroundStyle(FloatDoTheme.warningText)

                if let backupURL = notice.backupURL {
                    Text("Backup: \(backupURL.lastPathComponent)")
                        .font(.system(size: 10))
                        .foregroundStyle(FloatDoTheme.textSecondary)
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
                    .foregroundStyle(FloatDoTheme.textPrimary)
                    .frame(width: 18, height: 18)
                    .background(
                        Circle()
                            .fill(FloatDoTheme.controlFill)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(FloatDoTheme.warningBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(FloatDoTheme.warningBorder, lineWidth: 1)
        )
    }
}
