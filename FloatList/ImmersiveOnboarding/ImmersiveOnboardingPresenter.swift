import Foundation

@MainActor
final class ImmersiveOnboardingPresenter {
    private let window: ImmersiveOnboardingWindow

    init(realStore: TodoStore?) {
        self.window = ImmersiveOnboardingWindow(realStore: realStore)
    }

    func present(
        onComplete: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        window.present {
            onComplete()
            onClose()
        }
    }
}
