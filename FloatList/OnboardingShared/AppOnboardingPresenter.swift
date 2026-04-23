import AppKit

@MainActor
final class AppOnboardingPresenter {
    enum Completion {
        case showPanel(flyInFrom: NSRect?)
        case revealDocked(EdgeAnchor)
    }

    private var classicPresenter: AnyObject?
    private var immersivePresenter: AnyObject?

    var isPresenting: Bool {
        classicPresenter != nil || immersivePresenter != nil
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

        if presentClassicIfAvailable(variant: variant, realStore: realStore, onComplete: onComplete, onClose: onClose) {
            return
        }

        if presentImmersiveIfAvailable(variant: variant, realStore: realStore, onComplete: onComplete, onClose: onClose) {
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
        switch variant {
        case OnboardingCatalog.classic.variant:
            return presentClassicIfAvailable(variant: variant, realStore: realStore, onComplete: onComplete, onClose: onClose)
        case OnboardingCatalog.immersive.variant:
            return presentImmersiveIfAvailable(variant: variant, realStore: realStore, onComplete: onComplete, onClose: onClose)
        default:
            return false
        }
    }

    private func presentClassicIfAvailable(
        variant _: OnboardingVariant,
        realStore _: TodoStore?,
        onComplete: @escaping (Completion) -> Void,
        onClose: @escaping () -> Void
    ) -> Bool {
        let presenter = ClassicOnboardingPresenter()
        classicPresenter = presenter
        presenter.present(
            onComplete: { origin in
                onComplete(.showPanel(flyInFrom: origin))
            },
            onClose: { [weak self] in
                self?.classicPresenter = nil
                onClose()
            }
        )
        return true
    }

    private func presentImmersiveIfAvailable(
        variant _: OnboardingVariant,
        realStore: TodoStore?,
        onComplete: @escaping (Completion) -> Void,
        onClose: @escaping () -> Void
    ) -> Bool {
        let presenter = ImmersiveOnboardingPresenter(realStore: realStore)
        immersivePresenter = presenter
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
                self?.immersivePresenter = nil
                onClose()
            }
        )
        return true
    }
}
