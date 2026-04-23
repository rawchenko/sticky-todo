import AppKit

@MainActor
final class ClassicOnboardingPresenter {
    private let window = ClassicOnboardingWindow()
    private var completionObserver: NSObjectProtocol?
    private var onComplete: ((NSRect?) -> Void)?
    private var didComplete = false

    func present(
        onComplete: @escaping (NSRect?) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.onComplete = onComplete

        completionObserver = NotificationCenter.default.addObserver(
            forName: .floatListOnboardingCompleted,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleCompletion()
            }
        }

        window.present(onClose: { [weak self] in
            MainActor.assumeIsolated {
                self?.removeCompletionObserver()
                onClose()
            }
        })
    }

    private func handleCompletion() {
        guard !didComplete else { return }
        didComplete = true
        removeCompletionObserver()

        let origin = window.embeddedPanelScreenRect
        onComplete?(origin)
        onComplete = nil

        let dismissDelay: TimeInterval = 0.08
        DispatchQueue.main.asyncAfter(deadline: .now() + dismissDelay) { [weak self] in
            self?.window.dismiss()
        }
    }

    private func removeCompletionObserver() {
        if let observer = completionObserver {
            NotificationCenter.default.removeObserver(observer)
            completionObserver = nil
        }
    }

    deinit {
        if let observer = completionObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
