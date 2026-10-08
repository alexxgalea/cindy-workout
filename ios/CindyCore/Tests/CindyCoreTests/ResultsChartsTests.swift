import XCTest
@testable import CindyCore

/// The lifted card, the timeline and the round splits on the results page, ported from the
/// remaining results parts of `ScreenSmokeTest.kt`. Same shape as `ResultsPageTests`: the facts
/// Robolectric read off the inflated screen are read here off the `ResultsPage` and `ResultsModel`.
final class ResultsChartsTests: XCTestCase {

    private let zone = Zone("Europe/Bucharest")
    private lazy var today = LocalDate(2026, 10, 8)
    private lazy var now = zone.epochMs(today, hour: 12)
    private let day: Int64 = 24 * 60 * 60 * 1000

    private func input(_ a: Attempt, records: [Attempt]? = nil, body: Body = Body(0), reviewing: Bool = false,
                       trace: HeartRateTrace? = nil, marks: [RepMark]? = nil,
                       marksFor: @escaping (Int64) -> [RepMark]? = { _ in nil },
                       font: EmojiFont = AnyEmojiFont.all) -> ResultsInput {
        ResultsInput(attempt: a, reviewing: reviewing, records: records ?? [a], body: body, heartTrace: trace,
                     repMarks: marks, marksFor: marksFor, zone: zone, firstDayOfWeek: .monday, today: today, font: font)
    }

    private func page(_ a: Attempt, records: [Attempt]? = nil, body: Body = Body(0), reviewing: Bool = false,
                      trace: HeartRateTrace? = nil, marks: [RepMark]? = nil) -> ResultsPage {
        ResultsPageBuilder.build(input(a, records: records, body: body, reviewing: reviewing, trace: trace, marks: marks))
    }

    // MARK: the timeline

    /// One round of five, ten and fifteen reps, timed set by set, filed with its rep times.
    private func timedRound(_ atMillis: Int64, counted: Int = 30) -> Attempt {
        Attempt(rounds: 1, reps: 0, atMillis: atMillis, durationMs: 120_000, roundSplitsMs: [60_000],
                profile: .standard, countedReps: counted,
                setSplits: [SetSplit(.pullup, 10_000, 5, 0), SetSplit(.pushup, 20_000, 10, 0), SetSplit(.squat, 30_000, 15, 0)])
    }

    private var timedMarks: [RepMark] {
        let movements = Array(repeating: Exercise.pullup, count: 5) + Array(repeating: Exercise.pushup, count: 10)
            + Array(repeating: Exercise.squat, count: 15)
        return movements.enumerated().map { RepMark(Int64($0.offset + 1) * 2_000, $0.element, manual: false) }
    }

    private func heartAttempt(_ at: Int64) -> (Attempt, HeartRateTrace) {
        let a = Attempt(rounds: 1, reps: 0, atMillis: at, durationMs: 4_000, countedReps: 10)
        return (a, HeartRateTrace(startedAtMillis: at, samples: [HeartRateSample(0, 150)], pauses: []))
    }

    /// the results screen draws the timeline for a session with rep times and no earlier one
    func testTheResultsScreenDrawsTheTimelineForASessionWithRepTimesAndNoEarlierOne() {
        let a = timedRound(now)
        let model = ResultsModel(input(a, marks: timedMarks))
        let section = model.page.timeline

        XCTAssertNotNil(section)
        // Nothing earlier to measure against, so nothing dashed to explain.
        XCTAssertNil(section!.legend)
        XCTAssertEqual(section!.lanes.count, 1)
        XCTAssertEqual(model.timelineReadout(clockMs: nil)?.title, "2:00 · 1 round")
        XCTAssertEqual(model.timelineReadout(clockMs: nil)?.detail, "Drag across the chart to scrub through the session.")
        XCTAssertEqual(section!.stops.count, 2)
    }

    /// the results screen hides the timeline for a record with nothing to plot
    func testTheResultsScreenHidesTheTimelineForARecordWithNothingToPlot() {
        let old = Attempt(rounds: 5, reps: 0, atMillis: now, durationMs: 20 * 60_000, profile: .standard)
        XCTAssertNil(page(old).timeline)
    }

