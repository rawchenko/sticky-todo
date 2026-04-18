import SwiftUI
import AppKit

/// Liquid Glass shell for the panel.
/// Uses the macOS 26 (Tahoe) native glass effect when available,
/// and falls back to `NSVisualEffectView` on earlier systems.
struct PanelGlassBackground<S: Shape>: View {
    let shape: S

    var body: some View {
        if #available(macOS 26.0, *) {
            shape
                .fill(Color.clear)
                .glassEffect(.regular, in: shape)
        } else {
            ZStack {
                VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                    .clipShape(shape)
                shape.fill(FloatDoTheme.shellFallback)
            }
        }
    }
}

/// Transparent backdrop that explicitly opts in to AppKit's
/// `mouseDownCanMoveWindow`, so clicking on empty panel surface drags the
/// window. Paired with `WindowDragBlocker` on interactive rows/buttons.
struct WindowDragZone: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragZoneView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class DragZoneView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
}

struct VisualEffectBlur: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.isEmphasized = false
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
