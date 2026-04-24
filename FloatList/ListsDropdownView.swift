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
    var onSetColor: (TodoList, ListIconColor?) -> Void
    var onReorder: (Int, Int) -> Void
    var onAutoFocusConsumed: () -> Void

    @State private var isEditing = false
    @State private var draftName = ""
    @State private var isTriggerHovering = false
    @State private var isTriggerPressed = false
    @State private var isShowingMenu = false
    @State private var isShowingIconPicker = false
    @State private var isShowingColorPicker = false
    @State private var heldPanelHover = false
    @State private var dragSession: ListDragSession?
    @State private var dragSettleTask: Task<Void, Never>?
    @State private var rowFrames: [UUID: CGRect] = [:]
    @State private var rowHeights: [UUID: CGFloat] = [:]
    @FocusState private var isEditorFocused: Bool
    @ObservedObject private var tweaks = LayoutTweaks.shared
    @EnvironmentObject private var panelManager: PanelManager
    @EnvironmentObject private var onboarding: OnboardingMode

    private static let reorderCoordinateSpace = ReorderCoordinateSpace.listsDropdown
    private static let reorderAnimation = Animation.spring(response: 0.28, dampingFraction: 0.86)
    private static let reorderStepAnimation = Animation.interactiveSpring(response: 0.22, dampingFraction: 0.9)
    private static let reorderSettleDelayNanoseconds: UInt64 = 170_000_000

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
        .popover(isPresented: $isShowingColorPicker, arrowEdge: .bottom) {
            if let list = selected, !isSpecialList(list) {
                ListColorPickerView(
                    selected: list.iconColor,
                    onPick: { color in
                        onSetColor(list, color)
                        isShowingColorPicker = false
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
        .onChange(of: isShowingColorPicker) { _, _ in syncPanelHoverHold() }
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
        let shouldHold = isShowingMenu || isShowingIconPicker || isShowingColorPicker || isEditing
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
                .foregroundStyle(list.iconColor?.color ?? FloatListTheme.textPrimary)
                .symbolRenderingMode(.monochrome)
                .contentTransition(.symbolEffect(.replace))
                .animation(.easeOut(duration: 0.2), value: list.icon)
                .animation(.easeOut(duration: 0.2), value: list.iconColor)

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
            guard onboarding.allowsListDropdownOpen else { return }
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
                .foregroundStyle(list.iconColor?.color ?? FloatListTheme.textPrimary)
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
                let isBeingDragged = draggingID == item.id
                listRow(for: item, current: current, userActionsEnabled: true)
                    .opacity(isBeingDragged ? 0 : 1)
                    .overlay {
                        if isBeingDragged {
                            listDragLandingIndicator()
                                .allowsHitTesting(false)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if onboarding.allowsNewListAction {
                DropdownActionRow(
                    title: "New list",
                    systemImage: "plus",
                    action: {
                        isShowingMenu = false
                        DispatchQueue.main.async { onCreate() }
                    }
                )
            }

            let showSpecialLists = onboarding.allowsListSelection
            if showSpecialLists {
                Divider()
                    .padding(.vertical, 4)

                ForEach(specialLists) { item in
                    listRow(for: item, current: current, userActionsEnabled: false)
                }
            }

            if current.id == trashList.id && onboarding.allowsEmptyTrash {
                Divider()
                    .padding(.vertical, 4)

                DropdownActionRow(
                    title: "Empty Trash",
                    systemImage: "trash",
                    role: .destructive,
                    action: {
                        isShowingMenu = false
                        onEmptyTrash()
                    }
                )
            }
        }
        .coordinateSpace(name: Self.reorderCoordinateSpace)
        .animation(Self.reorderStepAnimation, value: dragSession?.targetIndex)
        .overlay(alignment: .topLeading) {
            if let session = dragSession {
                dragOverlay(for: session, current: current)
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.reorderCoordinateSpace))
                .onChanged { value in
                    handleMenuDragChanged(start: value.startLocation, pointerY: value.location.y)
                }
                .onEnded { value in
                    handleMenuDragEnded(pointerY: value.location.y)
                }
        )
        .padding(6)
        .frame(minWidth: 200)
        .onPreferenceChange(RowFramePreferenceKey.self) { frames in
            // Don't refresh the drag target here — see ContentView for why.
            rowFrames.merge(frames) { _, new in new }
        }
        .onPreferenceChange(RowHeightPreferenceKey.self) { heights in
            rowHeights.merge(heights) { _, new in new }
        }
    }

    @ViewBuilder
    private func listRow(for item: TodoList, current: TodoList, userActionsEnabled: Bool) -> some View {
        DropdownListRow(
            list: item,
            isSelected: item.id == current.id,
            coordinateSpace: userActionsEnabled ? Self.reorderCoordinateSpace : "",
            onTap: {
                guard dragSession == nil else { return }
                guard onboarding.allowsListSelection else { return }
                isShowingMenu = false
                if item.id != current.id {
                    onSelect(item.id)
                }
            },
            actions: userActionsEnabled ? listRowActions(for: item, current: current) : nil
        )
    }

    private func listRowActions(for item: TodoList, current: TodoList) -> DropdownListRowActions? {
        let canRename = onboarding.allowsListManagement
        let canChangeIcon = onboarding.allowsListManagement
        let canChangeColor = onboarding.allowsListColorPicker
        let canDelete = onboarding.allowsDeleteList

        guard canRename || canChangeIcon || canChangeColor || canDelete else { return nil }

        return DropdownListRowActions(
            canRename: canRename,
            canChangeIcon: canChangeIcon,
            canChangeColor: canChangeColor,
            canDelete: canDelete,
            onRename: { triggerRename(item, current: current) },
            onChangeIcon: { triggerIconChange(item, current: current) },
            onChangeColor: { triggerColorChange(item, current: current) },
            onDelete: { triggerDelete(item) }
        )
    }

    private func triggerRename(_ list: TodoList, current: TodoList) {
        isShowingMenu = false
        if list.id != current.id {
            onSelect(list.id)
        }
        DispatchQueue.main.async { beginEdit(list) }
    }

    private func triggerIconChange(_ list: TodoList, current: TodoList) {
        isShowingMenu = false
        if list.id != current.id {
            onSelect(list.id)
        }
        DispatchQueue.main.async { isShowingIconPicker = true }
    }

    private func triggerColorChange(_ list: TodoList, current: TodoList) {
        isShowingMenu = false
        if list.id != current.id {
            onSelect(list.id)
        }
        DispatchQueue.main.async { isShowingColorPicker = true }
    }

    private func triggerDelete(_ list: TodoList) {
        isShowingMenu = false
        onDelete(list)
    }

    private func listDragLandingIndicator() -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(FloatListTheme.controlFillStrong.opacity(0.22))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(FloatListTheme.hairline.opacity(0.55), lineWidth: 1)
            )
            .shadow(color: FloatListTheme.panelShadow(opacity: 0.12), radius: 6, y: 2)
            .padding(.vertical, 2)
            .allowsHitTesting(false)
    }

    // MARK: - Drag reordering

    private func handleMenuDragChanged(start: CGPoint, pointerY: CGFloat) {
        guard lists.count > 1, onboarding.allowsListReorder else { return }

        if let session = dragSession {
            advanceDrag(for: session.list.id, pointerY: pointerY)
            return
        }

        guard let id = userListID(at: start) else { return }
        advanceDrag(for: id, pointerY: pointerY)
    }

    private func handleMenuDragEnded(pointerY: CGFloat) {
        guard let session = dragSession else { return }
        commitDrag(for: session.list.id, pointerY: pointerY)
    }

    private func advanceDrag(for id: UUID, pointerY: CGFloat) {
        let order = lists.map(\.id)

        if dragSession == nil {
            guard let originalIndex = order.firstIndex(of: id),
                  let frame = rowFrames[id] else { return }
            let height = rowHeights[id] ?? frame.height
            dragSettleTask?.cancel()
            dragSettleTask = nil
            dragSession = ListDragSession(
                list: lists[originalIndex],
                originalIndex: originalIndex,
                rowFrame: CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: height),
                remainingOrder: order.filter { $0 != id },
                pointerY: pointerY,
                targetIndex: originalIndex,
                lastDirection: .stationary
            )
            ReorderHaptics.fire(.levelChange)
            return
        }

        guard var session = dragSession, session.list.id == id else { return }
        advance(&session, toPointerY: pointerY)
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

    private func commitDrag(for id: UUID, pointerY: CGFloat) {
        guard var session = dragSession, session.list.id == id else { return }
        dragSettleTask?.cancel()
        dragSettleTask = nil

        advance(&session, toPointerY: pointerY)
        session.snapsToRowFrame = true

        let target = clampedStoreTarget(session.targetIndex)
        let origin = session.originalIndex

        withAnimation(Self.reorderAnimation) {
            dragSession = session
        }

        dragSettleTask = Task { @MainActor in
            defer { dragSettleTask = nil }
            try? await Task.sleep(nanoseconds: Self.reorderSettleDelayNanoseconds)
            guard dragSession?.list.id == id else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                if target != origin {
                    onReorder(origin, target)
                }
                dragSession = nil
            }
        }
    }

    private func cancelDrag() {
        dragSettleTask?.cancel()
        dragSettleTask = nil
        guard dragSession != nil else { return }
        withAnimation(Self.reorderAnimation) {
            dragSession = nil
        }
    }

    private func advance(_ session: inout ListDragSession, toPointerY pointerY: CGFloat) {
        let delta = pointerY - session.pointerY
        session.lastDirection = ReorderDragDirection(delta: delta, fallback: session.lastDirection)
        session.pointerY = pointerY
        session.targetIndex = resolvedTargetIndex(for: session)
    }

    private func resolvedTargetIndex(for session: ListDragSession) -> Int {
        let frames = session.remainingOrder.map { rowFrames[$0] ?? .zero }
        return min(
            max(
                ReorderInteractionMath.targetIndex(
                    for: session.pointerY,
                    frames: frames,
                    direction: session.lastDirection
                ),
                0
            ),
            session.remainingOrder.count
        )
    }

    private func applyDragSessionUpdate(_ session: ListDragSession, triggerHaptic: Bool) {
        guard dragSession != session else { return }
        let previousTarget = dragSession?.targetIndex
        dragSession = session
        if previousTarget != session.targetIndex && triggerHaptic {
            ReorderHaptics.fire(.alignment)
        }
    }

    private func dragOverlay(for session: ListDragSession, current: TodoList) -> some View {
        let y: CGFloat
        if session.snapsToRowFrame, let frame = rowFrames[session.list.id] {
            y = frame.midY
        } else {
            y = session.pointerY
        }
        return DropdownListDragPreview(list: session.list, isSelected: session.list.id == current.id)
            .frame(width: session.rowFrame.width, height: session.rowFrame.height)
            .position(x: session.rowFrame.midX, y: y)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func clampedStoreTarget(_ targetIndex: Int) -> Int {
        guard !lists.isEmpty else { return 0 }
        return min(max(targetIndex, 0), lists.count - 1)
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

/// Pointer-Y-tracked drag session. Mirrors `ContentView.DragSession`; see
/// that type for the model's invariants.
private struct ListDragSession: Equatable {
    let list: TodoList
    let originalIndex: Int
    let rowFrame: CGRect
    let remainingOrder: [UUID]
    var pointerY: CGFloat
    var targetIndex: Int
    var lastDirection: ReorderDragDirection
    /// When true, the overlay reads its Y from `rowFrames[list.id]` instead
    /// of `pointerY`. Set at drop so the overlay rides the row's reflow
    /// animation into its new slot.
    var snapsToRowFrame: Bool = false

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.list.id == rhs.list.id
            && lhs.pointerY == rhs.pointerY
            && lhs.targetIndex == rhs.targetIndex
            && lhs.lastDirection == rhs.lastDirection
            && lhs.snapsToRowFrame == rhs.snapsToRowFrame
    }
}

// MARK: - Rows

/// Floating "lifted card" shown under the cursor while reordering a list in
/// the dropdown. Styled to match `TodoRowDragPreview` in the main task list so
/// both reorder gestures feel the same.
private struct DropdownListDragPreview: View {
    let list: TodoList
    let isSelected: Bool

    @ObservedObject private var tweaks = LayoutTweaks.shared

    var body: some View {
        DropdownListRow(
            list: list,
            isSelected: isSelected,
            coordinateSpace: "",
            onTap: {}
        )
        .background(
            RoundedRectangle(cornerRadius: tweaks.rowCornerRadius, style: .continuous)
                .fill(FloatListTheme.dragPreviewFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: tweaks.rowCornerRadius, style: .continuous)
                .stroke(FloatListTheme.hairline.opacity(0.38), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: tweaks.rowCornerRadius, style: .continuous))
        .compositingGroup()
        .shadow(color: FloatListTheme.panelShadow(opacity: 0.2), radius: 18, y: 10)
    }
}

struct DropdownListRowActions {
    var canRename: Bool
    var canChangeIcon: Bool
    var canChangeColor: Bool
    var canDelete: Bool
    var onRename: () -> Void
    var onChangeIcon: () -> Void
    var onChangeColor: () -> Void
    var onDelete: () -> Void
}

private struct DropdownListRow: View {
    let list: TodoList
    let isSelected: Bool
    var coordinateSpace: String = ""
    var onTap: () -> Void
    var actions: DropdownListRowActions? = nil

    @State private var isHovering = false
    @State private var isPressed = false
    @State private var isShowingActions = false
    @ObservedObject private var tweaks = LayoutTweaks.shared

    var body: some View {
        rowContent
            .background(framePreference)
            .overlay(rightClickOverlay)
            .popover(isPresented: $isShowingActions, arrowEdge: .leading) {
                if let actions {
                    ListRowActionsMenu(actions: actions) {
                        isShowingActions = false
                    }
                }
            }
    }

    @ViewBuilder
    private var rightClickOverlay: some View {
        if actions != nil {
            RightClickCatcher {
                isShowingActions = true
            }
            .allowsHitTesting(true)
        }
    }

    @ViewBuilder
    private var rowContent: some View {
        HStack(spacing: tweaks.pillSpacing + 4) {
            Image(systemName: list.icon)
                .symbolVariant(.fill)
                .font(.system(size: tweaks.listIconSize, weight: .medium))
                .foregroundStyle(list.iconColor?.color ?? FloatListTheme.textPrimary)
                .symbolRenderingMode(.monochrome)
                .frame(width: 20, alignment: .center)

            Text(list.name)
                .font(.system(size: tweaks.bodyTextSize, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(FloatListTheme.textPrimary)
                .lineLimit(1)

            Spacer(minLength: 8)

            trailingAccessory
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
    private var trailingAccessory: some View {
        if actions != nil && isHovering {
            ellipsisMenu
        } else if isSelected {
            Image(systemName: "checkmark")
                .font(.system(size: max(tweaks.secondaryTextSize - 1, 9), weight: .semibold))
                .foregroundStyle(FloatListTheme.textSecondary)
        }
    }

    @ViewBuilder
    private var ellipsisMenu: some View {
        Button {
            isShowingActions = true
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: max(tweaks.secondaryTextSize - 1, 10), weight: .semibold))
                .foregroundStyle(FloatListTheme.textSecondary)
                .frame(width: 20, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerCursor(.pointingHand)
        .accessibilityLabel("More actions")
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

private struct ListRowActionsMenu: View {
    let actions: DropdownListRowActions
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if actions.canRename {
                DropdownActionRow(
                    title: "Rename",
                    systemImage: "pencil",
                    action: {
                        onDismiss()
                        DispatchQueue.main.async { actions.onRename() }
                    }
                )
            }
            if actions.canChangeIcon {
                DropdownActionRow(
                    title: "Change icon",
                    systemImage: "app.dashed",
                    action: {
                        onDismiss()
                        DispatchQueue.main.async { actions.onChangeIcon() }
                    }
                )
            }
            if actions.canChangeColor {
                DropdownActionRow(
                    title: "Change color",
                    systemImage: "paintbrush",
                    action: {
                        onDismiss()
                        DispatchQueue.main.async { actions.onChangeColor() }
                    }
                )
            }
            if actions.canDelete {
                if actions.canRename || actions.canChangeIcon || actions.canChangeColor {
                    Divider()
                        .padding(.vertical, 4)
                }
                DropdownActionRow(
                    title: "Delete list",
                    systemImage: "trash",
                    role: .destructive,
                    action: {
                        onDismiss()
                        DispatchQueue.main.async { actions.onDelete() }
                    }
                )
            }
        }
        .padding(6)
        .frame(minWidth: 180)
    }
}

private struct RightClickCatcher: NSViewRepresentable {
    var onRightClick: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = CatcherView()
        view.onRightClick = onRightClick
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? CatcherView)?.onRightClick = onRightClick
    }

    final class CatcherView: NSView {
        var onRightClick: (() -> Void)?

        override func rightMouseDown(with event: NSEvent) {
            onRightClick?()
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent else { return nil }
            switch event.type {
            case .rightMouseDown, .rightMouseUp:
                return super.hitTest(point)
            default:
                return nil
            }
        }
    }
}
