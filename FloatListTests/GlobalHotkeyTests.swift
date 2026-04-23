import Carbon
import XCTest
@testable import FloatList

@MainActor
final class GlobalHotkeyTests: XCTestCase {
    func testResolvedBindingFallsBackWhenStoredKeyCodeIsNegative() {
        let binding = GlobalHotkey.resolvedBinding(
            storedKeyCode: -1,
            storedModifiers: Int(controlKey | optionKey),
            fallbackKeyCode: UInt32(kVK_ANSI_T),
            fallbackModifiers: UInt32(controlKey | optionKey)
        )

        XCTAssertEqual(binding.keyCode, UInt32(kVK_ANSI_T))
        XCTAssertEqual(binding.modifiers, UInt32(controlKey | optionKey))
        XCTAssertTrue(binding.repairedStoredValue)
    }

    func testResolvedBindingFallsBackWhenStoredBindingIsPartial() {
        let binding = GlobalHotkey.resolvedBinding(
            storedKeyCode: Int(kVK_ANSI_E),
            storedModifiers: nil,
            fallbackKeyCode: UInt32(kVK_ANSI_T),
            fallbackModifiers: UInt32(controlKey | optionKey)
        )

        XCTAssertEqual(binding.keyCode, UInt32(kVK_ANSI_T))
        XCTAssertEqual(binding.modifiers, UInt32(controlKey | optionKey))
        XCTAssertTrue(binding.repairedStoredValue)
    }

    func testResolvedBindingMasksUnsupportedModifierBits() {
        let storedModifiers = UInt32(controlKey) | UInt32(optionKey) | 0x4000_0000
        let binding = GlobalHotkey.resolvedBinding(
            storedKeyCode: Int(kVK_ANSI_E),
            storedModifiers: Int(storedModifiers),
            fallbackKeyCode: UInt32(kVK_ANSI_T),
            fallbackModifiers: UInt32(controlKey | optionKey)
        )

        XCTAssertEqual(binding.keyCode, UInt32(kVK_ANSI_E))
        XCTAssertEqual(binding.modifiers, UInt32(controlKey | optionKey))
        XCTAssertTrue(binding.repairedStoredValue)
    }

    func testResolvedBindingKeepsValidStoredBinding() {
        let validModifiers = UInt32(cmdKey) | UInt32(shiftKey)
        let binding = GlobalHotkey.resolvedBinding(
            storedKeyCode: Int(kVK_ANSI_E),
            storedModifiers: Int(validModifiers),
            fallbackKeyCode: UInt32(kVK_ANSI_T),
            fallbackModifiers: UInt32(controlKey | optionKey)
        )

        XCTAssertEqual(binding.keyCode, UInt32(kVK_ANSI_E))
        XCTAssertEqual(binding.modifiers, validModifiers)
        XCTAssertFalse(binding.repairedStoredValue)
    }

    func testResolvedBindingKeepsExplicitlyDisabledStoredBinding() {
        let binding = GlobalHotkey.resolvedBinding(
            storedKeyCode: 0,
            storedModifiers: 0,
            fallbackKeyCode: UInt32(kVK_ANSI_T),
            fallbackModifiers: UInt32(controlKey | optionKey)
        )

        XCTAssertEqual(binding.keyCode, 0)
        XCTAssertEqual(binding.modifiers, 0)
        XCTAssertFalse(binding.repairedStoredValue)
    }
}
