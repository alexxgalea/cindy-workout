import XCTest
@testable import CindyCore

/// The results page's decisions, ported from the results parts of `ScreenSmokeTest.kt`.
///
/// Robolectric inflated `ResultsActivity` and read its views; the same facts are read here off the
/// `ResultsPage` the screen draws. Each test is named after the Kotlin one it comes from. The tests
/// that open another screen from here (the leaderboard row, the day sheet, the chart's OPEN
/// button) belong to Progress, P12, and the tests that open a sheet (`askBodyWeight`, the heart-rate
/// details) to the menu, P13; what is held here is that the page asks for them.
final class ResultsPageTests: XCTestCase {

    private let zone = Zone("Europe/Bucharest")
    private lazy var today = LocalDate(2026, 10, 8)
    private lazy var now = zone.epochMs(today, hour: 12)
    private let day: Int64 = 24 * 60 * 60 * 1000

    private let timedRound = [
        SetSplit(.pullup, 14_000, 5, 0), SetSplit(.pushup, 17_000, 10, 0), SetSplit(.squat, 21_000, 15, 0)
    ]

    private func input(_ a: Attempt, records: [Attempt]? = nil, body: Body = Body(0), stopped: Bool = false,
                        reviewing: Bool = false, heelsFlat: Bool = false, trace: HeartRateTrace? = nil,
                        marks: [RepMark]? = nil, font: EmojiFont = AnyEmojiFont.all) -> ResultsInput {
        ResultsInput(attempt: a, stoppedEarly: stopped, reviewing: reviewing, heelsFlatSpotted: heelsFlat,
                     records: records ?? [a], body: body, heartTrace: trace, repMarks: marks,
                     zone: zone, firstDayOfWeek: .monday, today: today, font: font)
    }

    private func page(_ a: Attempt, records: [Attempt]? = nil, body: Body = Body(0), stopped: Bool = false,
                      reviewing: Bool = false, trace: HeartRateTrace? = nil) -> ResultsPage {
        ResultsPageBuilder.build(input(a, records: records, body: body, stopped: stopped, reviewing: reviewing, trace: trace))
    }

    private func value(_ page: ResultsPage, _ label: String) -> StatRow? { page.stats.first { $0.label == label } }

    // MARK: the top

    /// the results screen builds
    func testTheResultsScreenBuilds() {
        let a = Attempt(rounds: 18, reps: 7, atMillis: now, durationMs: 20 * 60_000,
                        roundSplitsMs: (0..<18).map { 55_000 + Int64($0) * 1_200 }, profile: .standard, manualReps: 4)
        let p = page(a)
        XCTAssertEqual(p.headline, "TIME")
        XCTAssertEqual(p.score, "18")
        XCTAssertEqual(p.scoreReps, "+7")
        XCTAssertEqual(p.level.title, "Advanced")
        XCTAssertEqual(p.level.rung, "4 of 6")
        XCTAssertTrue(p.offersProgress)
    }

    /// the results screen shows the reps that were counted, not the round tally
    func testTheResultsScreenShowsTheRepsThatWereCountedNotTheRoundTally() {
        // Pull-ups skipped: ten push-ups and fifteen squats is the whole round's work.
        let skipped = Attempt(rounds: 1, reps: 0, atMillis: now, durationMs: 116_000, countedReps: 25)
        let p = page(skipped, stopped: true)

        XCTAssertTrue(p.scoreDetail.contains("25 reps"), p.scoreDetail)
        XCTAssertFalse(p.scoreDetail.contains("30 reps"), p.scoreDetail)
        XCTAssertEqual(p.headline, "STOPPED")
    }

    /// the results screen builds for an adaptive session
    func testTheResultsScreenBuildsForAnAdaptiveSession() {
        // No rung, no progress bar, and a different line under the title.
        let a = Attempt(rounds: 9, reps: 0, atMillis: now, durationMs: 20 * 60_000, roundSplitsMs: [],
                        profile: CindyProfile(push: .kneePushUp))
        let p = page(a, stopped: true)

        XCTAssertEqual(p.level.title, "Adaptive Cindy")
        XCTAssertNil(p.level.rung)
        XCTAssertNil(p.level.progressPercent)
        XCTAssertEqual(p.level.next, "Ranked against your own sessions at these movements, not the strict ladder.")
        XCTAssertFalse(p.level.blurb.isEmpty)
    }

