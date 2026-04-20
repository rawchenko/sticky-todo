import SwiftUI
import AppKit

struct ListsDropdownView: View {
    let lists: [TodoList]
    let selectedID: UUID?
    let autoFocusRenameID: UUID?
    var onSelect: (UUID) -> Void
    var onCreate: () -> Void
    var onRename: (TodoList, String) -> Void
    var onDelete: (TodoList) -> Void
    var onSetIcon: (TodoList, String) -> Void
    var onAutoFocusConsumed: () -> Void

    @State private var isEditing = false
    @State private var draftName = ""
    @State private var isTriggerHovering = false
    @State private var isTriggerPressed = false
    @State private var isShowingMenu = false
    @State private var isShowingIconPicker = false
    @State private var heldPanelHover = false
    @FocusState private var isEditorFocused: Bool
    @ObservedObject private var tweaks = LayoutTweaks.shared
    @EnvironmentObject private var panelManager: PanelManager

    private var selected: TodoList? {
        guard let id = selectedID else { return nil }
        return lists.first(where: { $0.id == id })
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
            if let list = selected {
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
        .onChange(of: isShowingMenu) { _, _ in syncPanelHoverHold() }
        .onChange(of: isShowingIconPicker) { _, _ in syncPanelHoverHold() }
        .onChange(of: isEditing) { _, _ in syncPanelHoverHold() }
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
                .foregroundStyle(FloatDoTheme.textPrimary)
                .symbolRenderingMode(.hierarchical)
                .contentTransition(.symbolEffect(.replace))
                .animation(.easeOut(duration: 0.2), value: list.icon)

            Text(list.name)
                .font(.system(size: tweaks.bodyTextSize, weight: .medium))
                .foregroundStyle(FloatDoTheme.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)

            Image(systemName: "chevron.down")
                .font(.system(size: max(tweaks.secondaryTextSize - 2, 8), weight: .semibold))
                .foregroundStyle(FloatDoTheme.textSecondary)
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
        if isShowingMenu { return FloatDoTheme.controlFillStrong }
        if isTriggerHovering { return FloatDoTheme.rowHover }
        return FloatDoTheme.tabActiveFill
    }

    // MARK: - Rename

    @ViewBuilder
    private func renameTrigger(for list: TodoList) -> some View {
        HStack(spacing: tweaks.pillSpacing) {
            Image(systemName: list.icon)
                .symbolVariant(.fill)
                .font(.system(size: tweaks.listIconSize, weight: .medium))
                .foregroundStyle(FloatDoTheme.textPrimary)
                .symbolRenderingMode(.hierarchical)

            TextField("List name", text: $draftName)
                .textFieldStyle(.plain)
                .font(.system(size: tweaks.bodyTextSize, weight: .medium))
                .foregroundStyle(FloatDoTheme.textPrimary)
                .focused($isEditorFocused)
                .onSubmit { commitEdit(list) }
                .onExitCommand(perform: cancelEdit)
                .frame(minWidth: 80, idealWidth: 120)
        }
        .padding(.horizontal, tweaks.pillHorizontalPadding)
        .padding(.vertical, tweaks.pillVerticalPadding)
        .background(
            RoundedRectangle(cornerRadius: tweaks.pillCornerRadius, style: .continuous)
                .fill(FloatDoTheme.tabActiveFill)
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
            ForEach(lists) { item in
                DropdownListRow(
                    list: item,
                    isSelected: item.id == current.id,
                    onTap: {
                        isShowingMenu = false
                        if item.id != current.id {
                            onSelect(item.id)
                        }
                    }
                )
            }

            DropdownActionRow(
                title: "New list",
                systemImage: "plus",
                action: {
                    isShowingMenu = false
                    DispatchQueue.main.async { onCreate() }
                }
            )

            Divider()
                .padding(.vertical, 4)

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
        .padding(6)
        .frame(minWidth: 200)
    }

    // MARK: - Edit helpers

    private func beginEdit(_ list: TodoList) {
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
}

// MARK: - Rows

private struct DropdownListRow: View {
    let list: TodoList
    let isSelected: Bool
    var onTap: () -> Void

    @State private var isHovering = false
    @State private var isPressed = false
    @ObservedObject private var tweaks = LayoutTweaks.shared

    var body: some View {
        HStack(spacing: tweaks.pillSpacing + 4) {
            Image(systemName: list.icon)
                .symbolVariant(.fill)
                .font(.system(size: tweaks.listIconSize, weight: .medium))
                .foregroundStyle(FloatDoTheme.textPrimary)
                .symbolRenderingMode(.hierarchical)
                .frame(width: 20, alignment: .center)

            Text(list.name)
                .font(.system(size: tweaks.bodyTextSize, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(FloatDoTheme.textPrimary)
                .lineLimit(1)

            Spacer(minLength: 8)

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: max(tweaks.secondaryTextSize - 1, 9), weight: .semibold))
                    .foregroundStyle(FloatDoTheme.textSecondary)
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

    private var rowBackground: Color {
        if isSelected { return FloatDoTheme.tabActiveFill }
        if isHovering { return FloatDoTheme.rowHover }
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
                .fill(isHovering ? FloatDoTheme.rowHover : Color.clear)
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
        role == .destructive ? FloatDoTheme.destructive : FloatDoTheme.textPrimary
    }
}
