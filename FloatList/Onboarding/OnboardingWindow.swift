import AppKit
import SwiftUI

/// Borderless NSWindow. The `canBecomeKey/Main` overrides are the whole
/// reason this subclass exists: a plain borderless window swallows the
/// primary CTA's keyboard shortcut because it never becomes key.
private final class OnboardingNSWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class OnboardingWindow {
    let window: NSWindow
    let coordinator: OnboardingCoordinator
    let demoStore: TodoStore
    let demoPanelManager: PanelManager
    let scriptedInput: ScriptedInputBuffer

    private var embeddedPanelGlobalRect: CGRect = .zero

    private var closeObserver: NSObjectProtocol?
    private var closeKeyMonitor: Any?
    private var onClose: (() -> Void)?

    init() {
        let mode = OnboardingMode(isActive: true)
        self.scriptedInput = ScriptedInputBuffer()
        self.coordinator = OnboardingCoordinator()
        self.demoPanelManager = PanelManager(isOnboardingMode: true)
        self.demoStore = TodoStore(inMemory: true)

        let contentSize = NSSize(
            width: OnboardingLayout.cardWidth,
            height: OnboardingLayout.cardHeight
        )
        let window = OnboardingNSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.center()
        self.window = window

        let root = OnboardingRootView(
            coordinator: self.coordinator,
            demoStore: self.demoStore,
            demoPanelManager: self.demoPanelManager,
            scriptedInput: self.scriptedInput,
            onEmbeddedFrameChange: { [weak self] rect in
                MainActor.assumeIsolated {
                    self?.embeddedPanelGlobalRect = rect
                }
            }
        )
        .environmentObject(mode)
        .environmentObject(self.scriptedInput)

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

        // Borderless windows don't route Cmd+W through the responder chain.
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

    /// Converts the embedded panel's SwiftUI-global frame to AppKit screen
    /// coordinates (origin-flipped) for the completion handoff.
    var embeddedPanelScreenRect: NSRect {
        let windowFrame = window.frame
        let localRect = embeddedPanelGlobalRect
        if localRect == .zero {
            let size = NSSize(
                width: LayoutTweaks.shared.expandedWidth,
                height: LayoutTweaks.shared.expandedHeight
            )
            return NSRect(
                x: windowFrame.midX - size.width / 2,
                y: windowFrame.midY - size.height / 2,
                width: size.width,
                height: size.height
            )
        }
        return NSRect(
            x: windowFrame.minX + localRect.minX,
            y: windowFrame.minY + (windowFrame.height - localRect.maxY),
            width: localRect.width,
            height: localRect.height
        )
    }

    private func handleClose() {
        if let observer = closeObserver {
            NotificationCenter.default.removeObserver(observer)
            closeObserver = nil
        }
        if let monitor = closeKeyMonitor {
            NSEvent.removeMonitor(monitor)
            closeKeyMonitor = nil
        }
        if !coordinator.isComplete {
            coordinator.skip()
        }
        onClose?()
        onClose = nil
    }
}
