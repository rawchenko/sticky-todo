import SwiftUI

/// Ordered phases of the Immersive onboarding flow. Each case drives exactly
/// one scene view in `ImmersiveOnboardingRootView.sceneOverlay`; ordering is
/// significant — `next()` / `back()` walk the declaration order.
enum ImmersiveOnboardingScene: Int, CaseIterable {
    case firstContact
    case firstCapture
    case farewell
}

/// Styling shared across every chip in the Immersive onboarding stage.
///
/// `.glassEffect(.regular, ...)` samples the window-level backdrop
/// and (critically) ignores whatever's attached via `.background` on
/// the same view — so tinting the glass or painting a glow under it
/// both failed to make chips visually match the panel, which reads
/// warm cream from the halo that sits under it as a sibling layer.
///
/// Giving chips a theme-aware solid fill side-steps sampling
/// entirely: a warm cream pill in Light, a warm-dark pill in Dark.
/// Both feel like they belong to the same family as the panel
/// without depending on what's behind them on the stage.
enum ImmersiveOnboardingChip {
    static let fill = Color.dynamic(
        light: Color(red: 1.0, green: 0.93, blue: 0.81).opacity(0.88),
        dark: Color(red: 0.22, green: 0.17, blue: 0.12).opacity(0.88)
    )

    static let border = Color.dynamic(
        light: Color.white.opacity(0.55),
        dark: Color.white.opacity(0.10)
    )

}

extension View {
    /// Applies the shared Immersive onboarding pill style — solid
    /// theme-aware fill + hairline border. Use in place of
    /// `.liquidGlass(Capsule(...))` for chips on the stage.
    func immersiveOnboardingChip<S: InsettableShape>(_ shape: S) -> some View {
        self
            .background(shape.fill(ImmersiveOnboardingChip.fill))
            .overlay(shape.strokeBorder(ImmersiveOnboardingChip.border, lineWidth: 0.5))
    }
}

@MainActor
final class ImmersiveOnboardingCoordinator: ObservableObject {
    @Published var scene: ImmersiveOnboardingScene = .firstContact

    var isLast: Bool { scene == ImmersiveOnboardingScene.allCases.last }

    func next() {
        guard let idx = ImmersiveOnboardingScene.allCases.firstIndex(of: scene),
              idx + 1 < ImmersiveOnboardingScene.allCases.count
        else { return }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
            scene = ImmersiveOnboardingScene.allCases[idx + 1]
        }
    }

    func back() {
        guard let idx = ImmersiveOnboardingScene.allCases.firstIndex(of: scene),
              idx > 0
        else { return }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
            scene = ImmersiveOnboardingScene.allCases[idx - 1]
        }
    }
}

/// Full-screen transparent stage. Chrome is stripped — only the scene is
/// visible, and a discreet corner affordance for closing. The persistent
/// visual layers (dim, halo, panel) live here so they survive scene
/// transitions uninterrupted; scenes add their own overlay on top.
struct ImmersiveOnboardingRootView: View {
    /// Shared state is owned by `ImmersiveOnboardingWindow` so migration on
    /// close can see the final task list without fighting SwiftUI's
    /// view-lifecycle dealloc timing.
    @ObservedObject var state: ImmersiveOnboardingState
    var onFinish: () -> Void

