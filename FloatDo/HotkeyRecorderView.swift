import AppKit
import Carbon
import SwiftUI

struct HotkeyRecorderView: NSViewRepresentable {
    let keyCode: UInt32
    let modifiers: UInt32
    let onCapture: (UInt32, UInt32) -> Void
    let onClear: () -> Void

    func makeNSView(context: Context) -> HotkeyRecorderNSView {
        let view = HotkeyRecorderNSView()
        view.keyCode = keyCode
        view.modifiers = modifiers
        view.onCapture = onCapture
        view.onClear = onClear
        return view
    }

    func updateNSView(_ nsView: HotkeyRecorderNSView, context: Context) {
        nsView.keyCode = keyCode
        nsView.modifiers = modifiers
        nsView.onCapture = onCapture
        nsView.onClear = onClear
        nsView.refresh()
    }
}

final class HotkeyRecorderNSView: NSView {
    var keyCode: UInt32 = 0
    var modifiers: UInt32 = 0
    var onCapture: ((UInt32, UInt32) -> Void)?
    var onClear: (() -> Void)?

    private let label = NSTextField(labelWithString: "")
    private var isRecording = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    override var intrinsicContentSize: NSSize { NSSize(width: 160, height: 24) }
    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { false }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1

        label.translatesAutoresizingMaskIntoConstraints = false
        label.alignment = .center
        label.font = .systemFont(ofSize: 13)
        label.textColor = .labelColor
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8)
        ])
        refresh()
    }

    func refresh() {
        if isRecording {
            label.stringValue = "Recording… (⎋ cancel, ⌫ clear)"
            layer?.borderColor = NSColor.controlAccentColor.cgColor
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
        } else {
            label.stringValue = displayString()
            layer?.borderColor = NSColor.separatorColor.cgColor
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok {
            isRecording = true
            refresh()
        }
        return ok
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        refresh()
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        let code = event.keyCode

        if code == UInt16(kVK_Escape) {
            window?.makeFirstResponder(nil)
            return
        }

        if code == UInt16(kVK_Delete) || code == UInt16(kVK_ForwardDelete) {
            onClear?()
            window?.makeFirstResponder(nil)
            return
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let hasModifier = flags.contains(.command)
            || flags.contains(.option)
            || flags.contains(.control)
            || flags.contains(.shift)
        guard hasModifier else {
            NSSound.beep()
            return
        }

        let carbonMods = Self.carbonModifiers(from: flags)
        onCapture?(UInt32(code), carbonMods)
        window?.makeFirstResponder(nil)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else { return super.performKeyEquivalent(with: event) }
        keyDown(with: event)
        return true
    }

    private static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command)  { result |= UInt32(cmdKey) }
        if flags.contains(.option)   { result |= UInt32(optionKey) }
        if flags.contains(.control)  { result |= UInt32(controlKey) }
        if flags.contains(.shift)    { result |= UInt32(shiftKey) }
        return result
    }

    private func displayString() -> String {
        if keyCode == 0, modifiers == 0 { return "Click to record" }
        var result = ""
        if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if modifiers & UInt32(optionKey)  != 0 { result += "⌥" }
        if modifiers & UInt32(shiftKey)   != 0 { result += "⇧" }
        if modifiers & UInt32(cmdKey)     != 0 { result += "⌘" }
        result += KeyCodeTranslator.string(for: keyCode)
        return result
    }
}

enum KeyCodeTranslator {
    static func string(for keyCode: UInt32) -> String {
        if let mapped = specialKeys[keyCode] { return mapped }
        if let mapped = printableKeys[keyCode] { return mapped }
        return "Key \(keyCode)"
    }

    private static let specialKeys: [UInt32: String] = [
        UInt32(kVK_Space):      "Space",
        UInt32(kVK_Return):     "↩",
        UInt32(kVK_Tab):        "⇥",
        UInt32(kVK_Delete):     "⌫",
        UInt32(kVK_Escape):     "⎋",
        UInt32(kVK_LeftArrow):  "←",
        UInt32(kVK_RightArrow): "→",
        UInt32(kVK_UpArrow):    "↑",
        UInt32(kVK_DownArrow):  "↓",
        UInt32(kVK_Home):       "↖",
        UInt32(kVK_End):        "↘",
        UInt32(kVK_PageUp):     "⇞",
        UInt32(kVK_PageDown):   "⇟",
        UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3",
        UInt32(kVK_F4): "F4", UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6",
        UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8", UInt32(kVK_F9): "F9",
        UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12"
    ]

    private static let printableKeys: [UInt32: String] = [
        UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C",
        UInt32(kVK_ANSI_D): "D", UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
        UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_I): "I",
        UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
        UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O",
        UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
        UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_U): "U",
        UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
        UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
        UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2",
        UInt32(kVK_ANSI_3): "3", UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
        UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7", UInt32(kVK_ANSI_8): "8",
        UInt32(kVK_ANSI_9): "9",
        UInt32(kVK_ANSI_Minus):        "-",
        UInt32(kVK_ANSI_Equal):        "=",
        UInt32(kVK_ANSI_LeftBracket):  "[",
        UInt32(kVK_ANSI_RightBracket): "]",
        UInt32(kVK_ANSI_Semicolon):    ";",
        UInt32(kVK_ANSI_Quote):        "'",
        UInt32(kVK_ANSI_Comma):        ",",
        UInt32(kVK_ANSI_Period):       ".",
        UInt32(kVK_ANSI_Slash):        "/",
        UInt32(kVK_ANSI_Backslash):    "\\",
        UInt32(kVK_ANSI_Grave):        "`"
    ]
}
