import Foundation

extension Notification.Name {
    static let floatListOnboardingCompleted = Notification.Name("FloatList.onboardingCompleted")
}

enum OnboardingDefaults {
    static let completedKey = "floatlist.onboarding.completed"
    static let variantKey = "floatlist.onboarding.variant"
}

struct OnboardingVariant: RawRepresentable, Equatable, Hashable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    var title: String {
        rawValue.capitalized
    }
}

enum OnboardingConfiguration {
    /// The app ships with one active onboarding at a time. Override with
    /// `-floatlist.onboarding.variant alt` when testing the alternative flow.
    static var activeVariant: OnboardingVariant {
        let raw = UserDefaults.standard.string(forKey: OnboardingDefaults.variantKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        return OnboardingVariant(rawValue: raw?.isEmpty == false ? raw! : "original")
    }
}
