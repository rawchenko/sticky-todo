import SwiftUI

private struct CornerRadii {
    let topLeft: CGFloat
    let topRight: CGFloat
    let bottomRight: CGFloat
    let bottomLeft: CGFloat
}

private func clamped(_ radius: CGFloat, in rect: CGRect) -> CGFloat {
    min(radius, min(rect.width, rect.height) / 2)
}

private func interpolated(_ from: CGFloat, _ to: CGFloat, progress: CGFloat) -> CGFloat {
    from + ((to - from) * progress)
}

private func roundedRectPath(in rect: CGRect, radii: CornerRadii) -> Path {
    let tl = clamped(radii.topLeft, in: rect)
    let tr = clamped(radii.topRight, in: rect)
    let br = clamped(radii.bottomRight, in: rect)
    let bl = clamped(radii.bottomLeft, in: rect)

    var path = Path()
    path.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))

    if tr > 0 {
        path.addArc(
            center: CGPoint(x: rect.maxX - tr, y: rect.minY + tr),
            radius: tr,
            startAngle: .degrees(-90),
            endAngle: .degrees(0),
            clockwise: false
        )
    }

    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))

    if br > 0 {
        path.addArc(
            center: CGPoint(x: rect.maxX - br, y: rect.maxY - br),
            radius: br,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )
    }

    path.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))

    if bl > 0 {
        path.addArc(
            center: CGPoint(x: rect.minX + bl, y: rect.maxY - bl),
            radius: bl,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )
    }

    path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))

    if tl > 0 {
        path.addArc(
            center: CGPoint(x: rect.minX + tl, y: rect.minY + tl),
            radius: tl,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )
    }

    path.closeSubpath()
    return path
}

struct DockedPanelShape: Shape {
    let corner: ScreenCorner
    var radius: CGFloat = PanelMetrics.cornerRadius

    func path(in rect: CGRect) -> Path {
        roundedRectPath(in: rect, radii: radii(for: corner, radius: radius))
    }

    private func radii(for corner: ScreenCorner, radius: CGFloat) -> CornerRadii {
        switch corner {
        case .topLeft:
            return CornerRadii(topLeft: 0, topRight: radius, bottomRight: radius, bottomLeft: 0)
        case .topRight:
            return CornerRadii(topLeft: radius, topRight: 0, bottomRight: 0, bottomLeft: radius)
        case .bottomLeft:
            return CornerRadii(topLeft: 0, topRight: radius, bottomRight: radius, bottomLeft: 0)
        case .bottomRight:
            return CornerRadii(topLeft: radius, topRight: 0, bottomRight: 0, bottomLeft: radius)
        }
    }
}

struct DockedHandleShape: Shape {
    let corner: ScreenCorner
    var radius: CGFloat = 18

    func path(in rect: CGRect) -> Path {
        roundedRectPath(in: rect, radii: outerRadii(for: corner, radius: radius))
    }

    private func outerRadii(for corner: ScreenCorner, radius: CGFloat) -> CornerRadii {
        switch corner {
        case .topLeft:
            return CornerRadii(topLeft: 0, topRight: radius, bottomRight: radius, bottomLeft: 0)
        case .topRight:
            return CornerRadii(topLeft: radius, topRight: 0, bottomRight: 0, bottomLeft: radius)
        case .bottomLeft:
            return CornerRadii(topLeft: 0, topRight: radius, bottomRight: radius, bottomLeft: 0)
        case .bottomRight:
            return CornerRadii(topLeft: radius, topRight: 0, bottomRight: 0, bottomLeft: radius)
        }
    }
}

struct MorphingDockedShape: Shape {
    let corner: ScreenCorner
    var expansion: CGFloat
    var floatingProgress: CGFloat = 0
    var handleRadius: CGFloat = 18
    var panelRadius: CGFloat = PanelMetrics.cornerRadius

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(expansion, floatingProgress) }
        set {
            expansion = newValue.first
            floatingProgress = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let expProgress = min(max(expansion, 0), 1)
        let floatProgress = min(max(floatingProgress, 0), 1)

        let from = handleRadii(for: corner, radius: handleRadius)
        let docked = panelRadii(for: corner, radius: panelRadius)
        let floating = CornerRadii(topLeft: panelRadius, topRight: panelRadius, bottomRight: panelRadius, bottomLeft: panelRadius)

        let base = CornerRadii(
            topLeft: interpolated(from.topLeft, docked.topLeft, progress: expProgress),
            topRight: interpolated(from.topRight, docked.topRight, progress: expProgress),
            bottomRight: interpolated(from.bottomRight, docked.bottomRight, progress: expProgress),
            bottomLeft: interpolated(from.bottomLeft, docked.bottomLeft, progress: expProgress)
        )

        let radii = CornerRadii(
            topLeft: interpolated(base.topLeft, floating.topLeft, progress: floatProgress),
            topRight: interpolated(base.topRight, floating.topRight, progress: floatProgress),
            bottomRight: interpolated(base.bottomRight, floating.bottomRight, progress: floatProgress),
            bottomLeft: interpolated(base.bottomLeft, floating.bottomLeft, progress: floatProgress)
        )

        return roundedRectPath(in: rect, radii: radii)
    }

    private func handleRadii(for corner: ScreenCorner, radius: CGFloat) -> CornerRadii {
        switch corner {
        case .topLeft:
            return CornerRadii(topLeft: 0, topRight: radius, bottomRight: radius, bottomLeft: 0)
        case .topRight:
            return CornerRadii(topLeft: radius, topRight: 0, bottomRight: 0, bottomLeft: radius)
        case .bottomLeft:
            return CornerRadii(topLeft: 0, topRight: radius, bottomRight: radius, bottomLeft: 0)
        case .bottomRight:
            return CornerRadii(topLeft: radius, topRight: 0, bottomRight: 0, bottomLeft: radius)
        }
    }

    private func panelRadii(for corner: ScreenCorner, radius: CGFloat) -> CornerRadii {
        switch corner {
        case .topLeft:
            return CornerRadii(topLeft: 0, topRight: radius, bottomRight: radius, bottomLeft: 0)
        case .topRight:
            return CornerRadii(topLeft: radius, topRight: 0, bottomRight: 0, bottomLeft: radius)
        case .bottomLeft:
            return CornerRadii(topLeft: 0, topRight: radius, bottomRight: radius, bottomLeft: 0)
        case .bottomRight:
            return CornerRadii(topLeft: radius, topRight: 0, bottomRight: 0, bottomLeft: radius)
        }
    }
}
