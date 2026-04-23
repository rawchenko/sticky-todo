import SwiftUI

/// Timeline for the intro choreography. Each value is "seconds from
/// scene onAppear" (for `*Delay`) or "duration of the tween" (for
/// `*Duration` / named phases). Collected here so the full shape of the
/// intro is visible in one place instead of sprinkled through async
/// sleeps.
private enum IntroTiming {
    // Phase 0 — background dims.
    static let dimDuration: Double = 1.10
    // Phase 1 — ignition flash rises.
    static let flashRise: Double = 0.80
    // Phase 2 — halo blooms.
    static let haloDelay: Double = 0.55
    static let haloBloom: Double = 2.10
    // Phase 3 — panel is born out of the glow.
    static let panelBirthDelay: Double = 1.20
    static let panelBirth: Double = 1.50
    // Phase 4 — ignition fades.
    static let flashFadeDelay: Double = 1.50
    static let flashFade: Double = 1.20
    // Phase 5 — panel starts breathing.
    static let pulseDelay: Double = 2.40
    static let pulsePeriod: Double = 2.20
    // Hint chip arrives last.
    static let hintDelay: Double = 3.00
    static let hintFade: Double = 0.60
}

/// Scene 1 — "First contact".
/// Drives the intro animation choreography (background dim, halo bloom,
/// panel birth) by mutating the shared `ImmersiveOnboardingState`. The halo
/// and panel themselves are rendered by the root view, so they persist
/// across scene transitions. Scene 1 only overlays the hint and
/// greeting chips, and advances to Scene 2 once the greeting has
/// settled.
struct ImmersiveOnboardingFirstContactScene: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @EnvironmentObject private var state: ImmersiveOnboardingState
    @EnvironmentObject private var audio: ImmersiveOnboardingAudio
    @EnvironmentObject private var coordinator: ImmersiveOnboardingCoordinator
    @ObservedObject private var tweaks = LayoutTweaks.shared

    @State private var hintVisible = false
    @State private var greetingVisible = false
    @State private var didMount = false
    @State private var didHandleExpand = false
    /// Structured intro choreography. Cancelled in `onDisappear` so the
    /// remaining phases can't race and mutate `state` after the scene
    /// has been replaced or the window has closed.
    @State private var introTask: Task<Void, Never>?
    @State private var advanceTask: Task<Void, Never>?

    private var expanded: Bool { !state.panelManager.isCollapsed }

    var body: some View {
        ZStack {
            hintChip
                .offset(y: tweaks.collapsedHeight / 2 + 42)
                .opacity(hintVisible ? 1 : 0)
                .offset(y: hintVisible ? 0 : 18)

            greetingChip
                .offset(y: -(tweaks.expandedHeight / 2 + 44))
                .opacity((expanded && greetingVisible) ? 1 : 0)
                .offset(y: (expanded && greetingVisible) ? 0 : -6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.55), value: greetingVisible)
        .animation(reduceMotion ? nil : .easeIn(duration: 0.25), value: expanded)
        .onAppear(perform: onAppear)
        .onDisappear(perform: onDisappear)
        .onChange(of: state.panelManager.isCollapsed) { _, isCollapsed in
            guard !isCollapsed, !didHandleExpand else { return }
            didHandleExpand = true
            handleExpand()
        }
    }

    // MARK: - Chips

    private var hintChip: some View {
        Text("Hover to open")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .immersiveOnboardingChip(Capsule(style: .continuous))
            .allowsHitTesting(false)
    }

    private var greetingChip: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .semibold))
            Text("Your list is ready")
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .immersiveOnboardingChip(Capsule(style: .continuous))
        .allowsHitTesting(false)
    }

    // MARK: - Lifecycle

    private func onAppear() {
        guard !didMount else { return }
        didMount = true

        if reduceMotion {
            state.backgroundDim = 1.0
            state.orbitProgress = 1.0
            state.panelBirth = 1.0
            state.ignitionFlash = 0.0
            hintVisible = true
            return
        }

        introTask = Task { @MainActor in
            await runIntroChoreography()
        }
    }

    private func onDisappear() {
        introTask?.cancel()
        introTask = nil
        advanceTask?.cancel()
        advanceTask = nil
    }

    /// Drives the phases sequentially so each step can bail on
    /// cancellation. Returns between phases give SwiftUI room to
    /// coalesce the `withAnimation` transactions that each kick off.
    @MainActor
    private func runIntroChoreography() async {
        // Phase 0 — background dims.
        withAnimation(.easeOut(duration: IntroTiming.dimDuration)) {
            state.backgroundDim = 1.0
        }

        // Phase 1 — ignition flash + intro soundtrack.
        withAnimation(.easeOut(duration: IntroTiming.flashRise)) {
            state.ignitionFlash = 1.0
        }
        audio.playIntro()

        // Phase 2 — halo blooms.
        if await sleep(IntroTiming.haloDelay) == false { return }
        withAnimation(.easeInOut(duration: IntroTiming.haloBloom)) {
            state.orbitProgress = 1.0
        }

        // Phase 3 — panel is born out of the glow.
        if await sleep(IntroTiming.panelBirthDelay - IntroTiming.haloDelay) == false { return }
        withAnimation(.easeInOut(duration: IntroTiming.panelBirth)) {
            state.panelBirth = 1.0
        }

        // Phase 4 — ignition fades.
        if await sleep(IntroTiming.flashFadeDelay - IntroTiming.panelBirthDelay) == false { return }
        withAnimation(.easeInOut(duration: IntroTiming.flashFade)) {
            state.ignitionFlash = 0.0
        }

        // Phase 5 — panel starts breathing.
        if await sleep(IntroTiming.pulseDelay - IntroTiming.flashFadeDelay) == false { return }
        withAnimation(.easeInOut(duration: IntroTiming.pulsePeriod).repeatForever(autoreverses: true)) {
            state.panelPulse = 1.08
        }

        // Hint chip arrives last.
        if await sleep(IntroTiming.hintDelay - IntroTiming.pulseDelay) == false { return }
        guard state.panelManager.isCollapsed else { return }
        withAnimation(.easeOut(duration: IntroTiming.hintFade)) {
            hintVisible = true
        }
    }

    /// Returns `false` if the task was cancelled during the sleep — the
    /// caller should bail without mutating further. Using `try? await`
    /// would throw away the cancellation signal and keep driving phases
    /// after the scene is gone.
    private func sleep(_ seconds: Double) async -> Bool {
        do {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return !Task.isCancelled
        } catch {
            return false
        }
    }

    private func handleExpand() {
        // Dismiss the hint fast before the panel grows past it.
        withAnimation(.easeOut(duration: 0.12)) {
            hintVisible = false
        }

        let greetingDelay = reduceMotion ? 0.0 : 0.40
        let advanceDelay = reduceMotion ? 0.3 : greetingDelay + 1.40

        advanceTask = Task { @MainActor in
            if greetingDelay > 0 {
                if await sleep(greetingDelay) == false { return }
            }
            greetingVisible = true

            if await sleep(advanceDelay - greetingDelay) == false { return }
            coordinator.next()
        }
    }
}
