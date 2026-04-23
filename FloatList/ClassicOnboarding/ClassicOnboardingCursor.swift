import SwiftUI
import AppKit

/// Targets the faux onboarding cursor can travel to. Coordinates are resolved
/// at call-time against the current desktop-mock size and the panel's
/// collapsed/expanded state, so the same target name works across steps.
enum ClassicOnboardingCursorTarget {
    case resting
    case panelHandle
    case panelEdge
    case inputField
    case firstRowCheckbox
}

enum ClassicOnboardingCursorGesture: Equatable {
    case idle
    case press
}

/// Drives the position and gesture state of the scripted cursor overlay in the
/// onboarding demo column. Purely decorative — never touches the real
/// `NSCursor` and ignores all hit testing.
@MainActor
final class ClassicOnboardingCursorController: ObservableObject {
    @Published private(set) var position: CGPoint = .zero
    @Published private(set) var gesture: ClassicOnboardingCursorGesture = .idle
    @Published private(set) var isVisible: Bool = false
    /// Monotonic counter the overlay watches to spawn a new click ripple.
    @Published private(set) var rippleTrigger: Int = 0

    private let tweaks: ClassicOnboardingTweaks
    private var currentMockSize: CGSize = .zero
    private var currentPanelCollapsed: Bool = true
    /// Completes when the most recent `hide()` has finished its fade-out so
    /// that `show()` can safely snap a new position with opacity guaranteed
    /// to be zero. Without this gate, a rapid hide→show (e.g. Back button
    /// straight after a scene ended) let us snap the arrow to a new mock-
    /// local coordinate while the previous opacity was still ~0.5, producing
    /// a visible teleport across the card.
    private var pendingHideFade: Task<Void, Never>?

    init(tweaks: ClassicOnboardingTweaks = .shared) {
        self.tweaks = tweaks
    }

    // MARK: Visibility

    func show(at target: ClassicOnboardingCursorTarget, in size: CGSize, panelCollapsed: Bool) async {
        // Drain any in-flight fade-out before snapping the new position; the
        // arrow is only truly invisible once that fade is complete.
        if let pending = pendingHideFade {
            _ = await pending.value
        }
        pendingHideFade = nil

        currentMockSize = size
        currentPanelCollapsed = panelCollapsed
        // Belt-and-braces: force state to match "hidden" before snapping, so
        // even if the animation above was somehow interrupted opacity is 0.
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) {
            isVisible = false
            position = point(for: target)
            gesture = .idle
        }
        withAnimation(.easeInOut(duration: Double(tweaks.cursorFadeDuration))) {
            isVisible = true
        }
    }

    func hide() {
        guard isVisible || pendingHideFade != nil else { return }
        gesture = .idle
        let duration = Double(tweaks.cursorFadeDuration)
        withAnimation(.easeInOut(duration: duration)) {
            isVisible = false
        }
        pendingHideFade?.cancel()
        pendingHideFade = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
        }
    }

    // MARK: Motion

    func move(
        to target: ClassicOnboardingCursorTarget,
        in size: CGSize,
        panelCollapsed: Bool
    ) async {
        currentMockSize = size
        currentPanelCollapsed = panelCollapsed
        let destination = point(for: target)
        let spring = Animation.spring(
            response: tweaks.cursorMoveSpringResponse,
            dampingFraction: tweaks.cursorMoveSpringDamping
        )
        withAnimation(spring) {
            position = destination
        }
        let nanos = UInt64(max(0, Double(tweaks.cursorMoveDuration)) * 1_000_000_000)
        try? await Task.sleep(nanoseconds: nanos)
    }

    func press() async {
        withAnimation(.spring(response: 0.18, dampingFraction: 0.72)) {
            gesture = .press
        }
        rippleTrigger &+= 1
        try? await Task.sleep(nanoseconds: 180_000_000)
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            gesture = .idle
        }
        try? await Task.sleep(nanoseconds: 140_000_000)
    }

    // MARK: Position math

    private func point(for target: ClassicOnboardingCursorTarget) -> CGPoint {
        switch target {
        case .resting:
            return CGPoint(x: tweaks.cursorRestingX, y: tweaks.cursorRestingY)
        case .panelHandle:
            let rect = collapsedPanelRect()
            return CGPoint(x: rect.midX, y: rect.midY)
        case .panelEdge:
            let rect = expandedPanelRect()
            return CGPoint(
                x: rect.minX + tweaks.cursorPanelEdgeInsetX,
                y: rect.minY + rect.height * 0.5 + tweaks.cursorPanelEdgeInsetY
            )
        case .inputField:
            let rect = expandedPanelRect()
            return CGPoint(
                x: rect.minX + tweaks.cursorInputFieldInsetX,
                y: rect.maxY + tweaks.cursorInputFieldInsetY
            )
        case .firstRowCheckbox:
            let rect = expandedPanelRect()
            return CGPoint(
                x: rect.minX + tweaks.cursorCheckboxInsetX,
                y: rect.minY + tweaks.cursorCheckboxInsetY
            )
        }
    }

    /// Top-right-anchored docked panel rect in mock-local coordinates.
    /// Matches the layout in `ClassicOnboardingDesktopMock`: 28pt menubar + 18pt
    /// inset from the top and right edges.
    private func expandedPanelRect() -> CGRect {
        let w = ClassicOnboardingLayout.demoExpandedWidth
        let h = ClassicOnboardingLayout.demoExpandedHeight
        let x = max(currentMockSize.width - w - 18, 0)
        let y: CGFloat = 28 + 18
        return CGRect(x: x, y: y, width: w, height: h)
    }

    private func collapsedPanelRect() -> CGRect {
        let w = ClassicOnboardingLayout.demoCollapsedWidth
        let h = ClassicOnboardingLayout.demoCollapsedHeight
        let x = max(currentMockSize.width - w - 18, 0)
        let y: CGFloat = 28 + 18
        return CGRect(x: x, y: y, width: w, height: h)
    }
}