    @StateObject private var coordinator = ImmersiveOnboardingCoordinator()
    @StateObject private var audio = ImmersiveOnboardingAudio()
    @ObservedObject private var tweaks = LayoutTweaks.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Target opacity for the full-stage dimming layer (multiplied by
    /// `state.backgroundDim` to get the displayed value).
    private static let targetDim: CGFloat = 0.80

    var body: some View {
        ZStack(alignment: .topLeading) {
            stage
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            closeAffordance
                .padding(.top, tweaks.edgeInset)
                .padding(.leading, tweaks.edgeInset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
        .environmentObject(coordinator)
        .environmentObject(audio)
        .environmentObject(state)
        .environmentObject(state.mode)
        .environmentObject(state.scriptedInput)
    }

    @ViewBuilder
    private var stage: some View {
        ZStack {
            backgroundDim
            meshHalo
                .offset(
                    x: state.farewellProgress * state.farewellTarget.width,
                    y: state.farewellProgress * state.farewellTarget.height
                )
            panel
            sceneOverlay
        }
    }

    // MARK: - Persistent layers

    private var backgroundDim: some View {
        Color.black
            .opacity(Double(state.backgroundDim) * Double(Self.targetDim))
            .ignoresSafeArea()
    }

    private var expanded: Bool { !state.panelManager.isCollapsed }

    @ViewBuilder
    private var meshHalo: some View {
        ZStack {
            // Soft warm bed — fills the middle so the metaball orbit
            // doesn't leave a visible donut hole around the panel.
            //
            // Gradient `endRadius` and `frame` don't interpolate across
            // state changes, so expand/collapse used to pop. Hold both
            // at the expanded size and drive the change via
            // `scaleEffect` — that's animatable and stays in lockstep
            // with the metaballs, which already scale the same way.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 1.0, green: 0.58, blue: 0.25).opacity(0.32),
                            .clear,
                        ],
                        center: .center,
                        startRadius: 10,
                        endRadius: 260
                    )
                )
                .blur(radius: 40)
                .frame(width: 560, height: 560)
                .scaleEffect(expanded ? 1.0 : 440.0 / 560.0)
                .opacity(Double(state.orbitProgress))
                .animation(PanelMotion.stateAnimation, value: expanded)

            // Colored metaballs — three warm hues stacked. Always orbiting
            // at full radius; the intro bloom is driven by the outer
            // scaleEffect so the alpha-threshold merge stays smooth.
            metaballs(radiusScale: expanded ? 1.42 : 1.0)
                .frame(width: 640, height: 540)
                .mask(
                    RadialGradient(
                        colors: [.white, .white.opacity(0.7), .clear],
                        center: .center,
                        startRadius: 30,
                        endRadius: 240
                    )
                )
                .blur(radius: 28)
                // Bloom scale only tracks intro progress. Do not tie this
                // to panel expand/collapse: scaling the whole metaball
                // field while the blobs orbit makes them look like they
                // speed up compared with their idle motion.
                .scaleEffect(
                    state.farewellProgress > 0
                        ? 1.0
                        : 0.35 + 0.65 * state.orbitProgress
                )
                .opacity(Double(state.orbitProgress))
                .animation(PanelMotion.stateAnimation, value: expanded)

            // Ignition flash — bright warm core that peaks on entry and
            // fades as the halo blooms outward.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 1.0, green: 0.92, blue: 0.75).opacity(0.95),
                            Color(red: 1.0, green: 0.68, blue: 0.30).opacity(0.35),
                            .clear,
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 150
                    )
                )
                .blur(radius: 22)
                .frame(width: 300, height: 300)
                .opacity(Double(state.ignitionFlash))
        }
        // Give the halo room for the blur/gradient spill so the
        // rasterized bounds don't clip the glow at the edges.
        .frame(width: 900, height: 900)
        // Rasterize the halo to a single Metal layer so the soft warm
        // bed, metaballs Canvas, and ignition flash translate as one
        // unit during the farewell flight. The metaballs orbit is
        // frozen (see `farewellFrozenTime`) once the flight starts, so
        // this rasterization happens once and is translated cheaply —
        // no per-frame Metal cost.
        .drawingGroup()
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func metaballs(radiusScale: CGFloat) -> some View {
        if reduceMotion {
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 1.0, green: 0.55, blue: 0.20).opacity(0.55),
                            .clear,
                        ],
                        center: .center,
                        startRadius: 20,
                        endRadius: 240
                    )
                )
                .blur(radius: 50)
        } else if state.orbitProgress < 0.01 {
            // Halo is fully faded (pre-intro or post-farewell). Skip
            // the Canvas animation entirely so we don't pay the 60fps
            // compositing cost for something that's invisible anyway.
            EmptyView()
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
                // Freeze the orbit during the farewell flight so the
                // halo's `drawingGroup` rasterizes once and translates
                // cheaply — live 60fps redraws during flight cause the
                // outer offset animation to race the Canvas redraws,
                // which leaves some blobs fading in place at center.
                let t = state.farewellProgress > 0
                    ? state.farewellFrozenTime
                    : context.date.timeIntervalSinceReferenceDate
                ZStack {
                    MetaballCanvasLayer(t: t, color: Color(red: 1.0, green: 0.42, blue: 0.12), seed: 0.0, speed: 0.375, radiusScale: radiusScale).opacity(0.66)
                    MetaballCanvasLayer(t: t, color: Color(red: 1.0, green: 0.66, blue: 0.25), seed: 1.8, speed: -0.525, radiusScale: radiusScale).opacity(0.58)
                    MetaballCanvasLayer(t: t, color: Color(red: 1.0, green: 0.84, blue: 0.55), seed: 3.6, speed: 0.65, radiusScale: radiusScale).opacity(0.54)
                }
            }
        }
    }

    private struct MetaballCanvasLayer: View, Animatable {
        let t: Double
        let color: Color
        let seed: Double
        let speed: Double
        var radiusScale: CGFloat

        var animatableData: CGFloat {
            get { radiusScale }
            set { radiusScale = newValue }
        }

        private let blobs: [(radius: CGFloat, orbit: CGFloat, phase: Double, wobble: CGFloat)] = [
            (70, 40,  0.0, 46),
            (85, 130, 1.7, 34),
            (55, 160, 3.1, 44),
            (75, 85,  4.5, 38),
            (60, 110, 2.4, 42),
        ]

        var body: some View {
            Canvas { context, size in
            context.addFilter(.alphaThreshold(min: 0.40, color: color))
            context.addFilter(.blur(radius: 44))
            context.drawLayer { layer in
                let cx = size.width / 2
                let cy = size.height / 2
                for (i, blob) in blobs.enumerated() {
                    let blobDir: Double = (i % 2 == 0) ? 1.0 : -1.0
                    let a = t * speed * blobDir + blob.phase + seed
                    let x = cx + cos(a) * blob.orbit + sin(a * 0.73) * blob.wobble
                    let y = cy + sin(a) * blob.orbit + cos(a * 0.81) * blob.wobble
                    let r = blob.radius * radiusScale
                    let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
                    layer.fill(Path(ellipseIn: rect), with: .color(.white))
                }
            }
        }
        }
    }

    // MARK: - Panel

    /// The real panel. Hit testing is enabled in Scene 2+ via the mode
    /// gates; Scene 1's collapsed state lets the `onHover` below trigger
    /// expand without actually letting the user mutate the store.
    private var panel: some View {
        ContentView(store: state.store, panelManager: state.panelManager)
            .frame(
                width: expanded ? tweaks.expandedWidth : tweaks.collapsedWidth,
                height: expanded ? tweaks.expandedHeight : tweaks.collapsedHeight
            )
            .scaleEffect(expanded ? 1.0 : state.panelPulse)
            .compositingGroup()
            // The real NSPanel renders a subtle rim highlight at the
            // edge of its Liquid Glass material — an effect the window
            // server adds around opaque windows with `hasShadow = true`.
            // Our fake panel lives inside a borderless transparent
            // window without that treatment, so the edge looks "naked"
            // next to the real panel at handoff. Paint the hairline in
            // explicitly, using the same morphing shape so it animates
            // alongside expand/collapse.
            .overlay(
                MorphingDockedShape(
                    expansion: expanded ? 1.0 : 0.0,
                    handleRadius: tweaks.handleCornerRadius,
                    panelRadius: tweaks.panelCornerRadius
                )
                .stroke(FloatListTheme.hairline.opacity(0.55), lineWidth: 0.5)
                .allowsHitTesting(false)
            )
            // Approximate the real NSPanel's `hasShadow = true` drop
            // shadow so the handoff to the live panel at landing has
            // no visible shadow-pop. Uses the app's theme-aware
            // `panelShadow` helper (dark mode attenuation) to match
            // what TodoRowView and the production panel use.
            .shadow(color: FloatListTheme.panelShadow(opacity: 0.22), radius: 20, y: 10)
            .shadow(color: FloatListTheme.panelShadow(opacity: 0.10), radius: 3, y: 1)
            .animation(PanelMotion.stateAnimation, value: state.panelManager.isCollapsed)
            .opacity(Double(state.panelBirth))
            .scaleEffect(0.55 + 0.45 * state.panelBirth)
            .offset(
                x: state.farewellProgress * state.farewellTarget.width,
                y: (1 - state.panelBirth) * 14
                    + state.farewellProgress * state.farewellTarget.height
            )
            .focusable(false)
            .accessibilityElement(children: .contain)
            .onHover { hovering in
                state.isPanelHovered = hovering
                // Scene 1 uses hover-enter to trigger expand. The
                // panelBirth gate stops a cursor that happens to be
                // over the panel's frame during the intro animation
                // from yanking it open before the birth sequence
                // finishes. In reduce-motion panelBirth is 1.0 from
                // the start, so that path keeps working unchanged.
                guard state.panelBirth >= 1.0 else { return }
                if hovering, state.panelManager.isCollapsed {
                    state.panelManager.expand()
                }
            }
    }

    // MARK: - Scene overlay

    @ViewBuilder
    private var sceneOverlay: some View {
        Group {
            switch coordinator.scene {
            case .firstContact:
                ImmersiveOnboardingFirstContactScene()
            case .firstCapture:
                ImmersiveOnboardingFirstCaptureScene()
            case .farewell:
                ImmersiveOnboardingFarewellScene(onFinish: onFinish)
            }
        }
        .id(coordinator.scene)
        .transition(
            .asymmetric(
                insertion: .opacity.combined(with: .offset(y: 6)),
                removal: .opacity
            )
        )
    }

    private var closeAffordance: some View {
        Button(action: onFinish) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .bold))
                .frame(width: 28, height: 28)
                .foregroundStyle(.secondary)
                .liquidGlass(Circle(), interactive: true)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.cancelAction)
        .help("Close (⌘W)")
    }
}
