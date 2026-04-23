import SwiftUI
import AppKit
import Combine

class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private enum PanelResize {
    static let minimumExpandedWidth: CGFloat = 220
    static let minimumExpandedHeight: CGFloat = 220
}

private enum PanelHover {
    static let safeInset: CGFloat = 8
    static let bufferExitPollInterval: TimeInterval = 0.1
}

private enum GhostMetrics {
    /// Extra frame around the ghost's collapsed shape so the outer white halo
    /// (Paper spec: `#FFFFFF66 0 0 18 3`, ≈21pt reach) isn't clipped by the
    /// NSPanel bounds. The shape itself is still drawn at `collapsedSize`,
    /// centered inside the padded panel.
    static let glowPadding: CGFloat = 24
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

enum ScreenEdge: String, Codable {
    case left, right
}

extension ScreenEdge {
    /// SwiftUI alignment that pins child views toward the screen edge — so the
    /// expand/collapse morph "sticks" to that edge instead of drifting inward.
    var alignment: Alignment {
        switch self {
        case .left: return .leading
        case .right: return .trailing
        }
    }

    /// Anchor point for `scaleEffect`: scaling collapses the panel toward its
    /// screen edge, matching the alignment.
    var unitPoint: UnitPoint {
        switch self {
        case .left: return .leading
        case .right: return .trailing
        }
    }

    /// Direction the collapsed glyph "puffs" outward past the docked edge —
    /// the same direction the expanded panel grew from.
    var transitionOffset: CGSize {
        let d = PanelMotion.transitionDistance
        switch self {
        case .left: return CGSize(width: -d, height: 0)
        case .right: return CGSize(width: d, height: 0)
        }
    }
}

/// Which point on the panel stays fixed when the panel resizes between
/// expanded and collapsed. Picked at drop time based on the panel's vertical
/// position so collapsing doesn't appear to drift toward one screen edge.
enum VerticalAnchor: String, Codable {
    case top, center, bottom
}

struct EdgeAnchor: Equatable {
    var edge: ScreenEdge
    var vertical: VerticalAnchor
    /// AppKit screen Y of the stable point (matches `vertical`):
    /// `.top` → panel.maxY, `.center` → panel.midY, `.bottom` → panel.minY.
    var anchorY: CGFloat
}

private struct PersistedAnchor: Codable {
    var displayID: UInt32
    var edge: ScreenEdge
    var vertical: VerticalAnchor
    var anchorY: CGFloat
}

private enum DefaultsKey {
    static let panelAnchor = "FloatList.panelAnchor.v2"
}

@MainActor
class PanelManager: NSObject, ObservableObject, NSWindowDelegate {
    private var panel: KeyablePanel?
    private var ghostPanel: NSPanel?
    @Published var isCollapsed = true
    @Published var currentAnchor = EdgeAnchor(edge: .right, vertical: .top, anchorY: 0)
    @Published var isDragging = false

    /// When true, this instance is a lightweight state-only facade used by the
    /// onboarding window to feed `ContentView` the panel-state it reads
    /// (`currentAnchor`, `isCollapsed`, `isDragging`) without actually owning
    /// an `NSPanel`. Edge-snapping and collapse are fully suppressed.
    let isOnboardingMode: Bool

    init(isOnboardingMode: Bool = false) {
        self.isOnboardingMode = isOnboardingMode
        super.init()
        if isOnboardingMode {
            isCollapsed = false
            currentAnchor = EdgeAnchor(edge: .right, vertical: .center, anchorY: 0)
        }
    }

    private var expandedSize: NSSize {
        NSSize(width: LayoutTweaks.shared.expandedWidth, height: LayoutTweaks.shared.expandedHeight)
    }
    private var collapsedSize: NSSize {
        NSSize(width: LayoutTweaks.shared.collapsedWidth, height: LayoutTweaks.shared.collapsedHeight)
    }
    private var tweakCancellable: AnyCancellable?
    private var isProgrammaticMove = false
    private var pendingSnapWorkItem: DispatchWorkItem?
    private var pendingHoverWorkItem: DispatchWorkItem?
    private var isPointerInsidePanel = false
    private var isLiveResizing = false
    /// Set when the user expands the panel via the global shortcut. While true,
    /// hover-exit does not trigger collapse — the panel stays open until the
    /// user explicitly collapses it (shortcut again, or pointer enters then
    /// leaves). Without this, pressing the shortcut expands the panel and then
    /// the tracking area immediately collapses it because the pointer isn't
    /// over the newly-enlarged frame.
    private var isKeyboardPinned = false
    /// Number of transient UI affordances (popovers, inline editors) that want
    /// to keep the panel expanded even while the pointer leaves the panel
    /// frame — popovers extend outside that frame, so their own hover would
    /// otherwise trip the collapse timer.
    private var hoverHoldCount = 0
    private var isHoverHeld: Bool { hoverHoldCount > 0 }

