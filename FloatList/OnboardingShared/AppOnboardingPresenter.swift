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
        onComplete: @escaping (Completion) -> Void,
        onClose: @escaping () -> Void
    ) -> Bool {
        let presenter = OriginalOnboardingPresenter()
        originalPresenter = presenter
        presenter.present(
            onComplete: { origin in
                onComplete(.showPanel(flyInFrom: origin))
            },
            onClose: { [weak self] in
                self?.originalPresenter = nil
                onClose()
            }
        )
        return true
    }

    private func presentAltIfAvailable(
        variant _: OnboardingVariant,
        realStore: TodoStore?,
        onComplete: @escaping (Completion) -> Void,
        onClose: @escaping () -> Void
    ) -> Bool {
        let presenter = AltOnboardingPresenter(realStore: realStore)
        altPresenter = presenter
        presenter.present(
            onComplete: {
                let screen = NSScreen.main
                let anchor = EdgeAnchor(
                    edge: .right,
                    vertical: .top,
                    anchorY: screen?.visibleFrame.maxY ?? 0
                )
                onComplete(.revealDocked(anchor))
            },
            onClose: { [weak self] in
                self?.altPresenter = nil
                onClose()
            }
        )
        return true
    }
}
