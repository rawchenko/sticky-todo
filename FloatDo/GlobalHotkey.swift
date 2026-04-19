import AppKit
import Carbon

extension Notification.Name {
    static let floatDoToggleHotkey = Notification.Name("FloatDo.toggleHotkey")
}

@MainActor
final class GlobalHotkey: ObservableObject {
    static let shared = GlobalHotkey()

    @Published private(set) var keyCode: UInt32
    @Published private(set) var modifiers: UInt32

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    private static let signature: OSType = {
        let chars = Array("FlDo".utf8)
        return chars.reduce(OSType(0)) { ($0 << 8) | OSType($1) }
    }()

    private static let keyCodeKey = "floatdo.hotkey.keyCode"
    private static let modifiersKey = "floatdo.hotkey.modifiers"

    private init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Self.keyCodeKey) != nil {
            self.keyCode = UInt32(defaults.integer(forKey: Self.keyCodeKey))
            self.modifiers = UInt32(defaults.integer(forKey: Self.modifiersKey))
        } else {
            self.keyCode = UInt32(kVK_ANSI_T)
            self.modifiers = UInt32(controlKey | optionKey)
        }
        installHandler()
        register()
    }

    func setBinding(keyCode newKey: UInt32, modifiers newMods: UInt32) {
        unregister()
        self.keyCode = newKey
        self.modifiers = newMods
        UserDefaults.standard.set(Int(newKey), forKey: Self.keyCodeKey)
        UserDefaults.standard.set(Int(newMods), forKey: Self.modifiersKey)
        register()
    }

    func clearBinding() {
        unregister()
        self.keyCode = 0
        self.modifiers = 0
        UserDefaults.standard.removeObject(forKey: Self.keyCodeKey)
        UserDefaults.standard.removeObject(forKey: Self.modifiersKey)
    }

    private func installHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let callback: EventHandlerUPP = { _, _, _ -> OSStatus in
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .floatDoToggleHotkey, object: nil)
            }
            return noErr
        }
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
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: 1)
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
