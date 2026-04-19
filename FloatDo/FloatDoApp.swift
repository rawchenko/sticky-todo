import SwiftUI

@main
struct FloatDoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelManager: PanelManager?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = TodoStore()
        let manager = PanelManager()
        let contentView = ContentView(store: store, panelManager: manager)
        manager.setup(contentView: contentView)
        manager.showPanel()
        self.panelManager = manager
        setupStatusBarItem()
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
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit FloatDo", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    @objc private func togglePanel() {
        panelManager?.togglePanel()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
