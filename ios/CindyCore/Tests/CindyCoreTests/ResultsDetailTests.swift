import XCTest
@testable import CindyCore

/// What the results page says in the corners the ported Kotlin tests do not reach: the order and
/// number of badge rows, the level bar, each line of the movement card, which detail rows appear,
/// the sentences of the lifted and comparison cards, and the model's handling of the chosen
/// comparison. Written for the port: each was found by changing the line that decides it and
/// seeing every other test still pass.
final class ResultsDetailTests: XCTestCase {

    private let zone = Zone("Europe/Bucharest")
    private lazy var today = LocalDate(2026, 10, 8)
    private lazy var now = zone.epochMs(today, hour: 12)
    private let day: Int64 = 24 * 60 * 60 * 1000

    private let sets = [SetSplit(.pullup, 14_000, 5, 0), SetSplit(.pushup, 17_000, 10, 0), SetSplit(.squat, 21_000, 15, 0)]

    private func input(_ a: Attempt, records: [Attempt]? = nil, body: Body = Body(0), reviewing: Bool = false,
                       trace: HeartRateTrace? = nil) -> ResultsInput {
        ResultsInput(attempt: a, reviewing: reviewing, records: records ?? [a], body: body, heartTrace: trace,
                     zone: zone, firstDayOfWeek: .monday, today: today)
    }

    private func page(_ a: Attempt, records: [Attempt]? = nil, body: Body = Body(0), reviewing: Bool = false,
                      trace: HeartRateTrace? = nil) -> ResultsPage {
        ResultsPageBuilder.build(input(a, records: records, body: body, reviewing: reviewing, trace: trace))
    }

    private func plain(_ rounds: Int, at: Int64? = nil, profile: CindyProfile = .standard) -> Attempt {
        Attempt(rounds: rounds, reps: 0, atMillis: at ?? now, durationMs: 20 * 60_000, profile: profile)
    }

    private func oneRound(_ sets: [SetSplit], manual: Int = 0, untrackedMs: Int64 = 0,
                          profile: CindyProfile = .standard, at: Int64? = nil) -> Attempt {
        Attempt(rounds: 1, reps: 0, atMillis: at ?? now, durationMs: 120_000, roundSplitsMs: [60_000], profile: profile,
                manualReps: manual, countedReps: 30, untrackedMs: untrackedMs, setSplits: sets)
    }

    // MARK: the celebration

    /// The latest badges of the catalogue come first, and no more than three are named.
    func testTheNewestBadgesAreNamedFirstAndNoMoreThanThree() {
        let box = page(plain(18)).celebration!

        XCTAssertEqual(box.rows.map { $0.text }, ["First Cindy on the board.", "New badge: Advanced",
                                                   "New badge: Intermediate", "New badge: Novice"])
        XCTAssertEqual(box.rows.map { $0.headline }, [true, false, false, false])
        XCTAssertEqual(box.more, "+2 more in your profile")
    }

    /// A beaten record gets the trophy, and the line stands alone when nothing else was earned.
    func testABeatenRecordGetsTheTrophy() {
        let first = plain(10, at: now - 3 * day)
        let second = plain(14)
        let box = page(second, records: [first, second]).celebration!

        XCTAssertEqual(box.rows.map { $0.text }, ["New personal record."])
        XCTAssertEqual(box.rows[0].icon, .trophy)
    }

    /// A reopened session is credited with what had happened by then and nothing that came after.
    func testAReopenedSessionIsNotJudgedAgainstLaterSessions() {
        let first = plain(10, at: now - 3 * day)
        let second = plain(14, at: now - day)
        let later = plain(20)

        let p = page(second, records: [first, second, later], reviewing: true)

        XCTAssertEqual(p.celebration?.rows.map { $0.text }, ["New personal record."])
        XCTAssertEqual(p.compare?.card.referenceLine, "5 Oct · 10 · 300 reps")
    }

    // MARK: the level

