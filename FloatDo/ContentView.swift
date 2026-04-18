import SwiftUI
import AppKit

private let escapeKeyCode: UInt16 = 53

struct ContentView: View {
    @ObservedObject var store: TodoStore
    @ObservedObject var panelManager: PanelManager
    @State private var newTaskTitle = ""
    @State private var dismissedRecoveryNoticeID: UUID?
    @State private var draggingID: UUID?
    @State private var dragOffset: CGFloat = 0
    @State private var rowHeights: [UUID: CGFloat] = [:]
    @State private var lastTargetIndex: Int?
    @State private var escapeMonitor: Any?
    @FocusState private var isInputFocused: Bool

    private static let reorderAnimation = Animation.spring(response: 0.35, dampingFraction: 0.78)

    var body: some View {
        GeometryReader { proxy in
            let shape = MorphingDockedShape(
                corner: panelManager.currentCorner,
                expansion: expansionProgress,
                floatingProgress: panelManager.isDragging ? 1 : 0,
                panelRadius: PanelMetrics.cornerRadius
            )

            ZStack(alignment: panelManager.currentCorner.alignment) {
                PanelGlassBackground(shape: shape)
                    .shadow(
                        color: FloatDoTheme.panelShadow(opacity: 0.5),
                        radius: PanelMetrics.shadowRadius,
                        y: 8
                    )
                    .allowsHitTesting(false)

                WindowDragZone()
                    .clipShape(shape)

                expandedLayer

                collapsedGlyph
            }
            .frame(
                width: proxy.size.width,
                height: proxy.size.height,
                alignment: panelManager.currentCorner.alignment
            )
            .clipShape(shape)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
        .animation(PanelMotion.stateAnimation, value: panelManager.isCollapsed)
        .animation(PanelMotion.stateAnimation, value: panelManager.currentCorner)
        .animation(PanelMotion.stateAnimation, value: panelManager.isDragging)
        .onDisappear {
            removeEscapeMonitor()
        }
    }

    private var expandedLayer: some View {
        expandedContent
            .opacity(expandedOpacity)
            .scaleEffect(expandedScale, anchor: panelManager.currentCorner.unitPoint)
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

            if sortedItems.isEmpty {
                emptyState
            } else {
                taskList
            }

            inputBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .liquidGlassContainer(spacing: 0)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("Tasks")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(FloatDoTheme.textPrimary)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(FloatDoTheme.tabActiveFill)
                )

            Spacer(minLength: 0)

            Button {
                // Future: create a new list. No-op for now.
            } label: {
                Image(systemName: "plus")
            }
            .floatDoGlassButton()
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 10)
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
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(sortedItems.enumerated()), id: \.element.id) { index, item in
                    TodoRowView(
                        item: item,
                        isDragging: draggingID == item.id,
                        isDragActive: draggingID != nil,
                        yOffset: visualOffset(for: index),
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
        }
        .frame(maxHeight: .infinity)
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
            .scaleEffect(collapsedScale, anchor: panelManager.currentCorner.unitPoint)
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
        let distance = PanelMotion.transitionDistance

        switch panelManager.currentCorner {
        case .topLeft:
            return CGSize(width: -distance, height: -distance)
        case .topRight:
            return CGSize(width: distance, height: -distance)
        case .bottomLeft:
            return CGSize(width: -distance, height: distance)
        case .bottomRight:
            return CGSize(width: distance, height: distance)
        }
    }

    private var sortedItems: [TodoItem] {
        store.items
    }

    private func targetIndex(from original: Int, offset: CGFloat) -> Int {
        guard !store.items.isEmpty else { return 0 }
        var idx = original
        var accumulated: CGFloat = 0
        if offset > 0 {
            for i in (original + 1)..<store.items.count {
                let h = rowHeights[store.items[i].id] ?? RowMetrics.estimatedHeight
                accumulated += h
                if offset > accumulated - h / 2 {
                    idx = i
                } else {
                    break
                }
            }
        } else if offset < 0 {
            for i in stride(from: original - 1, through: 0, by: -1) {
                let h = rowHeights[store.items[i].id] ?? RowMetrics.estimatedHeight
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

    private func visualOffset(for index: Int) -> CGFloat {
        guard let dragID = draggingID,
              let originalIdx = store.items.firstIndex(where: { $0.id == dragID }) else {
            return 0
        }
        if index == originalIdx {
            return dragOffset
        }
        let target = targetIndex(from: originalIdx, offset: dragOffset)
        if target == originalIdx { return 0 }

        let currentOrder = store.items.map(\.id)
        var newOrder = currentOrder
        let draggedID = newOrder.remove(at: originalIdx)
        newOrder.insert(draggedID, at: target)

        let rowID = currentOrder[index]
        guard let newIdx = newOrder.firstIndex(of: rowID) else { return 0 }

        return yPosition(for: newIdx, in: newOrder) - yPosition(for: index, in: currentOrder)
    }

    private func handleDragChanged(for id: UUID, translation: CGFloat) {
        if draggingID == nil {
            draggingID = id
            lastTargetIndex = store.items.firstIndex(where: { $0.id == id })
            fireHaptic(.levelChange)
            installEscapeMonitor()
        }
        dragOffset = translation
        guard let original = store.items.firstIndex(where: { $0.id == id }) else { return }
        let target = targetIndex(from: original, offset: translation)
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
        let original = store.items.firstIndex(where: { $0.id == id }) ?? 0
        let target = targetIndex(from: original, offset: translation)
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
