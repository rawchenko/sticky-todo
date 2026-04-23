import SwiftUI
import AppKit

/// New-todo input bar. Swaps between the user's local `newTaskTitle` binding
/// and the onboarding autoplay's scripted buffer so the surrounding
/// `ContentView` tree isn't disturbed by per-char typing updates.
struct ScriptableInputBar: View {
    @Binding var userText: String
    let placeholder: String
    let font: NSFont
    let onSubmit: () -> Void

    @EnvironmentObject private var onboarding: OnboardingMode
    @EnvironmentObject private var scriptedInput: ScriptedInputBuffer
    @ObservedObject private var tweaks = LayoutTweaks.shared

    private var activeText: String {
        scriptedInput.isActive ? scriptedInput.text : userText
    }

    private var hasDraft: Bool {
        activeText.contains { !$0.isWhitespace && !$0.isNewline }
    }

    private var textBinding: Binding<String> {
        if scriptedInput.isActive {
            return Binding(
                get: { scriptedInput.text },
                set: { scriptedInput.text = $0 }
            )
        }
        return $userText
    }

    var body: some View {
        let allowsInput = onboarding.allowsNewTodoInput
        // Editable when either we're outside onboarding or the scene has
        // explicitly opened the new-todo gate (Scene 2 onward).
        let isEditable = !onboarding.isActive || allowsInput
        HStack(alignment: .bottom, spacing: 10) {
            AutoGrowingInputField(
                text: textBinding,
                placeholder: placeholder,
                font: font,
                textColor: NSColor(FloatListTheme.textPrimary),
                placeholderColor: .placeholderTextColor,
                maxLines: 5,
                onSubmit: onSubmit,
                focusOnAppear: false,
                isEditable: isEditable
            )
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .disabled(!allowsInput)

            Button(action: onSubmit) {
                Image(systemName: "arrow.up")
            }
            .floatListGlassButton(prominent: hasDraft)
            .disabled(!hasDraft || !allowsInput)
            .pointerCursor(hasDraft && allowsInput ? .pointingHand : nil)
            .animation(.easeInOut(duration: 0.15), value: hasDraft)
        }
        .padding(.leading, tweaks.inputLeadingPadding)
        .padding(.trailing, tweaks.inputTrailingPadding)
        .padding(.vertical, tweaks.inputVerticalPadding)
        .background(
            RoundedRectangle(cornerRadius: tweaks.inputCornerRadius, style: .continuous)
                .fill(FloatListTheme.inputFill)
        )
        .padding(.horizontal, 6)
        .padding(.bottom, 6)
        .animation(.easeOut(duration: 0.18), value: activeText)
    }
}
