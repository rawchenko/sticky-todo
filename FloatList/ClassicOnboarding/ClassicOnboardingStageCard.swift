import SwiftUI

/// Borderless-window content surface: material fill with rounded corners.
/// The window itself provides the shadow via `hasShadow = true`.
struct ClassicOnboardingStageCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
