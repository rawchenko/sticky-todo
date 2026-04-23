import AppKit
import SwiftUI

/// Scene 3 — "Farewell".
/// Runs in two phases:
/// 1. `awaitingDismiss` — panel is expanded from Scene 2, a hint below
///    tells the user to move their cursor off the panel. On cursor
///    exit the panel collapses **in place** (no travel yet) so the
///    user experiences the app's natural hover-expand / leave-collapse
///    loop without being rushed through.
/// 2. `allSet` — the collapsed panel sits in the middle, free for the
///    user to hover-expand / leave-collapse as they please. A
///    confirmation chip ("You're all set") appears above and a primary
///    Continue button below. Only when the user presses Continue does
///    the panel fly to the top-right corner and the window closes.
struct AltSceneFarewell: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @EnvironmentObject private var state: AltOnboardingState
    @ObservedObject private var tweaks = LayoutTweaks.shared

    var onFinish: () -> Void

    enum Phase: Equatable {
        case awaitingDismiss
        case allSet
        case departing
    }

    @State private var didMount = false
    @State private var phase: Phase = .awaitingDismiss
    @State private var dismissHintVisible = false
    @State private var allSetChipVisible = false
    @State private var continueButtonVisible = false
    @State private var pendingWork: [Task<Void, Never>] = []

    /// Grace period after the scene appears before we start listening
    /// for unhover. The user finished Scene 2 by clicking the checkbox,
    /// so their cursor is on the panel — without the grace the scene
    /// would dismiss the moment they moved to read the hint.
    private let hoverGracePeriod: TimeInterval = 0.8
    @State private var graceElapsed = false

    /// How long the panel takes to fly to the corner when Continue is
    /// pressed. Slower than production's docking animation so the
    /// handoff reads as a deliberate goodbye, not a snap-close.
    private let departureDuration: TimeInterval = 1.50

    var body: some View {
        ZStack {
            // Top slot — "Move your cursor off" (phase 1) and
            // "You're all set" (phase 2) share the same on-screen
            // position so the transition reads as a prompt update.
            dismissHintChip
                .offset(y: -(tweaks.expandedHeight / 2 + 44))
                .opacity(phase == .awaitingDismiss && dismissHintVisible ? 1 : 0)
                .offset(y: (phase == .awaitingDismiss && dismissHintVisible) ? 0 : -6)

            allSetChip
                .offset(y: -(tweaks.expandedHeight / 2 + 44))
                .opacity(phase == .allSet && allSetChipVisible ? 1 : 0)
                .offset(y: (phase == .allSet && allSetChipVisible) ? 0 : -6)

            // Bottom slot — Continue button, phase 2 only.
            continueButton
                .offset(y: tweaks.expandedHeight / 2 + 56)
                .opacity(continueButtonVisible ? 1 : 0)
                .offset(y: continueButtonVisible ? 0 : 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.45),
            value: dismissHintVisible
        )
        .animation(
            reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.78),
            value: allSetChipVisible
        )
        .animation(
            reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.82),
            value: continueButtonVisible
        )
        .onAppear(perform: onAppear)
        .onDisappear(perform: onDisappear)
        .onChange(of: state.isPanelHovered) { _, hovering in
            handleHoverChange(hovering: hovering)
        }
    }

    // MARK: - Chips

    private var dismissHintChip: some View {
        HStack(spacing: 6) {
            Image(systemName: "cursorarrow.motionlines")
                .font(.system(size: 11, weight: .semibold))
            Text("Move your cursor off to collapse it")
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .altOnboardingChip(Capsule(style: .continuous))
        .allowsHitTesting(false)
    }

    private var allSetChip: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .semibold))
            Text("You're all set")
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .altOnboardingChip(Capsule(style: .continuous))
        .allowsHitTesting(false)
    }

    // MARK: - Continue button

    @ViewBuilder
    private var continueButton: some View {
        if #available(macOS 26.0, *) {
            Button(action: handleContinue) {
                HStack(spacing: 6) {
                    Text("Continue")
                        .font(.system(size: 14, weight: .semibold))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .bold))
                }
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .buttonBorderShape(.capsule)
        } else {
            Button(action: handleContinue) {
                HStack(spacing: 6) {
                    Text("Continue")
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .bold))
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    // MARK: - Lifecycle

    private func onAppear() {
        guard !didMount else { return }
        didMount = true

        // Mark that the user reached the final scene. The window reads
        // this on close to decide whether to migrate the onboarding
        // tasks into the real Inbox.
        state.didReachFarewell = true

        if reduceMotion {
            dismissHintVisible = true
            graceElapsed = true
            if !state.isPanelHovered, phase == .awaitingDismiss {
                collapseInPlace()
            }
            return
        }

        let hintTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            dismissHintVisible = true
        }
        pendingWork.append(hintTask)

        let graceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(hoverGracePeriod * 1_000_000_000))
            if Task.isCancelled { return }
            graceElapsed = true
            if !state.isPanelHovered, phase == .awaitingDismiss {
                collapseInPlace()
            }
        }
        pendingWork.append(graceTask)
    }

    private func onDisappear() {
        for task in pendingWork { task.cancel() }
        pendingWork.removeAll()
    }

    // MARK: - Hover

    private func handleHoverChange(hovering: Bool) {
        switch phase {
        case .awaitingDismiss:
            guard graceElapsed, !hovering else { return }
            collapseInPlace()
        case .allSet:
            // Free-play: expand is driven by the root view's onHover.
            // Collapse-on-leave lives here so the user experiences the
            // full hover-expand / leave-collapse loop they'll use
            // day-to-day.
            guard !hovering, !state.panelManager.isCollapsed else { return }
            withAnimation(reduceMotion ? nil : PanelMotion.stateAnimation) {
                state.panelManager.isCollapsed = true
            }
        case .departing:
            break
        }
    }

    // MARK: - Transitions

    private func collapseInPlace() {
        guard phase == .awaitingDismiss else { return }
        phase = .allSet
        dismissHintVisible = false

        withAnimation(reduceMotion ? nil : PanelMotion.stateAnimation) {
            state.panelManager.isCollapsed = true
        }

        // Let the collapse settle a touch before the reward chip and
        // Continue button land — reads as "good, now here's what's
        // next" rather than flashing everything at once.
        let delay: TimeInterval = reduceMotion ? 0.05 : 0.4
        let showTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            if Task.isCancelled { return }
            allSetChipVisible = true
            continueButtonVisible = true
        }
        pendingWork.append(showTask)
    }

    private func handleContinue() {
        guard phase == .allSet else { return }
        phase = .departing

        // Hide the reward UI first so it doesn't trail the flying
        // panel — same reason the old scheduleDeparture did this.
        allSetChipVisible = false
        continueButtonVisible = false

        scheduleFly()
    }

    // MARK: - Fly to corner

    private func scheduleFly() {
        // Stop the Scene 1 breathing animation before the fly so the
        // collapsed panel lands at its natural 1.0 scale — otherwise
        // it oscillates through ±8% while travelling and the real
        // panel (which has no pulse) appears at a slightly different
        // size, reading as a jump at the moment of handoff.
        var stopPulseTxn = Transaction(animation: nil)
        stopPulseTxn.disablesAnimations = true
        withTransaction(stopPulseTxn) {
            state.panelPulse = 1.0
        }

        // Compute the landing target so the collapsed panel lands at
        // the same docked top-right slot `PanelManager` uses — the
        // real panel then takes over at that exact rect with no jump.
        let screen = NSScreen.main
        let fullFrame = screen?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let visibleFrame = screen?.visibleFrame ?? fullFrame
        let menuBarHeight = max(0, fullFrame.maxY - visibleFrame.maxY)
        let edgeInset = tweaks.edgeInset
        let panelHalfW = tweaks.collapsedWidth / 2
        let panelHalfH = tweaks.collapsedHeight / 2
        let targetX = fullFrame.width / 2 - panelHalfW - edgeInset
        let targetY = -(fullFrame.height / 2 - panelHalfH - edgeInset - menuBarHeight)
        state.farewellTarget = CGSize(width: targetX, height: targetY)

        if reduceMotion {
            state.panelManager.isCollapsed = true
            state.farewellProgress = 1.0
            state.orbitProgress = 0.0
            state.backgroundDim = 0.0
            onFinish()
            return
        }

        // If the user happened to be hovering the panel when they hit
        // Continue, make sure it collapses for the flight.
        if !state.panelManager.isCollapsed {
            withAnimation(PanelMotion.stateAnimation) {
                state.panelManager.isCollapsed = true
            }
        }

        // Fade the halo on its own quicker curve so the blobs don't
        // drag a trail behind the travelling panel.
        withAnimation(.easeOut(duration: 0.6)) {
            state.orbitProgress = 0.0
        }

        withAnimation(.easeInOut(duration: departureDuration)) {
            state.farewellProgress = 1.0
            state.backgroundDim = 0.0
        }

        let closeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64((departureDuration + 0.15) * 1_000_000_000))
            if Task.isCancelled { return }
            onFinish()
        }
        pendingWork.append(closeTask)
    }
}
