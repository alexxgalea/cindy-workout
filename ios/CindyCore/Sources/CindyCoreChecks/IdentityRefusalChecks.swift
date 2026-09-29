import Foundation
import CindyCore

/// A frame that has not been confirmed as the athlete must not count or teach, for every
/// movement, and a rep in flight survives only a bounded refusal. Mirrors the JVM
/// IdentityRefusalTest case for case.
func identityRefusalChecks() {
    var clock: Int64 = 0

    @discardableResult
    func feed(_ e: WorkoutEngine, _ pose: [Keypoint], identity: Bool = true, frames: Int = 1) -> RepEvent {
        var last = RepEvent.none
        for _ in 0..<frames {
            last = e.onFrame(pose, now: clock, identityStable: identity)
            clock += 100
        }
        return last
    }

    Check.suite("Identity refusal") {
        for movement in [Exercise.pushup, .squat] {
            let low = movement == .pushup ? PoseFixtures.pushup : PoseFixtures.squat
            let name = movement == .pushup ? "push-up" : "squat"

            let trusted = WorkoutEngine(fixedExercise: movement)
            feed(trusted, low(175), frames: 10)
            feed(trusted, low(80), frames: 10)
            feed(trusted, PoseFixtures.standing(), frames: 3)
            Check.equal(trusted.reps, 1, "three standing frames at the bottom of a \(name) book a rep when trusted")

            let refused = WorkoutEngine(fixedExercise: movement)
            feed(refused, low(175), frames: 10)
            feed(refused, low(80), frames: 10)
            feed(refused, PoseFixtures.standing(), identity: false, frames: 3)
            Check.equal(refused.reps, 0, "three standing frames at the bottom of a \(name) book nothing when refused")
        }

        let range = WorkoutEngine(fixedExercise: .pushup)
        feed(range, PoseFixtures.pushup(175), frames: 10)
        feed(range, PoseFixtures.pushup(80), frames: 10)
        let before = range.learnedRange
        feed(range, PoseFixtures.standing(), identity: false, frames: 5)
        Check.equal(range.learnedRange, before, "refused frames leave the learned range unchanged")

        let kept = WorkoutEngine(fixedExercise: .pushup)
        feed(kept, PoseFixtures.pushup(175), frames: 10)
        feed(kept, PoseFixtures.pushup(80), frames: 10)
        feed(kept, PoseFixtures.standing(), identity: false, frames: 5)
        feed(kept, PoseFixtures.pushup(175), frames: 10)
        Check.equal(kept.reps, 1, "a refused gap under a second keeps the push-up")

        let abandoned = WorkoutEngine(fixedExercise: .pushup)
        feed(abandoned, PoseFixtures.pushup(175), frames: 10)
        feed(abandoned, PoseFixtures.pushup(80), frames: 10)
        feed(abandoned, PoseFixtures.standing(), identity: false, frames: 15)
        feed(abandoned, PoseFixtures.pushup(175), frames: 10)
        Check.equal(abandoned.reps, 0, "a refused gap over a second abandons the push-up")
        feed(abandoned, PoseFixtures.pushup(80), frames: 10)
        feed(abandoned, PoseFixtures.pushup(175), frames: 10)
        Check.equal(abandoned.reps, 1, "the next full cycle after an abandoned one counts")

        // The gap runs from the first refused frame: the eleventh, 1000ms later, is exactly the limit.
        for (frames, expected) in [(11, 1), (12, 0)] {
            let squat = WorkoutEngine(fixedExercise: .squat)
            feed(squat, PoseFixtures.squat(175), frames: 10)
            feed(squat, PoseFixtures.squat(80), frames: 10)
            feed(squat, PoseFixtures.standing(), identity: false, frames: frames)
            feed(squat, PoseFixtures.squat(175), frames: 10)
            Check.equal(squat.reps, expected, "\(frames) refused frames: squat rep \(expected == 1 ? "kept" : "cleared")")

            let pull = WorkoutEngine()
            feed(pull, PoseFixtures.pullup(170), frames: 10)
            feed(pull, PoseFixtures.pullup(170), identity: false, frames: frames)
            feed(pull, PoseFixtures.pullup(60), frames: 10)
            Check.equal(pull.reps, expected, "\(frames) refused frames: pull-up rep \(expected == 1 ? "kept" : "cleared")")
        }

        let blackout = WorkoutEngine()
        feed(blackout, PoseFixtures.pullup(170), frames: 10)
        for _ in 0..<9 {
            var hidden = PoseFixtures.pullup(60)
            hidden[KP.nose] = .missing
            feed(blackout, hidden)
        }
        feed(blackout, PoseFixtures.pullup(60))
        Check.equal(blackout.reps, 0, "unreadable pull-up frames still clear the cycle after eight")

        let dwell = WorkoutEngine()
        for _ in 0..<5 {
            feed(dwell, PoseFixtures.pullup(170), frames: 10)
            feed(dwell, PoseFixtures.pullup(60), frames: 10)
        }
        for _ in 0..<10 {
            feed(dwell, PoseFixtures.pushup(175), frames: 10)
            feed(dwell, PoseFixtures.pushup(80), frames: 10)
            feed(dwell, PoseFixtures.pushup(175), frames: 10)
        }
        Check.equal(dwell.exercise, .squat, "the progression reaches squats")
        for _ in 0..<10 {
            feed(dwell, PoseFixtures.standing(), frames: 4)
            feed(dwell, PoseFixtures.standing(), identity: false, frames: 1)
        }
        Check.expect(dwell.awaitingStart, "refused frames interleaved with standing never complete the squat start dwell")
        feed(dwell, PoseFixtures.standing(), frames: 10)
        Check.expect(!dwell.awaitingStart, "500ms of uninterrupted confirmation completes the dwell")

        let setup = WorkoutEngine(fixedExercise: .pushup)
        setup.beginSetup()
        for _ in 0..<5 {
            _ = setup.onSetupFrame(PoseFixtures.pushup(175), now: clock, identityStable: false); clock += 100
            _ = setup.onSetupFrame(PoseFixtures.pushup(80), now: clock, identityStable: false); clock += 100
        }
        Check.equal(setup.learnedRange, 0, "refused setup frames teach no calibration")

        let bar = WorkoutEngine(fixedExercise: .pullup)
        bar.beginSetup()
        for _ in 0..<5 {
            _ = bar.onSetupFrame(PoseFixtures.pullup(170), now: clock, identityStable: false); clock += 100
        }
        Check.expect(!bar.barKnown, "refused hang frames teach no bar during setup")
    }
}
