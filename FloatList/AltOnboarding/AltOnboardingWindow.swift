import AppKit
import SwiftUI

private final class AltOnboardingNSWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Alternative immersive onboarding window. It lives entirely under
/// `AltOnboarding` so the app-level presenter can choose it without
/// mixing its scene code into the original onboarding implementation.
@MainActor
final class AltOnboardingWindow {
    let window: NSWindow
    /// Shared state visible to the window so migration can happen
    /// against the canonical onboarding store on close.
    let state = AltOnboardingState()
    private weak var realStore: TodoStore?

    private var closeObserver: NSObjectProtocol?
    private var closeKeyMonitor: Any?
    private var onClose: (() -> Void)?
    private var didMigrate = false

    init(realStore: TodoStore?) {
        self.realStore = realStore

        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let window = AltOnboardingNSWindow(
            contentRect: screenFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isMovableByWindowBackground = false
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        // Float above normal windows but stay below system-level UI
        // (permission prompts, alerts). `.popUpMenu` was too aggressive
        // — it could sit on top of system dialogs the onboarding itself
        // might trigger.
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        // No fade/scale on close — the farewell animation already
        // delivered the panel to its landing spot; the window should
        // disappear instantly so the real panel can take over without
        // a visible "fly away + fade" tail after the landing.
        window.animationBehavior = .none
        window.setFrame(screenFrame, display: true)
        self.window = window

        let root = AltOnboardingRootView(state: state, onFinish: { [weak self] in
            self?.window.close()
        })
        let hosting = NSHostingView(rootView: root)
        hosting.wantsLayer = true
        window.contentView = hosting
    }

    func present(onClose: @escaping () -> Void) {
        self.onClose = onClose

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleClose() }
        }

        closeKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }
            guard event.modifierFlags.contains(.command) else { return event }
            guard event.charactersIgnoringModifiers == "w", self.window.isKeyWindow else { return event }
            self.window.close()
            return nil
        }
    }

    func dismiss() {
        window.close()
    }

    private func handleClose() {
        migrateIfNeeded()

        if let observer = closeObserver {
            NotificationCenter.default.removeObserver(observer)
            closeObserver = nil
        }
        if let monitor = closeKeyMonitor {
            NSEvent.removeMonitor(monitor)
            closeKeyMonitor = nil
        }
        onClose?()
        onClose = nil
    }

    /// Copy anything the user produced during the onboarding flow
    /// (active, completed, and trashed tasks) into the real Inbox.
    /// Only migrates when the user actually reached Scene 3 — early
    /// ⌘W / close-X sessions are assumed to be exploratory and should
    /// leave the real store untouched.
    /// Runs at most once even if close fires through multiple paths.
    private func migrateIfNeeded() {
        guard !didMigrate else { return }
        didMigrate = true
        guard state.didReachFarewell else { return }
        realStore?.importOnboardingItems(state.store.items)
    }
}
