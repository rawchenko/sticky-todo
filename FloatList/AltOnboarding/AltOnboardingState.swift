import Combine
import SwiftUI

/// Shared state for the Alt Onboarding flow. Lives at the root-view level
/// so it survives scene transitions — the TodoStore, PanelManager, and
/// intro-animation progress all persist as the user moves from Scene 1
/// (first contact) to Scene 2 (first capture) and beyond.
///
/// The intro animation runs in Scene 1 and mutates the progress values
/// here; Scene 1 and the root view both observe them. After Scene 1
/// completes, the values stay at their terminal states (orbit=1, dim=1,
/// panelBirth=1, ignitionFlash=0) for the remainder of the onboarding.
@MainActor
final class AltOnboardingState: ObservableObject {
    /// In-memory store populated during the flow. Never touches the
    /// user's real TodoStore; at finish, tasks migrate to the real Inbox.
    let store: TodoStore

    let panelManager: PanelManager
    let scriptedInput = ScriptedInputBuffer()
    let mode = OnboardingMode(isActive: true)

    // MARK: - Intro animation state

    @Published var backgroundDim: CGFloat = 0.0   // 0 = transparent, 1 = target (0.80 × 1)
    @Published var orbitProgress: CGFloat = 0.0   // 0 = blobs stacked, 1 = full orbit
    @Published var ignitionFlash: CGFloat = 0.0   // peaks then fades at start
    @Published var panelBirth: CGFloat = 0.0      // 0 = absent, 1 = materialized
    @Published var panelPulse: CGFloat = 1.0      // collapsed-state breathing scale

    // MARK: - Interaction state

    /// Tracks whether the cursor is currently over the panel. Scene 3
    /// watches this to know when the user has moved their cursor away,
    /// which is the gesture that dismisses the onboarding.
    @Published var isPanelHovered: Bool = false

    /// ID of the first task the user created during onboarding, used
    /// as the pulse target in Scene 2 and as a reference during later
    /// phases. Set once by Scene 2 on first `store.items` insertion.
    @Published var firstTaskID: UUID?

    // MARK: - Farewell animation

    /// 0 = at rest (centered), 1 = fully flown to the top-right corner.
    /// Both a translation and the panel collapse are driven by the same
    /// `withAnimation` in Scene 3 so they move in sync.
    @Published var farewellProgress: CGFloat = 0.0

    /// Target offset for the farewell flight, computed at the moment the
    /// animation starts so it matches the current screen dimensions.
    @Published var farewellTarget: CGSize = .zero

    /// Flipped by Scene 3 on mount. The window uses this on close to
    /// decide whether to migrate the in-memory tasks into the real Inbox
    /// — early ⌘W or close in Scene 1/2 should leave the real store
    /// untouched, since those sessions are exploratory.
    @Published var didReachFarewell: Bool = false

    private var cancellables: Set<AnyCancellable> = []

    init() {
        self.store = TodoStore(inMemory: true)
        let pm = PanelManager(isOnboardingMode: true)
        pm.isCollapsed = true
        self.panelManager = pm

        // Forward nested-observable changes so anything observing this
        // state also re-renders when `store`, `panelManager`, or `mode`
        // publishes. Without this, root view's derived `expanded` (which
        // reads panelManager.isCollapsed) never refreshes on hover.
        for observable in [
            store.objectWillChange.eraseToAnyPublisher(),
            panelManager.objectWillChange.eraseToAnyPublisher(),
            mode.objectWillChange.eraseToAnyPublisher(),
        ] {
            observable.sink { [weak self] _ in
                self?.objectWillChange.send()
            }.store(in: &cancellables)
        }
    }
}