    /// the results screen celebrates a first session
    func testTheResultsScreenCelebratesAFirstSession() {
        let a = Attempt(rounds: 12, reps: 3, atMillis: now, durationMs: 20 * 60_000, profile: .standard)
        let p = page(a)

        let box = p.celebration
        XCTAssertNotNil(box)
        XCTAssertTrue(box!.rows[0].headline)
        XCTAssertEqual(box!.rows[0].icon, .trophy)
        XCTAssertFalse(box!.rows.dropFirst().contains { $0.headline })
    }

    /// the results screen stays quiet for an ordinary session
    func testTheResultsScreenStaysQuietForAnOrdinarySession() {
        // A lower score than the best one, three weeks on, is no record and no streak of either
        // kind (last week would make two weeks in a row, which is a milestone), so nothing is claimed.
        let old = Attempt(rounds: 20, reps: 0, atMillis: now - 21 * day, durationMs: 20 * 60_000, profile: .standard)
        let todays = Attempt(rounds: 10, reps: 0, atMillis: now, durationMs: 20 * 60_000, profile: .standard)

        XCTAssertNil(page(todays, records: [old, todays]).celebration)
    }

    // MARK: the numbers

    /// the results screen builds with set splits and shows the round numbers
    func testTheResultsScreenBuildsWithSetSplitsAndShowsTheRoundNumbers() {
        let a = Attempt(rounds: 1, reps: 0, atMillis: now, durationMs: 20 * 60_000, roundSplitsMs: [52_000],
                        profile: .standard, countedReps: 30, setSplits: timedRound)
        let p = page(a)

        XCTAssertNotNil(p.track)
        XCTAssertNotNil(p.movements)
        XCTAssertTrue(["ROUNDS", "REPS", "TIME", "FASTEST"].allSatisfy { label in p.tiles.contains { $0.label == label } },
                      "\(p.tiles.map { $0.label })")
        let pull = p.movements!.columns[0]
        XCTAssertEqual(pull.label, "pull-ups")
        XCTAssertTrue(pull.lines.contains("0:14 total"), "\(pull.lines)")
        // The headline numbers moved up into the tiles; the details keep only what is left.
        XCTAssertFalse(p.stats.contains { $0.label == "Total reps" || $0.label == "Rounds completed" })
    }

    /// the results screen says at least over a lower bound session's rounds
    func testTheResultsScreenSaysAtLeastOverALowerBoundSessionsRounds() {
        let a = Attempt(rounds: 1, reps: 0, atMillis: now, durationMs: 20 * 60_000, roundSplitsMs: [52_000],
                        profile: .standard, countedReps: 30, untrackedMs: 60_000, setSplits: timedRound)
        let p = page(a)

        XCTAssertTrue(p.track!.footnote.contains("The camera lost you for 1:00"), p.track!.footnote)
        XCTAssertEqual(p.movements!.columns.filter { $0.atLeast }.count, 3)
        XCTAssertTrue(p.movements!.columns[0].spoken.contains("at least"))
    }

    /// the results screen hides the round track and movements without set times
    func testTheResultsScreenHidesTheRoundTrackAndMovementsWithoutSetTimes() {
        let a = Attempt(rounds: 12, reps: 3, atMillis: now, durationMs: 20 * 60_000,
                        roundSplitsMs: Array(repeating: 100_000, count: 12), profile: .standard)
        let p = page(a)

        XCTAssertNil(p.track)
        XCTAssertNil(p.movements)
        XCTAssertTrue(p.tiles.contains { $0.value == "12" }, "\(p.tiles.map { $0.value })")
        XCTAssertTrue(p.tiles.contains { $0.value == "1:40" }, "\(p.tiles.map { $0.value })")
    }

