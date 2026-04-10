import SwiftUI

struct CollapsedView: View {
    let corner: ScreenCorner

    var body: some View {
        ZStack {
            collapsedSurface

            DockedHandleShape(corner: corner)
                .stroke(FloatDoTheme.border, lineWidth: 1)

            VStack(spacing: 10) {
                Image(systemName: "checklist")
                    .font(.system(size: 15, weight: .semibold))
                Capsule()
                    .fill(FloatDoTheme.textSecondary)
                    .frame(width: 12, height: 2)
                Capsule()
                    .fill(FloatDoTheme.textSecondary)
                    .frame(width: 12, height: 2)
            }
            .foregroundStyle(FloatDoTheme.textPrimary)
        }
        .frame(width: PanelMetrics.collapsedSize.width, height: PanelMetrics.collapsedSize.height)
        .mask(DockedHandleShape(corner: corner))
        .background(Color.clear)
        .contentShape(Rectangle())
    }

    private var collapsedSurface: some View {
        DockedHandleShape(corner: corner)
            .fill(FloatDoTheme.shell)
            .shadow(color: FloatDoTheme.shadow, radius: 8, y: 2)
    }
}