    /// The bar fills with the rounds, and the top of the ladder has nothing further to say.
    func testTheLevelBarFillsWithTheRoundsAndTheTopHasNoNext() {
        let low = page(plain(1)).level
        XCTAssertEqual(low.rung, "1 of 6")
        XCTAssertEqual(low.progressPercent, 20)
        XCTAssertEqual(low.next, "4 more rounds to Novice")

        let mid = page(plain(18)).level
        XCTAssertEqual(mid.progressPercent, 40)
        XCTAssertEqual(mid.next, "3 more rounds to Elite")

        let top = page(plain(30)).level
        XCTAssertEqual(top.rung, "6 of 6")
        XCTAssertEqual(top.progressPercent, 100)
        XCTAssertEqual(top.next, "Top of the ladder.")
    }

    /// A session with nothing timed draws neither the round track nor the movement card.
    func testNothingTimedDrawsNeitherTheTrackNorTheMovementCard() {
        let nothing = Attempt(rounds: 0, reps: 0, atMillis: now, durationMs: 0, profile: .standard)
        let p = page(nothing)
        XCTAssertNil(p.track)
        XCTAssertNil(p.movements)
    }

    // MARK: the movement card

    /// Each movement's lines, in order: its time, the average of its complete sets and its share.
    func testTheMovementCardGivesTimeAverageAndShareOfEachMovement() {
        let columns = page(oneRound(sets)).movements!.columns

        XCTAssertEqual(columns.map { $0.lines }, [
            ["0:14 total", "0:14 a set", "27% of set time"],
            ["0:17 total", "0:17 a set", "33% of set time"],
            ["0:21 total", "0:21 a set", "40% of set time"]])
        XCTAssertEqual(columns[0].spoken, "pull-ups: 5 reps, 0:14 total, 0:14 a set, 27% of set time")
    }

    /// Reps tapped in are named for the set that had them, and only where there were some.
    func testTheMovementCardNamesTappedRepsOnlyWhereThereWereSome() {
        let tapped = [SetSplit(.pullup, 14_000, 5, 2), SetSplit(.pushup, 17_000, 10, 0), SetSplit(.squat, 21_000, 15, 0)]
        let columns = page(oneRound(tapped, manual: 2)).movements!.columns

        XCTAssertTrue(columns[0].lines.contains("2 tapped"), "\(columns[0].lines)")
        XCTAssertFalse(columns[1].lines.contains { $0.contains("tapped") })
        XCTAssertFalse(columns[2].lines.contains { $0.contains("tapped") })
    }

    /// A label of ten characters still fits a third of a phone; eleven does not.
    func testTheMovementCardIsTallOnlyPastTenCharacters() {
        let box = CindyProfile(squat: .boxSquat)   // "box squats", exactly ten
        XCTAssertEqual(page(oneRound(sets, profile: box)).movements!.tall, false)

        let knees = CindyProfile(push: .kneePushUp)   // "knee push-ups", thirteen
        XCTAssertEqual(page(oneRound(sets, profile: knees)).movements!.tall, true)
    }

    // MARK: the detail rows

    /// Nothing is listed that did not happen.
    func testTheDetailRowsListOnlyWhatHappened() {
        let labels = page(oneRound(sets)).stats.map { $0.label }

        XCTAssertFalse(labels.contains("Paused"))
        XCTAssertFalse(labels.contains("Real time"))
        XCTAssertFalse(labels.contains("Added by hand"))
        XCTAssertFalse(labels.contains("Camera lost you"))
        XCTAssertFalse(labels.contains("Score"))
    }

    /// A short loss is reported and does not turn the score into a floor.
    func testAShortLossIsReportedWithoutMakingTheScoreAFloor() {
        let labels = page(oneRound(sets, untrackedMs: 2_000)).stats.map { $0.label }

        XCTAssertTrue(labels.contains("Camera lost you"))
        XCTAssertFalse(labels.contains("Score"))
    }

    /// A long loss makes the score a floor, in the rows, the track and the movement card.
    func testALongLossMakesTheScoreAFloor() {
        let p = page(oneRound(sets, untrackedMs: 90_000))

        XCTAssertEqual(p.stats.first { $0.label == "Score" }?.value, "At least 30 — some reps may be missing")
        XCTAssertTrue(p.track!.atLeast)
        XCTAssertTrue(p.movements!.columns.allSatisfy { $0.atLeast })
        XCTAssertTrue(p.movements!.columns[0].spoken.hasPrefix("pull-ups: at least 5 reps"))
    }

