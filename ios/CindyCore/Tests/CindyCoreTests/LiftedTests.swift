import XCTest
import CindyCore

/// How much body weight a session moved. Port of `LiftedTest.kt`.
final class LiftedTests: XCTestCase {

    private func split(_ movement: Exercise, _ reps: Int, manual: Int = 0) -> SetSplit {
        SetSplit(movement, 1_000, reps, manual)
    }

    private var oneRound: [SetSplit] { [split(.pullup, 5), split(.pushup, 10), split(.squat, 15)] }

    /// One full round, then `extraReps` more pull-ups in progress.
    private func attempt(profile: CindyProfile? = CindyProfile.standard, splits: [SetSplit]? = nil,
                         counted: Int?? = nil, untrackedMs: Int64 = 0, manualReps: Int = 0) -> Attempt {
        let sets = splits ?? oneRound
        let total: Int? = counted ?? sets.reduce(0) { $0 + $1.reps }
        return Attempt(rounds: (total ?? 0) / 30, reps: 0, atMillis: 0, profile: profile, manualReps: manualReps,
                       countedReps: total, untrackedMs: untrackedMs, setSplits: sets)
    }

    /// a standard round lifts the three shares of the body weight
    func testAStandardRoundLiftsTheThreeSharesOfTheBodyWeight() {
        let lifted = Lifted.of(attempt(), bodyWeightKg: 80.0)!

        XCTAssertEqual(lifted.parts.map { $0.movement }, [.pullup, .pushup, .squat])
        XCTAssertEqual(lifted.parts[0].kg, 5 * 0.95 * 80.0, accuracy: 1e-9)
        XCTAssertEqual(lifted.parts[1].kg, 10 * 0.64 * 80.0, accuracy: 1e-9)
        XCTAssertEqual(lifted.parts[2].kg, 15 * 0.88 * 80.0, accuracy: 1e-9)
        XCTAssertEqual(lifted.totalKg, (5 * 0.95 + 10 * 0.64 + 15 * 0.88) * 80.0, accuracy: 1e-9)
        XCTAssertTrue(lifted.omitted.isEmpty)
        XCTAssertFalse(lifted.atLeast)
    }

    /// reps are summed across rounds and include the movement in progress
    func testRepsAreSummedAcrossRoundsAndIncludeTheMovementInProgress() {
        let splits = [split(.pullup, 5), split(.pushup, 10), split(.squat, 15), split(.pullup, 5)]
        // 35 banked in splits, plus 4 push-ups still running when the clock stopped.
        let lifted = Lifted.of(attempt(splits: splits, counted: 39), bodyWeightKg: 70.0)!

        XCTAssertEqual(lifted.parts.map { $0.reps }, [10, 14, 15])
    }

    /// a standard session names its movements plainly
    func testAStandardSessionNamesItsMovementsPlainly() {
        let lifted = Lifted.of(attempt(), bodyWeightKg: 80.0)!

        XCTAssertEqual(lifted.parts.map { $0.label }, ["pull-ups", "push-ups", "squats"])
    }

    /// knee push-ups use their own share and their own name
    func testKneePushUpsUseTheirOwnShareAndTheirOwnName() {
        let lifted = Lifted.of(attempt(profile: CindyProfile(push: .kneePushUp)), bodyWeightKg: 80.0)!

        let push = lifted.parts.first { $0.movement == .pushup }!
        XCTAssertEqual(push.share, 0.49, accuracy: 0.0)
        XCTAssertEqual(push.label, "knee push-ups")
        XCTAssertEqual(push.kg, 10 * 0.49 * 80.0, accuracy: 1e-9)
    }

    /// heels-flat and box squats share the air squat's body fraction
    func testHeelsFlatAndBoxSquatsShareTheAirSquatsBodyFraction() {
        for variant in [SquatVariant.airSquat, .heelsFlat, .boxSquat] {
            let lifted = Lifted.of(attempt(profile: CindyProfile(squat: variant)), bodyWeightKg: 80.0)!
            XCTAssertEqual(lifted.parts.first { $0.movement == .squat }!.share, 0.88, accuracy: 0.0, "\(variant)")
        }
    }

    /// band-assisted pull-ups are left out by name, never guessed
    func testBandAssistedPullUpsAreLeftOutByNameNeverGuessed() {
        let lifted = Lifted.of(attempt(profile: CindyProfile(pull: .bandAssistedPullUp)), bodyWeightKg: 80.0)!

        XCTAssertEqual(lifted.parts.map { $0.movement }, [.pushup, .squat])
        XCTAssertEqual(lifted.omitted.count, 1)
        let left = lifted.omitted[0]
        XCTAssertEqual(left.movement, .pullup)
        XCTAssertEqual(left.label, "band-assisted pull-ups")
        XCTAssertEqual(left.reps, 5)
        // The pull-ups contribute nothing to the total.
        XCTAssertEqual(lifted.totalKg, (10 * 0.64 + 15 * 0.88) * 80.0, accuracy: 1e-9)
        XCTAssertTrue(lifted.footnote(tappedIn: false)
            .contains("Band-assisted pull-ups are left out: the band's share isn't known."))
    }

