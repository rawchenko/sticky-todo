import Foundation

/// Per-character state for the scripted typing animation. Kept out of
/// `OnboardingMode` so per-char `@Published` updates don't re-render the
/// whole onboarding tree — only the input field observes this instance.
@MainActor
final class ScriptedInputBuffer: ObservableObject {
    @Published var text: String = ""
    @Published var isActive: Bool = false
}
