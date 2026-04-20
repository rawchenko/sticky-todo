import SwiftUI
import AppKit

struct PointerCursorModifier: ViewModifier {
    let cursor: NSCursor?
    let isActive: Bool

    @State private var didPush = false
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                isHovering = hovering
                updatePush()
            }
            .onChange(of: cursor) { _, _ in
                if didPush { pop() }
                updatePush()
            }
            .onChange(of: isActive) { _, _ in
                updatePush()
            }
            .onDisappear {
                if didPush { pop() }
            }
    }

    private func updatePush() {
        let shouldPush = isHovering && isActive && cursor != nil
        if shouldPush && !didPush {
            cursor?.push()
            didPush = true
        } else if !shouldPush && didPush {
            pop()
        }
    }

    private func pop() {
        NSCursor.pop()
        didPush = false
    }
}

extension View {
    func pointerCursor(_ cursor: NSCursor?, active: Bool = true) -> some View {
        modifier(PointerCursorModifier(cursor: cursor, isActive: active))
    }
}
