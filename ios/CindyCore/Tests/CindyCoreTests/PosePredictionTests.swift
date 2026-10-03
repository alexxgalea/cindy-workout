import XCTest
import CindyCore

/// The bounds on the predicted skeleton.
///
/// Prediction exists to hide pipeline latency, and the way it goes wrong is by drawing a joint
/// where the body never went. Every test here is a bound on that: the cases assert what the
/// predictor *refuses* to do at least as often as what it does.
///
/// The reversal case is the one that matters. At the top of a pull-up the athlete stops rising and
/// starts falling, and that is the frame they are watching to see whether the rep counted.
///
/// Mirrors `PosePredictionTest.kt`.
final class PosePredictionTests: XCTestCase {

    private let ms: Int64 = 1_000_000

    /// A body spanning 200px, so the shift ceiling is a round 30px.
    private func body(_ x: Float, _ y: Float, score: Float = 0.9) -> [Keypoint] {
        (0..<KP.count).map { i in
            switch i {
            case KP.leftWrist: return Keypoint(x: x, y: y, score: score)
            // Two fixed joints 200px apart give bodySpan something to measure.
            case KP.leftAnkle: return Keypoint(x: 0, y: 200, score: 0.9)
            case KP.nose: return Keypoint(x: 0, y: 0, score: 0.9)
            default: return Keypoint(x: 0, y: 0, score: 0)
            }
        }
    }

    private func resolve(
        _ oldest: [Keypoint], _ previous: [Keypoint], _ newest: [Keypoint],
        gapMs: Int64 = 100, aheadMs: Int64 = 50, pipelineAgeMs: Float = 0
    ) -> [Float] {
        var out = [Float](repeating: 0, count: KP.count * 2)
        let t0: Int64 = 0
        let t1 = gapMs * ms
        let t2 = 2 * gapMs * ms
        PosePrediction.resolve(
            newest: newest, newestNanos: t2,
            previous: previous, previousNanos: t1,
            oldest: oldest, oldestNanos: t0,
            nowNanos: t2 + aheadMs * ms,
            pipelineAgeMs: pipelineAgeMs,
            out: &out
        )
        return out
    }

    private func wristY(_ out: [Float]) -> Float { out[KP.leftWrist * 2 + 1] }
    private func wristX(_ out: [Float]) -> Float { out[KP.leftWrist * 2] }

    /// the horizon covers the lag the pose arrived with, not just the redraw gap
    func testTheHorizonCoversTheLagThePoseArrivedWithNotJustTheRedrawGap() {
        // The bug this replaced: the horizon was measured from when the pose was PUBLISHED, so a
        // skeleton 200ms behind the body was carried forward by the tens of milliseconds since the
        // last redraw and stayed 200ms behind. Rising 10px per 100ms, 150ms of pipeline lag plus
        // 50ms since publication is 200ms of ground to make up: 20px, not 5px.
        let out = resolve(body(0, 120), body(0, 110), body(0, 100),
                          gapMs: 100, aheadMs: 50, pipelineAgeMs: 150)
        XCTAssertEqual(wristY(out), 80, accuracy: 0.001)
    }

    /// pipeline lag is still bounded by the cap
    func testPipelineLagIsStillBoundedByTheCap() {
        let absurd = resolve(body(0, 120), body(0, 110), body(0, 100),
                             gapMs: 100, aheadMs: 50, pipelineAgeMs: 9_000)
        let capped = resolve(body(0, 120), body(0, 110), body(0, 100),
                             gapMs: 100, aheadMs: 0, pipelineAgeMs: PosePrediction.maxAheadMs)
        XCTAssertEqual(wristY(absurd), wristY(capped), accuracy: 0.001)
    }

    /// a decelerating joint fades out before it has to be cut off
    func testADeceleratingJointFadesOutBeforeItHasToBeCutOff() {
        // Slowing from 30px per 100ms to 10px: still rising, so the sign rule allows it, but the
        // ramp scales it down. Without the ramp this would be a full 5px and then a hard drop to
        // zero on the frame the direction flipped — a visible snap at the top of every rep.
        let ramped = resolve(body(0, 140), body(0, 110), body(0, 100))
        let steady = resolve(body(0, 120), body(0, 110), body(0, 100))
        let rampedShift = 100 - wristY(ramped)
        let steadyShift = 100 - wristY(steady)
        XCTAssertGreaterThan(rampedShift, 0, "the ramp must still predict something, got \(rampedShift)")
        XCTAssertLessThan(rampedShift, steadyShift,
                          "a slowing joint must predict less than a steady one: \(rampedShift) vs \(steadyShift)")
    }

    /// an accelerating joint is not damped past constant velocity
    func testAnAcceleratingJointIsNotDampedPastConstantVelocity() {
        // Speeding up from 10px to 30px per 100ms. The ramp is clamped at 1, so this predicts
        // exactly the constant-velocity answer and never more — magnitude is only ever allowed to
        // make this more conservative.
        let out = resolve(body(0, 140), body(0, 130), body(0, 100))
        XCTAssertEqual(wristY(out), 85, accuracy: 0.001, "30px per 100ms carried 50ms")
    }

