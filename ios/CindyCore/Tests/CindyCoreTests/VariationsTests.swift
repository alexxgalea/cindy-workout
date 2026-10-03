import XCTest
import CindyCore
import CindyFixtures

///
/// An adapted session is recorded as what it was, and ranked against its own kind: never quietly
/// filed as strict, never taking the strict record, never earning a rung on a ladder calibrated
/// against a workout it did not attempt — while still counting as a session the athlete did.
/// Carried over from the `CindyCoreChecks` executable: Variations. Every check keeps its original wording as
/// its assertion message.
final class VariationsTests: XCTestCase {

    func testVariations() {
        let adaptive = CindyProfile(pull: .bandAssistedPullUp, push: .kneePushUp, squat: .boxSquat)
        func attempt(_ rounds: Int, reps: Int = 0, at: Int64 = 1000, profile: CindyProfile? = .standard,
                    manualReps: Int = 0) -> Attempt {
            Attempt(rounds: rounds, reps: reps, atMillis: at, durationMs: 20 * 60 * 1000,
                   profile: profile, manualReps: manualReps)
        }

        // The profile survives a round trip, and reps tapped in survive with it.
        let saved = Records.decode(Records.encode([attempt(7, reps: 12, profile: adaptive, manualReps: 4)]))
        XCTAssertEqual(saved.count, 1, "one attempt round-trips")
        XCTAssertEqual(saved.first?.profile, adaptive, "an adaptive session stores the movements it was run with")
        XCTAssertEqual(saved.first?.manualReps, 4, "reps tapped in survive a round trip")

        // History written before the choice existed was standard Cindy, because that was the only
        // thing the app did.
        let v3 = Records.decode("v3|8|12|1700000000000|1200000|0|150000,160000").first
        XCTAssertEqual(v3?.profile, CindyProfile.standard, "attempts written before variations existed read as standard")
        XCTAssertEqual(v3?.rounds, 8, "and the rounds are unaffected")

        // The one case where guessing would be a lie: a movement this build does not know cannot be
        // filed under one it does, or an assisted session would silently promote into the strict
        // record.
        let unknown = Records.decode("v4|8|0|1700000000000|1200000|0||ONE_ARM_PULL_UP|STANDARD_PUSH_UP|AIR_SQUAT|0").first
        XCTAssertEqual(unknown?.profile == nil, true, "an unrecognised movement leaves the profile unknown")
        XCTAssertEqual(unknown?.rounds, 8, "but the session itself is still theirs")

        // Separate records, and not merely "standard versus the rest": two different adaptations are
        // no more comparable to each other than either is to the strict movement.
        let history = [
            attempt(8, at: 1, profile: .standard),
            attempt(20, at: 2, profile: adaptive)
        ]
        XCTAssertEqual(Records.bestIn(history, profile: .standard)?.rounds, 8, "the strict record is untouched")
        XCTAssertEqual(Records.bestIn(history, profile: adaptive)?.rounds, 20, "an adaptive result never becomes it")

        let knees = CindyProfile(push: .kneePushUp)
        let box = CindyProfile(squat: .boxSquat)
        let twoAdaptations = [attempt(9, at: 1, profile: knees), attempt(14, at: 2, profile: box)]
        XCTAssertEqual(Records.bestIn(twoAdaptations, profile: knees)?.rounds, 9, "each adaptation keeps its own record")
        XCTAssertEqual(Records.bestIn(twoAdaptations, profile: box)?.rounds, 14, "the other adaptation does not share it")
        XCTAssertEqual(Records.bestIn(twoAdaptations, profile: .standard) == nil, true, "and neither is the strict record")

        // The strict ladder and the benchmark do not rank a session they do not describe.
        XCTAssertEqual(attempt(12).level, .intermediate, "a standard session gets a rung")
        XCTAssertEqual(attempt(12, profile: adaptive).level == nil, true, "an adaptive session gets no rung")
        XCTAssertEqual(attempt(12).caption, "Intermediate", "a standard caption is the rung")
        XCTAssertEqual(
            attempt(28, profile: adaptive).caption,
            "Adaptive Cindy · band-assisted pull-ups · knee push-ups · box squats",
            "an adaptive caption names what changed instead"
        )
        XCTAssertEqual(Records.beatsBenchmark(attempt(28)), true, "a strict score can pass the benchmark")
        XCTAssertEqual(Records.beatsBenchmark(attempt(28, profile: adaptive)), false,
                   "an adaptive session never does, however many rounds")

        // The picker's own memory: a preference, not a record, so an unknown choice can safely fall
        // back to standard rather than staying unknown.
        XCTAssertEqual(Variations.decode(Variations.encode(adaptive)), adaptive, "the chosen profile round-trips")
        XCTAssertEqual(Variations.decode(nil), CindyProfile.standard, "no saved choice is the standard movement")
        let partlyUnknown = Variations.decode("ONE_ARM_PULL_UP|KNEE_PUSH_UP|AIR_SQUAT")
        XCTAssertEqual(partlyUnknown.pull, .strictPullUp, "an unknown saved choice falls back to standard")
        XCTAssertEqual(partlyUnknown.push, .kneePushUp, "but the choices it does understand are kept")

        // Labels name only what changed.
        XCTAssertEqual(CindyProfile.standard.label(), "Cindy", "a standard profile is just Cindy")
        XCTAssertEqual(CindyProfile(push: .kneePushUp).label(), "Adaptive Cindy · knee push-ups",
                   "an adaptive one names only the change")
        XCTAssertEqual(CindyProfile.standard.fullyAutomatic, true, "the standard profile is fully automatic")
        XCTAssertEqual(adaptive.fullyAutomatic, true, "so is this adaptive one -- all three variants are AUTO-tracked")
        XCTAssertEqual(CindyProfile(pull: .negativePullUp).manualMovements, [.pullup],
                   "a profile knows which movements it will ask to be tapped in")
    }
}
