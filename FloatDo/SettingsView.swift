import SwiftUI

struct SettingsView: View {
    fileprivate enum Tab: Hashable { case general, layout, about }

    @State private var selection: Tab = .general

    var body: some View {
        VStack(spacing: 0) {
            SettingsTabBar(selection: $selection)

            Divider()

            Group {
                switch selection {
                case .general: GeneralSettingsView()
                case .layout:  LayoutSettingsView()
                case .about:   AboutSettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 460, height: 520)
    }
}

private struct SettingsTabBar: View {
    @Binding var selection: SettingsView.Tab

    var body: some View {
        HStack(spacing: 4) {
            tab(.general, title: "General", systemImage: "gearshape")
            tab(.layout,  title: "Layout",  systemImage: "rectangle.3.group")
            tab(.about,   title: "About",   systemImage: "info.circle")
        }
        .padding(8)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func tab(_ value: SettingsView.Tab, title: String, systemImage: String) -> some View {
        let isSelected = selection == value
        Button {
            selection = value
        } label: {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .regular))
                Text(title)
                    .font(.system(size: 11))
            }
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.secondary.opacity(0.15) : .clear)
            )
        }
        .buttonStyle(.plain)
    }
}


private struct LayoutSettingsView: View {
    @ObservedObject private var tweaks = LayoutTweaks.shared

    var body: some View {
        Form {
            Section("Panel size") {
                TweakSlider(label: "Expanded width",
                            value: $tweaks.expandedWidth,
                            range: 280...520, step: 4, suffix: "pt")
                TweakSlider(label: "Expanded height",
                            value: $tweaks.expandedHeight,
                            range: 400...800, step: 4, suffix: "pt")
                TweakSlider(label: "Collapsed width",
                            value: $tweaks.collapsedWidth,
                            range: 32...96, step: 2, suffix: "pt")
                TweakSlider(label: "Collapsed height",
                            value: $tweaks.collapsedHeight,
                            range: 32...160, step: 2, suffix: "pt")
            }

            Section("Shape") {
                TweakSlider(label: "Expanded corner radius",
                            value: $tweaks.panelCornerRadius,
                            range: 0...40, step: 1, suffix: "pt")
                TweakSlider(label: "Handle corner radius",
                            value: $tweaks.handleCornerRadius,
                            range: 0...40, step: 1, suffix: "pt")
            }

            Section("Position") {
                TweakSlider(label: "Edge inset",
                            value: $tweaks.edgeInset,
                            range: 0...32, step: 1, suffix: "pt")
            }

            Section("Content") {
                TweakSlider(label: "Horizontal padding",
                            value: $tweaks.contentHorizontalPadding,
                            range: 0...32, step: 1, suffix: "pt")
                TweakSlider(label: "Top padding",
                            value: $tweaks.contentTopPadding,
                            range: 0...32, step: 1, suffix: "pt")
                TweakSlider(label: "Header–list gap",
                            value: $tweaks.contentBottomPadding,
                            range: 0...32, step: 1, suffix: "pt")
                TweakSlider(label: "Row spacing",
                            value: $tweaks.rowSpacing,
                            range: 0...16, step: 1, suffix: "pt")
            }

            Section("Input") {
                TweakSlider(label: "Corner radius",
                            value: $tweaks.inputCornerRadius,
                            range: 0...32, step: 1, suffix: "pt")
                TweakSlider(label: "Leading padding",
                            value: $tweaks.inputLeadingPadding,
                            range: 0...32, step: 1, suffix: "pt")
                TweakSlider(label: "Trailing padding",
                            value: $tweaks.inputTrailingPadding,
                            range: 0...32, step: 1, suffix: "pt")
                TweakSlider(label: "Vertical padding",
                            value: $tweaks.inputVerticalPadding,
                            range: 0...24, step: 1, suffix: "pt")
            }

            Section("List item") {
                TweakSlider(label: "Corner radius",
                            value: $tweaks.rowCornerRadius,
                            range: 0...24, step: 1, suffix: "pt")
                TweakSlider(label: "Horizontal padding",
                            value: $tweaks.rowHorizontalPadding,
                            range: 0...24, step: 1, suffix: "pt")
                TweakSlider(label: "Vertical padding",
                            value: $tweaks.rowVerticalPadding,
                            range: 0...24, step: 1, suffix: "pt")
                TweakSlider(label: "Inner spacing",
                            value: $tweaks.rowInnerSpacing,
                            range: 0...24, step: 1, suffix: "pt")
            }

            Section("Typography") {
                TweakSlider(label: "Body text size",
                            value: $tweaks.bodyTextSize,
                            range: 11...20, step: 1, suffix: "pt")
                TweakSlider(label: "Secondary text size",
                            value: $tweaks.secondaryTextSize,
                            range: 10...18, step: 1, suffix: "pt")
            }

            Section("Icons") {
                TweakSlider(label: "Checkbox size",
                            value: $tweaks.checkboxSize,
                            range: 14...28, step: 1, suffix: "pt")
                TweakSlider(label: "Checkmark size",
                            value: $tweaks.checkmarkSize,
                            range: 6...16, step: 1, suffix: "pt")
                TweakSlider(label: "Action icon size",
                            value: $tweaks.actionIconSize,
                            range: 9...18, step: 1, suffix: "pt")
                TweakSlider(label: "List emoji size",
                            value: $tweaks.listIconSize,
                            range: 10...22, step: 1, suffix: "pt")
                TweakSlider(label: "Add-list + size",
                            value: $tweaks.addListIconSize,
                            range: 8...20, step: 1, suffix: "pt")
            }

            Section("List pill") {
                TweakSlider(label: "Corner radius",
                            value: $tweaks.pillCornerRadius,
                            range: 0...24, step: 1, suffix: "pt")
                TweakSlider(label: "Horizontal padding",
                            value: $tweaks.pillHorizontalPadding,
                            range: 0...24, step: 1, suffix: "pt")
                TweakSlider(label: "Vertical padding",
                            value: $tweaks.pillVerticalPadding,
                            range: 0...16, step: 1, suffix: "pt")
                TweakSlider(label: "Icon-name spacing",
                            value: $tweaks.pillSpacing,
                            range: 0...16, step: 1, suffix: "pt")
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
        .formStyle(.grouped)
    }
}

private struct TweakSlider: View {
    let label: String
    @Binding var value: CGFloat
    let range: ClosedRange<CGFloat>
    let step: CGFloat
    let suffix: String

    var body: some View {
        LabeledContent(label) {
            HStack(spacing: 10) {
                Slider(value: $value, in: range, step: step)
                    .frame(minWidth: 160)
                Text("\(Int(value))\(suffix)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 48, alignment: .trailing)
            }
        }
    }
}

private struct GeneralSettingsView: View {
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
    }
}

private struct AboutSettingsView: View {
    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? "FloatDo"
    }

    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 16) {
            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 96, height: 96)
            }

            VStack(spacing: 4) {
                Text(appName)
                    .font(.system(size: 20, weight: .semibold))
                Text(version)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Text("A floating to-do panel that stays out of your way.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer(minLength: 0)

            Text("© 2026 rawchenko")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    SettingsView()
}
