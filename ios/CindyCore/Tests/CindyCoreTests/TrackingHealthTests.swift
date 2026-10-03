import XCTest
import CindyCore

/// The monitor's job is to notice that the score has stopped being trustworthy *before* the athlete
/// does, and — just as importantly — to stay quiet on footage that is merely difficult.
///
/// The numbers these tests use are the ones measured by darkening real clips until they stopped
/// counting. A pull-up clip whose ground truth is five reps was 89% legible while scoring 5/5 and
/// 49% legible by the time it scored 3; a knee push-up clip sat at 31% legible the whole way through
/// and scored 12/12. Those two facts together are why the reading is a fraction of the session's own
/// baseline and never an absolute percentage.
///
/// Mirrors `TrackingHealthTest.kt`.
final class TrackingHealthTests: XCTestCase {

    private let monitor = TrackingHealthMonitor()
    private var clock: Int64 = 0

    /// Feeds `ms` of frames at 30fps, of which `legible` is the share the camera could read.
    ///
    /// The legible frames are spread through the run rather than grouped, because a window that
    /// happened to be filled with one or the other would test the arithmetic and not the rule.
    private func run(_ ms: Int64, legible: Float, exercise: Exercise = .pullup, softGain: Float = 1) {
        let until = clock + ms
        var index = 0
        while clock < until {
            // Deterministic interleave: every frame whose position crosses the next 1/legible
            // boundary is a legible one.
            let readable = legible > 0 && Int(Float(index) * legible) < Int(Float(index + 1) * legible)
            monitor.update(exercise: exercise, legible: readable, softGain: softGain, now: clock)
            clock += 33
            index += 1
        }
    }

    /// a session the camera can read stays good and says nothing
    func testASessionTheCameraCanReadStaysGoodAndSaysNothing() {
        run(10_000, legible: 1)
        XCTAssertEqual(monitor.health, .good)
        XCTAssertNil(monitor.advice)
    }

    /// footage that is merely difficult does not raise an alarm
    func testFootageThatIsMerelyDifficultDoesNotRaiseAnAlarm() {
        // The knee push-up clip: only a third of frames fully legible, start to finish, and it
        // scores 12 of 12. An absolute threshold anywhere near half would condemn it.
        run(20_000, legible: 0.31, exercise: .pushup)
        XCTAssertEqual(monitor.health, .good)
        XCTAssertNil(monitor.advice)
    }

    /// legibility falling away from the session's own baseline warns before reps are lost
    func testLegibilityFallingAwayFromTheSessionsOwnBaselineWarnsBeforeRepsAreLost() {
        run(10_000, legible: 0.90)
        XCTAssertEqual(monitor.health, .good)
        // 62% of a 0.90 baseline — past the warning line, short of the losing one. The clip was
        // still scoring every rep here, which is the moment a warning is worth giving.
        run(8_000, legible: 0.56)
        XCTAssertEqual(monitor.health, .weak)
        XCTAssertEqual(monitor.advice, "Losing you — more light helps")
    }

    /// a collapse past half the baseline reports reps are being missed
    func testACollapsePastHalfTheBaselineReportsRepsAreBeingMissed() {
        run(10_000, legible: 0.90)
        run(8_000, legible: 0.20)
        XCTAssertEqual(monitor.health, .lost)
    }

    /// a brief dropout inside the dwell never reaches the athlete
    func testABriefDropoutInsideTheDwellNeverReachesTheAthlete() {
        run(10_000, legible: 1)
        // Two seconds of nothing — a pull-up hiding its own wrists, or a walk past the camera.
        run(2_000, legible: 0)
        XCTAssertEqual(monitor.health, .good)
        XCTAssertNil(monitor.advice)
    }

    /// darkness is only claimed when the detector measured a dark picture
    func testDarknessIsOnlyClaimedWhenTheDetectorMeasuredADarkPicture() {
        run(10_000, legible: 0.90)
        run(8_000, legible: 0.10, softGain: 6)
        XCTAssertEqual(monitor.health, .lost)
        XCTAssertEqual(monitor.advice, "Too dark to count — tap +1")
    }

