import SwiftUI
import AppKit

class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class HoverTrackingHostingView<Content: View>: NSHostingView<Content> {
    var onHoverChange: ((Bool) -> Void)?
    private var trackingArea: NSTrackingArea?

    override var mouseDownCanMoveWindow: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Ensures transparent SwiftUI regions still count as "on the panel" so the
    /// `isMovableByWindowBackground` + `mouseDownCanMoveWindow` path can drag
    /// the window. Without this, empty regions return `nil` and clicks escape.
    override func hitTest(_ point: NSPoint) -> NSView? {
        if let hit = super.hitTest(point), hit !== self {
            return hit
        }
        let localPoint = convert(point, from: superview)
        return bounds.contains(localPoint) ? self : nil
    }

    override func updateTrackingAreas() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea

        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onHoverChange?(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHoverChange?(false)
    }
}

enum ScreenCorner {
    case topLeft, topRight, bottomLeft, bottomRight
}

extension ScreenCorner {
    var isTop: Bool {
        switch self {
        case .topLeft, .topRight:
            return true
        case .bottomLeft, .bottomRight:
            return false
        }
    }

    var isRight: Bool {
        switch self {
        case .topRight, .bottomRight:
            return true
        case .topLeft, .bottomLeft:
            return false
        }
    }

    var alignment: Alignment {
        switch self {
        case .topLeft:
            return .topLeading
        case .topRight:
            return .topTrailing
        case .bottomLeft:
            return .bottomLeading
        case .bottomRight:
            return .bottomTrailing
        }
    }

    var unitPoint: UnitPoint {
        switch self {
        case .topLeft:
            return .topLeading
        case .topRight:
            return .topTrailing
        case .bottomLeft:
            return .bottomLeading
        case .bottomRight:
            return .bottomTrailing
        }
    }
}

class PanelManager: NSObject, ObservableObject, NSWindowDelegate {
    private var panel: KeyablePanel?
    @Published var isCollapsed = true
    @Published var currentCorner: ScreenCorner = .topRight
    @Published var isDragging = false

    private let expandedSize = NSSize(width: PanelMetrics.expandedSize.width, height: PanelMetrics.expandedSize.height)
    private let collapsedSize = NSSize(width: PanelMetrics.collapsedSize.width, height: PanelMetrics.collapsedSize.height)
    private var isProgrammaticMove = false
    private var pendingSnapWorkItem: DispatchWorkItem?
    private var pendingHoverWorkItem: DispatchWorkItem?
    private var isPointerInsidePanel = false

    func setup<Content: View>(contentView: Content) {
        let panel = KeyablePanel(
            contentRect: NSRect(origin: .zero, size: expandedSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.level = .floating
        panel.isOpaque = false
        // Non-zero alpha avoids AppKit's window-server click-through on
        // fully-transparent pixels — otherwise right-clicks and drags on
        // empty regions of the panel leak through to the desktop below.
        panel.backgroundColor = NSColor(white: 0, alpha: 0.01)
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .utilityWindow
        panel.delegate = self

        let hostingView = HoverTrackingHostingView(rootView: contentView)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.layer?.isOpaque = false
        hostingView.layerContentsRedrawPolicy = .onSetNeedsDisplay
        hostingView.onHoverChange = { [weak self] isHovered in
            self?.handlePointerHoverChange(isHovered)
        }
        panel.contentView = hostingView

        self.panel = panel
        positionInCorner(.topRight)
    }

    func showPanel() {
        panel?.orderFront(nil)
        syncHoverStateWithPointerLocation(applyState: true)
    }

    func hidePanel() {
        panel?.orderOut(nil)
    }

    func togglePanel() {
        if panel?.isVisible == true {
            hidePanel()
        } else {
            showPanel()
        }
    }

    func collapse() {
        guard panel != nil, !isCollapsed else { return }
        withAnimation(PanelMotion.stateAnimation) {
            isCollapsed = true
        }
        positionInCorner(currentCorner, animated: true)
    }

    func expand() {
        guard panel != nil, isCollapsed else { return }
        withAnimation(PanelMotion.stateAnimation) {
            isCollapsed = false
        }
        positionInCorner(currentCorner, animated: true)
    }

    func toggleCollapse() {
        if isCollapsed {
            expand()
        } else {
            collapse()
        }
    }

    // MARK: - Corner snapping

    private func snapToNearestCorner() {
        if NSEvent.pressedMouseButtons & 1 != 0 {
            scheduleSnapToNearestCorner()
            return
        }

        guard let panel = panel, let screen = bestScreen(for: panel.frame) ?? NSScreen.main else { return }

        let frame = panel.frame
        let screenFrame = screen.visibleFrame
        let centerX = frame.midX
        let centerY = frame.midY
        let screenMidX = screenFrame.midX
        let screenMidY = screenFrame.midY

        let corner: ScreenCorner
        if centerX >= screenMidX {
            corner = centerY >= screenMidY ? .topRight : .bottomRight
        } else {
            corner = centerY >= screenMidY ? .topLeft : .bottomLeft
        }

        currentCorner = corner
        positionInCorner(corner, animated: true)
        withAnimation(PanelMotion.stateAnimation) {
            isDragging = false
        }
    }

    func windowDidMove(_ notification: Notification) {
        guard !isProgrammaticMove else { return }
        if !isDragging {
            withAnimation(PanelMotion.stateAnimation) {
                isDragging = true
            }
        }
        scheduleSnapToNearestCorner()
    }

    private func scheduleSnapToNearestCorner() {
        pendingSnapWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.snapToNearestCorner()
        }

        pendingSnapWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
    }

    private func positionInCorner(_ corner: ScreenCorner, animated: Bool = false) {
        guard let panel = panel, let screen = bestScreen(for: panel.frame) ?? NSScreen.main else { return }

        pendingSnapWorkItem?.cancel()

        currentCorner = corner
        let newFrame = frame(for: corner, on: screen)

        if animated {
            isProgrammaticMove = true
            NSAnimationContext.runAnimationGroup { context in
                context.duration = PanelMotion.frameAnimationDuration
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.18, 1.0, 0.22, 1.0)
                panel.animator().setFrame(newFrame, display: true)
            } completionHandler: { [weak self] in
                self?.isProgrammaticMove = false
                self?.syncHoverStateWithPointerLocation(applyState: true)
            }
        } else {
            isProgrammaticMove = true
            panel.setFrame(newFrame, display: true)
            DispatchQueue.main.async { [weak self] in
                self?.isProgrammaticMove = false
                self?.syncHoverStateWithPointerLocation(applyState: true)
            }
        }
    }

