import SwiftUI

@MainActor
final class OnboardingCoordinator: ObservableObject {
    @Published private(set) var currentIndex: Int = 0
    private(set) var isComplete: Bool = false
    let steps: [OnboardingStep]

    init(steps: [OnboardingStep] = OnboardingStep.defaultFlow) {
        self.steps = steps
    }

    var currentStep: OnboardingStep { steps[currentIndex] }
    var isFirst: Bool { currentIndex == 0 }
    var isLast: Bool { currentIndex == steps.count - 1 }

    func advance() {
        guard !isComplete else { return }
        if isLast {
            complete()
            return
        }
        withAnimation(OnboardingTweaks.shared.advanceSpring) {
            currentIndex += 1
        }
    }

    func back() {
        guard currentIndex > 0 else { return }
        withAnimation(OnboardingTweaks.shared.advanceSpring) {
            currentIndex -= 1
        }
    }

    func skip() {
        complete()
    }

    private func complete() {
        guard !isComplete else { return }
        isComplete = true
        UserDefaults.standard.set(true, forKey: OnboardingDefaults.completedKey)
        NotificationCenter.default.post(name: .floatListOnboardingCompleted, object: nil)
    }
}