/// Overlay view that renders the cursor arrow and any in-flight click ripples
/// inside the desktop mock. Positions come from the controller in mock-local
/// coordinates, so this view must be placed inside a container that matches
/// the mock's coordinate space (i.e., inside `ClassicOnboardingDesktopMock`).
struct ClassicOnboardingCursorOverlay: View {
    @ObservedObject var controller: ClassicOnboardingCursorController
    @ObservedObject var tweaks: ClassicOnboardingTweaks

    @State private var pulses: [Pulse] = []

    private struct Pulse: Identifiable, Equatable {
        let id: Int
        let origin: CGPoint
    }

    // Pulled once — the system arrow image is stable for the app's lifetime.
    private static let systemCursorImage: NSImage = NSCursor.arrow.image
    private static let systemCursorHotSpot: CGPoint = NSCursor.arrow.hotSpot

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(pulses) { pulse in
                RippleCircle()
                    .position(pulse.origin)
            }
            cursorShape
                .position(controller.position)
                .opacity(controller.isVisible ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: controller.rippleTrigger) { _, newValue in
            guard controller.isVisible else { return }
            let pulse = Pulse(id: newValue, origin: controller.position)
            pulses.append(pulse)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 560_000_000)
                pulses.removeAll { $0.id == newValue }
            }
        }
    }

    /// macOS system arrow, offset so the image's hotSpot lands exactly at
    /// `.position(controller.position)`. Scale shrinks around that hotSpot so
    /// a press pulse stays anchored to the visual tip.
    private var cursorShape: some View {
        let pressed = controller.gesture == .press
        let image = Self.systemCursorImage
        let hotSpot = Self.systemCursorHotSpot
        let size = image.size
        // `.position` centers a view at the target. We need the hotSpot (not
        // the frame center) to land at the target, so shift the image render
        // by (half the frame) - (hotSpot) inside its own frame.
        let dx = size.width / 2 - hotSpot.x
        let dy = size.height / 2 - hotSpot.y
        // Anchor for scale: the hotSpot expressed as a UnitPoint within the
        // image's own bounds, so "press" shrink visually pins to the tip.
        let anchor = UnitPoint(
            x: size.width > 0 ? hotSpot.x / size.width : 0,
            y: size.height > 0 ? hotSpot.y / size.height : 0
        )
        return Image(nsImage: image)
            .interpolation(.high)
            .offset(x: dx, y: dy)
            .frame(width: size.width, height: size.height)
            .scaleEffect(pressed ? 0.86 : 1.0, anchor: anchor)
            .animation(.spring(response: 0.22, dampingFraction: 0.72), value: controller.gesture)
    }
}

/// Expanding click ripple. Self-animates on appear, leaves behind no state —
/// the overlay removes it after the animation window closes.
private struct RippleCircle: View {
    @State private var scale: CGFloat = 0.25
    @State private var opacity: Double = 0.7

    var body: some View {
        Circle()
            .stroke(Color.white.opacity(0.95), lineWidth: 2)
            .frame(width: 22, height: 22)
            .scaleEffect(scale)
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeOut(duration: 0.5)) {
                    scale = 2.6
                    opacity = 0
                }
            }
    }
}