    /// the results screen uses the adaptive session's own movement names
    func testTheResultsScreenUsesTheAdaptiveSessionsOwnMovementNames() {
        let a = Attempt(rounds: 1, reps: 0, atMillis: now, durationMs: 20 * 60_000, roundSplitsMs: [52_000],
                        profile: CindyProfile(push: .kneePushUp), countedReps: 30, setSplits: timedRound)
        let p = page(a)

        XCTAssertTrue(p.movements!.columns.contains { $0.label == "knee push-ups" })
        XCTAssertFalse(p.movements!.columns.contains { $0.label.contains("standard push-ups") })
        XCTAssertTrue(p.track!.footnote.contains("10 knee push-ups"), p.track!.footnote)
    }

    // MARK: the energy row

    private func heartRateAttempt() -> (Attempt, HeartRateTrace) {
        let a = Attempt(rounds: 1, reps: 0, atMillis: now, durationMs: 4_000, countedReps: 10)
        return (a, HeartRateTrace(startedAtMillis: a.atMillis, samples: [HeartRateSample(0, 150)], pauses: []))
    }

    /// A trace whose one sample covers the whole of a short attempt's clock: no minute is left for
    /// the MET model to estimate, so the footnote is the "whole workout" wording rather than the
    /// blended one, and it says nothing about METs.
    /// the results screen credits heart rate for the whole workout
    func testTheResultsScreenCreditsHeartRateForTheWholeWorkout() {
        let (a, trace) = heartRateAttempt()
        let p = page(a, body: Body(70.0, age: 36, sex: .male), trace: trace)

        let footnote = value(p, "Calories (est.)")!.footnote!
        XCTAssertTrue(footnote.contains("heart rate"), footnote)
        XCTAssertFalse(footnote.contains("METs"), footnote)
        XCTAssertEqual(footnote, "From your heart rate across the whole workout · 70 kg, 36, male formula.")
    }

    /// the results screen invites adding age and sex once a trace exists
    func testTheResultsScreenInvitesAddingAgeAndSexOnceATraceExists() {
        let (a, trace) = heartRateAttempt()
        let p = page(a, body: Body(70.0, age: nil, sex: nil), trace: trace)

        let row = value(p, "Calories (est.)")!
        XCTAssertTrue(row.footnote!.contains("tap to add your age"), row.footnote!)
        // The weight prompt already ran; the details that would unlock the trace are what is offered.
        XCTAssertEqual(row.action, .askHeartRateDetails)
    }

    /// the results screen footnote is unchanged without a heart-rate trace
    func testTheResultsScreenFootnoteIsUnchangedWithoutAHeartRateTrace() {
        let (a, _) = heartRateAttempt()
        let p = page(a, body: Body(70.0, age: 36, sex: .male))

        let expected = "Estimated from 70 kg at about \(JavaText.fixed(Calories.met(totalReps: a.totalReps, activeMs: a.durationMs), 1))"
            + " METs. Tap to change your weight."
        XCTAssertEqual(value(p, "Calories (est.)")!.footnote, expected)
        XCTAssertEqual(value(p, "Calories (est.)")!.action, .askBodyWeight)
    }

    /// the energy row asks for a weight when there is none
    func testTheEnergyRowAsksForAWeightWhenThereIsNone() {
        let (a, _) = heartRateAttempt()
        let row = value(page(a), "Calories")!
        XCTAssertEqual(row.value, "Set your weight")
        XCTAssertEqual(row.action, .askBodyWeight)
        XCTAssertNil(row.footnote)
    }

    /// the blended wording names how much came from which
    func testTheBlendedWordingNamesHowMuchCameFromWhich() {
        let a = Attempt(rounds: 1, reps: 0, atMillis: now, durationMs: 20_000, countedReps: 10)
        let trace = HeartRateTrace(startedAtMillis: a.atMillis, samples: [HeartRateSample(0, 150)], pauses: [])
        let p = page(a, body: Body(70.0, age: 36, sex: .female), trace: trace)

        let footnote = value(p, "Calories (est.)")!.footnote!
        XCTAssertTrue(footnote.hasPrefix("From your heart rate for 0:05 of 0:20; the other 0:15 estimated from your reps at about "), footnote)
        XCTAssertTrue(footnote.hasSuffix("METs · 70 kg, 36, female formula."), footnote)
    }

    // MARK: the other rows