    /// A heart rate alone is enough: reps may be unknown, the watch was not.
    /// the results screen draws the timeline from a heart-rate trace alone
    func testTheResultsScreenDrawsTheTimelineFromAHeartRateTraceAlone() {
        let a = Attempt(rounds: 5, reps: 0, atMillis: now, durationMs: 20 * 60_000, profile: .standard)
        let trace = HeartRateTrace(startedAtMillis: a.atMillis,
                                   samples: (0..<60).map { HeartRateSample(Int64($0) * 1_000, 110 + $0) }, pauses: [])

        let section = page(a, trace: trace).timeline

        XCTAssertNotNil(section)
        XCTAssertEqual(section!.lanes.count, 1)
        XCTAssertEqual(section!.lanes[0].label, "HEART RATE")
    }

    /// the results screen stacks reps and heart rate when it has both
    func testTheResultsScreenStacksRepsAndHeartRateWhenItHasBoth() {
        let a = timedRound(now)
        let trace = HeartRateTrace(startedAtMillis: a.atMillis, samples: [HeartRateSample(1_000, 130)], pauses: [])

        let section = page(a, trace: trace, marks: timedMarks).timeline

        XCTAssertEqual(section!.lanes.map { $0.label }, ["REPS", "HEART RATE"])
        XCTAssertEqual(section!.description, "Timeline of this session: reps and heart rate, one stop for each round")
    }

    /// The KCAL lane needs a weight and nothing else: with a trace but no age it is one dashed
    /// stretch from the reps, and the heart-rate lane is still there beside it.
    /// the timeline grows a calorie lane once a body weight is on file
    func testTheTimelineGrowsACalorieLaneOnceABodyWeightIsOnFile() {
        let (a, trace) = heartAttempt(now)

        let section = page(a, body: Body(70.0, age: nil, sex: nil), trace: trace).timeline!

        XCTAssertEqual(section.lanes.count, 2)
        XCTAssertTrue(section.description.contains("estimated calories"), section.description)
        XCTAssertEqual(section.lanes[1].label, "KCAL (EST.)")
        XCTAssertEqual(section.lanes[1].runs.map { $0.dashed }, [true])
    }

    /// the timeline has no calorie lane without a body weight
    func testTheTimelineHasNoCalorieLaneWithoutABodyWeight() {
        let (a, trace) = heartAttempt(now)

        let section = page(a, body: Body(0), trace: trace).timeline!

        XCTAssertEqual(section.lanes.count, 1)
        XCTAssertFalse(section.description.contains("calories"), section.description)
    }

    /// The legend follows whichever chip is chosen, and the cursor the athlete left on the chart
    /// stays where it was across the change, with the readout drawn again from there.
    /// the timeline follows the comparison chip and keeps the cursor
    func testTheTimelineFollowsTheComparisonChipAndKeepsTheCursor() {
        // Best by a distance, then a worse one more recently, then today's.
        let best = timedRound(now - 3 * day, counted: 45)
        let last = timedRound(now - day)
        let todays = timedRound(now)
        let model = ResultsModel(input(todays, records: [best, last, todays], marks: timedMarks))

        XCTAssertTrue(model.page.timeline!.legend!.hasPrefix("Dashed: your best."), model.page.timeline!.legend ?? "")
        XCTAssertTrue(model.timelineReadout(clockMs: 30_000)!.title.hasPrefix("0:30 · Round 1"))

        XCTAssertEqual(model.page.compare!.labels, ["Your best", "Last time"])
        model.chooseComparison(1)

        XCTAssertTrue(model.page.timeline!.legend!.hasPrefix("Dashed: last time."), model.page.timeline!.legend ?? "")
        XCTAssertTrue(model.timelineReadout(clockMs: 30_000)!.title.hasPrefix("0:30 · Round 1"))
        XCTAssertEqual(model.page.compare!.chosen, 1)
    }

