import SwiftUI

@main
struct FloatDoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelManager: PanelManager?
    private var statusItem: NSStatusItem?
    private var hotkeyObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppearanceMode.current.apply()

        let store = TodoStore()
        let manager = PanelManager()
        let contentView = ContentView(store: store, panelManager: manager)
        manager.setup(contentView: contentView)
        manager.showPanel()
        self.panelManager = manager
        setupStatusBarItem()

        _ = GlobalHotkey.shared
        hotkeyObserver = NotificationCenter.default.addObserver(
            forName: .floatDoToggleHotkey,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.panelManager?.togglePanel()
        }
    }

    deinit {
        if let observer = hotkeyObserver {
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
        menu.addItem(NSMenuItem(title: "Quit FloatDo", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    @objc private func togglePanel() {
        panelManager?.togglePanel()
    }

    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            let event = NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: .command,
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: 0,
                context: nil,
                characters: ",",
                charactersIgnoringModifiers: ",",
                isARepeat: false,
                keyCode: 0x2B
            )
            if let event, NSApp.mainMenu?.performKeyEquivalent(with: event) == true {
                return
            }
            if #available(macOS 14, *) {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            } else {
                NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
            }
        }
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
