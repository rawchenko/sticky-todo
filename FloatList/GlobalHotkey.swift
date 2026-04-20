import AppKit
import Carbon

extension Notification.Name {
    static let floatListToggleHotkey = Notification.Name("FloatList.toggleHotkey")
    static let floatListExpandCollapseHotkey = Notification.Name("FloatList.expandCollapseHotkey")
}

@MainActor
final class GlobalHotkey: ObservableObject {
    static let toggleVisibility = GlobalHotkey(
        id: 1,
        defaultsPrefix: "floatlist.hotkey",
        notificationName: .floatListToggleHotkey,
        defaultKeyCode: UInt32(kVK_ANSI_T),
        defaultModifiers: UInt32(controlKey | optionKey)
    )

    static let expandCollapse = GlobalHotkey(
        id: 2,
        defaultsPrefix: "floatlist.hotkey.expand",
        notificationName: .floatListExpandCollapseHotkey,
        defaultKeyCode: UInt32(kVK_ANSI_E),
        defaultModifiers: UInt32(controlKey | optionKey)
    )

    /// Backward-compat alias for the original single-hotkey API.
    static var shared: GlobalHotkey { toggleVisibility }

    @Published private(set) var keyCode: UInt32
    @Published private(set) var modifiers: UInt32

    private let id: UInt32
    private let keyCodeKey: String
    private let modifiersKey: String
    private let notificationName: Notification.Name

    private var hotKeyRef: EventHotKeyRef?

    private static let signature: OSType = {
        let chars = Array("FlLi".utf8)
        return chars.reduce(OSType(0)) { ($0 << 8) | OSType($1) }
    }()

    private static var handlerInstalled = false
    private static var registry: [UInt32: GlobalHotkey] = [:]

    private init(id: UInt32,
                 defaultsPrefix: String,
                 notificationName: Notification.Name,
                 defaultKeyCode: UInt32,
                 defaultModifiers: UInt32) {
        self.id = id
        self.keyCodeKey = "\(defaultsPrefix).keyCode"
        self.modifiersKey = "\(defaultsPrefix).modifiers"
        self.notificationName = notificationName

        let defaults = UserDefaults.standard
        if defaults.object(forKey: keyCodeKey) != nil {
            self.keyCode = UInt32(defaults.integer(forKey: keyCodeKey))
            self.modifiers = UInt32(defaults.integer(forKey: modifiersKey))
        } else {
            self.keyCode = defaultKeyCode
            self.modifiers = defaultModifiers
        }

        Self.registry[id] = self
        Self.installHandlerIfNeeded()
        register()
    }

    func setBinding(keyCode newKey: UInt32, modifiers newMods: UInt32) {
        unregister()
        self.keyCode = newKey
        self.modifiers = newMods
        UserDefaults.standard.set(Int(newKey), forKey: keyCodeKey)
        UserDefaults.standard.set(Int(newMods), forKey: modifiersKey)
        register()
    }

    func clearBinding() {
        unregister()
        self.keyCode = 0
        self.modifiers = 0
        UserDefaults.standard.removeObject(forKey: keyCodeKey)
        UserDefaults.standard.removeObject(forKey: modifiersKey)
    }

    private static func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let callback: EventHandlerUPP = { _, event, _ -> OSStatus in
            var hkID = EventHotKeyID()
            GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hkID
            )
            let firedID = hkID.id
            DispatchQueue.main.async {
                if let instance = GlobalHotkey.registry[firedID] {
                    NotificationCenter.default.post(name: instance.notificationName, object: nil)
                }
            }
            return noErr
        }
        var handlerRef: EventHandlerRef?
        InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            nil,
            &handlerRef
        )
    }

    private func register() {
        guard keyCode != 0, modifiers != 0 else { return }
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    private func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }
}
