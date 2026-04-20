import SwiftUI
import AppKit

struct ListsDropdownView: View {
    let lists: [TodoList]
    let completedList: TodoList
    let trashList: TodoList
    let selectedID: UUID?
    let autoFocusRenameID: UUID?
    var onSelect: (UUID) -> Void
    var onCreate: () -> Void
    var onRename: (TodoList, String) -> Void
    var onDelete: (TodoList) -> Void
    var onEmptyTrash: () -> Void
    var onSetIcon: (TodoList, String) -> Void
    var onReorder: (Int, Int) -> Void
    var onAutoFocusConsumed: () -> Void

    @State private var isEditing = false
    @State private var draftName = ""
    @State private var isTriggerHovering = false
    @State private var isTriggerPressed = false
    @State private var isShowingMenu = false
    @State private var isShowingIconPicker = false
    @State private var heldPanelHover = false
    @State private var dragSession: ListDragSession?
    @State private var rowFrames: [UUID: CGRect] = [:]
    @State private var rowHeights: [UUID: CGFloat] = [:]
    @FocusState private var isEditorFocused: Bool
    @ObservedObject private var tweaks = LayoutTweaks.shared
    @EnvironmentObject private var panelManager: PanelManager

    private static let reorderCoordinateSpace = "listsMenu"
    private static let reorderAnimation = Animation.spring(response: 0.28, dampingFraction: 0.86)
    private static let reorderStepAnimation = Animation.interactiveSpring(response: 0.22, dampingFraction: 0.9)

    private var allLists: [TodoList] {
        lists + [completedList, trashList]
    }

    private var specialLists: [TodoList] {
        [completedList, trashList]
    }

    private var selected: TodoList? {
        guard let id = selectedID else { return allLists.first }
        return allLists.first(where: { $0.id == id }) ?? allLists.first
    }

    private var isSpecialSelected: Bool {
        guard let id = selected?.id else { return false }
        return id == completedList.id || id == trashList.id
    }

    private var draggingID: UUID? {
        dragSession?.list.id
    }

    private var projectedLists: [TodoList] {
        guard let session = dragSession else { return lists }
        var items = lists
        guard let currentIndex = items.firstIndex(where: { $0.id == session.list.id }) else {
            return items
        }
        let moving = items.remove(at: currentIndex)
        let target = min(max(session.targetIndex, 0), items.count)
        items.insert(moving, at: target)
        return items
    }

    var body: some View {
        Group {
            if let list = selected {
                if isEditing {
                    renameTrigger(for: list)
                } else {
                    pillTrigger(for: list)
                }
            } else {
                EmptyView()
            }
        }
        .popover(isPresented: $isShowingMenu, arrowEdge: .bottom) {
            if let list = selected {
                menuContent(for: list)
            }
        }
        .popover(isPresented: $isShowingIconPicker, arrowEdge: .bottom) {
            if let list = selected, !isSpecialList(list) {
                ListIconPickerView(
                    selected: list.icon,
                    onPick: { symbol in
                        onSetIcon(list, symbol)
                        isShowingIconPicker = false
                    }
                )
            }
        }
        .onAppear {
            if let id = autoFocusRenameID, let list = lists.first(where: { $0.id == id }) {
                beginEdit(list)
                onAutoFocusConsumed()
            }
        }
        .onChange(of: autoFocusRenameID) { _, id in
            guard let id, let list = lists.first(where: { $0.id == id }) else { return }
            beginEdit(list)
            onAutoFocusConsumed()
        }
        .onChange(of: isShowingMenu) { _, showing in
            syncPanelHoverHold()
            if !showing { cancelDrag() }
        }
        .onChange(of: isShowingIconPicker) { _, _ in syncPanelHoverHold() }
        .onChange(of: isEditing) { _, _ in syncPanelHoverHold() }
        .onChange(of: lists.map(\.id)) { _, ids in
            let live = Set(ids)
            rowFrames = rowFrames.filter { live.contains($0.key) }
            rowHeights = rowHeights.filter { live.contains($0.key) }
            if let id = dragSession?.list.id, !live.contains(id) {
                cancelDrag()
            }
        }
        .onDisappear { releasePanelHoverHoldIfNeeded() }
    }

