import SwiftUI

/// Character-by-character reveal with per-char fade+blur. Respects Reduce
/// Motion (renders instantly) and exposes a single accessibility label for
/// the whole string.
struct ClassicOnboardingStaggeredCharacterText: View {
    let text: String
    let font: Font
    var perCharacterDelay: Double = 0.035
    var startDelay: Double = 0.0
    var color: Color = .primary
    var lineSpacing: CGFloat = 4

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                Text(text)
                    .font(font)
                    .foregroundStyle(color)
                    .lineSpacing(lineSpacing)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                CharacterCascade(
                    text: text,
                    font: font,
                    perCharacterDelay: perCharacterDelay,
                    startDelay: startDelay,
                    color: color,
                    lineSpacing: lineSpacing
                )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(text))
    }
}

private struct CharacterCascade: View {
    let text: String
    let font: Font
    let perCharacterDelay: Double
    let startDelay: Double
    let color: Color
    let lineSpacing: CGFloat

    @State private var revealedCount: Int = 0

    var body: some View {
        let characters = Array(text)
        ClassicOnboardingFlowLayout(lineSpacing: lineSpacing) {
            ForEach(Array(characters.enumerated()), id: \.offset) { idx, ch in
                RevealingCharacter(
                    character: ch,
                    font: font,
                    color: color,
                    isRevealed: idx < revealedCount
                )
            }
        }
        .task(id: text) {
            await runReveal(count: characters.count)
        }
    }

    private func runReveal(count: Int) async {
        revealedCount = 0
        if startDelay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(startDelay * 1_000_000_000))
        }
        let step = UInt64(perCharacterDelay * 1_000_000_000)
        for idx in 0..<count {
            if Task.isCancelled { return }
            revealedCount = idx + 1
            try? await Task.sleep(nanoseconds: step)
        }
    }
}

private struct RevealingCharacter: View {
    let character: Character
    let font: Font
    let color: Color
    let isRevealed: Bool

    var body: some View {
        Text(String(character))
            .font(font)
            .foregroundStyle(color)
            .opacity(isRevealed ? 1 : 0)
            .blur(radius: isRevealed ? 0 : 10)
            .animation(.spring(response: 0.6, dampingFraction: 0.82), value: isRevealed)
    }
}

/// Word-level fade-in for body copy.
struct ClassicOnboardingFadingWordsText: View {
    let text: String
    let font: Font
    var perWordDelay: Double = 0.06
    var startDelay: Double = 0.0
    var color: Color = .secondary

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                Text(text)
                    .font(font)
                    .foregroundStyle(color)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                WordCascade(
                    text: text,
                    font: font,
                    perWordDelay: perWordDelay,
                    startDelay: startDelay,
                    color: color
                )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(text))
    }
}

private struct WordCascade: View {
    let text: String
    let font: Font
    let perWordDelay: Double
    let startDelay: Double
    let color: Color

    @State private var revealedCount: Int = 0

    var body: some View {
        let words = text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        ClassicOnboardingFlowLayout(lineSpacing: 4, horizontalSpacing: 0) {
            ForEach(Array(words.enumerated()), id: \.offset) { idx, word in
                RevealingWord(
                    word: idx == words.count - 1 ? word : word + " ",
                    font: font,
                    color: color,
                    isRevealed: idx < revealedCount
                )
            }
        }
        .task(id: text) {
            await runReveal(count: words.count)
        }
    }

    private func runReveal(count: Int) async {
        revealedCount = 0
        if startDelay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(startDelay * 1_000_000_000))
        }
        let step = UInt64(perWordDelay * 1_000_000_000)
        for idx in 0..<count {
            if Task.isCancelled { return }
            revealedCount = idx + 1
            try? await Task.sleep(nanoseconds: step)
        }
    }
}

private struct RevealingWord: View {
    let word: String
    let font: Font
    let color: Color
    let isRevealed: Bool

    var body: some View {
        Text(word)
            .font(font)
            .foregroundStyle(color)
            .opacity(isRevealed ? 1 : 0)
            .offset(y: isRevealed ? 0 : 4)
            .animation(.easeOut(duration: 0.32), value: isRevealed)
    }
}

/// Wrap-aware layout for character/word runs.
struct ClassicOnboardingFlowLayout: Layout {
    var lineSpacing: CGFloat = 4
    var horizontalSpacing: CGFloat = 0

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        return arrange(subviews: subviews, maxWidth: maxWidth).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let arrangement = arrange(subviews: subviews, maxWidth: bounds.width)
        for (idx, position) in arrangement.positions.enumerated() {
            subviews[idx].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private struct Arrangement {
        var size: CGSize
        var positions: [CGPoint]
    }

    private func arrange(subviews: Subviews, maxWidth: CGFloat) -> Arrangement {
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth && currentX > 0 {
                currentY += lineHeight + lineSpacing
                currentX = 0
                lineHeight = 0
            }
            positions.append(CGPoint(x: currentX, y: currentY))
            currentX += size.width + horizontalSpacing
            lineHeight = max(lineHeight, size.height)
            totalWidth = max(totalWidth, currentX)
        }

        return Arrangement(
            size: CGSize(width: totalWidth, height: currentY + lineHeight),
            positions: positions
        )
    }
}
