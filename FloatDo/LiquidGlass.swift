import SwiftUI

/// Apply a Liquid Glass effect to a view, falling back to a flat fill on
/// macOS < 26. Use this for the *chips* that sit on top of the panel shell
/// (tab pills, icon buttons, input capsule, hover row, delete buttons).
extension View {
    @ViewBuilder
    func liquidGlass<S: Shape>(
        _ shape: S,
        tint: Color? = nil,
        interactive: Bool = false,
        fallbackFill: Color = Color.white.opacity(0.10)
    ) -> some View {
        if #available(macOS 26.0, *) {
            modifier(LiquidGlassModifier(shape: shape, tint: tint, interactive: interactive))
        } else {
            background(shape.fill(fallbackFill))
        }
    }

    /// Primary-action glass: more prominent, typically with a saturated tint.
    @ViewBuilder
    func liquidGlassProminent<S: Shape>(
        _ shape: S,
        tint: Color,
        interactive: Bool = true,
        fallbackFill: Color? = nil
    ) -> some View {
        if #available(macOS 26.0, *) {
            modifier(LiquidGlassModifier(shape: shape, tint: tint, interactive: interactive))
        } else {
            background(shape.fill(fallbackFill ?? tint.opacity(0.9)))
        }
    }

    /// Wrap children in a `GlassEffectContainer` so nested glass chips
    /// render efficiently and can blend/morph when they're close together.
    @ViewBuilder
    func liquidGlassContainer(spacing: CGFloat = 12) -> some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { self }
        } else {
            self
        }
    }

    /// Route to Apple's official `.buttonStyle(.glass)` / `.glassProminent`
    /// on macOS 26, with a sensible fallback for earlier systems.
    @ViewBuilder
    func floatDoGlassButton(
        prominent: Bool = false,
        size: ControlSize = .large
    ) -> some View {
        if #available(macOS 26.0, *) {
            if prominent {
                self.buttonStyle(.glassProminent)
                    .buttonBorderShape(.circle)
                    .controlSize(size)
            } else {
                self.buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .controlSize(size)
            }
        } else {
            self
                .buttonStyle(.plain)
                .foregroundStyle(FloatDoTheme.textPrimary)
                .padding(size == .large ? 9 : 6)
                .background(
                    Circle().fill(prominent ? FloatDoTheme.prominentChipFill : FloatDoTheme.controlFill)
                )
        }
    }
}

@available(macOS 26.0, *)
private struct LiquidGlassModifier<S: Shape>: ViewModifier {
    let shape: S
    let tint: Color?
    let interactive: Bool

    func body(content: Content) -> some View {
        content.glassEffect(resolvedGlass, in: shape)
    }

    private var resolvedGlass: Glass {
        var g: Glass = .regular
        g = g.tint(tint)
        g = g.interactive(interactive)
        return g
    }
}
