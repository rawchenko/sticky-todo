import SwiftUI

enum BulkActionContext {
    case regular
    case completed
    case trash
}

struct BulkActionBar: View {
    let context: BulkActionContext
    let anySelectedIsActive: Bool
    let moveDestinations: [TodoList]
    var onToggleComplete: () -> Void = {}
    var onMoveTo: (UUID) -> Void = { _ in }
    var onDelete: () -> Void = {}
    var onRestore: () -> Void = {}
    var onDeleteForever: () -> Void = {}
    var onClear: () -> Void = {}

    @ObservedObject private var tweaks = LayoutTweaks.shared

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            actionButtons

            PillIconButton(help: "Clear selection", action: onClear) {
                pillGlyph("xmark", size: 13)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: tweaks.inputCornerRadius, style: .continuous)
                .fill(FloatListTheme.inputFill)
        )
        .padding(.horizontal, 6)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private var actionButtons: some View {
        switch context {
        case .regular, .completed:
            PillIconButton(
                help: anySelectedIsActive ? "Mark complete" : "Mark incomplete",
                action: onToggleComplete
            ) {
                pillGlyph(anySelectedIsActive ? "checkmark.circle" : "circle")
            }

            moveMenu

            PillIconButton(help: "Delete", action: onDelete) {
                pillGlyph("trash", tint: FloatListTheme.destructive)
            }

        case .trash:
            PillIconButton(help: "Restore", action: onRestore) {
                pillGlyph("arrow.uturn.backward")
            }

            PillIconButton(help: "Delete forever", action: onDeleteForever) {
                pillGlyph("trash.slash", tint: FloatListTheme.destructive)
            }
        }
    }

    @ViewBuilder
    private var moveMenu: some View {
        if !moveDestinations.isEmpty {
            PillIconMenu(
                help: "Move to\u{2026}",
                items: moveDestinations.map { list in
                    PillIconMenuItem(
                        id: list.id,
                        title: list.name,
                        systemImage: list.icon,
                        action: { onMoveTo(list.id) }
                    )
                }
            ) {
                pillGlyph("folder")
            }
        }
    }

    private func pillGlyph(_ name: String, size: CGFloat = 14, tint: Color = FloatListTheme.textPrimary) -> some View {
        Image(systemName: name)
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(tint)
            .symbolRenderingMode(.monochrome)
    }
}
