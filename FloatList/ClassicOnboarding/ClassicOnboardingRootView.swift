import SwiftUI
import AppKit

enum ClassicOnboardingLayout {
    static let cardWidth: CGFloat = 1040
    static let cardHeight: CGFloat = 620

    /// Demo panel sizes. Decoupled from `LayoutTweaks` so a user who resized
    /// the real panel doesn't blow out the preview.
    static let demoExpandedWidth: CGFloat = 280
    static let demoExpandedHeight: CGFloat = 400
    static let demoCollapsedWidth: CGFloat = 56
    static let demoCollapsedHeight: CGFloat = 56
}

/// Embedded panel's window-global SwiftUI frame, published so
/// `ClassicOnboardingWindow` can fly the real panel in from that visual position.
struct EmbeddedPanelFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

struct ClassicOnboardingRootView: View {
    @ObservedObject var coordinator: ClassicOnboardingCoordinator
    @ObservedObject var demoStore: TodoStore
    @ObservedObject var demoPanelManager: PanelManager
    let scriptedInput: ScriptedInputBuffer
    var onEmbeddedFrameChange: (CGRect) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @StateObject private var cursor = ClassicOnboardingCursorController()
    @ObservedObject private var tweaks = ClassicOnboardingTweaks.shared
    @State private var mockSize: CGSize = .zero

    private let demoTaskTitle = "Pick up groceries"