    /// A reopened page says nothing of today's streak, and a live one does.
    /// reopening a saved session shows its date and time, and a single DONE
    func testReopeningASavedSessionShowsItsDateAndTimeAndASingleDONE() {
        let a = Attempt(rounds: 12, reps: 3, atMillis: now - 2 * day, durationMs: 20 * 60_000, profile: .standard)
        let reopened = page(a, reviewing: true)
        let live = page(a)

        XCTAssertTrue(reopened.headline != "TIME" && reopened.headline != "STOPPED", reopened.headline)
        XCTAssertFalse(reopened.offersProgress, "review mode should offer only DONE")
        XCTAssertNil(value(reopened, "Streak"), "the streak row describes today, not the reviewed day")
        XCTAssertNotNil(value(live, "Streak"))
    }

    /// the date and time follow the phone's 12 and 24 hour setting
    func testTheDateAndTimeFollowThePhonesTwelveAndTwentyFourHourSetting() {
        // Tuesday 29 September 2026, 18:04 in Bucharest (UTC+3).
        let at = zone.epochMs(LocalDate(2026, 9, 29), hour: 18, minute: 4)
        let a = Attempt(rounds: 1, reps: 0, atMillis: at, durationMs: 1)
        XCTAssertEqual(ResultsPageBuilder.reviewHeadline(a, zone, true), "TUE 29 SEP 2026 · 18:04")
        XCTAssertEqual(ResultsPageBuilder.reviewHeadline(a, zone, false), "TUE 29 SEP 2026 · 6:04 PM")
        let midnight = Attempt(rounds: 1, reps: 0, atMillis: zone.epochMs(LocalDate(2026, 9, 29), hour: 0, minute: 5), durationMs: 1)
        XCTAssertEqual(ResultsPageBuilder.reviewHeadline(midnight, zone, false), "TUE 29 SEP 2026 · 12:05 AM")
        XCTAssertEqual(ResultsPageBuilder.reviewHeadline(midnight, zone, true), "TUE 29 SEP 2026 · 00:05")
    }

    /// a review intent for a session no longer on the board finishes
    func testAReviewIntentForASessionNoLongerOnTheBoardFinishes() {
        let a = Attempt(rounds: 1, reps: 0, atMillis: 5, durationMs: 1)
        XCTAssertNil(ResultsModel.session(at: 123_456_789, in: [a]))
        XCTAssertEqual(ResultsModel.session(at: 5, in: [a]), a)
    }

    /// the stat rows say what the camera lost, what was added by hand, and what was paused
    func testTheStatRowsSayWhatTheCameraLostWhatWasAddedByHandAndWhatWasPaused() {
        let a = Attempt(rounds: 2, reps: 5, atMillis: now, durationMs: 600_000, pausedMs: 65_000, manualReps: 4,
                        untrackedMs: 60_000)
        let p = page(a)

        XCTAssertEqual(p.stats.map { $0.label }, ["Paused", "Real time", "Streak", "Added by hand", "Camera lost you", "Score", "Calories"])
        XCTAssertEqual(value(p, "Paused")?.value, "1:05")
        XCTAssertEqual(value(p, "Real time")?.value, "11:05")
        XCTAssertEqual(value(p, "Added by hand")?.value, "4 of 65")
        XCTAssertEqual(value(p, "Camera lost you")?.value, "1:00")
        XCTAssertEqual(value(p, "Score")?.value, "At least 65 — some reps may be missing")
        XCTAssertEqual(value(p, "Streak")?.value, "1 day · 1 week")
    }

    /// the heels-flat row explains why the session says Adaptive Cindy
    func testTheHeelsFlatRowExplainsWhyTheSessionSaysAdaptiveCindy() {
        let a = Attempt(rounds: 1, reps: 0, atMillis: now, durationMs: 600_000,
                        profile: CindyProfile(squat: .heelsFlat))
        let p = ResultsPageBuilder.build(input(a, heelsFlat: true))
        XCTAssertEqual(value(p, "Squats"), StatRow("Squats", "Heels flat · Adaptive Cindy", action: .explainHeelsFlat))
        XCTAssertNil(value(page(a), "Squats"))
    }

