import SwiftUI

struct ClassicOnboardingSettingsContent: View {
    @ObservedObject private var tweaks = ClassicOnboardingTweaks.shared

    var body: some View {
        Section("Instruction chip") {
            TweakSlider(label: "Horizontal padding",
                        value: $tweaks.chipHorizontalPadding, range: 0...120, step: 1, suffix: "pt")
            TweakSlider(label: "Vertical padding",
                        value: $tweaks.chipVerticalPadding, range: 0...120, step: 1, suffix: "pt")
            TweakSlider(label: "Vertical spacing",
                        value: $tweaks.chipVerticalSpacing, range: 0...40, step: 1, suffix: "pt")
            TweakSlider(label: "Title size",
                        value: $tweaks.interactiveTitleSize, range: 14...44, step: 1, suffix: "pt")
            TweakSlider(label: "Body size",
                        value: $tweaks.interactiveBodySize, range: 10...24, step: 1, suffix: "pt")
        }

        Section("Progress bar") {
            TweakSlider(label: "Height",
                        value: $tweaks.progressBarHeight, range: 2...24, step: 1, suffix: "pt")
            TweakSlider(label: "Spring response",
                        value: $tweaks.progressSpringResponse, range: 10...150, step: 1, suffix: "/100")
            TweakSlider(label: "Spring damping",
                        value: $tweaks.progressSpringDamping, range: 40...100, step: 1, suffix: "/100")
        }

        Section("Timings") {
            TweakSlider(label: "Advance spring response",
                        value: $tweaks.advanceSpringResponse, range: 10...150, step: 1, suffix: "/100")
            TweakSlider(label: "Advance spring damping",
                        value: $tweaks.advanceSpringDamping, range: 40...100, step: 1, suffix: "/100")
        }

        Section {
            HStack {
                Spacer()
                Button("Reset to defaults") {
                    tweaks.resetToDefaults()
                }
            }
        }
    }
}
