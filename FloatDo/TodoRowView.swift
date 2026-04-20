import SwiftUI
import AppKit

struct WindowDragBlocker: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { BlockerView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class BlockerView: NSView {
        override var mouseDownCanMoveWindow: Bool { false }
    }
}

/// Detects two-finger horizontal trackpad swipes over its bounds and forwards
/// them as translation deltas. Vertical scrolls are left untouched so the
/// enclosing `ScrollView` keeps working normally.
struct TwoFingerSwipeDetector: NSViewRepresentable {
    var onBegan: () -> Void
    var onChanged: (CGFloat) -> Void
    /// `(total, predictedEnd)` — predicted end is a velocity-based projection.
    var onEnded: (CGFloat, CGFloat) -> Void
    var onCancelled: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = DetectorView()
        view.callbacks = (onBegan, onChanged, onEnded, onCancelled)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? DetectorView else { return }
        view.callbacks = (onBegan, onChanged, onEnded, onCancelled)
    }

    private final class DetectorView: NSView {
        typealias Callbacks = (
            began: () -> Void,
            changed: (CGFloat) -> Void,
            ended: (CGFloat, CGFloat) -> Void,
            cancelled: () -> Void
        )

        var callbacks: Callbacks?

        private var monitor: Any?

        private var accumulated: CGFloat = 0
        private var axis: Axis?
        private var tracking = false
        private var lastTimestamp: TimeInterval = 0
        private var velocity: CGFloat = 0

        private enum Axis { case horizontal, vertical }

        override var mouseDownCanMoveWindow: Bool { false }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil {
                installMonitorIfNeeded()
            } else {
                removeMonitor()
            }
        }

        deinit {
            removeMonitor()
        }

        private func installMonitorIfNeeded() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self else { return event }
                return self.handle(event)
            }
        }

        private func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        private func isCursorOverUs(_ event: NSEvent) -> Bool {
            guard let window, event.window === window else { return false }
            let pointInView = convert(event.locationInWindow, from: nil)
            return bounds.contains(pointInView)
        }

        private func resetState() {
            accumulated = 0
            axis = nil
            tracking = false
            lastTimestamp = 0
            velocity = 0
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            // Only trackpad swipes (precise deltas with phase info).
            guard event.hasPreciseScrollingDeltas else { return event }

            switch event.phase {
            case .mayBegin, .began:
                if isCursorOverUs(event) {
                    resetState()
                }
                return event

            case .changed:
                if !tracking && !isCursorOverUs(event) { return event }

                if axis == nil {
                    let dx = abs(event.scrollingDeltaX)
                    let dy = abs(event.scrollingDeltaY)
                    if dx > dy && dx > 1 {
                        axis = .horizontal
                        tracking = true
                        callbacks?.began()
                    } else if dy > 0 {
                        axis = .vertical
                    }
                }

                if tracking {
                    let dt = event.timestamp - lastTimestamp
                    if lastTimestamp > 0 && dt > 0 {
                        let instant = event.scrollingDeltaX / CGFloat(dt)
                        velocity = velocity * 0.6 + instant * 0.4
                    }
                    lastTimestamp = event.timestamp
                    accumulated += event.scrollingDeltaX
                    callbacks?.changed(accumulated)
                    return nil
                }
                return event

            case .ended:
                if tracking {
                    // Project ~120ms forward using smoothed velocity (px/s).
                    let predicted = accumulated + velocity * 0.12
                    callbacks?.ended(accumulated, predicted)
                    resetState()
                    return nil
                }
                resetState()
                return event

            case .cancelled:
                if tracking {
                    callbacks?.cancelled()
                    resetState()
                    return nil
                }
                resetState()
                return event

            default:
                return event
            }
        }
    }
}