    /// every variant without a stated share is left out
    func testEveryVariantWithoutAStatedShareIsLeftOut() {
        let leftOut = [CindyProfile(pull: .invertedRow), CindyProfile(pull: .footAssistedPullUp),
                       CindyProfile(pull: .negativePullUp), CindyProfile(push: .inclinePushUp),
                       CindyProfile(squat: .supportedSquat)]
        for profile in leftOut {
            let lifted = Lifted.of(attempt(profile: profile), bodyWeightKg: 80.0)!
            XCTAssertEqual(lifted.omitted.count, 1, profile.label())
            XCTAssertEqual(lifted.parts.count, 2, profile.label())
        }
    }

    /// a movement with no reps is not named as left out
    func testAMovementWithNoRepsIsNotNamedAsLeftOut() {
        // The pull-ups were skipped at zero: nothing was done, so nothing was omitted.
        let splits = [split(.pullup, 0), split(.pushup, 10), split(.squat, 15)]
        let lifted = Lifted.of(attempt(profile: CindyProfile(pull: .bandAssistedPullUp), splits: splits), bodyWeightKg: 80.0)!

        XCTAssertTrue(lifted.omitted.isEmpty)
    }

    /// a session of only left-out movements has nothing to show
    func testASessionOfOnlyLeftOutMovementsHasNothingToShow() {
        let a = attempt(profile: CindyProfile(pull: .bandAssistedPullUp), splits: [split(.pullup, 5)])

        XCTAssertNil(Lifted.of(a, bodyWeightKg: 80.0))
        XCTAssertFalse(Lifted.measurable(a))
    }

    /// a lower-bound attempt says at least
    func testALowerBoundAttemptSaysAtLeast() {
        let lifted = Lifted.of(attempt(untrackedMs: Records.untrackedToleranceMs), bodyWeightKg: 80.0)!

        XCTAssertTrue(lifted.atLeast)
        XCTAssertTrue(lifted.kgText().hasPrefix("At least "))
        XCTAssertTrue(lifted.footnote(tappedIn: false).contains("floor"))
    }

    /// no body weight, no tally
    func testNoBodyWeightNoTally() {
        XCTAssertNil(Lifted.of(attempt(), bodyWeightKg: 0.0))
        XCTAssertNil(Lifted.of(attempt(), bodyWeightKg: -5.0))
        XCTAssertNil(Lifted.of(attempt(), bodyWeightKg: Double.nan))
        // ...but the page can still tell that a weight would unlock something.
        XCTAssertTrue(Lifted.measurable(attempt()))
    }

    /// no sets, no tally
    func testNoSetsNoTally() {
        // Before set times existed the record carries a total but no way to say which movement.
        let old = attempt(splits: [], counted: 30)
        // 30 counted with no splits cannot be a pull-up set in progress, so the record is refused.
        XCTAssertNil(Lifted.of(old, bodyWeightKg: 80.0))
        XCTAssertFalse(Lifted.measurable(old))
    }

    /// an inferred tally is never lifted
    func testAnInferredTallyIsNeverLifted() {
        XCTAssertNil(Lifted.of(attempt(counted: .some(nil)), bodyWeightKg: 80.0))
    }

    /// a session of movements this build does not know is not relabelled as standard
    func testASessionOfMovementsThisBuildDoesNotKnowIsNotRelabelledAsStandard() {
        XCTAssertNil(Lifted.of(attempt(profile: nil), bodyWeightKg: 80.0))
    }

    /// tapped-in reps count and the footnote says they are a different claim
    func testTappedInRepsCountAndTheFootnoteSaysTheyAreADifferentClaim() {
        let splits = [split(.pullup, 5, manual: 5), split(.pushup, 10), split(.squat, 15)]
        let lifted = Lifted.of(attempt(splits: splits, manualReps: 5), bodyWeightKg: 80.0)!

        XCTAssertEqual(lifted.parts.first { $0.movement == .pullup }!.reps, 5)
        XCTAssertTrue(lifted.footnote(tappedIn: true).contains("tapped in"))
        XCTAssertFalse(lifted.footnote(tappedIn: false).contains("tapped in"))
    }

    /// the footnote names exactly the shares that were applied
    func testTheFootnoteNamesExactlyTheSharesThatWereApplied() {
        let note = Lifted.of(attempt(profile: CindyProfile(push: .kneePushUp)), bodyWeightKg: 80.0)!.footnote(tappedIn: false)

        // Unchanged movements keep their plain names; only the changed one is named by variant.
        XCTAssertTrue(note.contains("pull-ups 95%"), note)
        XCTAssertTrue(note.contains("knee push-ups 49%"), note)
        XCTAssertTrue(note.contains("squats 88%"), note)
        XCTAssertFalse(note.contains("strict"), note)
        XCTAssertFalse(note.contains("air squats"), note)
        XCTAssertFalse(note.contains("standard"), note)
        XCTAssertFalse(note.contains("64%"), note)
        XCTAssertTrue(note.hasPrefix("An estimate"), note)
    }

    /// the kilograms are rounded and grouped, and say about
    func testTheKilogramsAreRoundedAndGroupedAndSayAbout() {
        func lifted(_ kg: Double, atLeast: Bool = false) -> Lifted {
            Lifted(parts: [], omitted: [], totalKg: kg, atLeast: atLeast)
        }
        XCTAssertEqual(lifted(12_943.6).kgText(), "About 12,940 kg")
        XCTAssertEqual(lifted(86.6).kgText(), "About 87 kg")
        XCTAssertEqual(lifted(104.0).kgText(), "About 100 kg")
        XCTAssertEqual(lifted(12_943.6, atLeast: true).kgText(), "At least 12,940 kg")
    }
}