    var body: some View {
        ClassicOnboardingStageCard {
            HStack(spacing: 0) {
                instructionColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                demoColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: ClassicOnboardingLayout.cardWidth, height: ClassicOnboardingLayout.cardHeight)
        .onPreferenceChange(EmbeddedPanelFrameKey.self) { rect in
            onEmbeddedFrameChange(rect)
        }
        .task(id: coordinator.currentIndex) {
            await runScene(for: coordinator.currentStep)
        }
    }

    // MARK: - Left column

    private var instructionColumn: some View {
        ClassicOnboardingInstructionChip(
            coordinator: coordinator,
            title: coordinator.currentStep.kind.title,
            bodyText: coordinator.currentStep.kind.body,
            primaryTitle: primaryTitle(for: coordinator.currentStep),
            onPrimary: advance,
            onBack: goBack
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(accessibilitySummary(for: coordinator.currentStep)))
    }

    private func primaryTitle(for step: ClassicOnboardingStep) -> String {
        if case .basic = step.kind {
            if coordinator.isFirst { return "Start demo" }
            if coordinator.isLast { return "Launch FloatList" }
        }
        return "Continue"
    }

    // MARK: - Right column

    private var demoColumn: some View {
        ClassicOnboardingDesktopMock(
            onSizeChange: { mockSize = $0 },
            dockedContent: {
                livePanelPreview
                    .background(
                        GeometryReader { proxy in
                            Color.clear
                                .preference(key: EmbeddedPanelFrameKey.self, value: proxy.frame(in: .global))
                        }
                    )
            },
            overlay: {
                ClassicOnboardingCursorOverlay(controller: cursor, tweaks: tweaks)
            }
        )
    }

    /// Live panel preview. Stays mounted across every step — expand/collapse
    /// animates in place. All user input paths are sealed so the preview is
    /// strictly decorative.
    private var livePanelPreview: some View {
        ContentView(store: demoStore, panelManager: demoPanelManager)
            .frame(width: panelWidth, height: panelHeight)
            .animation(PanelMotion.stateAnimation, value: demoPanelManager.isCollapsed)
            .allowsHitTesting(false)
            .disabled(true)
            .focusable(false)
            .accessibilityElement(children: .ignore)
            .accessibilityHidden(true)
    }

    private var panelWidth: CGFloat {
        demoPanelManager.isCollapsed ? ClassicOnboardingLayout.demoCollapsedWidth : ClassicOnboardingLayout.demoExpandedWidth
    }

    private var panelHeight: CGFloat {
        demoPanelManager.isCollapsed ? ClassicOnboardingLayout.demoCollapsedHeight : ClassicOnboardingLayout.demoExpandedHeight
    }

    // MARK: - Navigation

    private func advance() {
        fastForwardCurrentScene()
        coordinator.advance()
    }

    private func goBack() {
        fastForwardCurrentScene()
        coordinator.back()
    }

    private func fastForwardCurrentScene() {
        resetScriptedInput()
        // Don't hide the cursor here — the next scene will either glide it to
        // its starting target (if still visible) or fade it in fresh. Hiding
        // mid-advance caused the arrow to snap across the card on step change.

        switch coordinator.currentStep.kind {
        case .panelHover(let content):
            setPanelCollapsed(content.targetCollapsed)
        case .interactive, .basic:
            break
        }
    }

    // MARK: - Autoplay

    private func runScene(for step: ClassicOnboardingStep) async {
        await applyInitialState(for: step)
        guard !Task.isCancelled else { return }

        switch step.kind {
        case .basic:
            cursor.hide()
            return
        case .panelHover(let content):
            if content.initialCollapsed && !content.targetCollapsed {
                // Expand: cursor drifts from resting (or its current spot) to
                // the collapsed handle, "triggers" the hover, then rests at
                // the expanded panel edge.
                await cursorBeginScene(at: .resting, panelCollapsed: true)
                await cursorMove(to: .panelHandle, panelCollapsed: true)
                await pause(0.35)
                guard !Task.isCancelled else { return }
                setPanelCollapsed(false)
                await cursorMove(to: .panelEdge, panelCollapsed: false)
            } else if !content.initialCollapsed && content.targetCollapsed {
                // Collapse: cursor drifts away from the panel, then the panel
                // tucks itself back.
                await cursorBeginScene(at: .panelEdge, panelCollapsed: false)
                await cursorMove(to: .resting, panelCollapsed: false)
                await pause(0.2)
                guard !Task.isCancelled else { return }
                setPanelCollapsed(true)
                await pause(0.4)
                cursor.hide()
            } else {
                await pause(0.6)
                guard !Task.isCancelled else { return }
                setPanelCollapsed(content.targetCollapsed)
            }
        case .interactive:
            switch step.id {
            case .createTask:
                await cursorBeginScene(at: .resting, panelCollapsed: demoPanelManager.isCollapsed)
                await cursorMove(to: .inputField, panelCollapsed: demoPanelManager.isCollapsed)
                await pause(0.2)
                guard !Task.isCancelled else { return }
                await typeDemoTitle()
                guard !Task.isCancelled else { return }
                await pause(0.25)
                submitDemoTitle()
            case .completeTask:
                await cursorBeginScene(at: .resting, panelCollapsed: demoPanelManager.isCollapsed)
                await cursorMove(to: .firstRowCheckbox, panelCollapsed: demoPanelManager.isCollapsed)
                await pause(0.15)
                guard !Task.isCancelled else { return }
                if !reduceMotion { await cursor.press() }
                guard !Task.isCancelled else { return }
                toggleFirstDemoItem()
            default:
                break
            }
        }
    }

    // MARK: Cursor helpers (gated on reduce motion)

    /// Enters a new scene. If the cursor is already on screen, leave it where
    /// it is — the following `cursorMove(to:)` call will glide it straight to
    /// the real target, reading as one continuous motion across scenes.
    /// If it's hidden, fade it in at the fallback start point (show internally
    /// waits for any prior fade-out to finish before snapping position, so
    /// quick hide→show cycles never reveal a teleport).
    private func cursorBeginScene(at fallback: ClassicOnboardingCursorTarget, panelCollapsed: Bool) async {
        guard !reduceMotion, mockSize != .zero else { return }
        guard !cursor.isVisible else { return }
        await cursor.show(at: fallback, in: mockSize, panelCollapsed: panelCollapsed)
        try? await Task.sleep(nanoseconds: UInt64(Double(tweaks.cursorFadeDuration) * 1_000_000_000))
    }

    private func cursorMove(to target: ClassicOnboardingCursorTarget, panelCollapsed: Bool) async {
        guard !reduceMotion, mockSize != .zero else { return }
        await cursor.move(to: target, in: mockSize, panelCollapsed: panelCollapsed)
    }

    private func applyInitialState(for step: ClassicOnboardingStep) async {
        resetScriptedInput()

        switch step.kind {
        case .basic:
            // Welcome/finish show the docked "FloatList on your desktop",
            // not the expanded workspace.
            if !demoPanelManager.isCollapsed {
                setPanelCollapsed(true)
            }
        case .panelHover(let content):
            if demoPanelManager.isCollapsed != content.initialCollapsed {
                setPanelCollapsed(content.initialCollapsed)
                await pause(reduceMotion ? 0 : 0.3)
            }
        case .interactive:
            if demoPanelManager.isCollapsed {
                setPanelCollapsed(false)
                await pause(reduceMotion ? 0 : 0.3)
            }
            switch step.id {
            case .createTask:
                removeAllDemoActiveItems()
            case .completeTask:
                ensureSampleDemoItemExists()
            default:
                break
            }
        }
    }

    private func resetScriptedInput() {
        if scriptedInput.isActive { scriptedInput.isActive = false }
        if !scriptedInput.text.isEmpty { scriptedInput.text = "" }
    }

    private func setPanelCollapsed(_ collapsed: Bool) {
        guard demoPanelManager.isCollapsed != collapsed else { return }
        if reduceMotion {
            var txn = Transaction()
            txn.disablesAnimations = true
            withTransaction(txn) {
                demoPanelManager.isCollapsed = collapsed
            }
        } else {
            if collapsed { demoPanelManager.collapse() }
            else { demoPanelManager.expand() }
        }
    }

    private func typeDemoTitle() async {
        if reduceMotion {
            scriptedInput.isActive = true
            scriptedInput.text = demoTaskTitle
            return
        }

        scriptedInput.isActive = true
        scriptedInput.text = ""
        let perCharNanos: UInt64 = 55_000_000
        for char in demoTaskTitle {
            guard !Task.isCancelled else { return }
            scriptedInput.text.append(char)
            try? await Task.sleep(nanoseconds: perCharNanos)
        }
    }

    private func submitDemoTitle() {
        let title = scriptedInput.text.trimmingCharacters(in: .whitespacesAndNewlines)
        resetScriptedInput()
        guard !title.isEmpty else { return }
        if reduceMotion {
            demoStore.add(title: title)
        } else {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                demoStore.add(title: title)
            }
        }
    }

    private func toggleFirstDemoItem() {
        guard let target = demoStore.visibleItems.first(where: { !$0.isCompleted && !$0.isTrashed }) else { return }
        if reduceMotion {
            demoStore.toggle(target)
        } else {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                demoStore.toggle(target)
            }
        }
    }

    private func removeAllDemoActiveItems() {
        guard let listID = demoStore.selectedListID else { return }
        for item in demoStore.items(in: listID) {
            demoStore.permanentlyDelete(item)
        }
    }

    private func ensureSampleDemoItemExists() {
        if demoStore.visibleItems.contains(where: { !$0.isCompleted && !$0.isTrashed }) {
            return
        }
        demoStore.add(title: demoTaskTitle)
    }

    private func pause(_ seconds: Double) async {
        guard seconds > 0, !reduceMotion else { return }
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    // MARK: - Accessibility

    private func accessibilitySummary(for step: ClassicOnboardingStep) -> String {
        "Step \(coordinator.currentIndex + 1) of \(coordinator.steps.count). \(step.kind.title). \(step.kind.body)"
    }
}