    func setup<Content: View>(contentView: Content) {
        guard !isOnboardingMode else { return }
        let panel = KeyablePanel(
            contentRect: NSRect(origin: .zero, size: expandedSize),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
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
        self.ghostPanel = makeGhostPanel()
        restoreOrSetDefaultAnchor()

        tweakCancellable = LayoutTweaks.shared.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.positionAtAnchor(self.currentAnchor, animated: true)
            }
    }

    private func makeGhostPanel() -> NSPanel {
        let pad = GhostMetrics.glowPadding
        let paddedSize = NSSize(
            width: collapsedSize.width + pad * 2,
            height: collapsedSize.height + pad * 2
        )
        let ghost = NSPanel(
            contentRect: NSRect(origin: .zero, size: paddedSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // Sit just below floating so the dragged panel always covers the ghost
        // when they overlap, but above normal app windows so the preview is
        // still visible over other apps.
        ghost.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)
        ghost.isOpaque = false
        ghost.backgroundColor = .clear
        ghost.hasShadow = false
        ghost.ignoresMouseEvents = true
        ghost.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        ghost.animationBehavior = .none
        ghost.alphaValue = 0
        let host = NSHostingView(rootView: GhostView())
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.clear.cgColor
        host.layer?.isOpaque = false
        ghost.contentView = host
        return ghost
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

    /// If the panel is hidden, show it expanded. If visible, toggle between
    /// collapsed and expanded. Used by the expand/collapse global shortcut so
    /// the user can reveal the full panel without hovering the handle.
    func showOrToggleExpansion() {
        if panel?.isVisible != true {
            showPanel()
            isKeyboardPinned = true
            expand()
            return
        }
        if isCollapsed {
            isKeyboardPinned = true
            expand()
        } else {
            isKeyboardPinned = false
            collapse()
        }
    }

    func collapse() {
        guard !isCollapsed else { return }
        withAnimation(PanelMotion.stateAnimation) {
            isCollapsed = true
        }
        guard panel != nil else { return }
        positionAtAnchor(currentAnchor, animated: true)
    }

    func expand() {
        guard isCollapsed else { return }
        withAnimation(PanelMotion.stateAnimation) {
            isCollapsed = false
        }
        guard panel != nil else { return }
        positionAtAnchor(currentAnchor, animated: true)
    }

    func toggleCollapse() {
        if isCollapsed {
            expand()
        } else {
            collapse()
        }
    }

    // MARK: - Edge snapping

    private func snapToNearestEdge() {
        guard !isOnboardingMode else { return }
        if NSEvent.pressedMouseButtons & 1 != 0 {
            scheduleSnapToNearestEdge()
            return
        }

        guard let panel = panel, let screen = bestScreen(for: panel.frame) ?? NSScreen.main else { return }

        let f = panel.frame
        let v = screen.visibleFrame

        // Tie-break: right wins when distances are equal.
        let distRight = v.maxX - f.maxX
        let distLeft = f.minX - v.minX
        let bestEdge: ScreenEdge = distRight <= distLeft ? .right : .left

        let (vertical, anchorY) = determineVerticalAnchor(panelFrame: f, visible: v)
        let anchor = EdgeAnchor(edge: bestEdge, vertical: vertical, anchorY: anchorY)

        // Collapse in the same motion as the edge snap when the cursor
        // won't land inside the docked glyph — otherwise the user sees two
        // sequential animations (snap, then collapse).
        if !isCollapsed && !isKeyboardPinned && !isHoverHeld {
            let docked = dockedCollapsedFrame(for: anchor, on: screen)
            if !pointerIsWithinSafeArea(of: docked) {
                withAnimation(PanelMotion.stateAnimation) {
                    isCollapsed = true
                }
            }
        }

        positionAtAnchor(anchor, on: screen, animated: true)
        persistAnchor(anchor, screen: screen)
        hideGhost()
        withAnimation(PanelMotion.stateAnimation) {
            isDragging = false
        }
    }

    /// Picks the vertical anchor based on which third of the available range the
    /// panel was dropped into — top third locks the top, bottom third locks the
    /// bottom, middle third locks the center. Computed against the panel's
    /// current height so it works whether the user dropped expanded or collapsed.
    private func determineVerticalAnchor(panelFrame f: NSRect, visible v: NSRect) -> (VerticalAnchor, CGFloat) {
        let availableRange = v.height - f.height
        if availableRange <= 0 {
            return (.center, f.midY)
        }
        let t = (f.minY - v.minY) / availableRange
        if t > 0.66 { return (.top, f.maxY) }
        if t < 0.33 { return (.bottom, f.minY) }
        return (.center, f.midY)
    }

    func windowDidMove(_ notification: Notification) {
        guard !isProgrammaticMove, !isLiveResizing else { return }
        if !isDragging {
            withAnimation(PanelMotion.stateAnimation) {
                isDragging = true
            }
            showGhost()
        }
        updateGhostFrame()
        scheduleSnapToNearestEdge()
    }

    private func scheduleSnapToNearestEdge() {
        guard !isOnboardingMode else { return }
        pendingSnapWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.snapToNearestEdge()
        }

        pendingSnapWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04, execute: workItem)
    }

