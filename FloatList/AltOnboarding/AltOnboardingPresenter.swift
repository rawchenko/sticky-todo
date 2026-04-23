import Foundation

@MainActor
final class AltOnboardingPresenter {
    private let window: AltOnboardingWindow

    init(realStore: TodoStore?) {
        self.window = AltOnboardingWindow(realStore: realStore)
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
