import SwiftUI
import AppKit

private enum PillMotion {
    static let selection = Animation.spring(response: 0.36, dampingFraction: 0.82)
    static let hover = Animation.easeOut(duration: 0.18)
    static let press = Animation.spring(response: 0.22, dampingFraction: 0.70)
    static let iconSwap = Animation.spring(response: 0.38, dampingFraction: 0.68)
    static let drag = Animation.spring(response: 0.30, dampingFraction: 0.80)
}

struct ListWidthPreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGFloat] = [:]
    static func reduce(value: inout [UUID: CGFloat], nextValue: () -> [UUID: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}

struct ListPillView: View {
    let list: TodoList
    let isSelected: Bool
    let autoFocusOnAppear: Bool
    var isDragging: Bool = false
    var isDragActive: Bool = false
    var xOffset: CGFloat = 0
    var onSelect: () -> Void
    var onRename: (String) -> Void
    var onDelete: () -> Void
    var onSetIcon: (String) -> Void = { _ in }
    var onDragChanged: (CGFloat) -> Void = { _ in }
    var onDragEnded: (CGFloat) -> Void = { _ in }
    var onAutoFocusConsumed: () -> Void = {}

    @State private var isEditing = false
    @State private var draftName = ""
    @State private var isHovering = false
    @State private var isPressed = false
    @State private var isShowingIconPicker = false
    @State private var didPushCursor = false
    @State private var didPushHoverCursor = false
    @FocusState private var isEditorFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(list.icon)
                .font(.system(size: 14))
                .contentTransition(.opacity)
                .animation(PillMotion.iconSwap, value: list.icon)
                .scaleEffect(iconScale)
                .animation(PillMotion.selection, value: isSelected)
                .animation(PillMotion.hover, value: isHovering)

            if isEditing {
                TextField("List name", text: $draftName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(FloatDoTheme.textPrimary)
                    .focused($isEditorFocused)
                    .onSubmit(commitEdit)
                    .onExitCommand(perform: cancelEdit)
                    .frame(minWidth: 40)
                    .fixedSize()
            } else if isSelected {
                Text(list.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(FloatDoTheme.textPrimary)
                    .lineLimit(1)
                    .fixedSize()
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.82, anchor: .leading)),
                            removal: .opacity.combined(with: .scale(scale: 0.9, anchor: .leading))
                        )
                    )
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(WindowDragBlocker())
        .background(pillBackground)
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: ListWidthPreferenceKey.self,
                    value: [list.id: geo.size.width]
                )
            }
        )
        .scaleEffect(pillScale)
        .shadow(color: .black.opacity(isDragging ? 0.42 : 0), radius: 14, y: 6)
        .offset(x: xOffset)
        .zIndex(isDragging ? 1 : 0)
        .animation(PillMotion.press, value: isPressed)
        .animation(PillMotion.selection, value: isSelected)
        .animation(PillMotion.drag, value: isDragging)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .help(list.name)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(list.icon) \(list.name)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint("Double-tap to select. Right-click for options.")
        .onTapGesture(count: 2, perform: beginEdit)
        .onTapGesture(count: 1) {
            guard !isEditing else { return }
            onSelect()
        }
        .onLongPressGesture(minimumDuration: .infinity, maximumDistance: 6, perform: {}) { pressing in
            isPressed = pressing
        }
        .gesture(
            DragGesture(minimumDistance: 6, coordinateSpace: .named("lists"))
                .onChanged { value in
                    if didPushHoverCursor {
                        NSCursor.pop()
                        didPushHoverCursor = false
                    }
                    if !didPushCursor {
                        NSCursor.closedHand.push()
                        didPushCursor = true
                    }
                    isPressed = false
                    onDragChanged(value.translation.width)
                }
                .onEnded { value in
                    if didPushCursor {
                        NSCursor.pop()
                        didPushCursor = false
                    }
                    onDragEnded(value.translation.width)
                },
            including: isEditing ? .subviews : .all
        )
        .contextMenu {
            Button("Rename", action: beginEdit)
            Button("Change Emoji…") { isShowingIconPicker = true }
            Divider()
            Button("Delete List", role: .destructive, action: onDelete)
        }
        .popover(isPresented: $isShowingIconPicker, arrowEdge: .bottom) {
            EmojiPickerView(
                selected: list.icon,
                onPick: { emoji in
                    onSetIcon(emoji)
                    isShowingIconPicker = false
                }
            )
        }
        .onHover { hovering in
            guard !isDragActive else { return }
            isHovering = hovering
            if !hovering { isPressed = false }

            let shouldShow = hovering && !isEditing
            if shouldShow && !didPushHoverCursor {
                NSCursor.openHand.push()
                didPushHoverCursor = true
            } else if !shouldShow && didPushHoverCursor {
                NSCursor.pop()
                didPushHoverCursor = false
            }
        }
        .onChange(of: isDragActive) { _, active in
            if active && isHovering {
                isHovering = false
            }
        }
        .onAppear {
            if autoFocusOnAppear {
                beginEdit()
                onAutoFocusConsumed()
            }
        }
        .onDisappear {
            if didPushCursor {
                NSCursor.pop()
                didPushCursor = false
            }
            if didPushHoverCursor {
                NSCursor.pop()
                didPushHoverCursor = false
            }
        }
        .onChange(of: isEditing) { _, editing in
            if editing && didPushHoverCursor {
                NSCursor.pop()
                didPushHoverCursor = false
            }
        }
        .onChange(of: isEditorFocused) { _, focused in
            if !focused && isEditing {
                commitEdit()
            }
        }
    }

    private var pillBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(FloatDoTheme.rowHover)
                .opacity(isHovering && !isSelected ? 1 : 0)
                .animation(PillMotion.hover, value: isHovering)
                .animation(PillMotion.hover, value: isSelected)

            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(FloatDoTheme.tabActiveFill)
                .opacity(isSelected ? 1 : 0)
                .scaleEffect(isSelected ? 1 : 0.9)
                .animation(PillMotion.selection, value: isSelected)
        }
    }

    private var iconScale: CGFloat {
        if isSelected { return 1.0 }
        return isHovering ? 1.06 : 0.96
    }

    private var pillScale: CGFloat {
        if isDragging { return 1.06 }
        return isPressed ? 0.95 : 1.0
    }

    private func beginEdit() {
        draftName = list.name
        isEditing = true
        isEditorFocused = true
    }

    private func commitEdit() {
        guard isEditing else { return }
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && trimmed != list.name {
            onRename(trimmed)
        }
        isEditing = false
        isEditorFocused = false
    }

    private func cancelEdit() {
        isEditing = false
        isEditorFocused = false
    }
}