    private func syncPanelHoverHold() {
        let shouldHold = isShowingMenu || isShowingIconPicker || isEditing
        guard shouldHold != heldPanelHover else { return }
        heldPanelHover = shouldHold
        if shouldHold {
            panelManager.pushHoverHold()
        } else {
            panelManager.popHoverHold()
        }
    }

    private func releasePanelHoverHoldIfNeeded() {
        if heldPanelHover {
            heldPanelHover = false
            panelManager.popHoverHold()
        }
    }

    // MARK: - Trigger

    @ViewBuilder
    private func pillTrigger(for list: TodoList) -> some View {
        HStack(spacing: tweaks.pillSpacing) {
            Image(systemName: list.icon)
                .symbolVariant(.fill)
                .font(.system(size: tweaks.listIconSize, weight: .medium))
                .foregroundStyle(FloatListTheme.textPrimary)
                .symbolRenderingMode(.monochrome)
                .contentTransition(.symbolEffect(.replace))
                .animation(.easeOut(duration: 0.2), value: list.icon)

            Text(list.name)
                .font(.system(size: tweaks.bodyTextSize, weight: .medium))
                .foregroundStyle(FloatListTheme.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)

            Image(systemName: "chevron.down")
                .font(.system(size: max(tweaks.secondaryTextSize - 2, 8), weight: .semibold))
                .foregroundStyle(FloatListTheme.textSecondary)
                .rotationEffect(.degrees(isShowingMenu ? 180 : 0))
                .animation(.easeOut(duration: 0.2), value: isShowingMenu)
                .padding(.leading, 2)
        }
        .padding(.horizontal, tweaks.pillHorizontalPadding)
        .padding(.vertical, tweaks.pillVerticalPadding)
        .background(
            RoundedRectangle(cornerRadius: tweaks.pillCornerRadius, style: .continuous)
                .fill(triggerBackground)
                .animation(.easeOut(duration: 0.15), value: isTriggerHovering)
                .animation(.easeOut(duration: 0.15), value: isShowingMenu)
        )
        .scaleEffect(isTriggerPressed ? 0.96 : 1.0)
        .animation(.spring(response: 0.22, dampingFraction: 0.7), value: isTriggerPressed)
        .contentShape(RoundedRectangle(cornerRadius: tweaks.pillCornerRadius, style: .continuous))
        .background(WindowDragBlocker())
        .pointerCursor(.pointingHand)
        .onHover { hovering in
            isTriggerHovering = hovering
            if !hovering { isTriggerPressed = false }
        }
        .onLongPressGesture(minimumDuration: .infinity, maximumDistance: 6, perform: {}) { pressing in
            isTriggerPressed = pressing
        }
        .onTapGesture {
            isShowingMenu.toggle()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(list.name)
        .accessibilityAddTraits([.isButton])
        .accessibilityHint("Tap to switch lists.")
    }

    private var triggerBackground: Color {
        if isSpecialSelected && !isShowingMenu && !isTriggerHovering {
            return FloatListTheme.controlFill
        }
        if isShowingMenu { return FloatListTheme.controlFillStrong }
        if isTriggerHovering { return FloatListTheme.rowHover }
        return FloatListTheme.tabActiveFill
    }

    // MARK: - Rename

    @ViewBuilder
    private func renameTrigger(for list: TodoList) -> some View {
        HStack(spacing: tweaks.pillSpacing) {
            Image(systemName: list.icon)
                .symbolVariant(.fill)
                .font(.system(size: tweaks.listIconSize, weight: .medium))
                .foregroundStyle(FloatListTheme.textPrimary)
                .symbolRenderingMode(.monochrome)

            TextField("List name", text: $draftName)
                .textFieldStyle(.plain)
                .font(.system(size: tweaks.bodyTextSize, weight: .medium))
                .foregroundStyle(FloatListTheme.textPrimary)
                .focused($isEditorFocused)
                .onSubmit { commitEdit(list) }
                .onExitCommand(perform: cancelEdit)
                .frame(minWidth: 80, idealWidth: 120)
        }
        .padding(.horizontal, tweaks.pillHorizontalPadding)
        .padding(.vertical, tweaks.pillVerticalPadding)
        .background(
            RoundedRectangle(cornerRadius: tweaks.pillCornerRadius, style: .continuous)
                .fill(FloatListTheme.tabActiveFill)
        )
        .background(WindowDragBlocker())
        .pointerCursor(.iBeam)
        .onChange(of: isEditorFocused) { _, focused in
            if !focused && isEditing {
                commitEdit(list)
            }
        }
    }

    // MARK: - Menu content

    @ViewBuilder
    private func menuContent(for current: TodoList) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(projectedLists) { item in
                if draggingID == item.id, let session = dragSession {
                    Color.clear
                        .frame(height: session.frozenHeight)
                        .frame(maxWidth: .infinity)
                        .overlay { listDragLandingIndicator() }
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else {
                    listRow(for: item, current: current)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            if !lists.isEmpty {
                Divider()
                    .padding(.vertical, 4)
            }

            ForEach(specialLists) { item in
                DropdownListRow(
                    list: item,
                    isSelected: item.id == current.id,
                    coordinateSpace: "",
                    onTap: {
                        isShowingMenu = false
                        if item.id != current.id {
                            onSelect(item.id)
                        }
                    }
                )
            }

            Divider()
                .padding(.vertical, 4)

            DropdownActionRow(
                title: "New list",
                systemImage: "folder.fill.badge.plus",
                action: {
                    isShowingMenu = false
                    DispatchQueue.main.async { onCreate() }
                }
            )

            if current.id == trashList.id {
                DropdownActionRow(
                    title: "Empty Trash",
                    systemImage: "trash",
                    role: .destructive,
                    action: {
                        isShowingMenu = false
                        onEmptyTrash()
                    }
                )
            } else if !isSpecialList(current) {
                DropdownActionRow(
                    title: "Rename",
                    systemImage: "pencil",
                    action: {
                        isShowingMenu = false
                        DispatchQueue.main.async { beginEdit(current) }
                    }
                )
                DropdownActionRow(
                    title: "Change icon",
                    systemImage: "square.grid.2x2",
                    action: {
                        isShowingMenu = false
                        DispatchQueue.main.async { isShowingIconPicker = true }
                    }
                )
                DropdownActionRow(
                    title: "Delete list",
                    systemImage: "trash",
                    role: .destructive,
                    action: {
                        isShowingMenu = false
                        onDelete(current)
                    }
                )
            }
        }
        .coordinateSpace(name: Self.reorderCoordinateSpace)
        .overlay(alignment: .topLeading) {
            if let session = dragSession {
                DropdownListRow(
                    list: session.list,
                    isSelected: session.list.id == current.id,
                    coordinateSpace: "",
                    onTap: {}
                )
                .frame(width: session.initialFrame.width, height: session.frozenHeight)
                .offset(
                    x: session.initialFrame.minX,
                    y: session.initialFrame.minY + session.gestureTranslation
                )
                .shadow(color: Color.black.opacity(0.22), radius: 10, y: 4)
                .allowsHitTesting(false)
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.reorderCoordinateSpace))
                .onChanged { value in
                    handleMenuDragChanged(start: value.startLocation, translation: value.translation.height)
                }
                .onEnded { value in
                    handleMenuDragEnded(start: value.startLocation, translation: value.translation.height)
                }
        )
        .padding(6)
        .frame(minWidth: 200)
        .onPreferenceChange(RowFramePreferenceKey.self) { frames in
            rowFrames.merge(frames) { _, new in new }
            refreshDragSessionTarget()
        }
        .onPreferenceChange(RowHeightPreferenceKey.self) { heights in
            rowHeights.merge(heights) { _, new in new }
        }
        .animation(Self.reorderStepAnimation, value: dragSession?.targetIndex)
    }

    @ViewBuilder
    private func listRow(for item: TodoList, current: TodoList) -> some View {
        DropdownListRow(
            list: item,
            isSelected: item.id == current.id,
            coordinateSpace: Self.reorderCoordinateSpace,
            onTap: {
                guard dragSession == nil else { return }
                isShowingMenu = false
                if item.id != current.id {
                    onSelect(item.id)
                }
            }
        )
    }

    private func listDragLandingIndicator() -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(FloatListTheme.controlFillStrong.opacity(0.14))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(FloatListTheme.hairline.opacity(0.35), lineWidth: 1)
            )
            .shadow(color: FloatListTheme.panelShadow(opacity: 0.08), radius: 4, y: 1)
            .padding(.vertical, 2)
            .allowsHitTesting(false)
    }

    // MARK: - Drag

    private func handleMenuDragChanged(start: CGPoint, translation: CGFloat) {
        guard lists.count > 1 else { return }

        if let session = dragSession {
            updateDrag(for: session.list.id, translation: translation)
            return
        }

        guard let id = userListID(at: start) else { return }
        updateDrag(for: id, translation: translation)
    }

    private func handleMenuDragEnded(start: CGPoint, translation: CGFloat) {
        guard let session = dragSession else { return }
        commitDrag(for: session.list.id, translation: translation)
    }

    private func updateDrag(for id: UUID, translation: CGFloat) {
        let order = lists.map(\.id)
        guard beginDragSessionIfNeeded(for: id, translation: translation, order: order) else { return }

        guard var session = dragSession, session.list.id == id else { return }
        session = updatedDragSession(session, translation: translation, in: order)
        applyDragSessionUpdate(session, triggerHaptic: true)
    }

    private func userListID(at point: CGPoint) -> UUID? {
        for list in lists {
            if let frame = rowFrames[list.id], frame.contains(point) {
                return list.id
            }
        }
        return nil
    }

    private func commitDrag(for id: UUID, translation: CGFloat) {
        guard let session = dragSession, session.list.id == id else { return }

        let order = lists.map(\.id)
        let updated = updatedDragSession(session, translation: translation, in: order)
        let target = clampedStoreTarget(updated.targetIndex)
        let origin = updated.originalIndex

        withAnimation(Self.reorderAnimation) {
            if target != origin {
                onReorder(origin, target)
            }
            dragSession = nil
        }
    }

    private func cancelDrag() {
        guard dragSession != nil else { return }
        withAnimation(Self.reorderAnimation) {
            dragSession = nil
        }
    }

    private func refreshDragSessionTarget() {
        guard var session = dragSession else { return }
        let order = lists.map(\.id)
        guard order.contains(session.list.id) else {
            cancelDrag()
            return
        }
        session = updatedDragSession(session, in: order)
        applyDragSessionUpdate(session, triggerHaptic: true)
    }

    private func applyDragSessionUpdate(_ session: ListDragSession, triggerHaptic: Bool) {
        let previousTarget = dragSession?.targetIndex
        dragSession = session
        if previousTarget != session.targetIndex && triggerHaptic {
            fireHaptic(.alignment)
        }
    }

    private func beginDragSessionIfNeeded(
        for id: UUID,
        translation: CGFloat,
        order: [UUID]
    ) -> Bool {
        if dragSession != nil { return true }

        guard let originalIndex = order.firstIndex(of: id),
              let initialFrame = rowFrames[id]
        else { return false }

        let height = rowHeights[id] ?? initialFrame.height
        let list = lists[originalIndex]

        dragSession = ListDragSession(
            list: list,
            originalIndex: originalIndex,
            initialFrame: initialFrame,
            frozenHeight: height,
            gestureTranslation: translation,
            lastCompositeTranslation: translation,
            dragDirection: .stationary,
            targetIndex: originalIndex
        )
        fireHaptic(.levelChange)
        return true
    }

    private func updatedDragSession(
        _ session: ListDragSession,
        translation: CGFloat? = nil,
        in order: [UUID]
    ) -> ListDragSession {
        var updated = session
        let nextTranslation = translation ?? session.gestureTranslation
        let delta = nextTranslation - session.lastCompositeTranslation
        updated.dragDirection = ReorderDragDirection(delta: delta, fallback: session.dragDirection)
        updated.gestureTranslation = nextTranslation
        updated.lastCompositeTranslation = nextTranslation
        updated.targetIndex = resolvedTargetIndex(for: updated, in: order)
        return updated
    }

    private func resolvedTargetIndex(for session: ListDragSession, in order: [UUID]) -> Int {
        let draggingID = session.list.id
        let overlayMidY = session.overlayMidY
        let remaining = order.filter { $0 != draggingID }
        let frames = remaining.map { id -> CGRect in
            rowFrames[id] ?? .zero
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

    private func clampedStoreTarget(_ targetIndex: Int) -> Int {
        guard !lists.isEmpty else { return 0 }
        return min(max(targetIndex, 0), lists.count - 1)
    }

    private func fireHaptic(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .default)
    }

    // MARK: - Edit helpers

    private func beginEdit(_ list: TodoList) {
        guard !isSpecialList(list) else { return }
        draftName = list.name
        isEditing = true
        DispatchQueue.main.async {
            isEditorFocused = true
        }
    }

    private func commitEdit(_ list: TodoList) {
        guard isEditing else { return }
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && trimmed != list.name {
            onRename(list, trimmed)
        }
        isEditing = false
        isEditorFocused = false
    }

    private func cancelEdit() {
        isEditing = false
        isEditorFocused = false
    }

    private func isSpecialList(_ list: TodoList) -> Bool {
        list.id == completedList.id || list.id == trashList.id
    }
}