    /// an empty but well-lit frame is not blamed on the light
    func testAnEmptyButWellLitFrameIsNotBlamedOnTheLight() {
        run(10_000, legible: 0.90)
        // Same collapse, but the crop needed no brightening — so the app cannot claim darkness, and
        // says the one thing it does know.
        run(8_000, legible: 0.10, softGain: 1)
        XCTAssertEqual(monitor.health, .lost)
        XCTAssertEqual(monitor.advice, "Can't see you — tap +1")
    }

    /// recovering clears the advice without making the athlete wait
    func testRecoveringClearsTheAdviceWithoutMakingTheAthleteWait() {
        run(10_000, legible: 0.90)
        run(8_000, legible: 0.10)
        XCTAssertEqual(monitor.health, .lost)
        // A light going on should read as having worked, so recovery is not held for the dwell.
        run(5_000, legible: 0.90)
        XCTAssertEqual(monitor.health, .good)
        XCTAssertNil(monitor.advice)
    }

    /// each movement is judged against its own baseline
    func testEachMovementIsJudgedAgainstItsOwnBaseline() {
        // Pull-ups need both wrists overhead and are the first thing a fading light takes; squats
        // need ankles and survive far longer. A squat held to the pull-up's baseline would look
        // healthy when it was not, and vice versa.
        run(10_000, legible: 0.90, exercise: .pullup)
        run(10_000, legible: 0.40, exercise: .squat)
        // 0.40 is under half the pull-up baseline, but it is the only squat reading there is, so
        // it establishes the squat baseline rather than condemning it.
        XCTAssertEqual(monitor.health, .good)
    }

    /// time spent unable to read the athlete is accumulated
    func testTimeSpentUnableToReadTheAthleteIsAccumulated() {
        run(10_000, legible: 0.90)
        XCTAssertEqual(monitor.lostMs, 0)
        run(12_000, legible: 0.10)
        XCTAssertEqual(monitor.health, .lost)
        // The dwell and the window are not counted as lost time — only what followed them.
        XCTAssertGreaterThan(monitor.lostMs, 3_000, "expected several seconds of lost time, got \(monitor.lostMs)")
        XCTAssertLessThan(monitor.lostMs, 12_000)
    }

    /// a moved camera forgets the baseline but not the damage
    func testAMovedCameraForgetsTheBaselineButNotTheDamage() {
        run(10_000, legible: 0.90)
        run(12_000, legible: 0.10)
        let suffered = monitor.lostMs
        XCTAssertGreaterThan(suffered, 0)
        monitor.reframe()
        // The new framing gets to establish its own baseline from scratch...
        run(10_000, legible: 0.45)
        XCTAssertEqual(monitor.health, .good)
        // ...but the reps already missed were still missed.
        XCTAssertGreaterThanOrEqual(monitor.lostMs, suffered)
    }

    /// nothing is reported before the window has filled
    func testNothingIsReportedBeforeTheWindowHasFilled() {
        run(2_000, legible: 0)
        XCTAssertEqual(monitor.health, .good)
        XCTAssertNil(monitor.advice)
    }

    /// reset returns the monitor to a fresh session
    func testResetReturnsTheMonitorToAFreshSession() {
        run(10_000, legible: 0.90)
        run(12_000, legible: 0.10)
        XCTAssertNotNil(monitor.advice)
        monitor.reset()
        XCTAssertEqual(monitor.health, .good)
        XCTAssertNil(monitor.advice)
        XCTAssertEqual(monitor.lostMs, 0)
        XCTAssertEqual(monitor.weakMs, 0)
    }

    /// a session that is unreadable from the first frame is not called healthy
    func testASessionThatIsUnreadableFromTheFirstFrameIsNotCalledHealthy() {
        // The case a purely relative reading cannot see: there is no good baseline to fall away
        // from, because nothing ever worked. Measured on a clip made bright but noisy — the regime
        // brightening cannot rescue — where not one frame in the whole clip was legible.
        run(12_000, legible: 0, softGain: 2.4)
        XCTAssertEqual(monitor.health, .lost)
        XCTAssertEqual(monitor.advice, "Too dark to count — tap +1")
    }

    /// a session that starts badly still recovers when the light comes on
    func testASessionThatStartsBadlyStillRecoversWhenTheLightComesOn() {
        run(12_000, legible: 0)
        XCTAssertEqual(monitor.health, .lost)
        run(8_000, legible: 0.8)
        XCTAssertEqual(monitor.health, .good)
        XCTAssertNil(monitor.advice)
    }
}