    /// a reopened session draws its own timeline against what came before it
    func testAReopenedSessionDrawsItsOwnTimelineAgainstWhatCameBeforeIt() {
        let earlier = timedRound(now - 2 * day)
        let reopened = timedRound(now - day)
        let later = timedRound(now)
        let marksFor: (Int64) -> [RepMark]? = { _ in self.timedMarks }

        let p = ResultsPageBuilder.build(input(reopened, records: [earlier, reopened, later], reviewing: true,
                                               marks: timedMarks, marksFor: marksFor))

        XCTAssertNotNil(p.timeline)
        XCTAssertTrue(p.timeline!.legend!.hasPrefix("Dashed: your best"), p.timeline!.legend ?? "")
    }

    // MARK: what was lifted and burned

    /// A full round with its sets banked, so there is something for the lifted card to count.
    private func liftedAttempt(_ profile: CindyProfile = .standard) -> Attempt {
        Attempt(rounds: 1, reps: 0, atMillis: now, durationMs: 20 * 60_000, profile: profile, countedReps: 30,
                setSplits: [SetSplit(.pullup, 14_000, 5, 0), SetSplit(.pushup, 17_000, 10, 0), SetSplit(.squat, 21_000, 15, 0)])
    }

    private func card(_ p: ResultsPage) -> LiftedCard? {
        if case .card(let c) = p.lifted { return c }
        return nil
    }

    /// With a weight on file the card says what was lifted and burned, as one screen reader sentence.
    /// the results screen shows what was lifted and burned once a weight is on file
    func testTheResultsScreenShowsWhatWasLiftedAndBurnedOnceAWeightIsOnFile() {
        let c = card(page(liftedAttempt(), body: Body(80.0)))!

        // (5 x 0.95 + 10 x 0.64 + 15 x 0.88) x 80 = 1,948 kg, rounded to the nearest 10.
        XCTAssertTrue(c.spoken.contains("You lifted about 1,950 kg."), c.spoken)
        XCTAssertTrue(c.spoken.contains("You burned"), c.spoken)
        XCTAssertTrue(c.spoken.contains("An estimate from your weight"), c.spoken)
    }

    /// Without one, a single row invites the athlete to enter it, and nothing is made up.
    /// the results screen invites a weight rather than showing an empty card
    func testTheResultsScreenInvitesAWeightRatherThanShowingAnEmptyCard() {
        XCTAssertEqual(page(liftedAttempt(), body: Body(0)).lifted, .invite)
    }

    /// An old record cannot say which movement its reps were, so only the burned half remains.
    /// the results screen says nothing of what was lifted for an old record
    func testTheResultsScreenSaysNothingOfWhatWasLiftedForAnOldRecord() {
        let old = Attempt(rounds: 2, reps: 0, atMillis: now, durationMs: 20 * 60_000, profile: .standard)
        let c = card(page(old, body: Body(80.0)))!

        XCTAssertTrue(c.spoken.contains("You burned"), c.spoken)
        XCTAssertFalse(c.spoken.contains("You lifted"), c.spoken)
        XCTAssertNil(c.lifted)
    }

    /// Band-assisted pull-ups are named as left out, and the shares applied are the athlete's own.
    /// the results screen names the movements it left out of what was lifted
    func testTheResultsScreenNamesTheMovementsItLeftOutOfWhatWasLifted() {
        let c = card(page(liftedAttempt(CindyProfile(pull: .bandAssistedPullUp)), body: Body(80.0)))!

        XCTAssertTrue(c.spoken.contains("Band-assisted pull-ups are left out"), c.spoken)
        XCTAssertFalse(c.spoken.contains("strict pull-ups"), c.spoken)
    }

    /// a reopened session shows the lifted card too
    func testAReopenedSessionShowsTheLiftedCardToo() {
        let c = card(page(liftedAttempt(), body: Body(80.0), reviewing: true))!
        XCTAssertTrue(c.spoken.contains("You lifted"), c.spoken)
    }

