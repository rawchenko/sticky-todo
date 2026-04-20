import SwiftUI

struct ListIconPickerView: View {
    let selected: String
    var onPick: (String) -> Void

    static let presets: [String] = [
        "checklist", "checkmark.circle", "star", "heart", "flag", "bookmark",
        "briefcase", "house", "cart", "book", "pencil", "graduationcap",
        "airplane", "car", "figure.walk", "fork.knife", "gift", "gamecontroller",
        "folder", "tag", "leaf", "flame", "bolt", "sun.max",
        "moon", "calendar", "alarm", "lightbulb", "target", "paintpalette",
        "music.note", "laptopcomputer", "iphone", "suitcase", "dumbbell", "pawprint"
    ]

    private let columns = Array(repeating: GridItem(.fixed(32), spacing: 4), count: 6)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(Self.presets, id: \.self) { symbol in
                IconCell(
                    symbol: symbol,
                    isSelected: selected == symbol,
                    action: { onPick(symbol) }
                )
            }
        }
        .padding(12)
        .frame(width: 236)
    }
}

private struct IconCell: View {
    let symbol: String
    let isSelected: Bool
    var action: () -> Void

    @State private var isHovering = false
    @State private var isPressed = false
    @ObservedObject private var tweaks = LayoutTweaks.shared

    var body: some View {
        Image(systemName: symbol)
            .symbolVariant(.fill)
            .font(.system(size: 16, weight: .medium))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(FloatDoTheme.textPrimary)
            .frame(width: 32, height: 32)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(background)
            )
            .scaleEffect(cellScale)
            .animation(.easeOut(duration: 0.18), value: isHovering)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: isPressed)
            .animation(.spring(response: 0.36, dampingFraction: 0.82), value: isSelected)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(symbol)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .onHover { hovering in
                isHovering = hovering
                if !hovering { isPressed = false }
            }
            .pointerCursor(.pointingHand)
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
