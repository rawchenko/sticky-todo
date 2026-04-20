import SwiftUI

struct SettingsView: View {
    fileprivate enum Tab: Hashable {
        case general, layout, about

        var title: String {
            switch self {
            case .general: return "General"
            case .layout:  return "Layout"
            case .about:   return "About"
            }
        }

        var systemImage: String {
            switch self {
            case .general: return "gear"
            case .layout:  return "rectangle.3.group"
            case .about:   return "info.circle"
            }
        }
    }

    @State private var selection: Tab = .general

    var body: some View {
        VStack(spacing: 0) {
            SettingsTabBar(selection: $selection)

            Divider()
                .opacity(0.6)

            Group {
                switch selection {
                case .general: GeneralSettingsView()
                case .layout:  LayoutSettingsView()
                case .about:   AboutSettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 520, height: 560)
        .background(WindowTitleUpdater(title: selection.title))
        .background(
            // Hidden shortcut buttons: ⌘1 / ⌘2 / ⌘3 jump directly to each tab,
            // matching the system Settings convention.
            VStack {
                Button("") { selection = .general }
                    .keyboardShortcut("1", modifiers: .command)
                Button("") { selection = .layout }
                    .keyboardShortcut("2", modifiers: .command)
                Button("") { selection = .about }
                    .keyboardShortcut("3", modifiers: .command)
            }
            .opacity(0)
            .frame(width: 0, height: 0)
        )
    }
}

/// Keeps the hosting NSWindow's title in sync with the active tab so the window
/// chrome reads "General", "Layout", or "About" — mirroring system Settings.
private struct WindowTitleUpdater: NSViewRepresentable {
    let title: String

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            nsView.window?.title = title
        }
    }
}

private struct SettingsTabBar: View {
    @Binding var selection: SettingsView.Tab
    @Namespace private var indicator

    var body: some View {
        HStack(spacing: 2) {
            tab(.general)
            tab(.layout)
            tab(.about)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func tab(_ value: SettingsView.Tab) -> some View {
        let isSelected = selection == value
        Button {
            withAnimation(.easeOut(duration: 0.15)) {
                selection = value
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: value.systemImage)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(height: 22)
                Text(value.title)
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
            .fixedSize()
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .background(
                ZStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.secondary.opacity(0.15))
                            .matchedGeometryEffect(id: "tab", in: indicator)
                    }
                }
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

            Section {
                LabeledContent("Appearance") {
                    AppearancePicker(selection: $appearanceRaw)
                        .onChange(of: appearanceRaw) { _, newValue in
                            (AppearanceMode(rawValue: newValue) ?? .system).apply()
                        }
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

private struct AppearancePicker: View {
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 18) {
            ForEach(AppearanceMode.allCases) { mode in
                AppearanceOption(
                    mode: mode,
                    isSelected: selection == mode.rawValue
                ) {
                    selection = mode.rawValue
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct AppearanceOption: View {
    let mode: AppearanceMode
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                AppearanceThumbnail(mode: mode)
                    .frame(width: 76, height: 48)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(
                                isSelected ? Color.accentColor : Color.primary.opacity(0.12),
                                lineWidth: isSelected ? 2.5 : 1
                            )
                    )
                    .padding(2)

                Text(mode.label)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct AppearanceThumbnail: View {
    let mode: AppearanceMode

    var body: some View {
        ZStack {
            wallpaper

            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(windowFill)
                .overlay(alignment: .topLeading) {
                    HStack(spacing: 3) {
                        TrafficLight(color: Color(red: 1.0, green: 0.37, blue: 0.36))
                        TrafficLight(color: Color(red: 1.0, green: 0.74, blue: 0.18))
                        TrafficLight(color: Color(red: 0.29, green: 0.80, blue: 0.29))
                    }
                    .padding(.leading, 5)
                    .padding(.top, 5)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(windowStroke, lineWidth: 0.5)
                )
                .frame(width: 46, height: 30)
                .offset(x: -6, y: -3)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private var wallpaper: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        switch mode {
        case .system:
            shape.fill(
                LinearGradient(
                    stops: [
                        .init(color: Color(red: 0.78, green: 0.82, blue: 0.88), location: 0.0),
                        .init(color: Color(red: 0.78, green: 0.82, blue: 0.88), location: 0.5),
                        .init(color: Color(red: 0.16, green: 0.12, blue: 0.32), location: 0.5),
                        .init(color: Color(red: 0.16, green: 0.12, blue: 0.32), location: 1.0)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        case .light:
            shape.fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.40, green: 0.58, blue: 0.92),
                        Color(red: 0.24, green: 0.36, blue: 0.78)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        case .dark:
            shape.fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.22, green: 0.14, blue: 0.40),
                        Color(red: 0.10, green: 0.06, blue: 0.22)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }

    private var windowFill: Color {
        switch mode {
        case .system, .light: return Color(red: 0.97, green: 0.97, blue: 0.97)
        case .dark:           return Color(red: 0.18, green: 0.18, blue: 0.20)
        }
    }

    private var windowStroke: Color {
        switch mode {
        case .system, .light: return Color.black.opacity(0.08)
        case .dark:           return Color.white.opacity(0.08)
        }
    }
}

private struct TrafficLight: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 4, height: 4)
    }
}

private struct AboutSettingsView: View {
    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? "FloatList"
    }

    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 12)

            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 104, height: 104)
                    .shadow(color: Color.black.opacity(0.12), radius: 12, y: 4)
            }

            VStack(spacing: 4) {
                Text(appName)
                    .font(.system(size: 22, weight: .semibold))
                Text(version)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Text("A floating to-do panel that stays out of your way.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer(minLength: 0)

            Text("© 2026 rawchenko")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 4)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    SettingsView()
}
