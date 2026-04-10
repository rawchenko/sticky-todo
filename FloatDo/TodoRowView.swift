import SwiftUI

struct TodoRowView: View {
    let item: TodoItem
    var onToggle: () -> Void
    var onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onToggle) {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(item.isCompleted ? FloatDoTheme.success : FloatDoTheme.textSecondary)
            }
            .buttonStyle(.plain)

            Text(item.title)
                .font(.system(size: 13))
                .strikethrough(item.isCompleted)
                .foregroundStyle(item.isCompleted ? FloatDoTheme.textSecondary : FloatDoTheme.textPrimary)
                .lineLimit(2)

            Spacer()

            if isHovering {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(FloatDoTheme.textPrimary)
                        .frame(width: 20, height: 20)
                        .background(
                            Circle()
                                .fill(FloatDoTheme.controlFillStrong)
                        )
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isHovering ? FloatDoTheme.rowHover : .clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}