    /// The paused time is explained under the splits only when there was some.
    func testThePausedNoteUnderTheSplitsAppearsOnlyWithPausedTime() {
        let paused = Attempt(rounds: 2, reps: 0, atMillis: now, durationMs: 300_000, pausedMs: 30_000,
                             roundSplitsMs: [140_000, 160_000], profile: .standard)
        let unpaused = Attempt(rounds: 2, reps: 0, atMillis: now, durationMs: 300_000,
                               roundSplitsMs: [140_000, 160_000], profile: .standard)

        XCTAssertTrue(page(paused).splits!.note.contains("Splits exclude paused time."))
        XCTAssertFalse(page(unpaused).splits!.note.contains("paused"))
        XCTAssertTrue(page(paused).stats.map { $0.label }.starts(with: ["Paused", "Real time"]))
    }

    /// With nothing earlier to compare with the splits do not mention a tick.
    func testTheSplitsMentionNoTickWithoutAComparison() {
        let a = Attempt(rounds: 2, reps: 0, atMillis: now, durationMs: 300_000, roundSplitsMs: [140_000, 160_000],
                        profile: .standard)
        XCTAssertFalse(page(a).splits!.note.contains("tick"))
    }

    // MARK: lifted and burned

    /// With nothing counted and no clock there is nothing to invite a weight for.
    func testNothingIsOfferedForASessionWithNothingToMeasure() {
        let nothing = Attempt(rounds: 0, reps: 0, atMillis: now, durationMs: 0, profile: .standard)
        XCTAssertEqual(page(nothing).lifted, .hidden)
    }

    /// A floor is said where the figure is read, but the note only repeats it when no lifted half
    /// has already said so.
    func testAFloorIsSaidOnTheBurnedFigureAndRepeatedInTheNoteOnlyWithoutALiftedHalf() {
        guard case .card(let both) = page(oneRound(sets, untrackedMs: 90_000), body: Body(80)).lifted else {
            return XCTFail("no card")
        }
        XCTAssertEqual(both.burned?.figure.prefix, "At least")
        XCTAssertTrue(both.spoken.contains("You burned at least "), both.spoken)
        // The lifted half already says it; the energy sentence must not say it again.
        XCTAssertEqual(both.note.components(separatedBy: "so this is a floor").count - 1, 1, both.note)

        let old = Attempt(rounds: 2, reps: 0, atMillis: now, durationMs: 20 * 60_000, profile: .standard,
                          untrackedMs: 90_000)
        guard case .card(let burnedOnly) = page(old, body: Body(80)).lifted else { return XCTFail("no card") }
        XCTAssertNil(burnedOnly.lifted)
        XCTAssertTrue(burnedOnly.note.contains("so this is a floor"), burnedOnly.note)

        guard case .card(let exact) = page(oneRound(sets), body: Body(80)).lifted else { return XCTFail("no card") }
        XCTAssertNil(exact.burned?.figure.prefix)
    }

    /// The animal follows the day, so the same lift is not always the same animal.
    func testTheAnimalFollowsTheDay() {
        var animals = Set<String>()
        for d in 0..<14 {
            if case .card(let c) = page(oneRound(sets, at: now - Int64(d) * day), body: Body(80)).lifted,
               let emoji = c.lifted?.animalEmoji { animals.insert(emoji) }
        }
        XCTAssertTrue(animals.count > 1, "\(animals)")
    }

