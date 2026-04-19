import SwiftUI

struct MorphingDockedShape: Shape {
    var expansion: CGFloat
    var handleRadius: CGFloat = 18
    var panelRadius: CGFloat = PanelMetrics.cornerRadius

    var animatableData: CGFloat {
        get { expansion }
        set { expansion = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let progress = min(max(expansion, 0), 1)
        let interpolated = handleRadius + (panelRadius - handleRadius) * progress
        let radius = min(interpolated, min(rect.width, rect.height) / 2)
        return RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect)
    }
}