    /// without history the newest pose is drawn exactly
    func testWithoutHistoryTheNewestPoseIsDrawnExactly() {
        var out = [Float](repeating: 0, count: KP.count * 2)
        PosePrediction.resolve(
            newest: body(40, 90), newestNanos: 0,
            previous: nil, previousNanos: 0,
            oldest: nil, oldestNanos: 0,
            nowNanos: 500 * ms,
            pipelineAgeMs: 200,
            out: &out
        )
        XCTAssertEqual(wristX(out), 40, accuracy: 0.001)
        XCTAssertEqual(wristY(out), 90, accuracy: 0.001)
    }

    /// a joint moving steadily is carried forward along its velocity
    func testAJointMovingSteadilyIsCarriedForwardAlongItsVelocity() {
        // Rising 10px per 100ms; half a gap ahead should be 5px further up.
        let out = resolve(body(0, 120), body(0, 110), body(0, 100), gapMs: 100, aheadMs: 50)
        XCTAssertEqual(wristY(out), 95, accuracy: 0.001)
    }

    /// a reversal predicts nothing, which is the top of a pull-up
    func testAReversalPredictsNothingWhichIsTheTopOfAPullUp() {
        // Up 10px, then down 10px: the athlete has turned around.
        let out = resolve(body(0, 110), body(0, 100), body(0, 110), gapMs: 100, aheadMs: 50)
        XCTAssertEqual(wristY(out), 110, accuracy: 0.001,
                       "a joint that just changed direction must be drawn where it was last seen")
    }

    /// one axis reversing does not freeze the other
    func testOneAxisReversingDoesNotFreezeTheOther() {
        // Sliding steadily right while turning around vertically.
        let out = resolve(body(0, 110), body(10, 100), body(20, 110), gapMs: 100, aheadMs: 50)
        XCTAssertEqual(wristX(out), 25, accuracy: 0.001, "x is still rising and carries on")
        XCTAssertEqual(wristY(out), 110, accuracy: 0.001, "y reversed and holds")
    }

    /// a joint that was still is not set moving
    func testAJointThatWasStillIsNotSetMoving() {
        let out = resolve(body(0, 100), body(0, 100), body(0, 90), gapMs: 100, aheadMs: 50)
        XCTAssertEqual(wristY(out), 90, accuracy: 0.001)
    }

    /// a wild velocity is clamped to a share of the body
    func testAWildVelocityIsClampedToAShareOfTheBody() {
        // 400px in 100ms, extrapolated 50ms, would be 200px — a wrist across the whole picture.
        let out = resolve(body(0, 900), body(0, 500), body(0, 100), gapMs: 100, aheadMs: 50)
        let span = PosePrediction.bodySpan(body(0, 100))
        let limit = span * PosePrediction.maxShiftShare
        XCTAssertGreaterThan(limit, 0, "limit should be a real number, was \(limit)")
        XCTAssertEqual(wristY(out), 100 - limit, accuracy: 0.001)
    }

    /// prediction never reaches further ahead than the cap
    func testPredictionNeverReachesFurtherAheadThanTheCap() {
        // Asking 5 seconds ahead must give the same answer as asking at the cap.
        let far = resolve(body(0, 120), body(0, 110), body(0, 100), gapMs: 100, aheadMs: 5_000)
        let capped = resolve(body(0, 120), body(0, 110), body(0, 100),
                             gapMs: 100, aheadMs: Int64(PosePrediction.maxAheadMs))
        XCTAssertEqual(wristY(far), wristY(capped), accuracy: 0.001)
    }

    /// a stall is not a frame interval
    func testAStallIsNotAFrameInterval() {
        // A gap longer than maxGapMs says the pipeline stopped, not that the body moved slowly.
        let out = resolve(body(0, 120), body(0, 110), body(0, 100), gapMs: 600, aheadMs: 50)
        XCTAssertEqual(wristY(out), 100, accuracy: 0.001)
    }

    /// a joint unseen in any of the three poses is not predicted
    func testAJointUnseenInAnyOfTheThreePosesIsNotPredicted() {
        let faded = body(0, 110, score: 0.1)
        let out = resolve(faded, body(0, 105), body(0, 100), gapMs: 100, aheadMs: 50)
        XCTAssertEqual(wristY(out), 100, accuracy: 0.001)
    }

    /// every predicted joint stays within the cap of where it was seen
    func testEveryPredictedJointStaysWithinTheCapOfWhereItWasSeen() {
        // The property behind the individual cases: whatever the input, nothing moves far.
        let span = PosePrediction.bodySpan(body(0, 100))
        let limit = span * PosePrediction.maxShiftShare
        for dy: Float in [-900, -37, -1, 0, 1, 37, 900] {
            for dx: Float in [-900, -12, 0, 12, 900] {
                let out = resolve(body(-2 * dx, 100 - 2 * dy), body(-dx, 100 - dy), body(0, 100),
                                  gapMs: 100, aheadMs: 120)
                XCTAssertLessThanOrEqual(abs(wristX(out) - 0), limit + 0.001,
                                         "dx=\(dx) dy=\(dy) moved x by \(abs(wristX(out)))")
                XCTAssertLessThanOrEqual(abs(wristY(out) - 100), limit + 0.001,
                                         "dx=\(dx) dy=\(dy) moved y by \(abs(wristY(out) - 100))")
            }
        }
    }
}