struct RowHeightPreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGFloat] = [:]
    static func reduce(value: inout [UUID: CGFloat], nextValue: () -> [UUID: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// Reminders-style circular checkbox. Uses a standard `Toggle` under the hood;
/// this is the `ToggleStyle` that renders it.
struct TodoCheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            ZStack {
                if configuration.isOn {
                    Circle()
                        .fill(FloatDoTheme.success)
                        .frame(width: LayoutTweaks.shared.checkboxSize, height: LayoutTweaks.shared.checkboxSize)
                    Image(systemName: "checkmark")
                        .font(.system(size: LayoutTweaks.shared.checkmarkSize, weight: .bold))
                        .foregroundStyle(Color.white)
                } else {
                    Circle()
                        .strokeBorder(
                            Color.dynamic(
                                light: Color.black.opacity(0.35),
                                dark: Color.white.opacity(0.45)
                            ),
                            lineWidth: 1.5
                        )
                        .frame(width: LayoutTweaks.shared.checkboxSize, height: LayoutTweaks.shared.checkboxSize)
                }
            }
            .frame(width: 18, height: 18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerCursor(.pointingHand)
    }
}

struct TodoRowView: View {
    let item: TodoItem
    let isDragging: Bool
    let isDragActive: Bool
    let yOffset: CGFloat
    var onToggle: () -> Void
    var onDelete: () -> Void
    var onRename: (String) -> Void = { _ in }
    var onDragChanged: (CGFloat) -> Void = { _ in }
    var onDragEnded: (CGFloat) -> Void = { _ in }

    @State private var isHovering = false
    @State private var didPushCursor = false
    @State private var draftTitle = ""
    @State private var swipeOffset: CGFloat = 0
    @State private var hasCommittedHaptic = false
    @State private var rowWidth: CGFloat = 0
    @FocusState private var isEditorFocused: Bool
    @ObservedObject private var tweaks = LayoutTweaks.shared

    private var commitThreshold: CGFloat { max(80, rowWidth * 0.35) }

    private var showsStrikethroughOverlay: Bool {
        item.isCompleted && !isEditorFocused
    }

    private var titleColor: Color {
        if showsStrikethroughOverlay { return .clear }
        return item.isCompleted ? FloatDoTheme.textSecondary : FloatDoTheme.textPrimary
    }

    var body: some View {
        HStack(alignment: .top, spacing: tweaks.rowInnerSpacing) {
            Toggle(isOn: Binding(
                get: { item.isCompleted },
                set: { _ in onToggle() }
            )) {
                EmptyView()
            }
            .toggleStyle(TodoCheckboxToggleStyle())

            ZStack(alignment: .topLeading) {
                TextField("Task", text: $draftTitle, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: tweaks.bodyTextSize))
                    .foregroundStyle(titleColor)
                    .lineLimit(1...5)
                    .focused($isEditorFocused)
                    .onSubmit { isEditorFocused = false }
                    .onExitCommand(perform: cancelEdit)
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                if showsStrikethroughOverlay {
                    Text(item.title)
                        .font(.system(size: tweaks.bodyTextSize))
                        .strikethrough(true)
                        .foregroundStyle(FloatDoTheme.textSecondary)
                        .lineLimit(1...5)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .allowsHitTesting(false)
                }
            }
            .frame(minHeight: 18, alignment: .topLeading)
            .pointerCursor(.iBeam, active: !isDragActive)
        }
        .padding(.horizontal, tweaks.rowHorizontalPadding)
        .padding(.vertical, tweaks.rowVerticalPadding)
        .background(WindowDragBlocker())
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: tweaks.rowCornerRadius, style: .continuous))
        .offset(x: swipeOffset)
        .background(swipeRevealLayer)
        .background(
            TwoFingerSwipeDetector(
                onBegan: { hasCommittedHaptic = false },
                onChanged: { total in applySwipeOffset(total) },
                onEnded: { _, predicted in handleSwipeEnd(predictedEnd: predicted) },
                onCancelled: {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                        swipeOffset = 0
                    }
                    hasCommittedHaptic = false
                }
            )
        )
        .background(
            GeometryReader { geo in
                Color.clear
                    .preference(
                        key: RowHeightPreferenceKey.self,
                        value: [item.id: geo.size.height]
                    )
                    .onAppear { rowWidth = geo.size.width }
                    .onChange(of: geo.size.width) { _, new in rowWidth = new }
            }
        )
        .contentShape(Rectangle())
        .brightness(isDragging ? 0.04 : 0)
        .offset(y: yOffset)
        .scaleEffect(isDragging ? 1.03 : 1.0)
        .shadow(color: .black.opacity(isDragging ? 0.45 : 0), radius: 16, y: 6)
        .zIndex(isDragging ? 1 : 0)
        .pointerCursor(hoverCursor, active: !isDragActive)
        .onHover { hovering in
            guard !isDragActive else { return }
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .onChange(of: isDragActive) { _, active in
            if active && isHovering {
                isHovering = false
            }
        }
        .onChange(of: isEditorFocused) { _, focused in
            if !focused { commitEdit() }
        }
        .task(id: item.id) { draftTitle = item.title }
        .onChange(of: item.title) { _, new in
            if !isEditorFocused { draftTitle = new }
        }
        .contextMenu {
            Button(item.isCompleted ? "Mark Incomplete" : "Mark Complete") { onToggle() }
            Divider()
            Button("Delete", role: .destructive) { onDelete() }
        }
        .gesture(
            DragGesture(minimumDistance: 8, coordinateSpace: .named("list"))
                .onChanged { value in
                    if !didPushCursor {
                        NSCursor.closedHand.push()
                        didPushCursor = true
                    }
                    onDragChanged(value.translation.height)
                }
                .onEnded { value in
                    if didPushCursor {
                        NSCursor.pop()
                        didPushCursor = false
                    }
                    onDragEnded(value.translation.height)
                },
            including: isEditorFocused ? .subviews : .all
        )
    }

    private var swipeRevealLayer: some View {
        HStack(spacing: 0) {
            if swipeOffset > 0 {
                revealPill(
                    width: max(0, swipeOffset - tweaks.pillSpacing),
                    progress: min(1, swipeOffset / commitThreshold),
                    color: FloatDoTheme.success,
                    systemImage: "checkmark.circle.fill",
                    alignment: .leading
                )
            }
            Spacer(minLength: 0)
            if swipeOffset < 0 {
                revealPill(
                    width: max(0, -swipeOffset - tweaks.pillSpacing),
                    progress: min(1, -swipeOffset / commitThreshold),
                    color: FloatDoTheme.destructive,
                    systemImage: "trash.circle.fill",
                    alignment: .trailing
                )
            }
        }
        .allowsHitTesting(false)
    }

    private func revealPill(
        width: CGFloat,
        progress: CGFloat,
        color: Color,
        systemImage: String,
        alignment: Alignment
    ) -> some View {
        ZStack(alignment: alignment) {
            RoundedRectangle(cornerRadius: tweaks.rowCornerRadius, style: .continuous)
                .fill(color.opacity(progress))
            Image(systemName: systemImage)
                .foregroundStyle(.white)
                .font(.system(size: tweaks.actionIconSize + 4, weight: .semibold))
                .scaleEffect(hasCommittedHaptic ? 1.18 : 1.0)
                .frame(width: tweaks.checkboxSize)
                .padding(.leading, alignment == .leading ? tweaks.rowHorizontalPadding : 0)
                .padding(.trailing, alignment == .trailing ? tweaks.rowHorizontalPadding : 0)
        }
        .frame(width: width)
        .brightness(hasCommittedHaptic ? 0.08 : 0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hasCommittedHaptic)
    }

    private func applySwipeOffset(_ total: CGFloat) {
        let absT = abs(total)
        let sign: CGFloat = total >= 0 ? 1 : -1
        let threshold = commitThreshold

        // Linear up to the commit threshold, then saturate with diminishing
        // return so the row can still move but feels progressively firmer.
        let clamped: CGFloat
        if absT <= threshold {
            clamped = total
        } else {
            let maxExtra = threshold * 0.9
            let extra = absT - threshold
            let pulled = maxExtra * (1 - exp(-extra / maxExtra))
            clamped = sign * (threshold + pulled)
        }

        swipeOffset = clamped
        let crossed = abs(clamped) >= commitThreshold
        if crossed != hasCommittedHaptic {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            hasCommittedHaptic = crossed
        }
    }

    private func handleSwipeEnd(predictedEnd: CGFloat) {
        // Velocity-based commit: honor either the current offset crossing the
        // threshold or the velocity projection doing so in the same direction.
        let current = swipeOffset
        let sameDirection = (predictedEnd >= 0) == (current >= 0) || current == 0
        let projected = sameDirection ? predictedEnd : 0
        let decisionMag = max(abs(current), abs(projected))
        let direction: CGFloat = current != 0
            ? (current > 0 ? 1 : -1)
            : (predictedEnd > 0 ? 1 : -1)
        let shouldCommit = decisionMag >= commitThreshold

        let revert = Animation.spring(response: 0.38, dampingFraction: 0.82)

        if shouldCommit && direction > 0 {
            onToggle()
            withAnimation(revert) { swipeOffset = 0 }
        } else if shouldCommit && direction < 0 {
            withAnimation(.easeOut(duration: 0.18)) {
                swipeOffset = -max(rowWidth + 60, 400)
            } completion: {
                onDelete()
            }
        } else {
            withAnimation(revert) { swipeOffset = 0 }
        }
        hasCommittedHaptic = false
    }

    private func commitEdit() {
        let trimmed = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            draftTitle = item.title
            return
        }
        if trimmed != item.title {
            onRename(trimmed)
        }
    }

    private func cancelEdit() {
        draftTitle = item.title
        isEditorFocused = false
    }

    private var hoverCursor: NSCursor? { .openHand }

    private var rowBackground: some View {
        Rectangle()
            .fill(isDragging
                ? FloatDoTheme.controlFillStrong
                : (isHovering && !isDragActive ? FloatDoTheme.rowHover : .clear))
    }
}