    private func frame(for corner: ScreenCorner, on screen: NSScreen) -> NSRect {
        let screenFrame = screen.visibleFrame
        let targetSize = resolvedSize(for: screenFrame)

        let origin = NSPoint(
            x: corner.isRight ? screenFrame.maxX - targetSize.width : screenFrame.minX,
            y: corner.isTop ? screenFrame.maxY - targetSize.height : screenFrame.minY
        )

        return NSRect(origin: origin, size: targetSize)
    }

    private func resolvedSize(for screenFrame: NSRect) -> NSSize {
        let baseSize = isCollapsed ? collapsedSize : expandedSize
        return NSSize(
            width: min(baseSize.width, screenFrame.width),
            height: min(baseSize.height, screenFrame.height)
        )
    }

    private func bestScreen(for frame: NSRect) -> NSScreen? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return nil }

        let screenByIntersection = screens.max { lhs, rhs in
            intersectionArea(of: lhs.visibleFrame, with: frame) < intersectionArea(of: rhs.visibleFrame, with: frame)
        }

        if let screenByIntersection, intersectionArea(of: screenByIntersection.visibleFrame, with: frame) > 0 {
            return screenByIntersection
        }

        let center = CGPoint(x: frame.midX, y: frame.midY)
        return screens.min { lhs, rhs in
            distanceSquared(from: center, to: lhs.visibleFrame) < distanceSquared(from: center, to: rhs.visibleFrame)
        }
    }

    private func intersectionArea(of lhs: NSRect, with rhs: NSRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else { return 0 }
        return intersection.width * intersection.height
    }

    private func distanceSquared(from point: CGPoint, to rect: NSRect) -> CGFloat {
        let clampedX = min(max(point.x, rect.minX), rect.maxX)
        let clampedY = min(max(point.y, rect.minY), rect.maxY)
        let dx = point.x - clampedX
        let dy = point.y - clampedY
        return (dx * dx) + (dy * dy)
    }

    private func handlePointerHoverChange(_ isHovered: Bool) {
        pendingHoverWorkItem?.cancel()
        isPointerInsidePanel = isHovered

        if isDragging {
            return
        }

        if isHovered {
            expand()
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.syncHoverStateWithPointerLocation()
            if !self.isPointerInsidePanel && !self.isDragging {
                self.collapse()
            }
        }

        pendingHoverWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + PanelMotion.hoverExitDelay, execute: workItem)
    }

    private func syncHoverStateWithPointerLocation(applyState: Bool = false) {
        guard let panel else { return }
        let isPointerInside = panel.frame.contains(NSEvent.mouseLocation)
        isPointerInsidePanel = isPointerInside

        guard applyState else { return }

        if isPointerInside {
            expand()
        } else {
            collapse()
        }
    }
}