    /// the score line says it passed the benchmark
    func testTheScoreLineSaysItPassedTheBenchmark() {
        let a = Attempt(rounds: 28, reps: 0, atMillis: now, durationMs: 20 * 60_000, pausedMs: 30_000,
                        profile: .standard, countedReps: 840)
        XCTAssertEqual(page(a).scoreDetail, "840 reps in 20:00 of clock · 20:30 real  ·  past Tom Holland")
    }

    // MARK: the heart-rate card

    /// Two rounds, a minute at 140 bpm then fifty seconds at 170 and ten at 150, a reading a second.
    private func twoRoundHeartRateAttempt() -> (Attempt, HeartRateTrace) {
        let a = Attempt(rounds: 2, reps: 0, atMillis: now, durationMs: 120_000, roundSplitsMs: [60_000, 50_000],
                        countedReps: 60)
        let samples = (0..<120).map { HeartRateSample(Int64($0) * 1_000, $0 < 60 ? 140 : ($0 < 110 ? 170 : 150)) }
        return (a, HeartRateTrace(startedAtMillis: a.atMillis, samples: samples, pauses: []))
    }

    /// the heart-rate card shows figures, zones, the hardest round and its method with an age on file
    func testTheHeartRateCardShowsFiguresZonesTheHardestRoundAndItsMethodWithAnAgeOnFile() {
        let (a, trace) = twoRoundHeartRateAttempt()
        let p = page(a, body: Body(70.0, age: 30, sex: .male), trace: trace)
        let card = p.heart!

        XCTAssertNotNil(card.zones)
        XCTAssertFalse(card.invitesAge)
        XCTAssertEqual(card.zones!.count, 5)
        XCTAssertTrue(card.hardestRound!.hasPrefix("Round 2") && card.hardestRound!.contains("bpm avg"), card.hardestRound ?? "")
        XCTAssertTrue(card.footnote.contains("Tanaka") && card.footnote.contains("187"), card.footnote)
        XCTAssertTrue(card.footnote.contains("lag your actual effort"), card.footnote)
        XCTAssertTrue(card.verdict!.hasPrefix("Longest in "), card.verdict ?? "")
        XCTAssertEqual(card.figures.map { $0.value }, ["\(card.figures[0].value)", "\(card.figures[1].value)", "2:00"])
        XCTAssertEqual(card.figures[2].unit, "of 2:00")
        XCTAssertEqual(card.hardestRoundSpoken, "Hardest round, round 2, \(card.hardestRound!.split(separator: "·")[1].split(separator: " ")[0]) beats per minute on average")
    }

    /// without an age the card keeps its figures and offers to ask for one instead of zones
    func testWithoutAnAgeTheCardKeepsItsFiguresAndOffersToAskForOneInsteadOfZones() {
        let (a, trace) = twoRoundHeartRateAttempt()
        let card = page(a, body: Body(70.0, age: nil, sex: nil), trace: trace).heart!

        XCTAssertNil(card.zones, "zones need an age")
        XCTAssertTrue(card.invitesAge)
        XCTAssertTrue(card.figures.contains { $0.label == "AVERAGE" } && card.figures.contains { $0.label == "MAXIMUM" })
        XCTAssertFalse(card.footnote.contains("Tanaka"), "no Tanaka claim without an age")
        XCTAssertNil(card.verdict, "no verdict without zones")
    }

    /// the heart-rate card is hidden without a trace
    func testTheHeartRateCardIsHiddenWithoutATrace() {
        let a = Attempt(rounds: 1, reps: 0, atMillis: now, durationMs: 4_000, countedReps: 10)
        XCTAssertNil(page(a, body: Body(70.0, age: 36, sex: .male)).heart)
    }

    /// a reopened session draws the heart-rate card too
    func testAReopenedSessionDrawsTheHeartRateCardToo() {
        let (a, trace) = twoRoundHeartRateAttempt()
        XCTAssertNotNil(page(a, body: Body(70.0, age: 36, sex: .male), reviewing: true, trace: trace).heart)
    }

    /// rendering again rebuilds the heart-rate card instead of stacking another
    func testRenderingAgainRebuildsTheHeartRateCardInsteadOfStackingAnother() {
        let (a, trace) = twoRoundHeartRateAttempt()
        let model = ResultsModel(input(a, body: Body(70.0, age: nil, sex: nil), trace: trace))
        XCTAssertNil(model.page.heart!.zones)

        model.update { $0.body = Body(70.0, age: 30, sex: .male) }
        model.update { $0.body = Body(70.0, age: 30, sex: .male) }

        XCTAssertNotNil(model.page.heart!.zones, "the age did not turn the zones on")
        XCTAssertEqual(model.page.heart!.zones!.count, 5)
    }

