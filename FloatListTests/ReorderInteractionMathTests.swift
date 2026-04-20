import XCTest
@testable import FloatList

final class ReorderInteractionMathTests: XCTestCase {
    func testTargetIndexMovingDownWaitsForDeeperThreshold() {
        let frames = sampleFrames()

        XCTAssertEqual(
            ReorderInteractionMath.targetIndex(for: 70, frames: frames, direction: .down),
            1
        )
        XCTAssertEqual(
            ReorderInteractionMath.targetIndex(for: 72, frames: frames, direction: .down),
            2
        )
    }

    func testTargetIndexMovingUpSwitchesEarlier() {
        let frames = sampleFrames()

        XCTAssertEqual(
            ReorderInteractionMath.targetIndex(for: 57, frames: frames, direction: .up),
            2
        )
        XCTAssertEqual(
            ReorderInteractionMath.targetIndex(for: 57, frames: frames, direction: .stationary),
            1
        )
    }

    func testTargetIndexStationaryUsesMidpointThreshold() {
        let frames = sampleFrames()

        XCTAssertEqual(
            ReorderInteractionMath.targetIndex(for: 64, frames: frames, direction: .stationary),
            2
        )
        XCTAssertEqual(
            ReorderInteractionMath.targetIndex(for: 63, frames: frames, direction: .stationary),
            1
        )
    }

    func testTargetIndexAllowsTerminalDropNearBottomEdge() {
        let frames = sampleFrames()

        XCTAssertEqual(
            ReorderInteractionMath.targetIndex(for: 109.5, frames: frames, direction: .down),
            2
        )
        XCTAssertEqual(
            ReorderInteractionMath.targetIndex(for: 110.1, frames: frames, direction: .down),
            3
        )
    }

    func testAutoScrollVelocityActivatesOnlyNearEdges() {
        let viewport = CGRect(x: 0, y: 0, width: 280, height: 320)

        XCTAssertEqual(
            ReorderInteractionMath.autoScrollVelocity(pointerY: 160, viewport: viewport),
            0,
            accuracy: 0.001
        )
        XCTAssertLessThan(
            ReorderInteractionMath.autoScrollVelocity(pointerY: 10, viewport: viewport),
            0
        )
        XCTAssertGreaterThan(
            ReorderInteractionMath.autoScrollVelocity(pointerY: 310, viewport: viewport),
            0
        )
    }

    func testAutoScrollVelocityScalesWithEdgeProximityAndCaps() {
        let viewport = CGRect(x: 0, y: 0, width: 280, height: 320)
        let farTop = abs(ReorderInteractionMath.autoScrollVelocity(pointerY: 40, viewport: viewport))
        let nearTop = abs(ReorderInteractionMath.autoScrollVelocity(pointerY: 4, viewport: viewport))

        XCTAssertGreaterThan(nearTop, farTop)
        XCTAssertLessThanOrEqual(nearTop, ReorderInteractionMath.maxAutoScrollSpeed)
    }

    private func sampleFrames() -> [CGRect] {
        [
            CGRect(x: 0, y: 0, width: 240, height: 40),
            CGRect(x: 0, y: 44, width: 240, height: 40),
            CGRect(x: 0, y: 88, width: 240, height: 40)
        ]
    }
}
