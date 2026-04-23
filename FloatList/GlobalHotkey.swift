import AppKit
import Carbon

extension Notification.Name {
    static let floatListToggleHotkey = Notification.Name("FloatList.toggleHotkey")
    static let floatListExpandCollapseHotkey = Notification.Name("FloatList.expandCollapseHotkey")
}

@MainActor
final class GlobalHotkey: ObservableObject {
    struct ResolvedBinding: Equatable {
        let keyCode: UInt32
        let modifiers: UInt32
        let repairedStoredValue: Bool
    }

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

    /// Legacy alias for the single-hotkey API.
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

    private static let supportedModifierMask = UInt32(cmdKey | optionKey | controlKey | shiftKey)
    private static let maxSupportedKeyCode = UInt32(UInt16.max)

    private static var handlerRef: EventHandlerRef?
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
        let resolvedBinding = Self.resolvedBinding(
            storedKeyCode: Self.defaultsInteger(forKey: keyCodeKey, in: defaults),
            storedModifiers: Self.defaultsInteger(forKey: modifiersKey, in: defaults),
            fallbackKeyCode: defaultKeyCode,
            fallbackModifiers: defaultModifiers
        )
        self.keyCode = resolvedBinding.keyCode
        self.modifiers = resolvedBinding.modifiers

        if resolvedBinding.repairedStoredValue {
            if resolvedBinding.keyCode == 0 || resolvedBinding.modifiers == 0 {
                defaults.removeObject(forKey: keyCodeKey)
                defaults.removeObject(forKey: modifiersKey)
            } else {
                defaults.set(Int(resolvedBinding.keyCode), forKey: keyCodeKey)
                defaults.set(Int(resolvedBinding.modifiers), forKey: modifiersKey)
            }
        }

        Self.registry[id] = self
        Self.installHandlerIfNeeded()
        register()
    }

    func setBinding(keyCode newKey: UInt32, modifiers newMods: UInt32) {
        guard let binding = Self.normalizedBinding(keyCode: Int64(newKey), modifiers: Int64(newMods)) else {
            NSLog(
                "FloatList ignored invalid hotkey binding for %@: keyCode=%@ modifiers=%@",
                keyCodeKey,
                String(newKey),
                String(newMods)
            )
            return
        }

        unregister()
        self.keyCode = binding.keyCode
        self.modifiers = binding.modifiers
        UserDefaults.standard.set(Int(binding.keyCode), forKey: keyCodeKey)
        UserDefaults.standard.set(Int(binding.modifiers), forKey: modifiersKey)
        register()
    }

    func clearBinding() {
        unregister()
        self.keyCode = 0
        self.modifiers = 0
        UserDefaults.standard.set(0, forKey: keyCodeKey)
        UserDefaults.standard.set(0, forKey: modifiersKey)
    }

    private static func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let callback: EventHandlerUPP = { _, event, _ -> OSStatus in
            var hkID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hkID
            )
            guard status == noErr else {
                GlobalHotkey.logCarbonError(status, action: "read hotkey event")
                return status
            }
            let firedID = hkID.id
            DispatchQueue.main.async {
                if let instance = GlobalHotkey.registry[firedID] {
                    NotificationCenter.default.post(name: instance.notificationName, object: nil)
                }
            }
            return noErr
        }
        var newHandlerRef: EventHandlerRef?
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            nil,
            &newHandlerRef
        )
        guard status == noErr, let newHandlerRef else {
            GlobalHotkey.logCarbonError(status, action: "install hotkey handler")
            return
        }
        handlerRef = newHandlerRef
    }

    private func register() {
        guard keyCode != 0, modifiers != 0 else { return }
        guard Self.handlerRef != nil else { return }
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        var newHotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &newHotKeyRef
        )
        guard status == noErr else {
            Self.logCarbonError(status, action: "register hotkey \(id)")
            hotKeyRef = nil
            return
        }
        hotKeyRef = newHotKeyRef
    }

    private func unregister() {
        if let ref = hotKeyRef {
            let status = UnregisterEventHotKey(ref)
            if status != noErr {
                Self.logCarbonError(status, action: "unregister hotkey \(id)")
            }
            hotKeyRef = nil
        }
    }

    static func resolvedBinding(
        storedKeyCode: Int?,
        storedModifiers: Int?,
        fallbackKeyCode: UInt32,
        fallbackModifiers: UInt32
    ) -> ResolvedBinding {
        let fallbackBinding = normalizedFallbackBinding(
            keyCode: fallbackKeyCode,
            modifiers: fallbackModifiers
        )

        guard storedKeyCode != nil || storedModifiers != nil else {
            return ResolvedBinding(
                keyCode: fallbackBinding.keyCode,
                modifiers: fallbackBinding.modifiers,
                repairedStoredValue: false
            )
        }

        guard let storedKeyCode, let storedModifiers else {
            return ResolvedBinding(
                keyCode: fallbackBinding.keyCode,
                modifiers: fallbackBinding.modifiers,
                repairedStoredValue: true
            )
        }

        if storedKeyCode == 0, storedModifiers == 0 {
            return ResolvedBinding(
                keyCode: 0,
                modifiers: 0,
                repairedStoredValue: false
            )
        }

        guard let binding = normalizedBinding(
            keyCode: Int64(storedKeyCode),
            modifiers: Int64(storedModifiers)
        ) else {
            return ResolvedBinding(
                keyCode: fallbackBinding.keyCode,
                modifiers: fallbackBinding.modifiers,
                repairedStoredValue: true
            )
        }

        let repaired = Int64(binding.keyCode) != Int64(storedKeyCode)
            || Int64(binding.modifiers) != Int64(storedModifiers)
        return ResolvedBinding(
            keyCode: binding.keyCode,
            modifiers: binding.modifiers,
            repairedStoredValue: repaired
        )
    }

    private static func defaultsInteger(forKey key: String, in defaults: UserDefaults) -> Int? {
        guard let value = defaults.object(forKey: key) as? NSNumber else {
            return nil
        }
        return Int(exactly: value.int64Value)
    }

    private static func normalizedFallbackBinding(keyCode: UInt32, modifiers: UInt32) -> (keyCode: UInt32, modifiers: UInt32) {
        if let binding = normalizedBinding(keyCode: Int64(keyCode), modifiers: Int64(modifiers)) {
            return binding
        }

        NSLog(
            "FloatList encountered an invalid default hotkey binding: keyCode=%@ modifiers=%@",
            String(keyCode),
            String(modifiers)
        )
        return (0, 0)
    }

    private static func normalizedBinding(keyCode: Int64, modifiers: Int64) -> (keyCode: UInt32, modifiers: UInt32)? {
        guard keyCode > 0, keyCode <= Int64(maxSupportedKeyCode), modifiers >= 0 else {
            return nil
        }

        let maskedModifiers = UInt32(truncatingIfNeeded: modifiers) & supportedModifierMask
        guard maskedModifiers != 0 else {
            return nil
        }

        return (UInt32(keyCode), maskedModifiers)
    }

    private static func logCarbonError(_ status: OSStatus, action: String) {
        NSLog("FloatList failed to %@: OSStatus %d", action, status)
    }
}
