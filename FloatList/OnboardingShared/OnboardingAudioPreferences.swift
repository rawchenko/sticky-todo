import Foundation

enum OnboardingAudioPreferences {
    static let preferenceKey = "floatlist.onboarding.audio.enabled"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: preferenceKey) as? Bool ?? true
    }
}
