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

    private var panelManager: PanelManager?
    private var statusItem: NSStatusItem?
    private var hotkeyObserver: NSObjectProtocol?
    private var expandHotkeyObserver: NSObjectProtocol?
    private var settingsWindow: NSWindow?
    private var settingsCloseObserver: NSObjectProtocol?
    private var wasAccessoryBeforeSettings = false

    override init() {
        super.init()
        AppDelegate.shared = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppearanceMode.current.apply()

        let store = TodoStore()
        let manager = PanelManager()
        let contentView = ContentView(store: store, panelManager: manager)
        manager.setup(contentView: contentView)
        manager.showPanel()
        self.panelManager = manager
        setupStatusBarItem()

        _ = GlobalHotkey.toggleVisibility
        _ = GlobalHotkey.expandCollapse
        hotkeyObserver = NotificationCenter.default.addObserver(
            forName: .floatListToggleHotkey,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.panelManager?.togglePanel()
            }
        }
        expandHotkeyObserver = NotificationCenter.default.addObserver(
            forName: .floatListExpandCollapseHotkey,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.panelManager?.showOrToggleExpansion()
            }
        }
    }

    deinit {
        if let observer = hotkeyObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = expandHotkeyObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = settingsCloseObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func setupStatusBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            let image = NSImage(named: "PanelGlyph")
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
        if let observer = settingsCloseObserver {
            NotificationCenter.default.removeObserver(observer)
            settingsCloseObserver = nil
        }
        settingsWindow = nil
        if wasAccessoryBeforeSettings {
            NSApp.setActivationPolicy(.accessory)
            wasAccessoryBeforeSettings = false
        }
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