private struct ListDragSession {
    let list: TodoList
    let originalIndex: Int
    let initialFrame: CGRect
    let frozenHeight: CGFloat
    var gestureTranslation: CGFloat
    var lastCompositeTranslation: CGFloat
    var dragDirection: ReorderDragDirection
    var targetIndex: Int

    var overlayMidY: CGFloat {
        initialFrame.midY + gestureTranslation
    }
}

// MARK: - Rows

private struct DropdownListRow: View {
    let list: TodoList
    let isSelected: Bool
    var coordinateSpace: String = ""
    var onTap: () -> Void

    @State private var isHovering = false
    @State private var isPressed = false
    @ObservedObject private var tweaks = LayoutTweaks.shared

    var body: some View {
        rowContent
            .background(framePreference)
    }

    @ViewBuilder
    private var rowContent: some View {
        HStack(spacing: tweaks.pillSpacing + 4) {
            Image(systemName: list.icon)
                .symbolVariant(.fill)
                .font(.system(size: tweaks.listIconSize, weight: .medium))
                .foregroundStyle(FloatListTheme.textPrimary)
                .symbolRenderingMode(.monochrome)
                .frame(width: 20, alignment: .center)

            Text(list.name)
                .font(.system(size: tweaks.bodyTextSize, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(FloatListTheme.textPrimary)
                .lineLimit(1)

            Spacer(minLength: 8)

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: max(tweaks.secondaryTextSize - 1, 9), weight: .semibold))
                    .foregroundStyle(FloatListTheme.textSecondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(rowBackground)
                .animation(.easeOut(duration: 0.12), value: isHovering)
                .animation(.easeOut(duration: 0.12), value: isSelected)
        )
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.spring(response: 0.22, dampingFraction: 0.7), value: isPressed)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { hovering in
            isHovering = hovering
            if !hovering { isPressed = false }
        }
        .onLongPressGesture(minimumDuration: .infinity, maximumDistance: 6, perform: {}) { pressing in
            isPressed = pressing
        }
        .onTapGesture(perform: onTap)
        .pointerCursor(.pointingHand)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(list.name)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private var framePreference: some View {
        if coordinateSpace.isEmpty {
            Color.clear
        } else {
            GeometryReader { geo in
                Color.clear
                    .preference(
                        key: RowFramePreferenceKey.self,
                        value: [list.id: geo.frame(in: .named(coordinateSpace))]
                    )
                    .preference(
                        key: RowHeightPreferenceKey.self,
                        value: [list.id: geo.size.height]
                    )
            }
        }
    }

    private var rowBackground: Color {
        if isSelected { return FloatListTheme.tabActiveFill }
        if isHovering { return FloatListTheme.rowHover }
        return .clear
    }
}

private struct DropdownActionRow: View {
    let title: String
    let systemImage: String
    var role: ButtonRole? = nil
    var action: () -> Void

    @State private var isHovering = false
    @State private var isPressed = false
    @ObservedObject private var tweaks = LayoutTweaks.shared

    var body: some View {
        HStack(spacing: tweaks.pillSpacing + 4) {
            Image(systemName: systemImage)
                .font(.system(size: tweaks.actionIconSize, weight: .medium))
                .foregroundStyle(foreground)
                .frame(width: 20, alignment: .center)

            Text(title)
                .font(.system(size: tweaks.bodyTextSize))
                .foregroundStyle(foreground)

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovering ? FloatListTheme.rowHover : Color.clear)
                .animation(.easeOut(duration: 0.12), value: isHovering)
        )
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.spring(response: 0.22, dampingFraction: 0.7), value: isPressed)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { hovering in
            isHovering = hovering
            if !hovering { isPressed = false }
        }
        .onLongPressGesture(minimumDuration: .infinity, maximumDistance: 6, perform: {}) { pressing in
            isPressed = pressing
        }
        .onTapGesture(perform: action)
        .pointerCursor(.pointingHand)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
    }

    private var foreground: Color {
        role == .destructive ? FloatListTheme.destructive : FloatListTheme.textPrimary
    }
}