    /// The animal row: as many of the animal as the count, five at most, and a "×N" beyond that.
    /// The JVM had no emoji font, so the Kotlin test told the font check every glyph was available;
    /// so does the default here.
    /// the lifted card draws the animal and its count when the phone can draw it
    func testTheLiftedCardDrawsTheAnimalAndItsCountWhenThePhoneCanDrawIt() {
        let c = card(page(liftedAttempt(), body: Body(80.0)))!

        // 1,948 kg is 2.8 cows, 3.9 horses or 6.5 bears, whichever the day's rotation picked.
        XCTAssertTrue(c.spoken.contains("As heavy as "), c.spoken)
        let drawn = c.lifted!.emojiCount + (c.burned?.emoji != nil ? 1 : 0)
        // Three to five of the animal, plus the one beside the energy figure.
        XCTAssertTrue((4...6).contains(drawn), "emoji drawn: \(drawn)")
        XCTAssertNotNil(c.lifted!.animalEmoji)
    }

    /// an animal the phone cannot draw is never picked
    func testAnAnimalThePhoneCannotDrawIsNeverPicked() {
        let none = AnyEmojiFont { _ in false }
        let p = ResultsPageBuilder.build(input(liftedAttempt(), body: Body(80.0), font: none))
        let c = card(p)!

        XCTAssertNil(c.lifted!.animalEmoji)
        XCTAssertNil(c.burned!.emoji)
        XCTAssertFalse(c.spoken.contains("As heavy as "), c.spoken)
    }

    // MARK: the round splits

    private func splitsAttempt(_ at: Int64, _ splits: [Int64], sets: [SetSplit] = [], durationMs: Int64? = nil,
                               counted: Int?? = .some(nil)) -> Attempt {
        let countedReps: Int? = counted == .some(nil) ? splits.count * 30 : counted!
        return Attempt(rounds: splits.count, reps: 0, atMillis: at, durationMs: durationMs ?? splits.reduce(0, +),
                       roundSplitsMs: splits, profile: .standard, countedReps: countedReps, setSplits: sets)
    }

    private func threeSets(_ pull: Int64, _ push: Int64, _ squat: Int64) -> [SetSplit] {
        [SetSplit(.pullup, pull, 5, 0), SetSplit(.pushup, push, 10, 0), SetSplit(.squat, squat, 15, 0)]
    }

    /// the splits are stacked by movement when the sets were timed, and read out when chosen
    func testTheSplitsAreStackedByMovementWhenTheSetsWereTimedAndReadOutWhenChosen() {
        let a = splitsAttempt(now, [168_000, 150_000], sets: threeSets(41_000, 52_000, 75_000) + threeSets(40_000, 50_000, 60_000))
        let model = ResultsModel(input(a))

        XCTAssertNotNil(model.page.splits)
        XCTAssertEqual(model.page.splits!.split.bars.count, 2)
        XCTAssertEqual(model.splitsReadout(selected: nil)?.title, "Fastest: round 2 at 2:30 · average 2:39")

        let r = model.splitsReadout(selected: 0)!
        XCTAssertEqual(r.title, "Round 1 · 2:48")
        XCTAssertEqual(r.detail, "Pull-ups 0:41 · push-ups 0:52 · squats 1:15")
        XCTAssertEqual(r.versusVisibility, .gone, "no comparison, so no line for one")
    }

    /// A record from before set times existed has round splits and nothing else.
    /// a very old record still draws plain bars and says it has no movement times
    func testAVeryOldRecordStillDrawsPlainBarsAndSaysItHasNoMovementTimes() {
        let a = splitsAttempt(now, [168_000, 150_000, 160_000], counted: .some(nil as Int?))
        let old = Attempt(rounds: 3, reps: 0, atMillis: now, durationMs: 478_000, roundSplitsMs: [168_000, 150_000, 160_000],
                          profile: .standard)
        _ = a
        let model = ResultsModel(input(old))

        XCTAssertEqual(model.page.splits!.split.bars.count, 3)
        XCTAssertEqual(model.splitsReadout(selected: 1)?.detail, "No per-movement times for this round")
        XCTAssertFalse(model.page.splits!.note.contains("stacks"))
    }

    /// no complete round hides the splits instead of charting nothing
    func testNoCompleteRoundHidesTheSplitsInsteadOfChartingNothing() {
        let a = splitsAttempt(now, [], durationMs: 90_000)
        let p = page(a)
        XCTAssertNil(p.splits)
    }

