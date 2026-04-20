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

/// Fires `onClickOutside` when a mouse-down lands outside the hosted view's
/// bounds while `isActive` is true. Used to exit the inline editor when the
/// user clicks elsewhere in the panel.
struct ClickOutsideDetector: NSViewRepresentable {
    var isActive: Bool
    var onClickOutside: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = DetectorView()
        view.onClickOutside = onClickOutside
        view.setActive(isActive)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? DetectorView else { return }
        view.onClickOutside = onClickOutside
        view.setActive(isActive)
    }

    private final class DetectorView: NSView {
        var onClickOutside: (() -> Void)?
        private var monitor: Any?
        private var active = false

        override var mouseDownCanMoveWindow: Bool { false }

        func setActive(_ newValue: Bool) {
            guard newValue != active else { return }
            active = newValue
            if active, window != nil { install() } else { remove() }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil {
                remove()
            } else if active {
                install()
            }
        }

        deinit { remove() }

        private func install() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                guard let self, let window = self.window else { return event }
                guard event.window === window else { return event }
                let pointInView = self.convert(event.locationInWindow, from: nil)
                if !self.bounds.contains(pointInView) {
                    self.onClickOutside?()
                }
                return event
            }
        }

        private func remove() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
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
                        .fill(FloatListTheme.success)
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
    let isTrashItem: Bool
    let isDragging: Bool
    let isDragActive: Bool
    let yOffset: CGFloat
    var subtitle: String? = nil
    var completionOverride: Bool? = nil
    var isExiting = false
    var onToggle: () -> Void
    var onDelete: () -> Void
    var onRestore: (() -> Void)? = nil
    var onRename: (String) -> Void = { _ in }
    var onDragChanged: (CGFloat) -> Void = { _ in }
    var onDragEnded: (CGFloat) -> Void = { _ in }
    var isToggleEnabled = true
    var isReorderEnabled = true

    @State private var isHovering = false
    @State private var didPushCursor = false
    @State private var draftTitle = ""
    @State private var swipeOffset: CGFloat = 0
    @State private var swipeBase: CGFloat = 0
    @State private var swipeRest: SwipeRestSide?
    @State private var hasCommittedHaptic = false
    @State private var rowWidth: CGFloat = 0
    @State private var isEditing = false
    @ObservedObject private var tweaks = LayoutTweaks.shared

    private enum SwipeRestSide { case leading, trailing }

    private var commitThreshold: CGFloat { max(110, rowWidth * 0.5) }
    private var revealThreshold: CGFloat { 28 }
    private var revealWidth: CGFloat { 72 }
    private var displayedIsCompleted: Bool { completionOverride ?? item.isCompleted }

    private var titleColor: Color {
        displayedIsCompleted ? FloatListTheme.textSecondary : FloatListTheme.textPrimary
    }

    var body: some View {
        HStack(alignment: .top, spacing: tweaks.rowInnerSpacing) {
            checkbox

            VStack(alignment: .leading, spacing: subtitle == nil ? 0 : 4) {
                ZStack(alignment: .topLeading) {
                    if isEditing {
                        AutoGrowingInputField(
                            text: $draftTitle,
                            placeholder: "Task",
                            font: NSFont.systemFont(ofSize: tweaks.bodyTextSize),
                            textColor: NSColor(FloatListTheme.textPrimary),
                            placeholderColor: .placeholderTextColor,
                            maxLines: 5,
                            onSubmit: commitAndExit,
                            onCancel: cancelEdit,
                            onFocusChange: { focused in
                                if !focused && isEditing { commitAndExit() }
                            },
                            focusOnAppear: true
                        )
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    } else {
                        Text(item.title)
                            .font(.system(size: tweaks.bodyTextSize))
                            .strikethrough(displayedIsCompleted)
                            .foregroundStyle(titleColor)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) { isEditing = true }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: tweaks.secondaryTextSize - 1, weight: .medium))
                        .foregroundStyle(FloatListTheme.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(FloatListTheme.controlFill)
                        )
                }
            }
            .frame(minHeight: 18, alignment: .topLeading)
            .pointerCursor(.iBeam, active: isEditing && !isDragActive)
        }
        .padding(.horizontal, tweaks.rowHorizontalPadding)
        .padding(.vertical, tweaks.rowVerticalPadding)
        .background(WindowDragBlocker())
        .background(
            ClickOutsideDetector(isActive: isEditing || swipeRest != nil) {
                if isEditing {
                    commitAndExit()
                }
                if swipeRest != nil {
                    closeReveal()
                }
            }
        )
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: tweaks.rowCornerRadius, style: .continuous))
        .offset(x: swipeOffset)
        .background(swipeRevealLayer)
        .background(
            TwoFingerSwipeDetector(
                onBegan: {
                    swipeBase = swipeOffset
                    swipeRest = nil
                    hasCommittedHaptic = abs(swipeOffset) >= commitThreshold
                },
                onChanged: { total in applySwipeOffset(total) },
                onEnded: { _, predicted in handleSwipeEnd(predictedEnd: predicted) },
                onCancelled: {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                        swipeOffset = 0
                    }
                    swipeBase = 0
                    swipeRest = nil
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
        .allowsHitTesting(!isExiting)
        .opacity(isExiting ? 0.78 : 1)
        .brightness(isDragging ? 0.04 : (isExiting ? -0.01 : 0))
        .offset(y: yOffset)
        .scaleEffect(isDragging ? 1.03 : (isExiting ? 0.992 : 1.0), anchor: .topLeading)
        .shadow(color: .black.opacity(isDragging ? 0.45 : 0), radius: 16, y: 6)
        .zIndex(isDragging ? 1 : 0)
        .pointerCursor(hoverCursor, active: !isDragActive && isReorderEnabled)
        .animation(.easeOut(duration: 0.18), value: isExiting)
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
        .onChange(of: item.listID) { _, _ in
            resetTransientRowState()
        }
        .onChange(of: isTrashItem) { _, _ in
            resetTransientRowState()
        }
        .task(id: item.id) {
            draftTitle = item.title
            resetTransientRowState()
        }
        .onChange(of: item.title) { _, new in
            if !isEditing { draftTitle = new }
        }
        .contextMenu {
            if isTrashItem {
                if let onRestore {
                    Button {
                        onRestore()
                    } label: {
                        Label("Restore", systemImage: "arrow.uturn.backward")
                    }
                }
                Divider()
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete Forever", systemImage: "trash")
                }
            } else {
                Button {
                    onToggle()
                } label: {
                    Label(
                        item.isCompleted ? "Mark Incomplete" : "Mark Complete",
                        systemImage: item.isCompleted ? "circle" : "checkmark.circle"
                    )
                }
                Divider()
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
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
            including: (isEditing || !isReorderEnabled) ? .subviews : .all
        )
    }

    private var checkbox: some View {
        Toggle(isOn: Binding(
            get: { displayedIsCompleted },
            set: { _ in onToggle() }
        )) {
            EmptyView()
        }
        .toggleStyle(TodoCheckboxToggleStyle())
        .allowsHitTesting(isToggleEnabled)
    }

    private var swipeRevealLayer: some View {
        HStack(spacing: 0) {
            if swipeOffset > 0 {
                revealPill(
                    width: max(0, swipeOffset - tweaks.pillSpacing),
                    progress: min(1, swipeOffset / commitThreshold),
                    color: isTrashItem ? FloatListTheme.controlFillStrong : FloatListTheme.success,
                    systemImage: isTrashItem ? "arrow.uturn.backward.circle.fill" : "checkmark.circle.fill",
                    alignment: .leading,
                    isInteractive: swipeRest == .leading,
                    action: performPrimaryAction
                )
            }
            Spacer(minLength: 0)
            if swipeOffset < 0 {
                revealPill(
                    width: max(0, -swipeOffset - tweaks.pillSpacing),
                    progress: min(1, -swipeOffset / commitThreshold),
                    color: FloatListTheme.destructive,
                    systemImage: "trash.circle.fill",
                    alignment: .trailing,
                    isInteractive: swipeRest == .trailing,
                    action: performSecondaryAction
                )
            }
        }
        .allowsHitTesting(swipeRest != nil)
    }

    @ViewBuilder
    private func revealPill(
        width: CGFloat,
        progress: CGFloat,
        color: Color,
        systemImage: String,
        alignment: Alignment,
        isInteractive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let displayProgress = isInteractive ? 1 : progress
        let pill = ZStack(alignment: alignment) {
            RoundedRectangle(cornerRadius: tweaks.rowCornerRadius, style: .continuous)
                .fill(color.opacity(displayProgress))
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
        .contentShape(Rectangle())

        if isInteractive {
            Button(action: action) { pill }
                .buttonStyle(.plain)
                .pointerCursor(.pointingHand)
        } else {
            pill
        }
    }

    private func applySwipeOffset(_ total: CGFloat) {
        let raw = swipeBase + total
        let absT = abs(raw)
        let sign: CGFloat = raw >= 0 ? 1 : -1
        let threshold = commitThreshold

        // Linear up to the commit threshold, then saturate with diminishing
        // return so the row can still move but feels progressively firmer.
        let clamped: CGFloat
        if absT <= threshold {
            clamped = raw
        } else {
            let maxExtra = threshold * 0.9
            let extra = absT - threshold
            let pulled = maxExtra * (1 - exp(-extra / maxExtra))
            clamped = sign * (threshold + pulled)
        }

        swipeOffset = clamped
        let crossed = abs(clamped) >= commitThreshold
        if crossed != hasCommittedHaptic {
            let performer = NSHapticFeedbackManager.defaultPerformer
            performer.perform(.levelChange, performanceTime: .now)
            if crossed {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
                    performer.perform(.levelChange, performanceTime: .now)
                }
            }
            hasCommittedHaptic = crossed
        }
    }

    private func handleSwipeEnd(predictedEnd: CGFloat) {
        // Velocity-based commit: honor either the current offset crossing the
        // threshold or the velocity projection doing so in the same direction.
        let current = swipeOffset
        let predictedOffset = swipeBase + predictedEnd
        let sameDirection = (predictedOffset >= 0) == (current >= 0) || current == 0
        let projected = sameDirection ? predictedOffset : 0
        let decisionMag = max(abs(current), abs(projected))
        let direction: CGFloat = current != 0
            ? (current > 0 ? 1 : -1)
            : (predictedOffset > 0 ? 1 : -1)

        if decisionMag >= commitThreshold {
            if direction > 0 {
                performPrimaryAction()
            } else {
                performSecondaryAction()
            }
        } else if decisionMag >= revealThreshold {
            snapToRest(direction: direction)
        } else {
            closeReveal()
        }
    }

    private func performPrimaryAction() {
        if isTrashItem {
            onRestore?()
        } else {
            onToggle()
        }
        closeReveal()
    }

    private func performSecondaryAction() {
        swipeRest = nil
        swipeBase = 0
        hasCommittedHaptic = false
        withAnimation(.easeOut(duration: 0.22)) {
            swipeOffset = -max(rowWidth + 60, 400)
        } completion: {
            onDelete()
        }
    }

    private func snapToRest(direction: CGFloat) {
        let side: SwipeRestSide = direction > 0 ? .leading : .trailing
        let target = direction * revealWidth
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
            swipeOffset = target
        }
        swipeRest = side
        swipeBase = target
        hasCommittedHaptic = false
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    private func closeReveal() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
            swipeOffset = 0
        }
        swipeRest = nil
        swipeBase = 0
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
        isEditing = false
    }

    private func commitAndExit() {
        commitEdit()
        isEditing = false
    }

    private func resetTransientRowState() {
        swipeOffset = 0
        swipeBase = 0
        swipeRest = nil
        hasCommittedHaptic = false
        isHovering = false
    }

    private var hoverCursor: NSCursor? {
        isReorderEnabled ? .openHand : nil
    }

    private var rowBackground: some View {
        let fill: Color
        if isDragging || isEditing {
            fill = FloatListTheme.controlFillStrong
        } else if isExiting {
            fill = FloatListTheme.controlFill.opacity(0.55)
        } else if isHovering && !isDragActive {
            fill = FloatListTheme.rowHover
        } else {
            fill = .clear
        }
        return Rectangle().fill(fill)
    }
}