    /// Animates the panel in from an arbitrary starting rect (e.g. the onboarding
    /// window's embedded panel) to its final docked collapsed frame. Called once
    /// at onboarding completion so the real panel appears to "emerge" from where
    /// the user was just interacting.
    func flyInFromCenter(from originFrame: NSRect) {
        guard !isOnboardingMode, let panel, let screen = bestScreen(for: originFrame) ?? NSScreen.main else { return }

        pendingSnapWorkItem?.cancel()
        isProgrammaticMove = true

        // Make sure `currentAnchor` reflects a valid docked position. Without
        // this, a brand-new PanelManager whose `setup(contentView:)` just ran
        // may still hold the stale default (`anchorY: 0`), which clamps the
        // destination to the bottom of the screen instead of the intended top.
        ensureDefaultAnchor(on: screen)

        // Start at the onboarding-window rect with the panel fully expanded so
        // the handoff reads as continuous.
        panel.setFrame(originFrame, display: true)
        isCollapsed = false
        panel.orderFront(nil)

        let destination = dockedCollapsedFrame(for: currentAnchor, on: screen)
        withAnimation(PanelMotion.stateAnimation) {
            isCollapsed = true
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = PanelMotion.frameAnimationDuration
            context.timingFunction = PanelMotion.frameTiming
            context.allowsImplicitAnimation = true
            panel.animator().setFrame(destination, display: true)
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                self?.isProgrammaticMove = false
                self?.syncHoverStateWithPointerLocation(applyState: true)
            }
        }
    }

    /// Places the panel at the docked collapsed frame for `anchor` and
    /// brings it on screen without animation. Used by the Immersive onboarding
    /// handoff — the stage already animated its fake panel into place,
    /// so the real panel just materializes at the same spot.
    func revealDocked(at anchor: EdgeAnchor) {
        guard !isOnboardingMode,
              let panel,
              let screen = NSScreen.main
        else { return }

        pendingSnapWorkItem?.cancel()

        // Disable animations on the state change. ContentView listens
        // to `isCollapsed` via `.animation(_, value:)` — if the panel
        // was left expanded before Immersive onboarding hid it, a bare
        // `isCollapsed = true` here would run an expand→collapse
        // animation on reveal, producing a visible twitch.
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isCollapsed = true
            currentAnchor = anchor
        }

