import SwiftUI
import AppKit

struct WindowDragBlocker: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { BlockerView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class BlockerView: NSView {
        override var mouseDownCanMoveWindow: Bool { false }
    }
}

struct RowHeightPreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGFloat] = [:]
    static func reduce(value: inout [UUID: CGFloat], nextValue: () -> [UUID: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// Reminders-style circular checkbox. Uses a standard `Toggle` under the hood;
/// this is the `ToggleStyle` that renders it.
struct TodoCheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            ZStack {
                if configuration.isOn {
                    Circle()
                        .fill(FloatDoTheme.success)
                        .frame(width: 18, height: 18)
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.white)
                } else {
                    Circle()
                        .strokeBorder(
                            Color.dynamic(
                                light: Color.black.opacity(0.35),
                                dark: Color.white.opacity(0.45)
                            ),
                            lineWidth: 1.5
                        )
                        .frame(width: 18, height: 18)
                }
            }
            .frame(width: 18, height: 18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerCursor(.pointingHand)
    }
}

struct TodoRowView: View {
    let item: TodoItem
    let isDragging: Bool
    let isDragActive: Bool
    let yOffset: CGFloat
    var onToggle: () -> Void
    var onDelete: () -> Void
    var onRename: (String) -> Void = { _ in }
    var onDragChanged: (CGFloat) -> Void = { _ in }
    var onDragEnded: (CGFloat) -> Void = { _ in }

    @State private var isHovering = false
    @State private var didPushCursor = false
    @State private var isEditing = false
    @State private var draftTitle = ""
    @FocusState private var isEditorFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Toggle(isOn: Binding(
                get: { item.isCompleted },
                set: { _ in onToggle() }
            )) {
                EmptyView()
            }
            .toggleStyle(TodoCheckboxToggleStyle())

            if isEditing {
                TextField("Task", text: $draftTitle, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundStyle(FloatDoTheme.textPrimary)
                    .lineLimit(1...5)
                    .focused($isEditorFocused)
                    .onSubmit(commitEdit)
                    .onExitCommand(perform: cancelEdit)
                    .frame(maxWidth: .infinity, minHeight: 18, alignment: .topLeading)
            } else {
                Text(item.title)
                    .font(.system(size: 14))
                    .strikethrough(item.isCompleted)
                    .foregroundStyle(item.isCompleted ? FloatDoTheme.textSecondary : FloatDoTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 18, alignment: .topLeading)
                    .pointerCursor(.iBeam, active: !isDragActive)
                    .onTapGesture(perform: beginEdit)
            }

            Spacer(minLength: 4)

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(FloatDoTheme.textSecondary)
                    .frame(width: 22, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerCursor(.pointingHand, active: isHovering && !isDragActive && !isEditing)
            .opacity(isHovering && !isDragActive && !isEditing ? 1 : 0)
            .allowsHitTesting(isHovering && !isDragActive && !isEditing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(WindowDragBlocker())
        .background(rowBackground)
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: RowHeightPreferenceKey.self,
                    value: [item.id: geo.size.height]
                )
            }
        )
        .contentShape(Rectangle())
        .brightness(isDragging ? 0.04 : 0)
        .offset(y: yOffset)
        .scaleEffect(isDragging ? 1.03 : 1.0)
        .shadow(color: .black.opacity(isDragging ? 0.45 : 0), radius: 16, y: 6)
        .zIndex(isDragging ? 1 : 0)
        .pointerCursor(hoverCursor, active: !isDragActive)
        .onHover { hovering in
            guard !isDragActive else { return }
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .onChange(of: isDragActive) { _, active in
            if active && isHovering {
                isHovering = false
            }
        }
        .onChange(of: isEditorFocused) { _, focused in
            if !focused && isEditing {
                commitEdit()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 8, coordinateSpace: .named("list"))
                .onChanged { value in
                    if !didPushCursor {
                        NSCursor.closedHand.push()
                        didPushCursor = true
                    }
                    onDragChanged(value.translation.height)
                }
                .onEnded { value in
                    if didPushCursor {
                        NSCursor.pop()
                        didPushCursor = false
                    }
                    onDragEnded(value.translation.height)
                },
            including: isEditing ? .subviews : .all
        )
    }

    private func beginEdit() {
        draftTitle = item.title
        isEditing = true
        isEditorFocused = true
    }

    private func commitEdit() {
        guard isEditing else { return }
        let trimmed = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && trimmed != item.title {
            onRename(trimmed)
        }
        isEditing = false
        isEditorFocused = false
    }

    private func cancelEdit() {
        isEditing = false
        isEditorFocused = false
    }

    private var hoverCursor: NSCursor? { .openHand }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(isDragging
                ? FloatDoTheme.controlFillStrong
                : (isHovering && !isDragActive ? FloatDoTheme.rowHover : .clear))
    }
}
