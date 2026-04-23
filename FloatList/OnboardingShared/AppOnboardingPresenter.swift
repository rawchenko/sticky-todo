import AppKit

@MainActor
final class AppOnboardingPresenter {
    enum Completion {
        case showPanel(flyInFrom: NSRect?)
        case revealDocked(EdgeAnchor)
    }

    private var originalPresenter: AnyObject?
    private var altPresenter: AnyObject?

    var isPresenting: Bool {
        originalPresenter != nil || altPresenter != nil
    }

    func present(
        variant: OnboardingVariant,
        realStore: TodoStore?,
        onComplete: @escaping (Completion) -> Void,
        onClose: @escaping () -> Void
    ) {
        if presentRequestedVariant(variant, realStore: realStore, onComplete: onComplete, onClose: onClose) {
            return
        }

        if presentOriginalIfAvailable(variant: variant, realStore: realStore, onComplete: onComplete, onClose: onClose) {
            return
        }

        if presentAltIfAvailable(variant: variant, realStore: realStore, onComplete: onComplete, onClose: onClose) {
            return
        }

        onComplete(.showPanel(flyInFrom: nil))
        onClose()
    }

    private func presentRequestedVariant(
        _ variant: OnboardingVariant,
        realStore: TodoStore?,
        onComplete: @escaping (Completion) -> Void,
        onClose: @escaping () -> Void
    ) -> Bool {
        switch variant.rawValue {
        case "original":
            return presentOriginalIfAvailable(variant: variant, realStore: realStore, onComplete: onComplete, onClose: onClose)
        case "alt":
            return presentAltIfAvailable(variant: variant, realStore: realStore, onComplete: onComplete, onClose: onClose)
        default:
            return false
        }
    }

    private func presentOriginalIfAvailable(
        variant _: OnboardingVariant,
        realStore _: TodoStore?,
        onComplete _: @escaping (Completion) -> Void,
        onClose _: @escaping () -> Void
    ) -> Bool {
        false
    }

    private func presentAltIfAvailable(
        variant _: OnboardingVariant,
        realStore _: TodoStore?,
        onComplete _: @escaping (Completion) -> Void,
        onClose _: @escaping () -> Void
    ) -> Bool {
        false
    }
}
