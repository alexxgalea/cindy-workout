import XCTest
import CindyCore

/// That an adapted session is recorded as what it was, and ranked against its own kind.
///
/// The counting rules are tested elsewhere. What is tested here is the promise the app makes about
/// its own history: a band-assisted Cindy is never quietly filed as a strict one, never takes the
/// strict record, and never earns a rung on a ladder calibrated against a workout it did not
/// attempt — while still being a session the athlete did, on a day they trained.
///
/// Mirrors `VariationsTest.kt`, all of it: `adaptive sessions count toward the streak` came with
/// `Streak` in P8. It replaces the old checks' "Variations" class.
final class VariationsTests: XCTestCase {

    private let adaptive = CindyProfile(pull: .bandAssistedPullUp, push: .kneePushUp, squat: .boxSquat)

    private func attempt(_ rounds: Int, reps: Int = 0, at: Int64 = 1_000,
                         profile: CindyProfile? = .standard, manualReps: Int = 0) -> Attempt {
        Attempt(rounds: rounds, reps: reps, atMillis: at, durationMs: 20 * 60 * 1000,
                profile: profile, manualReps: manualReps)
    }

    // ── the profile survives a round trip ─────────────────────────────────────

    /// an adaptive session stores the movements it was run with
    func testAnAdaptiveSessionStoresTheMovementsItWasRunWith() {
        let saved = Records.decode(Records.encode([attempt(7, reps: 12, profile: adaptive)]))

        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.profile, adaptive)
        XCTAssertEqual(saved.first?.profile?.mode, .adaptive)
    }

    /// reps tapped in survive a round trip
    func testRepsTappedInSurviveARoundTrip() {
        let saved = Records.decode(Records.encode([attempt(3, reps: 0, manualReps: 12)]))

        XCTAssertEqual(saved.first?.manualReps, 12)
    }

    /// History written before the choice existed was standard Cindy, because that was the only
    /// thing the app did. Reading it as standard is a fact, not an assumption.
    ///
    /// attempts written before variations existed read as standard
    func testAttemptsWrittenBeforeVariationsExistedReadAsStandard() {
        let v3 = "v3|8|12|1700000000000|1200000|0|150000,160000"

        let decoded = Records.decode(v3).first

        XCTAssertEqual(decoded?.profile, .standard)
        XCTAssertEqual(decoded?.rounds, 8)
    }

    /// The one case where guessing would be a lie.
    ///
    /// A movement this build does not know cannot be filed under a movement it does — that would
    /// silently promote someone's assisted session into the strict record. It stays unknown, and
    /// unknown is its own category.
    ///
    /// an unrecognised movement leaves the profile unknown rather than standard
    func testAnUnrecognisedMovementLeavesTheProfileUnknownRatherThanStandard() {
        let v4 = "v4|8|0|1700000000000|1200000|0||ONE_ARM_PULL_UP|STANDARD_PUSH_UP|AIR_SQUAT|0"

        let decoded = Records.decode(v4).first

        XCTAssertNil(decoded?.profile, "not silently relabelled as standard")
        XCTAssertEqual(decoded?.rounds, 8, "but the session itself is still theirs")
        XCTAssertNotEqual(decoded?.profile, .some(.standard))
    }

    // ── separate records ──────────────────────────────────────────────────────

    /// an adaptive result never becomes the strict record
    func testAnAdaptiveResultNeverBecomesTheStrictRecord() {
        let history = [
            attempt(8, at: 1, profile: .standard),
            attempt(20, at: 2, profile: adaptive)
        ]

        XCTAssertEqual(Records.bestIn(history, profile: .standard)?.rounds, 8)
        XCTAssertEqual(Records.bestIn(history, profile: adaptive)?.rounds, 20)
    }

    /// And not merely "standard versus the rest": two different adaptations are no more comparable
    /// to each other than either is to the strict movement.
    ///
    /// two different adaptations are separate categories
    func testTwoDifferentAdaptationsAreSeparateCategories() {
        let knees = CindyProfile(push: .kneePushUp)
        let box = CindyProfile(squat: .boxSquat)
        let history = [attempt(9, at: 1, profile: knees), attempt(14, at: 2, profile: box)]

        XCTAssertEqual(Records.bestIn(history, profile: knees)?.rounds, 9)
        XCTAssertEqual(Records.bestIn(history, profile: box)?.rounds, 14)
        XCTAssertNil(Records.bestIn(history, profile: .standard))
    }

    /// a personal record is beaten only by the same movements
    func testAPersonalRecordIsBeatenOnlyByTheSameMovements() {
        let history = [attempt(10, at: 1, profile: adaptive)]
        let betterAdaptive = attempt(11, at: 2, profile: adaptive)
        let strictOfSameSize = attempt(11, at: 3, profile: .standard)

        XCTAssertTrue(Records.isPersonalRecord(history + [betterAdaptive], of: betterAdaptive))
        XCTAssertTrue(Records.isPersonalRecord(history + [strictOfSameSize], of: strictOfSameSize),
                      "first strict session sets its own record")
        XCTAssertEqual(Records.personalRecord(history + [betterAdaptive], of: betterAdaptive)?.rounds, 10)
        XCTAssertNil(Records.personalRecord(history + [strictOfSameSize], of: strictOfSameSize),
                     "nothing strict to compare against")
    }

    // ── the ladder and the benchmark ──────────────────────────────────────────

    /// the strict ladder does not rank an adaptive session
    func testTheStrictLadderDoesNotRankAnAdaptiveSession() {
        XCTAssertEqual(attempt(12).level, .intermediate)
        XCTAssertNil(attempt(12, profile: adaptive).level, "no rung for a workout the ladder does not describe")
        XCTAssertNil(attempt(12, profile: nil).level)
    }

    /// an adaptive session is captioned with its movements instead of a rung
    func testAnAdaptiveSessionIsCaptionedWithItsMovementsInsteadOfARung() {
        XCTAssertEqual(attempt(12).caption, "Intermediate")
        XCTAssertEqual(attempt(12, profile: adaptive).caption,
                       "Adaptive Cindy · band-assisted pull-ups · knee push-ups · box squats")
    }

    /// Twenty-seven rounds of knee push-ups is not level with a strict twenty-seven.
    ///
    /// an adaptive session never passes the benchmark
    func testAnAdaptiveSessionNeverPassesTheBenchmark() {
        XCTAssertTrue(Records.beatsBenchmark(attempt(28)))
        XCTAssertFalse(Records.beatsBenchmark(attempt(28, profile: adaptive)))
        XCTAssertFalse(Records.beatsBenchmark(attempt(28, profile: nil)))
    }

    // ── what adaptive sessions still count for ────────────────────────────────

    /// The streak measures showing up, and an adaptive athlete showed up.
    ///
    /// Deliberate: separating the *scores* is honesty, but withholding the streak would make the
    /// separation a punishment, which is the opposite of the point.
    ///
    /// adaptive sessions count toward the streak
    func testAdaptiveSessionsCountTowardTheStreak() {
        let zone = Zone.utc
        let today = LocalDate(2026, 3, 10)
        func onDay(_ day: Int, _ profile: CindyProfile?) -> Attempt {
            attempt(5, at: zone.epochMs(LocalDate(2026, 3, day)), profile: profile)
        }

        let days = Streak.daysTrained([onDay(8, .standard), onDay(9, adaptive), onDay(10, adaptive)], zone: zone)

        XCTAssertEqual(Streak.current(days, today: today), 3)
    }

    // ── the picker's own memory ───────────────────────────────────────────────

    /// the chosen profile survives being saved and read back
    func testTheChosenProfileSurvivesBeingSavedAndReadBack() {
        XCTAssertEqual(Variations.decode(Variations.encode(adaptive)), adaptive)
        XCTAssertEqual(Variations.decode(nil), .standard)
        XCTAssertEqual(Variations.decode("nonsense"), .standard)
    }

    /// A preference is not a record: falling back here costs the athlete one visit to the picker,
    /// whereas falling back in `Records` would rewrite what they did.
    ///
    /// an unknown saved choice falls back to the standard movement
    func testAnUnknownSavedChoiceFallsBackToTheStandardMovement() {
        let decoded = Variations.decode("ONE_ARM_PULL_UP|KNEE_PUSH_UP|AIR_SQUAT")

        XCTAssertEqual(decoded.pull, .strictPullUp)
        XCTAssertEqual(decoded.push, .kneePushUp, "the choices it does understand are kept")
    }

    // ── labels ────────────────────────────────────────────────────────────────

    /// a profile names only what was changed
    func testAProfileNamesOnlyWhatWasChanged() {
        XCTAssertEqual(CindyProfile.standard.label(), "Cindy")
        XCTAssertEqual(CindyProfile(push: .kneePushUp).label(), "Adaptive Cindy · knee push-ups")
    }

    /// a profile knows which movements it will ask to be tapped in
    func testAProfileKnowsWhichMovementsItWillAskToBeTappedIn() {
        XCTAssertTrue(CindyProfile.standard.fullyAutomatic)
        XCTAssertTrue(adaptive.fullyAutomatic)
        XCTAssertEqual(CindyProfile(pull: .negativePullUp).manualMovements, [.pullup])
    }
}
