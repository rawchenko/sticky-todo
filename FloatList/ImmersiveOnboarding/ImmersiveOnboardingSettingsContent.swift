import SwiftUI

struct ImmersiveOnboardingSettingsContent: View {
    @AppStorage(OnboardingAudioPreferences.preferenceKey) private var audioEnabled: Bool = true

    var body: some View {
        Section("Sound") {
            Toggle("Play sound effects", isOn: $audioEnabled)
        }
    }
}