    /// More animals than fit a row are drawn as five and a count.
    func testMoreAnimalsThanFitAreDrawnAsFiveAndACount() {
        let heavy = Attempt(rounds: 30, reps: 0, atMillis: now, durationMs: 20 * 60_000, roundSplitsMs: Array(repeating: 40_000, count: 30),
                            profile: .standard, countedReps: 900,
                            setSplits: Array((0..<30).flatMap { _ in sets }))
        var counts = Set<String>()
        for d in 0..<14 {
            let attempt = Attempt(rounds: heavy.rounds, reps: 0, atMillis: now - Int64(d) * day, durationMs: heavy.durationMs,
                                  roundSplitsMs: heavy.roundSplitsMs, profile: .standard, countedReps: 900,
                                  setSplits: heavy.setSplits)
            guard case .card(let c) = page(attempt, body: Body(120)).lifted, let part = c.lifted else { continue }
            XCTAssertTrue(part.emojiCount <= Equivalents.maxEmoji, "drew \(part.emojiCount)")
            if let more = part.more { counts.insert(more) }
        }
        XCTAssertFalse(counts.isEmpty, "no day needed a count")
        XCTAssertTrue(counts.allSatisfy { $0.hasPrefix("×") }, "\(counts)")
    }

    // MARK: the comparison card

    /// Level on reps says so, and is not ahead.
    func testLevelOnRepsSaysSoAndIsNotAhead() {
        let before = plain(10, at: now - day)
        let p = page(plain(10), records: [before, plain(10)])

        XCTAssertEqual(p.compare?.card.deltaLine, "level on reps")
        XCTAssertEqual(p.compare?.card.ahead, false)
    }

    /// Behind says how many, in singular or plural.
    func testBehindSaysHowManyInSingularOrPlural() {
        let before = plain(12, at: now - day)

        XCTAssertEqual(page(plain(11), records: [before, plain(11)]).compare?.card.deltaLine,
                       "30 fewer reps · 1 round fewer · 0:09 slower a round")
        XCTAssertEqual(page(plain(10), records: [before, plain(10)]).compare?.card.deltaLine,
                       "60 fewer reps · 2 rounds fewer · 0:20 slower a round")
        XCTAssertEqual(page(plain(11), records: [before, plain(11)]).compare?.card.ahead, false)
    }

    // MARK: the model

    /// Rebuilding the page for a new weight keeps the earlier session the athlete chose.
    func testRebuildingForANewWeightKeepsTheComparisonChosen() {
        let best = plain(20, at: now - 3 * day)
        let last = plain(12, at: now - day)
        let todays = plain(14)
        let model = ResultsModel(input(todays, records: [best, last, todays]))
        model.chooseComparison(1)
        XCTAssertEqual(model.page.compare?.chosen, 1)

        model.update { $0.body = Body(80) }

        XCTAssertEqual(model.page.compare?.chosen, 1)
        XCTAssertEqual(model.page.comparison?.atMillis, last.atMillis)
    }

    /// Choosing what is already chosen, or something that is not there, builds nothing.
    func testChoosingWhatIsAlreadyChosenBuildsNothing() {
        let best = plain(20, at: now - 3 * day)
        let last = plain(12, at: now - day)
        let todays = plain(14)
        let model = ResultsModel(input(todays, records: [best, last, todays]))
        var builds = 0
        model.onChange = { builds += 1 }

        model.chooseComparison(0)
        model.chooseComparison(7)
        XCTAssertEqual(builds, 0)

        model.chooseComparison(1)
        XCTAssertEqual(builds, 1)
    }

    // MARK: the heart-rate card

    /// Shares are of the time the watch covered, not of the whole clock.
    func testZoneSharesAreOfTheCoveredTimeAndTheLowestZoneIsOpenBelow() {
        let a = Attempt(rounds: 1, reps: 0, atMillis: now, durationMs: 120_000, roundSplitsMs: [60_000], profile: .standard,
                        countedReps: 30)
        let trace = HeartRateTrace(startedAtMillis: a.atMillis,
                                   samples: (0..<60).map { HeartRateSample(Int64($0) * 1_000, 170) }, pauses: [])

        let zones = page(a, body: Body(70, age: 30, sex: .male), trace: trace).heart!.zones!

        XCTAssertTrue(zones[4].spoken.contains("100 percent of covered time"), zones[4].spoken)
        XCTAssertTrue(zones[0].spoken.hasSuffix("under 113 beats per minute"), zones[0].spoken)
        XCTAssertTrue(zones[4].spoken.hasSuffix("169 and over beats per minute"), zones[4].spoken)
    }
}