        // Skip the shared `positionAtAnchor(animated: false)` path
        // because it async-schedules `syncHoverStateWithPointerLocation`
        // which, if the user's cursor happens to be over the docked
        // spot, immediately re-triggers `expand()` with its own
        // animation — the exact jitter we're trying to avoid.
        isProgrammaticMove = true
        let newFrame = frame(for: anchor, on: screen)
        panel.setFrame(newFrame, display: true)
        persistAnchor(anchor, screen: screen)
        panel.orderFront(nil)
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.isProgrammaticMove = false
            }
        }
    }

    /// If the current anchor hasn't been initialized to a valid screen position
    /// yet, replace it with the persisted anchor (if any) or the default for
    /// this screen. Does NOT animate the panel — pure state update.
    private func ensureDefaultAnchor(on screen: NSScreen) {
        let needsDefault = currentAnchor.anchorY == 0
        guard needsDefault else { return }
        if let (persisted, _) = loadPersistedAnchor() {
            currentAnchor = EdgeAnchor(edge: persisted.edge, vertical: persisted.vertical, anchorY: persisted.anchorY)
        } else {
            currentAnchor = defaultAnchor(for: screen)
        }
    }

    func windowWillStartLiveResize(_ notification: Notification) {
        isLiveResizing = true
        pendingSnapWorkItem?.cancel()
        hideGhost()
        if isDragging {
            withAnimation(PanelMotion.stateAnimation) {
                isDragging = false
            }
        }
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        isLiveResizing = false
        persistExpandedSizeFromPanelFrame()
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        guard !isCollapsed else { return collapsedSize }
        guard let screen = bestScreen(for: sender.frame) ?? NSScreen.main else {
            return NSSize(
                width: max(frameSize.width, PanelResize.minimumExpandedWidth),
                height: max(frameSize.height, PanelResize.minimumExpandedHeight)
            )
        }

        let visible = screen.visibleFrame.size
        return NSSize(
            width: min(max(frameSize.width, PanelResize.minimumExpandedWidth), visible.width),
            height: min(max(frameSize.height, PanelResize.minimumExpandedHeight), visible.height)
        )
    }

    private func positionAtAnchor(_ anchor: EdgeAnchor, on screen: NSScreen? = nil, animated: Bool = false) {
        guard let panel = panel else { return }
        let resolvedScreen = screen ?? bestScreen(for: panel.frame) ?? NSScreen.main
        guard let resolvedScreen else { return }

        pendingSnapWorkItem?.cancel()

        currentAnchor = anchor
        let newFrame = frame(for: anchor, on: resolvedScreen)

        if animated {
            isProgrammaticMove = true
            NSAnimationContext.runAnimationGroup { context in
                context.duration = PanelMotion.frameAnimationDuration
                context.timingFunction = PanelMotion.frameTiming
                context.allowsImplicitAnimation = true
                panel.animator().setFrame(newFrame, display: true)
            } completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    self?.isProgrammaticMove = false
                    self?.syncHoverStateWithPointerLocation(applyState: true)
                }
            }
        } else {
            isProgrammaticMove = true
            panel.setFrame(newFrame, display: true)
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    self?.isProgrammaticMove = false
                    self?.syncHoverStateWithPointerLocation(applyState: true)
                }
            }
        }
    }

    private func frame(for anchor: EdgeAnchor, on screen: NSScreen, size overrideSize: NSSize? = nil) -> NSRect {
        let visible = screen.visibleFrame
        let size = overrideSize ?? resolvedSize(for: visible)
        let inset = LayoutTweaks.shared.edgeInset

        let rawMinY: CGFloat
        switch anchor.vertical {
        case .top:    rawMinY = anchor.anchorY - size.height
        case .center: rawMinY = anchor.anchorY - size.height / 2
        case .bottom: rawMinY = anchor.anchorY
        }
        let clampedMinY = clampPanelMinY(rawMinY, height: size.height, in: visible)

        let originX: CGFloat
        switch anchor.edge {
        case .left:  originX = visible.minX + inset
        case .right: originX = visible.maxX - size.width - inset
        }

        return NSRect(x: originX, y: clampedMinY, width: size.width, height: size.height)
    }

    /// Where the panel will snap to (in collapsed size) given its current
    /// position. Used by the drag-time ghost preview.
    private func predictedSnapFrame(for panelFrame: NSRect, on screen: NSScreen) -> NSRect {
        let v = screen.visibleFrame
        let bestEdge: ScreenEdge = (v.maxX - panelFrame.maxX) <= (panelFrame.minX - v.minX) ? .right : .left
        let (vertical, anchorY) = determineVerticalAnchor(panelFrame: panelFrame, visible: v)
        let anchor = EdgeAnchor(edge: bestEdge, vertical: vertical, anchorY: anchorY)
        return dockedCollapsedFrame(for: anchor, on: screen)
    }

    private func dockedCollapsedFrame(for anchor: EdgeAnchor, on screen: NSScreen) -> NSRect {
        let v = screen.visibleFrame
        let size = NSSize(
            width: min(collapsedSize.width, v.width),
            height: min(collapsedSize.height, v.height)
        )
        return frame(for: anchor, on: screen, size: size)
    }

    private func clampPanelMinY(_ minY: CGFloat, height: CGFloat, in visible: NSRect) -> CGFloat {
        let inset = LayoutTweaks.shared.edgeInset
        let lower = visible.minY + inset
        let upper = max(lower, visible.maxY - height - inset)
        return min(max(minY, lower), upper)
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

    // MARK: - Ghost preview

    private func showGhost() {
        guard let ghost = ghostPanel, !ghost.isVisible else { return }
        updateGhostFrame()
        ghost.alphaValue = 0
        ghost.orderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            ghost.animator().alphaValue = 1
        }
    }

    private func updateGhostFrame() {
        guard let ghost = ghostPanel,
              ghost.isVisible || isDragging,
              let panel,
              let screen = bestScreen(for: panel.frame) ?? NSScreen.main else { return }
        // Inflate around the snap target so the ghost panel can render its
        // white outer halo outside the 48×48 shape without being clipped.
        let target = predictedSnapFrame(for: panel.frame, on: screen)
            .insetBy(dx: -GhostMetrics.glowPadding, dy: -GhostMetrics.glowPadding)
        let current = ghost.frame
        // Animate large jumps (edge swap, vertical-zone change) but track
        // small continuous motion instantly so the ghost doesn't lag behind
        // the panel during ordinary dragging.
        let delta = max(abs(target.minX - current.minX), abs(target.minY - current.minY))
        if delta > 24 {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.22
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 1.0, 0.4, 1.0)
                ghost.animator().setFrame(target, display: true)
            }
        } else {
            ghost.setFrame(target, display: true)
        }
    }

    private func hideGhost() {
        guard let ghost = ghostPanel, ghost.isVisible else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            ghost.animator().alphaValue = 0
        } completionHandler: { [weak ghost] in
            MainActor.assumeIsolated {
                ghost?.orderOut(nil)
            }
        }
    }

    // MARK: - Persistence

    private func restoreOrSetDefaultAnchor() {
        if let (persisted, screen) = loadPersistedAnchor() {
            let anchor = EdgeAnchor(edge: persisted.edge, vertical: persisted.vertical, anchorY: persisted.anchorY)
            positionAtAnchor(anchor, on: screen)
            return
        }
        if let screen = NSScreen.main {
            positionAtAnchor(defaultAnchor(for: screen), on: screen)
        }
    }

    private func defaultAnchor(for screen: NSScreen) -> EdgeAnchor {
        // Top of the right edge — matches the previous first-launch position.
        return EdgeAnchor(edge: .right, vertical: .top, anchorY: screen.visibleFrame.maxY)
    }

    private func persistAnchor(_ anchor: EdgeAnchor, screen: NSScreen) {
        guard let displayID = screenID(for: screen) else { return }
        let persisted = PersistedAnchor(
            displayID: displayID,
            edge: anchor.edge,
            vertical: anchor.vertical,
            anchorY: anchor.anchorY
        )
        if let data = try? JSONEncoder().encode(persisted) {
            UserDefaults.standard.set(data, forKey: DefaultsKey.panelAnchor)
        }
    }

    private func loadPersistedAnchor() -> (PersistedAnchor, NSScreen)? {
        guard let data = UserDefaults.standard.data(forKey: DefaultsKey.panelAnchor),
              let persisted = try? JSONDecoder().decode(PersistedAnchor.self, from: data),
              let screen = NSScreen.screens.first(where: { screenID(for: $0) == persisted.displayID }) else {
            return nil
        }
        return (persisted, screen)
    }

    private func screenID(for screen: NSScreen) -> UInt32? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return screen.deviceDescription[key] as? UInt32
    }

    // MARK: - Hover

    private func handlePointerHoverChange(_ isHovered: Bool) {
        // Onboarding stage has no NSPanel, so `isPointerInsidePanel` is
        // always false — that would cause `popHoverHold()` (fired when
        // the user submits a task and the input clears) to schedule a
        // phantom collapse. Let the onboarding scene control collapse
        // explicitly instead.
        guard !isOnboardingMode else { return }
        pendingHoverWorkItem?.cancel()
        isPointerInsidePanel = pointerIsWithinHoverSafeArea()

        if isDragging {
            return
        }

        if isHovered {
            // Pointer entered the keyboard-pinned panel — release the pin so
            // subsequent hover-exit can collapse normally.
            isKeyboardPinned = false
            panel?.makeKey()
            expand()
            return
        }

        if isKeyboardPinned || isHoverHeld {
            return
        }

        scheduleHoverExitCheck(after: PanelMotion.hoverExitDelay)
    }

    private func syncHoverStateWithPointerLocation(applyState: Bool = false) {
        let isPointerInside = pointerIsWithinHoverSafeArea()
        isPointerInsidePanel = isPointerInside

        guard applyState else { return }

        if isPointerInside {
            isKeyboardPinned = false
            expand()
        } else if !isKeyboardPinned && !isHoverHeld {
            collapse()
        }
    }

    // MARK: - Hover hold

    /// Increment the hover-hold counter. While the count is positive, the
    /// panel will not auto-collapse on pointer exit. Callers must pair each
    /// push with a later `popHoverHold()`.
    func pushHoverHold() {
        hoverHoldCount += 1
        pendingHoverWorkItem?.cancel()
    }

    /// Decrement the hover-hold counter. When the count reaches zero and the
    /// pointer is outside the panel, collapse after the usual exit delay.
    func popHoverHold() {
        guard hoverHoldCount > 0 else { return }
        hoverHoldCount -= 1
        guard hoverHoldCount == 0, !isPointerInsidePanel, !isKeyboardPinned, !isDragging else { return }
        handlePointerHoverChange(false)
    }

    private func pointerIsWithinHoverSafeArea() -> Bool {
        guard let panel else { return false }
        return pointerIsWithinSafeArea(of: panel.frame)
    }

    private func pointerIsWithinSafeArea(of rect: NSRect) -> Bool {
        rect.insetBy(dx: -PanelHover.safeInset, dy: -PanelHover.safeInset)
            .contains(NSEvent.mouseLocation)
    }

    private func pointerIsWithinWindowBounds() -> Bool {
        guard let panel else { return false }
        return panel.frame.contains(NSEvent.mouseLocation)
    }

    private func scheduleHoverExitCheck(after delay: TimeInterval) {
        pendingHoverWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.syncHoverStateWithPointerLocation()
            guard !self.isDragging, !self.isKeyboardPinned, !self.isHoverHeld else { return }

            if !self.isPointerInsidePanel {
                self.collapse()
                return
            }

            // AppKit does not emit another `mouseExited` when the pointer moves
            // from the 8pt safe buffer to truly outside the panel, so keep
            // polling while we're only in that buffer zone.
            if !self.pointerIsWithinWindowBounds() {
                self.scheduleHoverExitCheck(after: PanelHover.bufferExitPollInterval)
            }
        }

        pendingHoverWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    func windowDidResize(_ notification: Notification) {
        guard !isCollapsed, !isLiveResizing else { return }
        persistExpandedSizeFromPanelFrame()
    }

    private func persistExpandedSizeFromPanelFrame() {
        guard let panel,
              !isCollapsed,
              let screen = bestScreen(for: panel.frame) ?? NSScreen.main else { return }

        let visible = screen.visibleFrame
        let size = NSSize(
            width: max(PanelResize.minimumExpandedWidth, min(panel.frame.width, visible.width)),
            height: max(PanelResize.minimumExpandedHeight, min(panel.frame.height, visible.height))
        )

        let tweaks = LayoutTweaks.shared
        if abs(tweaks.expandedWidth - size.width) > 0.5 {
            tweaks.expandedWidth = size.width
        }
        if abs(tweaks.expandedHeight - size.height) > 0.5 {
            tweaks.expandedHeight = size.height
        }

        let (vertical, anchorY) = determineVerticalAnchor(panelFrame: panel.frame, visible: visible)
        let edge = currentAnchor.edge
        let anchor = EdgeAnchor(edge: edge, vertical: vertical, anchorY: anchorY)
        currentAnchor = anchor
        persistAnchor(anchor, screen: screen)
    }
}

/// Mirrors the Paper "Ghost UI" artboard: a soft glassy rounded square with a
/// dark inset ring, a 2pt bright inner rim, and a diffuse white outer halo.
/// Exact values taken from `get_computed_styles` on the design's Rectangle.
private struct GhostView: View {
    @ObservedObject private var tweaks = LayoutTweaks.shared

    var body: some View {
        // Paper ratio: 16px corner on a 48px square. Preserve that ratio if
        // the user has tweaked the collapsed size in LayoutTweaks.
        let minEdge = min(tweaks.collapsedWidth, tweaks.collapsedHeight)
        let cornerRadius = minEdge * (16.0 / 48.0)
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        shape
            .fill(
                Color.white.opacity(0.2)
                    .shadow(.inner(color: Color.black.opacity(0.12), radius: 3))
                    .shadow(.inner(color: .white, radius: 1))
            )
            .frame(width: tweaks.collapsedWidth, height: tweaks.collapsedHeight)
            .shadow(color: Color.white.opacity(0.4), radius: 9)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