    /// the zone rows read as a person would
    func testTheZoneRowsReadAsAPersonWould() {
        let (a, trace) = twoRoundHeartRateAttempt()
        let zones = page(a, body: Body(70.0, age: 30, sex: .male), trace: trace).heart!.zones!

        XCTAssertEqual(zones.map { $0.name }, ["Z1 Warm-up", "Z2 Easy", "Z3 Aerobic", "Z4 Threshold", "Z5 Maximum"])
        XCTAssertEqual(zones.map { $0.range }, ["under 113 bpm", "113–130 bpm", "131–149 bpm", "150–168 bpm", "169+ bpm"])
        XCTAssertEqual(zones[4].spoken, "Z5 Maximum, 50 seconds, 42 percent of covered time, 169 and over beats per minute")
    }

    // MARK: the comparison

    /// the compare card is hidden without an earlier session at the same movements
    func testTheCompareCardIsHiddenWithoutAnEarlierSessionAtTheSameMovements() {
        let a = Attempt(rounds: 10, reps: 0, atMillis: now, durationMs: 20 * 60_000, profile: .standard)
        XCTAssertNil(page(a).compare)
        XCTAssertNil(page(a).comparison)
    }

    /// the compare card shows an earlier session and opens it when tapped
    func testTheCompareCardShowsAnEarlierSessionAndOpensItWhenTapped() {
        let earlier = Attempt(rounds: 8, reps: 0, atMillis: now - 2 * day, durationMs: 20 * 60_000, profile: .standard)
        let a = Attempt(rounds: 10, reps: 0, atMillis: now, durationMs: 20 * 60_000, profile: .standard)
        let p = page(a, records: [earlier, a])

        let card = p.compare!.card
        XCTAssertTrue(card.referenceLine.contains("\(Progress.formatReps(earlier.totalReps)) reps"), card.referenceLine)
        XCTAssertEqual(card.attemptAtMillis, earlier.atMillis)
        XCTAssertEqual(card.deltaLine, "+60 reps · 2 rounds more · 0:30 faster a round")
        XCTAssertTrue(card.ahead)
        // Tapping reopens it: the page for that session is built from its own record.
        let reopened = ResultsPageBuilder.build(input(earlier, records: [earlier, a], reviewing: true))
        XCTAssertEqual(reopened.score, "8")
    }

    /// the delta says at least when this session's score is a lower bound, and fewer when behind
    func testTheDeltaSaysAtLeastWhenThisSessionsScoreIsALowerBoundAndFewerWhenBehind() {
        let best = Attempt(rounds: 12, reps: 0, atMillis: now - 2 * day, durationMs: 20 * 60_000, profile: .standard)
        let behind = Attempt(rounds: 10, reps: 0, atMillis: now, durationMs: 20 * 60_000, profile: .standard,
                             untrackedMs: 60_000)
        let card = page(behind, records: [best, behind]).compare!.card
        XCTAssertEqual(card.deltaLine, "At least 60 fewer reps · 2 rounds fewer · 0:20 slower a round")
        XCTAssertFalse(card.ahead)
    }

    /// a reopened session draws its comparison from what came before it
    func testAReopenedSessionDrawsItsComparisonFromWhatCameBeforeIt() {
        let earlier = Attempt(rounds: 8, reps: 0, atMillis: now - 2 * day, durationMs: 20 * 60_000, profile: .standard)
        let reopened = Attempt(rounds: 9, reps: 0, atMillis: now - day, durationMs: 20 * 60_000, profile: .standard)
        let later = Attempt(rounds: 30, reps: 0, atMillis: now, durationMs: 20 * 60_000, profile: .standard)
        let p = page(reopened, records: [earlier, reopened, later], reviewing: true)

        XCTAssertEqual(p.compare!.card.attemptAtMillis, earlier.atMillis)
        XCTAssertEqual(p.compare!.labels.count, 1)
    }
}
