import SwiftUI

/// Left-column instruction content. Progress bar stays mounted so its width
/// animates smoothly across steps; title/body/footer re-identify per step to
/// drive the reveal cascades + transition without disturbing the bar.
struct OnboardingInstructionChip: View {
    @ObservedObject var coordinator: OnboardingCoordinator
    @ObservedObject private var tweaks = OnboardingTweaks.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let title: String
    let bodyText: String
    let primaryTitle: String
    let onPrimary: () -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: tweaks.chipVerticalSpacing) {
            OnboardingProgressBar(
                currentIndex: coordinator.currentIndex,
                stepCount: coordinator.steps.count
            )

            VStack(alignment: .leading, spacing: tweaks.chipVerticalSpacing) {
                StaggeredCharacterText(
                    text: title,
                    font: .system(size: tweaks.interactiveTitleSize, weight: .semibold, design: .default),
                    startDelay: 0.1,
                    color: Color.primary
                )

                FadingWordsText(
                    text: bodyText,
                    font: .system(size: tweaks.interactiveBodySize, weight: .regular),
                    startDelay: 0.35,
                    color: Color.secondary
                )

                Spacer(minLength: 0)

                OnboardingFooterControls(
                    primaryTitle: primaryTitle,
                    onPrimary: onPrimary,
                    onBack: coordinator.isFirst ? nil : onBack
                )
            }
            .id(coordinator.currentStep.id)
            .transition(stepTransition)
        }
        .padding(.horizontal, tweaks.chipHorizontalPadding)
        .padding(.vertical, tweaks.chipVerticalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var stepTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.98)),
            removal: .opacity
        )
    }
}

/// Shared footer row: Back on the left, primary CTA on the right. `Back` is
/// omitted (pass nil) on the first step where it doesn't apply.
struct OnboardingFooterControls: View {
    let primaryTitle: String
    let onPrimary: () -> Void
    let onBack: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            if let onBack {
                OnboardingSecondaryPillButton(title: "Back", systemImage: "arrow.left", action: onBack)
                    .accessibilityLabel("Back")
            }

            Spacer(minLength: 0)

            OnboardingPrimaryPillButton(title: primaryTitle, action: onPrimary)
                .accessibilityLabel(primaryTitle)
        }
    }
}

/// Calm linear progress indicator. No step counter (that detail is noise for
/// a short autoplay demo); VoiceOver still gets "Step N of M" via the
/// accessibility label.
struct OnboardingProgressBar: View {
    @ObservedObject private var tweaks = OnboardingTweaks.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let currentIndex: Int
    let stepCount: Int

    private var progress: CGFloat {
        guard stepCount > 0 else { return 0 }
        return CGFloat(currentIndex + 1) / CGFloat(stepCount)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(Color.primary.opacity(0.55))
                    .frame(width: max(proxy.size.width * progress, 6))
                    .animation(reduceMotion ? nil : tweaks.progressSpring, value: progress)
            }
        }
        .frame(height: tweaks.progressBarHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(currentIndex + 1) of \(stepCount)")
    }
}

/// Dark pill button — the step's main forward action. Bound to the
/// default keyboard action so Return advances when focus is anywhere in
/// the onboarding card.
struct OnboardingPrimaryPillButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Image(systemName: "return")
                    .imageScale(.small)
            }
        }
        .buttonStyle(OnboardingPrimaryPillButtonStyle())
        .keyboardShortcut(.defaultAction)
    }
}

struct OnboardingPrimaryPillButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(scheme == .dark ? Color.black : Color.white)
            .padding(.horizontal, 18)
            .frame(minHeight: 36)
            .background(
                Capsule()
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.78 : 1.0))
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.85), value: configuration.isPressed)
    }
}

/// Muted pill for Back — same hit size as the primary so users don't have to
/// aim for a small target.
struct OnboardingSecondaryPillButton: View {
    let title: String
    let systemImage: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .imageScale(.small)
                }
                Text(title)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .buttonStyle(OnboardingSecondaryPillButtonStyle())
    }
}

struct OnboardingSecondaryPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color.primary.opacity(0.75))
            .padding(.horizontal, 14)
            .frame(minHeight: 32)
            .background(
                Capsule()
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.10 : 0.055))
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.85), value: configuration.isPressed)
    }
}
