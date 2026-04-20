import SwiftUI

struct SettingsView: View {
    @AppStorage(AppearanceMode.storageKey) private var appearanceRaw = AppearanceMode.system.rawValue
    @StateObject private var launchAtLogin = LaunchAtLoginController()
    @StateObject private var hotkey = GlobalHotkey.toggleVisibility
    @StateObject private var expandHotkey = GlobalHotkey.expandCollapse

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: launchAtLogin.toggleBinding)
            }

            Section("Appearance") {
                Picker("Theme", selection: $appearanceRaw) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.label).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: appearanceRaw) { _, newValue in
                    (AppearanceMode(rawValue: newValue) ?? .system).apply()
                }
            }

            Section("Global shortcuts") {
                LabeledContent("Toggle panel") {
                    HotkeyRecorderView(
                        keyCode: hotkey.keyCode,
                        modifiers: hotkey.modifiers,
                        onCapture: { code, mods in
                            hotkey.setBinding(keyCode: code, modifiers: mods)
                        },
                        onClear: {
                            hotkey.clearBinding()
                        }
                    )
                    .frame(width: 200, height: 24)
                }
                LabeledContent("Expand / collapse") {
                    HotkeyRecorderView(
                        keyCode: expandHotkey.keyCode,
                        modifiers: expandHotkey.modifiers,
                        onCapture: { code, mods in
                            expandHotkey.setBinding(keyCode: code, modifiers: mods)
                        },
                        onClear: {
                            expandHotkey.clearBinding()
                        }
                    )
                    .frame(width: 200, height: 24)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 320)
    }
}

#Preview {
    SettingsView()
}