    /// the round the clock stopped in is drawn as an open bar
    func testTheRoundTheClockStoppedInIsDrawnAsAnOpenBar() {
        let a = splitsAttempt(now, [168_000], sets: threeSets(41_000, 52_000, 75_000) + [SetSplit(.pullup, 38_000, 5, 0)],
                              durationMs: 248_000, counted: .some(35))
        let model = ResultsModel(input(a))

        XCTAssertEqual(model.page.splits!.split.bars.count, 2)
        let r = model.splitsReadout(selected: 1)!
        XCTAssertEqual(r.title, "Round 2 · 1:20 so far")
        XCTAssertTrue(r.detail.hasPrefix("5 of 30 reps"), r.detail)
        XCTAssertTrue(model.page.splits!.note.contains("outlined bar"), model.page.splits!.note)
    }

    /// an earlier session adds a tick and a line against it, and the chip changes which
    func testAnEarlierSessionAddsATickAndALineAgainstItAndTheChipChangesWhich() {
        let best = splitsAttempt(now - 3 * day, [177_000, 140_000, 150_000, 150_000])
        let last = splitsAttempt(now - day, [160_000, 160_000])
        let a = splitsAttempt(now, [168_000, 150_000])
        let model = ResultsModel(input(a, records: [best, last, a]))

        var r = model.splitsReadout(selected: 0)!
        XCTAssertEqual(r.versus, "9 s faster than your best's round 1")
        XCTAssertTrue(model.page.splits!.note.contains("in your best"))
        XCTAssertEqual(model.page.splits!.reference, [177_000, 140_000])

        model.chooseComparison(1)

        // The selection (the caller's) survives the new comparison; the sentence is now about the other one.
        r = model.splitsReadout(selected: 0)!
        XCTAssertEqual(r.versus, "8 s slower than round 1 last time")
        XCTAssertTrue(model.page.splits!.note.contains("last time"))
        XCTAssertEqual(model.page.splits!.reference, [160_000, 160_000])
    }

    /// a round the comparison never played keeps its line's room, so the chart does not move
    func testARoundTheComparisonNeverPlayedKeepsItsLinesRoomSoTheChartDoesNotMove() {
        let last = splitsAttempt(now - day, [160_000])
        let a = splitsAttempt(now, [168_000, 150_000])
        let model = ResultsModel(input(a, records: [last, a]))

        XCTAssertEqual(model.splitsReadout(selected: 0)?.versusVisibility, .visible)
        XCTAssertEqual(model.splitsReadout(selected: 1)?.versusVisibility, .invisible)
        XCTAssertEqual(model.splitsReadout(selected: nil)?.versusVisibility, .invisible)
    }

    // MARK: the track and movements, with the fingers

    /// the caption follows the pill, and the hint stands for none
    func testTheCaptionFollowsThePillAndTheHintStandsForNone() {
        let a = Attempt(rounds: 1, reps: 0, atMillis: now, durationMs: 20 * 60_000, roundSplitsMs: [52_000],
                        profile: .standard, countedReps: 30,
                        setSplits: [SetSplit(.pullup, 14_000, 5, 0), SetSplit(.pushup, 17_000, 10, 0), SetSplit(.squat, 21_000, 15, 0)])
        let model = ResultsModel(input(a))

        XCTAssertEqual(model.trackCaption(selected: nil), "Tap a round to see what went into it.")
        XCTAssertEqual(model.trackCaption(selected: 0), model.page.track!.caption(0))
        XCTAssertTrue(model.page.track!.caption(0).hasPrefix("Round 1"), model.page.track!.caption(0))
    }

    /// the splits are spoken one bar at a time
    func testTheSplitsAreSpokenOneBarAtATime() {
        let a = splitsAttempt(now, [168_000, 150_000])
        let model = ResultsModel(input(a))
        XCTAssertTrue(model.splitsSpoken(0).hasPrefix("Round 1 · 2:48"), model.splitsSpoken(0))
    }
}
