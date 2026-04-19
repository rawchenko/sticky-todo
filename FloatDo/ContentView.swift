import SwiftUI
import AppKit

private let escapeKeyCode: UInt16 = 53

private struct AddListButton: View {
    var action: () -> Void

    @State private var isHovering = false
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .medium))
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

private struct AddSubtaskRow: View {
    static let estimatedHeight: CGFloat = 34

    let parentID: UUID
    var onSubmit: (String) -> Void
    var onDismiss: () -> Void
    var yOffset: CGFloat = 0

    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Circle()
                .strokeBorder(
                    Color.dynamic(
                        light: Color.black.opacity(0.35),
                        dark: Color.white.opacity(0.45)
                    ),
                    lineWidth: 1.5
                )
                .frame(width: 18, height: 18)

            TextField("Subtask", text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(FloatDoTheme.textPrimary)
                .focused($isFocused)
                .onSubmit(commit)
                .onExitCommand(perform: onDismiss)

            Spacer(minLength: 0)
        }
        .padding(.leading, 34)
        .padding(.trailing, 12)
        .padding(.vertical, 8)
        .background(WindowDragBlocker())
        .contentShape(Rectangle())
        .onAppear {
            DispatchQueue.main.async { isFocused = true }
        }
        .onChange(of: isFocused) { _, focused in
            if !focused && draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                onDismiss()
            }
        }
        .offset(y: yOffset)
    }

    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            onDismiss()
            return
        }
        onSubmit(trimmed)
        draft = ""
    }
}

private enum TaskEntry: Identifiable {
    case parent(TodoItem)
    case child(TodoItem, parentID: UUID)
    case addSubtask(parentID: UUID)

    var id: String {
        switch self {
        case .parent(let item): return "p-\(item.id.uuidString)"
        case .child(let item, _): return "c-\(item.id.uuidString)"
        case .addSubtask(let pid): return "add-\(pid.uuidString)"
        }
    }
}

struct ContentView: View {
    @ObservedObject var store: TodoStore
    @ObservedObject var panelManager: PanelManager
    @State private var newTaskTitle = ""
    @State private var dismissedRecoveryNoticeID: UUID?
    @State private var draggingID: UUID?
    @State private var draggingChildParentID: UUID?
    @State private var dragOffset: CGFloat = 0
    @State private var rowHeights: [UUID: CGFloat] = [:]
    @State private var lastTargetIndex: Int?
    @State private var escapeMonitor: Any?
    @State private var pendingAutoFocusListID: UUID?
    @State private var draggingListID: UUID?
    @State private var listDragOffset: CGFloat = 0
    @State private var listWidths: [UUID: CGFloat] = [:]
    @State private var lastListTargetIndex: Int?
    @State private var listEscapeMonitor: Any?
    @State private var addingSubtaskFor: UUID?
    @FocusState private var isInputFocused: Bool

    private static let reorderAnimation = Animation.spring(response: 0.35, dampingFraction: 0.78)