private struct EmojiPickerView: View {
    let selected: String
    var onPick: (String) -> Void

    private static let presets: [String] = [
        "📝", "✅", "⭐️", "❤️", "🚩", "🔖",
        "💼", "🏠", "🛒", "📚", "✏️", "🎓",
        "✈️", "🚗", "🏋️", "🍴", "🎁", "🎮",
        "📁", "🏷️", "🌱", "🔥", "⚡️", "☀️",
        "🌙", "📅", "⏰", "💡", "🎯", "🎨",
        "🎵", "💻", "📱", "🧳", "💪", "🐶"
    ]

    private let columns = Array(repeating: GridItem(.fixed(32), spacing: 4), count: 6)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(Self.presets, id: \.self) { emoji in
                EmojiCell(
                    emoji: emoji,
                    isSelected: selected == emoji,
                    action: { onPick(emoji) }
                )
            }
        }
        .padding(12)
        .frame(width: 236)
    }
}

private struct EmojiCell: View {
    let emoji: String
    let isSelected: Bool
    var action: () -> Void

    @State private var isHovering = false
    @State private var isPressed = false

    var body: some View {
        Text(emoji)
            .font(.system(size: 18))
            .frame(width: 32, height: 32)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(background)
            )
            .scaleEffect(cellScale)
            .animation(PillMotion.hover, value: isHovering)
            .animation(PillMotion.press, value: isPressed)
            .animation(PillMotion.selection, value: isSelected)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(emoji)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .onHover { hovering in
                isHovering = hovering
                if !hovering { isPressed = false }
            }
            .onTapGesture { action() }
            .onLongPressGesture(minimumDuration: .infinity, maximumDistance: 24, perform: {}) { pressing in
                isPressed = pressing
            }
    }

    private var cellScale: CGFloat {
        if isPressed { return 0.88 }
        if isSelected { return 1.04 }
        if isHovering { return 1.1 }
        return 1.0
    }

    private var background: Color {
        if isSelected { return FloatDoTheme.controlFillStrong }
        if isHovering { return FloatDoTheme.rowHover }
        return .clear
    }
}
