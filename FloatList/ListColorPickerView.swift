import SwiftUI

struct ListColorPickerView: View {
    let selected: ListIconColor?
    var onPick: (ListIconColor?) -> Void

    private let columns = Array(repeating: GridItem(.fixed(32), spacing: 4), count: 5)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ColorCell(
                swatch: .none,
                isSelected: selected == nil,
                action: { onPick(nil) }
            )
            ForEach(ListIconColor.allCases, id: \.self) { option in
                ColorCell(
                    swatch: .color(option),
                    isSelected: selected == option,
                    action: { onPick(option) }
                )
            }
        }
        .padding(12)
        .frame(width: 196)
    }
}

private enum ColorSwatch: Equatable {
    case none
    case color(ListIconColor)
}

private struct ColorCell: View {
    let swatch: ColorSwatch
    let isSelected: Bool
    var action: () -> Void

    @State private var isHovering = false
    @State private var isPressed = false

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(fill)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(FloatListTheme.textPrimary.opacity(isSelected ? 0.85 : 0), lineWidth: 1.5)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(FloatListTheme.textSecondary.opacity(0.25), lineWidth: 0.5)
            )
            .frame(width: 32, height: 32)
            .scaleEffect(cellScale)
            .animation(.easeOut(duration: 0.18), value: isHovering)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: isPressed)
            .animation(.spring(response: 0.36, dampingFraction: 0.82), value: isSelected)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
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

    private var fill: Color {
        switch swatch {
        case .none:
            return FloatListTheme.textPrimary
        case .color(let option):
            return option.color
        }
    }

    private var cellScale: CGFloat {
        if isPressed { return 0.88 }
        if isSelected { return 1.04 }
        if isHovering { return 1.1 }
        return 1.0
    }

    private var accessibilityLabel: String {
        switch swatch {
        case .none: return "Default"
        case .color(let option): return option.rawValue.capitalized
        }
    }
}