    var body: some View {
        GeometryReader { proxy in
            let shape = MorphingDockedShape(
                expansion: expansionProgress,
                panelRadius: PanelMetrics.cornerRadius
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
        .animation(PanelMotion.stateAnimation, value: panelManager.isCollapsed)
        .animation(PanelMotion.stateAnimation, value: panelManager.currentAnchor)
        .animation(PanelMotion.stateAnimation, value: panelManager.isDragging)
        .onDisappear {
            removeEscapeMonitor()
            removeListEscapeMonitor()
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
        HStack(spacing: 6) {
            if store.lists.isEmpty {
                Text("No lists yet")
                    .font(.system(size: 13))
                    .foregroundStyle(FloatDoTheme.textSecondary)
                    .padding(.horizontal, 4)
                Spacer(minLength: 0)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(Array(store.lists.enumerated()), id: \.element.id) { index, list in
                                ListPillView(
                                    list: list,
                                    isSelected: store.selectedListID == list.id,
                                    autoFocusOnAppear: pendingAutoFocusListID == list.id,
                                    isDragging: draggingListID == list.id,
                                    isDragActive: draggingListID != nil,
                                    xOffset: visualListOffset(for: index, in: store.lists),
                                    onSelect: { selectList(list.id) },
                                    onRename: { store.renameList(list, to: $0) },
                                    onDelete: { deleteList(list) },
                                    onSetIcon: { store.setListIcon(list, to: $0) },
                                    onDragChanged: { handleListDragChanged(for: list.id, translation: $0) },
                                    onDragEnded: { commitListDrag(for: list.id, translation: $0) },
                                    onAutoFocusConsumed: { pendingAutoFocusListID = nil }
                                )
                                .id(list.id)
                                .transition(
                                    .asymmetric(
                                        insertion: .opacity.combined(with: .scale(scale: 0.7, anchor: .center)),
                                        removal: .opacity.combined(with: .scale(scale: 0.6, anchor: .center))
                                    )
                                )
                            }
                        }
                        .padding(.vertical, 2)
                        .coordinateSpace(name: "lists")
                        .onPreferenceChange(ListWidthPreferenceKey.self) { widths in
                            listWidths.merge(widths) { _, new in new }
                        }
                        .onChange(of: store.lists.map(\.id)) { _, ids in
                            let live = Set(ids)
                            listWidths = listWidths.filter { live.contains($0.key) }
                            if let pending = pendingAutoFocusListID, !live.contains(pending) {
                                pendingAutoFocusListID = nil
                            }
                        }
                        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: store.lists.map(\.id))
                        .animation(.spring(response: 0.36, dampingFraction: 0.82), value: store.selectedListID)
                    }
                    .onChange(of: store.selectedListID) { _, id in
                        guard draggingListID == nil else { return }
                        scroll(toListID: id, using: proxy)
                    }
                    .onChange(of: pendingAutoFocusListID) { _, id in scroll(toListID: id, using: proxy) }
                }
            }

            AddListButton(action: createList)
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private func createList() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
            let newList = store.addList(name: TodoList.defaultName)
            pendingAutoFocusListID = newList.id
        }
    }

    private func deleteList(_ list: TodoList) {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.84)) {
            store.deleteList(list)
        }
    }

    private func selectList(_ id: UUID) {
        withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
            store.selectList(id)
        }
    }

    private func scroll(toListID id: UUID?, using proxy: ScrollViewProxy) {
        guard let id else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(id, anchor: .center)
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
                .font(.system(size: 14))
                .foregroundStyle(FloatDoTheme.textSecondary)
        }
        .opacity(isInputFocused ? 0.42 : 0.7)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.2), value: isInputFocused)
    }

    private var taskList: some View {
        let entries = currentEntries
        return ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(entries) { entry in
                    entryView(for: entry)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.horizontal, 12)
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
                addingSubtaskFor = nil
            }
        }
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private func entryView(for entry: TaskEntry) -> some View {
        switch entry {
        case .parent(let item):
            parentRow(item)
        case .child(let item, let parentID):
            childRow(item, parentID: parentID)
        case .addSubtask(let parentID):
            AddSubtaskRow(
                parentID: parentID,
                onSubmit: { title in
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                        store.addSubtask(title: title, parentID: parentID)
                    }
                },
                onDismiss: {
                    withAnimation(.easeOut(duration: 0.18)) {
                        addingSubtaskFor = nil
                    }
                },
                yOffset: offsetForAddSubtask(parentID: parentID)
            )
        }
    }

    private func parentRow(_ item: TodoItem) -> some View {
        TodoRowView(
            item: item,
            isDragging: draggingID == item.id,
            isDragActive: draggingID != nil,
            yOffset: offsetForParent(id: item.id),
            depth: 0,
            onToggle: {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                    store.toggle(item)
                }
            },
            onDelete: {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                    if addingSubtaskFor == item.id {
                        addingSubtaskFor = nil
                    }
                    store.delete(item)
                }
            },
            onRename: { newTitle in
                store.rename(item, to: newTitle)
            },
            onAddSubtask: {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.84)) {
                    addingSubtaskFor = item.id
                }
            },
            onDragChanged: { translation in
                handleParentDragChanged(for: item.id, translation: translation)
            },
            onDragEnded: { translation in
                commitParentDrag(for: item.id, translation: translation)
            }
        )
    }

    private func childRow(_ item: TodoItem, parentID: UUID) -> some View {
        TodoRowView(
            item: item,
            isDragging: draggingID == item.id,
            isDragActive: draggingID != nil,
            yOffset: offsetForChild(id: item.id, parentID: parentID),
            depth: 1,
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
                handleChildDragChanged(for: item.id, parentID: parentID, translation: translation)
            },
            onDragEnded: { translation in
                commitChildDrag(for: item.id, parentID: parentID, translation: translation)
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
                .font(.system(size: 14))
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
        .padding(.leading, 18)
        .padding(.trailing, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous).fill(FloatDoTheme.inputFill)
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
        Image(systemName: "checklist")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(FloatDoTheme.textPrimary)
            .frame(width: PanelMetrics.collapsedSize.width, height: PanelMetrics.collapsedSize.height)
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

    private var currentEntries: [TaskEntry] {
        guard let listID = store.selectedListID else { return [] }
        var entries: [TaskEntry] = []
        for parent in store.topLevelItems(in: listID) {
            entries.append(.parent(parent))
            for child in store.children(of: parent.id) {
                entries.append(.child(child, parentID: parent.id))
            }
            if addingSubtaskFor == parent.id {
                entries.append(.addSubtask(parentID: parent.id))
            }
        }
        return entries
    }

    // MARK: - Parent drag

    private func handleParentDragChanged(for id: UUID, translation: CGFloat) {
        guard let listID = store.selectedListID else { return }
        let topLevel = store.topLevelItems(in: listID).map(\.id)
        if draggingID == nil {
            draggingID = id
            draggingChildParentID = nil
            lastTargetIndex = topLevel.firstIndex(of: id)
            fireHaptic(.levelChange)
            installEscapeMonitor()
        }
        dragOffset = translation
        guard let original = topLevel.firstIndex(of: id) else { return }
        let target = topLevelTargetIndex(from: original, offset: translation, in: topLevel)
        if target != lastTargetIndex {
            lastTargetIndex = target
            fireHaptic(.alignment)
        }
    }

    private func commitParentDrag(for id: UUID, translation: CGFloat) {
        guard draggingID == id, draggingChildParentID == nil else {
            removeEscapeMonitor()
            lastTargetIndex = nil
            return
        }
        guard let listID = store.selectedListID else { return }
        let topLevel = store.topLevelItems(in: listID).map(\.id)
        let original = topLevel.firstIndex(of: id) ?? 0
        let target = topLevelTargetIndex(from: original, offset: translation, in: topLevel)
        withAnimation(Self.reorderAnimation) {
            if target != original {
                store.moveTopLevel(from: original, to: target)
            }
            dragOffset = 0
            draggingID = nil
            draggingChildParentID = nil
        }
        lastTargetIndex = nil
        removeEscapeMonitor()
    }

    // MARK: - Child drag

    private func handleChildDragChanged(for id: UUID, parentID: UUID, translation: CGFloat) {
        let siblings = store.children(of: parentID).map(\.id)
        if draggingID == nil {
            draggingID = id
            draggingChildParentID = parentID
            lastTargetIndex = siblings.firstIndex(of: id)
            fireHaptic(.levelChange)
            installEscapeMonitor()
        }
        dragOffset = translation
        guard let original = siblings.firstIndex(of: id) else { return }
        let target = childTargetIndex(from: original, offset: translation, in: siblings)
        if target != lastTargetIndex {
            lastTargetIndex = target
            fireHaptic(.alignment)
        }
    }

    private func commitChildDrag(for id: UUID, parentID: UUID, translation: CGFloat) {
        guard draggingID == id, draggingChildParentID == parentID else {
            removeEscapeMonitor()
            lastTargetIndex = nil
            return
        }
        let siblings = store.children(of: parentID).map(\.id)
        let original = siblings.firstIndex(of: id) ?? 0
        let target = childTargetIndex(from: original, offset: translation, in: siblings)
        withAnimation(Self.reorderAnimation) {
            if target != original {
                store.moveChild(parentID: parentID, from: original, to: target)
            }
            dragOffset = 0
            draggingID = nil
            draggingChildParentID = nil
        }
        lastTargetIndex = nil
        removeEscapeMonitor()
    }

    private func cancelDrag() {
        withAnimation(Self.reorderAnimation) {
            dragOffset = 0
            draggingID = nil
            draggingChildParentID = nil
        }
        lastTargetIndex = nil
        removeEscapeMonitor()
    }

    // MARK: - Drag math helpers

    private func topLevelTargetIndex(from original: Int, offset: CGFloat, in order: [UUID]) -> Int {
        guard !order.isEmpty else { return 0 }
        var idx = original
        var accumulated: CGFloat = 0
        if offset > 0 {
            for i in (original + 1)..<order.count {
                let h = blockHeight(for: order[i])
                accumulated += h
                if offset > accumulated - h / 2 {
                    idx = i
                } else {
                    break
                }
            }
        } else if offset < 0 {
            for i in stride(from: original - 1, through: 0, by: -1) {
                let h = blockHeight(for: order[i])
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

    private func childTargetIndex(from original: Int, offset: CGFloat, in order: [UUID]) -> Int {
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

    private func blockHeight(for parentID: UUID) -> CGFloat {
        var h = rowHeights[parentID] ?? RowMetrics.estimatedHeight
        for child in store.children(of: parentID) {
            h += rowHeights[child.id] ?? RowMetrics.estimatedHeight
        }
        if addingSubtaskFor == parentID {
            h += AddSubtaskRow.estimatedHeight
        }
        return h
    }

    private func topLevelYPosition(for index: Int, in order: [UUID]) -> CGFloat {
        var y: CGFloat = 0
        for i in 0..<index {
            y += blockHeight(for: order[i])
        }
        return y
    }

    private func childYPosition(for index: Int, in order: [UUID]) -> CGFloat {
        var y: CGFloat = 0
        for i in 0..<index {
            y += rowHeights[order[i]] ?? RowMetrics.estimatedHeight
        }
        return y
    }

    private func offsetForParent(id: UUID) -> CGFloat {
        guard let draggingID else { return 0 }
        if draggingChildParentID != nil {
            return 0
        }
        if id == draggingID { return dragOffset }
        guard let listID = store.selectedListID else { return 0 }
        let order = store.topLevelItems(in: listID).map(\.id)
        guard let originalIdx = order.firstIndex(of: draggingID),
              let myIdx = order.firstIndex(of: id) else { return 0 }
        let target = topLevelTargetIndex(from: originalIdx, offset: dragOffset, in: order)
        if target == originalIdx { return 0 }

        var newOrder = order
        newOrder.remove(at: originalIdx)
        newOrder.insert(draggingID, at: target)
        guard let newIdx = newOrder.firstIndex(of: id) else { return 0 }
        return topLevelYPosition(for: newIdx, in: newOrder) - topLevelYPosition(for: myIdx, in: order)
    }

    private func offsetForChild(id: UUID, parentID: UUID) -> CGFloat {
        guard let draggingID else { return 0 }
        if let childParent = draggingChildParentID {
            // Child drag
            if id == draggingID { return dragOffset }
            guard childParent == parentID else { return 0 }
            let order = store.children(of: parentID).map(\.id)
            guard let originalIdx = order.firstIndex(of: draggingID),
                  let myIdx = order.firstIndex(of: id) else { return 0 }
            let target = childTargetIndex(from: originalIdx, offset: dragOffset, in: order)
            if target == originalIdx { return 0 }
            var newOrder = order
            newOrder.remove(at: originalIdx)
            newOrder.insert(draggingID, at: target)
            guard let newIdx = newOrder.firstIndex(of: id) else { return 0 }
            return childYPosition(for: newIdx, in: newOrder) - childYPosition(for: myIdx, in: order)
        } else {
            // Parent drag — child follows its parent's shift
            return offsetForParent(id: parentID)
        }
    }

    private func offsetForAddSubtask(parentID: UUID) -> CGFloat {
        guard draggingID != nil else { return 0 }
        if draggingChildParentID != nil { return 0 }
        return offsetForParent(id: parentID)
    }

    private func targetListIndex(from original: Int, offset: CGFloat, in order: [TodoList]) -> Int {
        guard !order.isEmpty else { return 0 }
        var idx = original
        var accumulated: CGFloat = 0
        if offset > 0 {
            for i in (original + 1)..<order.count {
                let w = listWidths[order[i].id] ?? ListPillMetrics.estimatedWidth
                accumulated += w
                if offset > accumulated - w / 2 {
                    idx = i
                } else {
                    break
                }
            }
        } else if offset < 0 {
            for i in stride(from: original - 1, through: 0, by: -1) {
                let w = listWidths[order[i].id] ?? ListPillMetrics.estimatedWidth
                accumulated += w
                if -offset > accumulated - w / 2 {
                    idx = i
                } else {
                    break
                }
            }
        }
        return idx
    }

    private func xPosition(for index: Int, in order: [UUID]) -> CGFloat {
        var x: CGFloat = 0
        for i in 0..<index {
            x += listWidths[order[i]] ?? ListPillMetrics.estimatedWidth
        }
        return x
    }

    private func visualListOffset(for index: Int, in visible: [TodoList]) -> CGFloat {
        guard let dragID = draggingListID,
              let originalIdx = visible.firstIndex(where: { $0.id == dragID }) else {
            return 0
        }
        if index == originalIdx {
            return listDragOffset
        }
        let target = targetListIndex(from: originalIdx, offset: listDragOffset, in: visible)
        if target == originalIdx { return 0 }

        let currentOrder = visible.map(\.id)
        var newOrder = currentOrder
        let draggedID = newOrder.remove(at: originalIdx)
        newOrder.insert(draggedID, at: target)

        let rowID = currentOrder[index]
        guard let newIdx = newOrder.firstIndex(of: rowID) else { return 0 }

        return xPosition(for: newIdx, in: newOrder) - xPosition(for: index, in: currentOrder)
    }

    private func handleListDragChanged(for id: UUID, translation: CGFloat) {
        let visible = store.lists
        if draggingListID == nil {
            draggingListID = id
            lastListTargetIndex = visible.firstIndex(where: { $0.id == id })
            fireHaptic(.levelChange)
            installListEscapeMonitor()
        }
        listDragOffset = translation
        guard let original = visible.firstIndex(where: { $0.id == id }) else { return }
        let target = targetListIndex(from: original, offset: translation, in: visible)
        if target != lastListTargetIndex {
            lastListTargetIndex = target
            fireHaptic(.alignment)
        }
    }

    private func commitListDrag(for id: UUID, translation: CGFloat) {
        guard draggingListID == id else {
            removeListEscapeMonitor()
            lastListTargetIndex = nil
            return
        }
        let visible = store.lists
        let original = visible.firstIndex(where: { $0.id == id }) ?? 0
        let target = targetListIndex(from: original, offset: translation, in: visible)
        withAnimation(Self.reorderAnimation) {
            if target != original {
                store.moveList(from: original, to: target)
            }
            listDragOffset = 0
            draggingListID = nil
        }
        lastListTargetIndex = nil
        removeListEscapeMonitor()
    }

    private func cancelListDrag() {
        withAnimation(Self.reorderAnimation) {
            listDragOffset = 0
            draggingListID = nil
        }
        lastListTargetIndex = nil
        removeListEscapeMonitor()
    }

    private func installListEscapeMonitor() {
        if listEscapeMonitor != nil { return }
        listEscapeMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            if event.keyCode == escapeKeyCode {
                cancelListDrag()
                return nil
            }
            return event
        }
    }

    private func removeListEscapeMonitor() {
        if let monitor = listEscapeMonitor {
            NSEvent.removeMonitor(monitor)
            listEscapeMonitor = nil
        }
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
