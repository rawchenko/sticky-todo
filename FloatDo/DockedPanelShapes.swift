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
            return CornerRadii(topLeft: 0, topRight: radius, bottomRight: radius, bottomLeft: radius)
        case .topRight:
            return CornerRadii(topLeft: radius, topRight: 0, bottomRight: radius, bottomLeft: radius)
        case .bottomLeft:
            return CornerRadii(topLeft: radius, topRight: radius, bottomRight: radius, bottomLeft: 0)
        case .bottomRight:
            return CornerRadii(topLeft: radius, topRight: radius, bottomRight: 0, bottomLeft: radius)
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
    var handleRadius: CGFloat = 18
    var panelRadius: CGFloat = PanelMetrics.cornerRadius

    var animatableData: CGFloat {
        get { expansion }
        set { expansion = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let progress = min(max(expansion, 0), 1)
        let from = handleRadii(for: corner, radius: handleRadius)
        let to = panelRadii(for: corner, radius: panelRadius)

        let radii = CornerRadii(
            topLeft: interpolated(from.topLeft, to.topLeft, progress: progress),
            topRight: interpolated(from.topRight, to.topRight, progress: progress),
            bottomRight: interpolated(from.bottomRight, to.bottomRight, progress: progress),
            bottomLeft: interpolated(from.bottomLeft, to.bottomLeft, progress: progress)
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
            return CornerRadii(topLeft: 0, topRight: radius, bottomRight: radius, bottomLeft: radius)
        case .topRight:
            return CornerRadii(topLeft: radius, topRight: 0, bottomRight: radius, bottomLeft: radius)
        case .bottomLeft:
            return CornerRadii(topLeft: radius, topRight: radius, bottomRight: radius, bottomLeft: 0)
        case .bottomRight:
            return CornerRadii(topLeft: radius, topRight: radius, bottomRight: 0, bottomLeft: radius)
        }
    }
}
