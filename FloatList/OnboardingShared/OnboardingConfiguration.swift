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
}

struct OnboardingVariantDefinition: Equatable {
    let variant: OnboardingVariant
    let displayName: String
}

enum OnboardingSelectionSource: String {
    case appDefault
    case savedOverride
    case launchOverride

    var title: String {
        switch self {
        case .appDefault: return "App default"
        case .savedOverride: return "Saved override"
        case .launchOverride: return "Launch override"
        }
    }
}

struct ResolvedOnboardingVariant: Equatable {
    let definition: OnboardingVariantDefinition
    let source: OnboardingSelectionSource
}

enum OnboardingCatalog {
    /// Keep these identifiers stable. They are persisted in user defaults and
    /// used by launch overrides.
    static let classic = OnboardingVariantDefinition(
        variant: OnboardingVariant(rawValue: "classic"),
        displayName: "Classic"
    )

    static let immersive = OnboardingVariantDefinition(
        variant: OnboardingVariant(rawValue: "immersive"),
        displayName: "Immersive"
    )

    static let appDefault = immersive

    static let all = [immersive, classic]

    static func definition(for variant: OnboardingVariant) -> OnboardingVariantDefinition? {
        all.first { $0.variant == variant }
    }

    static func resolve(rawValue: String?) -> OnboardingVariantDefinition? {
        guard let normalized = normalize(rawValue) else { return nil }
        return all.first { $0.variant.rawValue == normalized }
    }

    private static func normalize(_ rawValue: String?) -> String? {
        let normalized = rawValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalized?.isEmpty == false ? normalized : nil
    }
}

enum OnboardingConfiguration {
    /// The app ships with Immersive as the main onboarding. Override with
    /// `-floatlist.onboarding.variant classic` when testing the Classic flow.
    static var activeSelection: ResolvedOnboardingVariant {
        if let launchOverride = launchOverrideDefinition {
            return ResolvedOnboardingVariant(definition: launchOverride, source: .launchOverride)
        }
        if let savedOverride = savedOverrideDefinition {
            return ResolvedOnboardingVariant(definition: savedOverride, source: .savedOverride)
        }
        return ResolvedOnboardingVariant(definition: OnboardingCatalog.appDefault, source: .appDefault)
    }

    static var activeVariant: OnboardingVariant {
        activeSelection.definition.variant
    }

    static var activeDefinition: OnboardingVariantDefinition {
        activeSelection.definition
    }

    static var activeSource: OnboardingSelectionSource {
        activeSelection.source
    }

    private static var launchOverrideDefinition: OnboardingVariantDefinition? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: "-\(OnboardingDefaults.variantKey)"),
              arguments.indices.contains(flagIndex + 1)
        else {
            return nil
        }
        return OnboardingCatalog.resolve(rawValue: arguments[flagIndex + 1])
    }

    private static var savedOverrideDefinition: OnboardingVariantDefinition? {
        guard let bundleID = Bundle.main.bundleIdentifier,
              let persisted = UserDefaults.standard.persistentDomain(forName: bundleID),
              let raw = persisted[OnboardingDefaults.variantKey] as? String
        else {
            return nil
        }
        return OnboardingCatalog.resolve(rawValue: raw)
    }
}
