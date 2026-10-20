import XCTest
import CindyCore

/// The motion of the start-position figure, from `StartPoseView.kt`: the loop it walks, the turn it
/// takes, how it is projected into the card, and how depth dims and thins the far limbs.
final class StartPoseMotionTests: XCTestCase {

    private let movements: [Exercise] = [.pullup, .pushup, .squat]

    private func assertJoints(_ a: [Float], _ b: [Float], _ message: String = "",
                              file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.count, b.count, message, file: file, line: line)
        for (x, y) in zip(a, b) { XCTAssertEqual(x, y, accuracy: 1e-3, message, file: file, line: line) }
    }

    /// the loop starts on the first frame and holds the last
    func testTheLoopStartsOnTheFirstFrameAndHoldsTheLast() {
        for movement in movements {
            let loop = StartPoses.of(movement)
            let start = StartPoseMotion.pose(of: loop, atMs: 0)
            assertJoints(start.joints, loop.frames[0], "\(movement)")
            XCTAssertEqual(start.alpha, 1)

            let settled = StartPoseMotion.pose(of: loop, atMs: StartPoseMotion.loopMs * StartPoseMotion.settleEnd)
            assertJoints(settled.joints, loop.frames[2], "\(movement)")

            let held = StartPoseMotion.pose(of: loop, atMs: StartPoseMotion.loopMs * 0.7)
            assertJoints(held.joints, loop.frames[2], "\(movement)")
            XCTAssertEqual(held.alpha, 1)
        }
    }

    /// the rewind fades to a quarter at its halfway point and comes back, rather than cutting
    func testTheRewindDipsToAQuarterAndComesBack() {
        let loop = StartPoses.of(.pullup)
        let top = StartPoseMotion.pose(of: loop, atMs: StartPoseMotion.loopMs * StartPoseMotion.holdEnd)
        XCTAssertEqual(top.alpha, 1, accuracy: 1e-3)
        assertJoints(top.joints, loop.frames[2])

        let middle = StartPoseMotion.holdEnd + (1 - StartPoseMotion.holdEnd) / 2
        XCTAssertEqual(StartPoseMotion.pose(of: loop, atMs: StartPoseMotion.loopMs * middle).alpha,
                       0.25, accuracy: 1e-3)
    }

    /// the loop repeats
    func testTheLoopRepeats() {
        let loop = StartPoses.of(.squat)
        for t: Float in [0, 300, 1500, 3100] {
            XCTAssertEqual(StartPoseMotion.pose(of: loop, atMs: t),
                           StartPoseMotion.pose(of: loop, atMs: t + StartPoseMotion.loopMs))
        }
    }

    /// the figure turns fifteen degrees either way, on a slower beat than the loop
    func testYawSwingsFifteenDegreesEitherWay() {
        XCTAssertEqual(StartPoseMotion.yaw(atMs: 0), 0, accuracy: 1e-3)
        XCTAssertEqual(StartPoseMotion.yaw(atMs: StartPoseMotion.yawMs / 4), 15, accuracy: 1e-3)
        XCTAssertEqual(StartPoseMotion.yaw(atMs: 3 * StartPoseMotion.yawMs / 4), -15, accuracy: 1e-3)
    }

    /// facing front, a joint is where its own depth puts it: nearer joints a little larger
    func testAFigureFacingFrontIsOnlyScaledByDepth() {
        for movement in movements {
            let loop = StartPoses.of(movement)
            let joints = loop.frames[2]
            let projected = StartPoseMotion.project(joints, loop: loop, yawDegrees: 0,
                                                    width: loop.boxWidth, height: loop.boxHeight)
            let cx = loop.boxWidth / 2, cy = loop.boxHeight / 2
            for j in 0..<StartPoses.joints {
                let x = joints[j * 3], y = joints[j * 3 + 1], z = joints[j * 3 + 2]
                let p = StartPoseMotion.focal / (StartPoseMotion.focal - z)
                XCTAssertEqual(projected.x[j], cx + (x - cx) * p, accuracy: 1e-3, "\(movement) joint \(j)")
                XCTAssertEqual(projected.y[j], cy + (y - cy) * p, accuracy: 1e-3, "\(movement) joint \(j)")
                XCTAssertEqual(projected.z[j], z, accuracy: 1e-3)
            }
        }
    }

    /// a view twice the box's size doubles the figure about the middle, and a wider one centres it
    func testTheFigureFitsTheCardAndIsCentredInIt() {
        let loop = StartPoses.of(.pullup)
        let joints = loop.frames[2]
        let wide = StartPoseMotion.project(joints, loop: loop, yawDegrees: 0,
                                           width: loop.boxWidth * 2 + 100, height: loop.boxHeight * 2)
        let plain = StartPoseMotion.project(joints, loop: loop, yawDegrees: 0,
                                            width: loop.boxWidth, height: loop.boxHeight)
        for j in 0..<StartPoses.joints {
            XCTAssertEqual(wide.x[j], plain.x[j] * 2 + 50, accuracy: 1e-3)
            XCTAssertEqual(wide.y[j], plain.y[j] * 2, accuracy: 1e-3)
        }
    }

    /// depth is the only cue: the nearest bone is brightest and the furthest is a third as bright
    func testDepthCues() {
        XCTAssertEqual(StartPoseMotion.depthUnit(-9), 0)
        XCTAssertEqual(StartPoseMotion.depthUnit(9), 1)
        XCTAssertEqual(StartPoseMotion.depthUnit(0), 0.5)
        XCTAssertEqual(StartPoseMotion.depthUnit(40), 1)
        XCTAssertEqual(StartPoseMotion.depthAlpha(-9), 0.30, accuracy: 1e-6)
        XCTAssertEqual(StartPoseMotion.depthAlpha(9), 1.0, accuracy: 1e-6)
    }

    /// bones are drawn furthest first, so a near limb crosses over a far one
    func testBonesAreDrawnFurthestFirst() {
        for movement in movements {
            let loop = StartPoses.of(movement)
            let projected = StartPoseMotion.project(loop.frames[2], loop: loop, yawDegrees: 15,
                                                    width: 132, height: 126)
            let order = StartPoseMotion.boneOrder(projected)
            XCTAssertEqual(order.sorted(), Array(0..<StartPoses.bones.count))
            let depths = order.map { i -> Float in
                let b = StartPoses.bones[i]
                return (projected.z[b[0]] + projected.z[b[1]]) / 2
            }
            XCTAssertEqual(depths, depths.sorted(), "\(movement)")
        }
    }
}
