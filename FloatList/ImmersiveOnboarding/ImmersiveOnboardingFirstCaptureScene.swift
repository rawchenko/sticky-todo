import SwiftUI

/// Scene 2 — "First capture".
/// Two interactive phases share the same stage:
///   1. **awaitingTask** — user types their first task (or several) and
///      hits return. Prompt: "Type your first task and press return".
///   2. **awaitingCompletion** — the first task's checkbox starts
///      pulsing, the `.completeToggle` gate opens, and a new prompt
///      invites the user to mark it done. User can still add more
///      tasks freely during this phase.
///
/// The moment any task becomes completed, the scene advances to the
/// farewell (Scene 3).
struct ImmersiveOnboardingFirstCaptureScene: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @EnvironmentObject private var state: ImmersiveOnboardingState
    @EnvironmentObject private var coordinator: ImmersiveOnboardingCoordinator
    @ObservedObject private var tweaks = LayoutTweaks.shared

    enum Phase {
        case awaitingTask
        case awaitingCompletion
    }

    @State private var didMount = false
    @State private var phase: Phase = .awaitingTask
    @State private var promptVisible = false
    @State private var baselineCount = 0
    /// Deferred work scheduled by this scene (prompt fade-in, advance to
    /// farewell). Cancelled on disappear so it can't fire into a dead
    /// scene or a window that's already closing.
    @State private var pendingWork: [Task<Void, Never>] = []

    var body: some View {
        ZStack {
            activePromptChip
                .offset(y: tweaks.expandedHeight / 2 + 44)
                .opacity(promptVisible ? 1 : 0)
                .offset(y: promptVisible ? 0 : 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.55), value: promptVisible)
        .onAppear(perform: onAppear)
        .onDisappear(perform: onDisappear)
        .onChange(of: state.store.items.count) { _, newCount in
            handleItemCountChange(newCount: newCount)
        }
        .onChange(of: state.store.items.contains(where: { $0.isCompleted })) { _, anyDone in
            if anyDone { handleTaskCompletion() }
        }
    }

    // MARK: - Chips

    /// The phase-driven chip. `.id(phase)` forces SwiftUI to treat each
    /// phase's chip as a distinct view so the `.transition` can swap
    /// them instead of silently mutating the Text — a pure text swap
    /// reads as a glitch on a small capsule.
    @ViewBuilder
    private var activePromptChip: some View {
        Group {
            switch phase {
            case .awaitingTask:
                typingPromptChip
            case .awaitingCompletion:
                completionPromptChip
            }
        }
        .id(phase)
        .transition(
            .asymmetric(
                insertion: .opacity.combined(with: .offset(y: 10)),
                removal: .opacity.combined(with: .offset(y: -10))
            )
        )
    }

    private var typingPromptChip: some View {
        HStack(spacing: 6) {
            Image(systemName: "text.cursor")
                .font(.system(size: 11, weight: .semibold))
            Text("Type your first task and press return")
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .immersiveOnboardingChip(Capsule(style: .continuous))
        .allowsHitTesting(false)
    }

    private var completionPromptChip: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 11, weight: .semibold))
            Text("When you finish a task, mark it done")
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .immersiveOnboardingChip(Capsule(style: .continuous))
        .allowsHitTesting(false)
    }

    // MARK: - Lifecycle

    private func onAppear() {
        guard !didMount else { return }
        didMount = true

        baselineCount = state.store.items.count
        state.mode.open(.newTodoInput)

        let delay = reduceMotion ? 0.0 : 0.30
        let task = Task { @MainActor in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                if Task.isCancelled { return }
            }
            promptVisible = true
        }
        pendingWork.append(task)
    }

    private func onDisappear() {
        for task in pendingWork { task.cancel() }
        pendingWork.removeAll()
        // Leaving Scene 2: close interaction gates and clear the pulse
        // so they don't leak into Scene 3 / farewell.
        state.mode.close(.newTodoInput)
        state.mode.close(.completeToggle)
        state.mode.pulsingCheckboxItemID = nil
    }

    // MARK: - Phase transitions

    private func handleItemCountChange(newCount: Int) {
        // If the user ends up with no addressable tasks while we're
        // prompting them to complete one, roll the prompt back instead
        // of leaving the scene stuck. In today's gates the row can't be
        // deleted from Scene 2, but the fallback makes this safe if
        // someone later opens `.rowSwipe` or `.rowContextMenu` here.
        let activeCount = state.store.items.lazy
            .filter { !$0.isTrashed && !$0.isCompleted }
            .count

        if phase == .awaitingCompletion, activeCount == 0 {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) {
                phase = .awaitingTask
            }
            state.mode.close(.completeToggle)
            state.mode.pulsingCheckboxItemID = nil
            state.firstTaskID = nil
            baselineCount = state.store.items.count
            return
        }

        guard phase == .awaitingTask, newCount > baselineCount else { return }

        // Remember the first task so the pulse sticks to it even if the
        // user keeps adding more.
        if state.firstTaskID == nil,
           let first = state.store.items.first(where: { !$0.isCompleted && !$0.isTrashed })
        {
            state.firstTaskID = first.id
        }

        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.45)) {
            phase = .awaitingCompletion
        }
        state.mode.open(.completeToggle)
        state.mode.pulsingCheckboxItemID = state.firstTaskID
    }

    private func handleTaskCompletion() {
        guard phase == .awaitingCompletion else { return }
        // Clear the pulse so the completed task doesn't keep glowing.
        state.mode.pulsingCheckboxItemID = nil

        let delay = reduceMotion ? 0.1 : 0.45
        let task = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            if Task.isCancelled { return }
            coordinator.next()
        }
        pendingWork.append(task)
    }
}
