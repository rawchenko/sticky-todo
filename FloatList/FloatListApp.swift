import SwiftUI
import AppKit

@main
struct FloatListApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Empty scene; the AppDelegate owns the panel and settings windows
        // directly via AppKit, so SwiftUI doesn't need to manage any.
        Settings { EmptyView() }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    /// Exposed so SwiftUI views hosted inside our AppKit panel can call back
    /// into the delegate without relying on `NSApp.delegate as? AppDelegate`,
    /// which returns nil under `@NSApplicationDelegateAdaptor` in some setups.
    static private(set) weak var shared: AppDelegate?

    private var store: TodoStore?
    private var panelManager: PanelManager?
    private var statusItem: NSStatusItem?
    private var hotkeyObserver: NSObjectProtocol?
    private var expandHotkeyObserver: NSObjectProtocol?
    private var settingsWindow: NSWindow?
    private var settingsCloseObserver: NSObjectProtocol?
    private var wasAccessoryBeforeSettings = false
    private var onboardingPresenter: AppOnboardingPresenter?
    private let onboardingMode = OnboardingMode(isActive: false)
    private let scriptedInput = ScriptedInputBuffer()

    override init() {
        super.init()
        AppDelegate.shared = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppearanceMode.current.apply()

        let store = TodoStore()
        self.store = store
        setupStatusBarItem()
        registerHotkeyObservers()

        if UserDefaults.standard.bool(forKey: OnboardingDefaults.completedKey) {
            presentRealPanel(store: store)
        } else {
            presentConfiguredOnboarding()
        }
    }

    private func presentRealPanel(store: TodoStore, flyInFrom originFrame: NSRect? = nil) {
        let manager = PanelManager()
        let contentView = ContentView(store: store, panelManager: manager)
            .environmentObject(onboardingMode)
            .environmentObject(scriptedInput)
        manager.setup(contentView: contentView)
        self.panelManager = manager

        if let originFrame {
            manager.flyInFromCenter(from: originFrame)
        } else {
            manager.showPanel()
        }
    }

    private func presentConfiguredOnboarding() {
        guard let store else { return }
        let presenter = AppOnboardingPresenter()
        onboardingPresenter = presenter
        presenter.present(
            variant: OnboardingConfiguration.activeVariant,
            realStore: store,
            onComplete: { [weak self] completion in
                MainActor.assumeIsolated {
                    self?.handleOnboardingCompletion(completion)
                }
            },
            onClose: { [weak self, weak presenter] in
                MainActor.assumeIsolated {
                    guard let self, self.onboardingPresenter === presenter else { return }
                    self.onboardingPresenter = nil
                }
            }
        )
    }

    private func handleOnboardingCompletion(_ completion: AppOnboardingPresenter.Completion) {
        guard let store else { return }

        switch completion {
        case .showPanel(let originFrame):
            guard panelManager == nil else { return }
            presentRealPanel(store: store, flyInFrom: originFrame)
            NSApp.setActivationPolicy(.accessory)
        case .revealDocked(let anchor):
            UserDefaults.standard.set(true, forKey: OnboardingDefaults.completedKey)
            if panelManager == nil {
                presentRealPanel(store: store)
            }
            NSApp.setActivationPolicy(.accessory)
            panelManager?.revealDocked(at: anchor)
        }
    }

    func restartOnboarding() {
        guard store != nil else { return }
        guard onboardingPresenter?.isPresenting != true else { return }

        UserDefaults.standard.set(false, forKey: OnboardingDefaults.completedKey)

        // Close Settings so it doesn't bleed through the full-screen onboarding.
        if let settings = settingsWindow {
            settings.close()
            settingsWindow = nil
        }
        removeSettingsCloseObserver()

        if let panel = panelManager {
            panel.hidePanel()
            panelManager = nil
        }

        presentConfiguredOnboarding()
    }

    private func registerHotkeyObservers() {
        _ = GlobalHotkey.toggleVisibility
        _ = GlobalHotkey.expandCollapse
        hotkeyObserver = NotificationCenter.default.addObserver(
            forName: .floatListToggleHotkey,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.onboardingPresenter?.isPresenting != true else { return }
                self.panelManager?.togglePanel()
            }
        }
        expandHotkeyObserver = NotificationCenter.default.addObserver(
            forName: .floatListExpandCollapseHotkey,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.onboardingPresenter?.isPresenting != true else { return }
                self.panelManager?.showOrToggleExpansion()
            }
        }
    }

    private func setupStatusBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            let image = NSImage(named: "MenuBarGlyph")
            image?.isTemplate = true
            image?.size = NSSize(width: 14, height: 14)
            button.image = image
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Toggle Panel", action: #selector(togglePanel), keyEquivalent: "t"))
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.keyEquivalentModifierMask = [.command]
        menu.addItem(settingsItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit FloatList", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    @objc private func togglePanel() {
        panelManager?.togglePanel()
    }

    @objc func openSettings() {
        let wasAccessory = NSApp.activationPolicy() == .accessory
        if wasAccessory {
            NSApp.setActivationPolicy(.regular)
        }

        let window: NSWindow
        if let existing = settingsWindow {
            window = existing
        } else {
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 560),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "General"
            window.contentView = NSHostingView(rootView: SettingsView())
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 480, height: 480)
            window.center()

            settingsWindow = window
            wasAccessoryBeforeSettings = wasAccessory

            settingsCloseObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.handleSettingsWindowClose()
                }
            }
        }

        // Clicks inside the nonactivating panel don't promote FloatList to
        // frontmost, so the fresh Settings window otherwise orders behind the
        // previously-active app. `orderFrontRegardless` forces it on top,
        // then `activate` brings the app forward so the window can take focus.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func handleSettingsWindowClose() {
        removeSettingsCloseObserver()
        settingsWindow = nil
        if wasAccessoryBeforeSettings {
            NSApp.setActivationPolicy(.accessory)
            wasAccessoryBeforeSettings = false
        }
    }

    private func removeSettingsCloseObserver() {
        if let observer = settingsCloseObserver {
            NotificationCenter.default.removeObserver(observer)
            settingsCloseObserver = nil
        }
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
