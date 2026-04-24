import AppKit
import CoreGraphics

enum ReorderCoordinateSpace {
    static let taskList = "taskListContent"
    static let listsDropdown = "listsMenu"
}

enum ReorderHaptics {
    static func fire(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .default)
    }
}

enum ReorderDragDirection: Equatable {
    case up
    case down
    case stationary

    init(delta: CGFloat, tolerance: CGFloat = 0.75, fallback: ReorderDragDirection = .stationary) {
        if delta > tolerance {
            self = .down
        } else if delta < -tolerance {
            self = .up
        } else {
            self = fallback
        }
    }
}

struct ReorderInteractionMath {
    static let downwardThresholdFraction: CGFloat = 0.68
    static let upwardThresholdFraction: CGFloat = 0.32
    static let autoScrollEdgeInset: CGFloat = 46
    static let maxAutoScrollSpeed: CGFloat = 520
    static let terminalDropInset: CGFloat = 18

    static func targetIndex(
        for overlayMidY: CGFloat,
        frames: [CGRect],
        direction: ReorderDragDirection
    ) -> Int {
        var target = 0

        for (index, frame) in frames.enumerated() {
            if overlayMidY >= thresholdY(for: frame, direction: direction) {
                target = index + 1
            } else {
                break
            }
        }

        guard let lastFrame = frames.last else { return target }
        guard direction != .up else { return target }

        let terminalThreshold = lastFrame.maxY - min(
            terminalDropInset,
            max(10, lastFrame.height * 0.45)
        )

        if overlayMidY >= terminalThreshold {
            return frames.count
        }

        return target
    }

    static func autoScrollVelocity(
        pointerY: CGFloat,
        viewport: CGRect,
        edgeInset: CGFloat = ReorderInteractionMath.autoScrollEdgeInset,
        maxSpeed: CGFloat = ReorderInteractionMath.maxAutoScrollSpeed
    ) -> CGFloat {
        guard !viewport.isEmpty else { return 0 }

        let activationInset = min(edgeInset, max(24, viewport.height * 0.22))
        let topZone = viewport.minY + activationInset
        let bottomZone = viewport.maxY - activationInset

        if pointerY < topZone {
            let progress = min(1, max(0, (topZone - pointerY) / activationInset))
            return -maxSpeed * easedEdgeProgress(progress)
        }

        if pointerY > bottomZone {
            let progress = min(1, max(0, (pointerY - bottomZone) / activationInset))
            return maxSpeed * easedEdgeProgress(progress)
        }

        return 0
    }

    private static func thresholdY(for frame: CGRect, direction: ReorderDragDirection) -> CGFloat {
        let fraction: CGFloat
        switch direction {
        case .down:
            fraction = downwardThresholdFraction
        case .up:
            fraction = upwardThresholdFraction
        case .stationary:
            fraction = 0.5
        }

        return frame.minY + (frame.height * fraction)
    }

    private static func easedEdgeProgress(_ progress: CGFloat) -> CGFloat {
        progress * progress
    }
}
