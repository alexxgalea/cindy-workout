import XCTest
import CindyCore
import CindyFixtures

/// Everything an athlete can earn. Port of `BadgesTest.kt`.
final class BadgesTests: XCTestCase {

    private let zone = Zone("Europe/Bucharest")
    private let monday = DayOfWeek.monday

    /// A Monday, so that days and weeks can be counted on the page.
    private let start = LocalDate(2026, 3, 2)

    private let adaptive = CindyProfile(squat: .boxSquat)
    private let tolerance = Records.untrackedToleranceMs

    private func millis(_ day: LocalDate, _ hour: Int = 12, _ minute: Int = 0, at: Zone? = nil) -> Int64 {
        (at ?? zone).epochMs(day, hour: hour, minute: minute)
    }

    /// A session that earns as little as it can: short, standard, nothing remarkable about it.
    private func attempt(_ day: LocalDate? = nil, rounds: Int = 10, reps: Int = 0,
                         profile: CindyProfile? = CindyProfile.standard, untrackedMs: Int64 = 0,
                         manualReps: Int = 0, durationMs: Int64 = 10 * 60_000, splitsMs: [Int64] = [],
                         countedReps: Int? = nil) -> Attempt {
        Attempt(rounds: rounds, reps: reps, atMillis: millis(day ?? start), durationMs: durationMs,
                roundSplitsMs: splitsMs, profile: profile, manualReps: manualReps,
                countedReps: countedReps, untrackedMs: untrackedMs)
    }

    private func earned(_ attempts: [Attempt], weekStart: DayOfWeek? = nil, at: Zone? = nil) -> Set<Badge> {
        Set(Badges.earned(attempts, zone: at ?? zone, firstDayOfWeek: weekStart ?? monday).map { $0.badge })
    }

    private func stamps(_ attempts: [Attempt]) -> [Badge: Int64] {
        Dictionary(uniqueKeysWithValues: Badges.earned(attempts, zone: zone, firstDayOfWeek: monday).map { ($0.badge, $0.atMillis) })
    }

    private func progress(_ badge: Badge, _ attempts: [Attempt], today: LocalDate? = nil,
                          weekStart: DayOfWeek? = nil) -> BadgeProgress? {
        Badges.progress(badge, attempts, today: today ?? start, zone: zone, firstDayOfWeek: weekStart ?? monday)
    }

    /// One session on each of `n` days in a row, starting at `from`.
    private func everyDay(_ n: Int, from: LocalDate? = nil) -> [Attempt] {
        (0..<n).map { attempt((from ?? start).plusDays($0)) }
    }

    /// One session in each of `n` weeks in a row, starting at `from`.
    private func everyWeek(_ n: Int, from: LocalDate? = nil) -> [Attempt] {
        (0..<n).map { attempt((from ?? start).plusWeeks($0)) }
    }

    /// `n` sessions two days apart, so that no streak gets in the way of counting them.
    private func spaced(_ n: Int, make: (LocalDate) -> Attempt) -> [Attempt] {
        (0..<n).map { make(start.plusDays(2 * $0)) }
    }

    private func spacedDefault(_ n: Int) -> [Attempt] { spaced(n) { self.attempt($0) } }

    private func family(_ badges: Set<Badge>, _ families: BadgeFamily...) -> Set<Badge> {
        badges.filter { families.contains($0.family) }.reduce(into: Set<Badge>()) { $0.insert($1) }
    }

    // MARK: the catalogue

    /// the catalogue has 26 badges
    func testTheCatalogueHas26Badges() {
        XCTAssertEqual(Badge.allCases.count, 26)
    }

    /// titles are unique and faces are unique within a family
    func testTitlesAreUniqueAndFacesAreUniqueWithinAFamily() {
        XCTAssertEqual(Badge.allCases.count, Set(Badge.allCases.map { $0.title }).count)
        for family in BadgeFamily.allCases {
            let badges = Badge.allCases.filter { $0.family == family }
            XCTAssertEqual(badges.count, Set(badges.map { $0.face }).count, "faces in \(family)")
        }
    }

    /// the families sit together, in the order the profile lists them
    func testTheFamiliesSitTogetherInTheOrderTheProfileListsThem() {
        let families = Badge.allCases.map { $0.family }
        var distinct: [BadgeFamily] = []
        for f in families where !distinct.contains(f) { distinct.append(f) }
        XCTAssertEqual(distinct, BadgeFamily.allCases)
        // One block per family: the family only changes as many times as there are borders.
        let changes = zip(families, families.dropFirst()).filter { $0 != $1 }.count
        XCTAssertEqual(changes, BadgeFamily.allCases.count - 1)
    }

    /// every badge says what earns it, in a sentence
    func testEveryBadgeSaysWhatEarnsItInASentence() {
        for badge in Badge.allCases {
            XCTAssertFalse(badge.requirement.trimmingCharacters(in: .whitespaces).isEmpty, "\(badge) has no requirement")
            XCTAssertTrue(badge.requirement.hasSuffix("."), "\(badge): \(badge.requirement)")
            XCTAssertFalse(badge.face.trimmingCharacters(in: .whitespaces).isEmpty, "\(badge) has no face")
            XCTAssertLessThanOrEqual(badge.face.utf16.count, 4, "\(badge)'s face is too wide for its disc")
        }
    }

    /// the round badges are the rungs of the ladder and are read from it
    func testTheRoundBadgesAreTheRungsOfTheLadderAndAreReadFromIt() {
        let rungs: [(Badge, Level)] = [(.novice, .novice), (.intermediate, .intermediate), (.advanced, .advanced),
                                       (.elite, .elite), (.legend, .legend)]
        for (badge, level) in rungs {
            XCTAssertEqual(badge.title, level.title)
            XCTAssertEqual(badge.face, "\(level.minRounds)R")
            XCTAssertTrue(badge.requirement.hasPrefix("\(level.minRounds) rounds"), badge.requirement)
            XCTAssertTrue(earned([attempt(rounds: level.minRounds)]).contains(badge), "\(badge) at \(level.minRounds) rounds")
            XCTAssertFalse(earned([attempt(rounds: level.minRounds - 1)]).contains(badge), "\(badge) one round short")
        }
    }

    /// no rung of the ladder can be mistaken for First round
    func testNoRungOfTheLadderCanBeMistakenForFirstRound() {
        // First round asks for one round, and the menu finds the highest rung held by its round
        // count. A ladder retuned to put a rung at one round or fewer would collide with it, and
        // lose its progress line, which is not shown for a target of one.
        for level in Level.allCases where level != .firstSteps {
            XCTAssertGreaterThan(level.minRounds, 1, "\(level.title) at \(level.minRounds) rounds")
        }
    }

    // MARK: nothing yet

    /// there is nothing to earn before the first session
    func testThereIsNothingToEarnBeforeTheFirstSession() {
        XCTAssertTrue(Badges.earned([], zone: zone, firstDayOfWeek: monday).isEmpty)
    }

    /// an empty history is at zero on every badge that counts something
    func testAnEmptyHistoryIsAtZeroOnEveryBadgeThatCountsSomething() {
        XCTAssertEqual(progress(.sessions10, []), BadgeProgress(0, 10, "sessions"))
        XCTAssertEqual(progress(.intermediate, []), BadgeProgress(0, 10, "rounds"))
        XCTAssertEqual(progress(.streak7, []), BadgeProgress(0, 7, "days"))
        XCTAssertEqual(progress(.weeks4, []), BadgeProgress(0, 4, "weeks"))
        XCTAssertEqual(progress(.reps1000, []), BadgeProgress(0, 1_000, "reps"))
    }

    // MARK: sessions

    /// any first session earns First Cindy, however it went
    func testAnyFirstSessionEarnsFirstCindyHoweverItWent() {
        let sessions = [attempt(), attempt(untrackedMs: tolerance), attempt(profile: adaptive),
                        attempt(profile: nil), attempt(rounds: 0, reps: 3)]
        for a in sessions { XCTAssertTrue(earned([a]).contains(.firstCindy)) }
    }

    /// each session count is earned at its number and not the one before
    func testEachSessionCountIsEarnedAtItsNumberAndNotTheOneBefore() {
        let counts: [(Badge, Int)] = [(.sessions10, 10), (.sessions25, 25), (.sessions50, 50), (.sessions100, 100)]
        for (badge, n) in counts {
            XCTAssertFalse(earned(spacedDefault(n - 1)).contains(badge), "\(badge) at \(n - 1)")
            XCTAssertTrue(earned(spacedDefault(n)).contains(badge), "\(badge) at \(n)")
        }
    }

    /// every kind of session counts towards the number of sessions
    func testEveryKindOfSessionCountsTowardsTheNumberOfSessions() {
        let kinds: [(LocalDate) -> Attempt] = [
            { self.attempt($0) },
            { self.attempt($0, untrackedMs: self.tolerance) },
            { self.attempt($0, profile: self.adaptive) },
            { self.attempt($0, profile: nil) },
            { self.attempt($0, rounds: 0, reps: 2) }
        ]
        let ten = spaced(10) { day in kinds[day.epochDay % kinds.count](day) }
        XCTAssertTrue(earned(ten).contains(.sessions10))
    }

    // MARK: rounds

    /// First round needs a whole round, not most of one
    func testFirstRoundNeedsAWholeRoundNotMostOfOne() {
        XCTAssertFalse(earned([attempt(rounds: 0, reps: 29)]).contains(.firstRound))
        XCTAssertTrue(earned([attempt(rounds: 1)]).contains(.firstRound))
    }

    /// the rungs are about one session, so rounds in two sessions do not add up
    func testTheRungsAreAboutOneSessionSoRoundsInTwoSessionsDoNotAddUp() {
        let two = [attempt(start, rounds: 6), attempt(start.plusDays(2), rounds: 6)]
        XCTAssertFalse(earned(two).contains(.intermediate))
        XCTAssertTrue(earned(two).contains(.novice))
    }

    /// the rung badges match the level that a score earns, rounds 0 to 30
    func testTheRungBadgesMatchTheLevelThatAScoreEarnsRounds0To30() {
        let rungBadges = Badge.allCases.filter { $0.family == .rounds && $0 != .firstRound && $0 != .pastBenchmark }
        for rounds in 0...30 {
            let a = attempt(rounds: rounds)
            let expected = Level.allCases.filter { $0 != .firstSteps && $0.rawValue <= a.level!.rawValue }.map { $0.title }
            let got = Badges.earned([a], zone: zone, firstDayOfWeek: monday).map { $0.badge }
                .filter { rungBadges.contains($0) }.map { $0.title }
            XCTAssertEqual(got, expected, "at \(rounds) rounds")
        }
    }

    /// Legend is level with the benchmark and only going past it beats it
    func testLegendIsLevelWithTheBenchmarkAndOnlyGoingPastItBeatsIt() {
        let level = earned([attempt(rounds: 27)])
        XCTAssertTrue(level.contains(.legend))
        XCTAssertFalse(level.contains(.pastBenchmark))

        XCTAssertTrue(earned([attempt(rounds: 27, reps: 1)]).contains(.pastBenchmark))
    }

    /// Past the benchmark says what the record board says
    func testPastTheBenchmarkSaysWhatTheRecordBoardSays() {
        let scores = [(26, 29), (27, 0), (27, 1), (28, 0)]
        let profiles: [CindyProfile?] = [CindyProfile.standard, adaptive, nil]
        for profile in profiles {
            for untracked in [Int64(0), tolerance - 1, tolerance] {
                for (rounds, reps) in scores {
                    let a = attempt(rounds: rounds, reps: reps, profile: profile, untrackedMs: untracked)
                    XCTAssertEqual(earned([a]).contains(.pastBenchmark), Records.beatsBenchmark(a),
                                   "\(rounds)+\(reps), \(String(describing: profile)), \(untracked) ms untracked")
                }
            }
        }
    }

    /// a session the camera lost the athlete in earns no round badge
    func testASessionTheCameraLostTheAthleteInEarnsNoRoundBadge() {
        let a = attempt(rounds: 27, reps: 1, untrackedMs: tolerance)
        let got = earned([a])
        XCTAssertEqual(family(got, .rounds), [])
        XCTAssertTrue(got.contains(.firstCindy), "it still counts as a session")
    }

    /// a moment short of the tolerance is still an exact score
    func testAMomentShortOfTheToleranceIsStillAnExactScore() {
        let a = attempt(rounds: 10, untrackedMs: tolerance - 1)
        XCTAssertTrue(earned([a]).contains(.intermediate))
    }

    /// an adaptive session earns no round or pace badge, but it counts for the rest
    func testAnAdaptiveSessionEarnsNoRoundOrPaceBadgeButItCountsForTheRest() {
        let a = attempt(rounds: 27, reps: 1, profile: adaptive, splitsMs: [30_000])
        let got = earned([a])
        XCTAssertEqual(family(got, .rounds, .pace), [])
        XCTAssertTrue(got.contains(.firstCindy))
        XCTAssertTrue(got.contains(.madeItYours))
    }

    /// a profile this build cannot read earns no round or pace badge and is not called adaptive
    func testAProfileThisBuildCannotReadEarnsNoRoundOrPaceBadgeAndIsNotCalledAdaptive() {
        let a = attempt(rounds: 27, reps: 1, profile: nil, splitsMs: [30_000])
        let got = earned([a])
        XCTAssertEqual(family(got, .rounds, .pace), [])
        XCTAssertFalse(got.contains(.madeItYours), "what it was is unknown, so it is not claimed")
        XCTAssertTrue(got.contains(.firstCindy))
    }

    // MARK: streaks

    /// three days in a row earn the badge on the third day
    func testThreeDaysInARowEarnTheBadgeOnTheThirdDay() {
        let got = stamps(everyDay(3))
        XCTAssertEqual(got[.streak3], millis(start.plusDays(2)))
        XCTAssertFalse(earned(everyDay(2)).contains(.streak3))
    }

    /// each daily run is earned at its length and not the day before
    func testEachDailyRunIsEarnedAtItsLengthAndNotTheDayBefore() {
        let runs: [(Badge, Int)] = [(.streak3, 3), (.streak7, 7), (.streak14, 14), (.streak30, 30)]
        for (badge, n) in runs {
            XCTAssertFalse(earned(everyDay(n - 1)).contains(badge), "\(badge) at \(n - 1)")
            XCTAssertTrue(earned(everyDay(n)).contains(badge), "\(badge) at \(n)")
        }
    }

    /// a missed day starts the run again
    func testAMissedDayStartsTheRunAgain() {
        // Two days, a day off, two more: never three together.
        let days = [0, 1, 3, 4].map { attempt(start.plusDays($0)) }
        XCTAssertFalse(earned(days).contains(.streak3))

        // A fifth day makes three: 3, 4 and 5.
        let fifth = days + [attempt(start.plusDays(5))]
        XCTAssertEqual(stamps(fifth)[.streak3], millis(start.plusDays(5)))
    }

    /// several sessions in one day are one day
    func testSeveralSessionsInOneDayAreOneDay() {
        let sessions = [attempt(start), attempt(start), attempt(start), attempt(start.plusDays(1))]
        XCTAssertFalse(earned(sessions).contains(.streak3))
    }

    /// a streak is for keeping, so stopping does not take it back
    func testAStreakIsForKeepingSoStoppingDoesNotTakeItBack() {
        let sevenThenNothing = everyDay(7) + [attempt(start.plusDays(400))]
        XCTAssertTrue(earned(sevenThenNothing).contains(.streak7))
    }

    /// a day is the athlete's local day, not a UTC one
    func testADayIsTheAthletesLocalDayNotAUTCOne() {
        // 23:50 and 00:10 in Bucharest fall on one UTC date and on two dates of the athlete's.
        let sessions = [Attempt(rounds: 10, reps: 0, atMillis: millis(start, 23, 50)),
                        Attempt(rounds: 10, reps: 0, atMillis: millis(start.plusDays(1), 0, 10)),
                        Attempt(rounds: 10, reps: 0, atMillis: millis(start.plusDays(2), 12, 0))]
        XCTAssertTrue(earned(sessions, at: zone).contains(.streak3))
        XCTAssertFalse(earned(sessions, at: Zone("UTC")).contains(.streak3))
    }

    /// four weeks in a row earn the badge in the fourth week
    func testFourWeeksInARowEarnTheBadgeInTheFourthWeek() {
        let got = stamps(everyWeek(4))
        XCTAssertEqual(got[.weeks4], millis(start.plusWeeks(3)))
        XCTAssertFalse(earned(everyWeek(3)).contains(.weeks4))
    }

    /// each weekly run is earned at its length and not the week before
    func testEachWeeklyRunIsEarnedAtItsLengthAndNotTheWeekBefore() {
        let runs: [(Badge, Int)] = [(.weeks4, 4), (.weeks12, 12), (.weeks26, 26)]
        for (badge, n) in runs {
            XCTAssertFalse(earned(everyWeek(n - 1)).contains(badge), "\(badge) at \(n - 1)")
            XCTAssertTrue(earned(everyWeek(n)).contains(badge), "\(badge) at \(n)")
        }
    }

    /// a week with no session breaks the run
    func testAWeekWithNoSessionBreaksTheRun() {
        let weeks = [0, 1, 3, 4].map { attempt(start.plusWeeks($0)) }
        XCTAssertFalse(earned(weeks).contains(.weeks4))
    }

    /// where the week starts is the locale's call
    func testWhereTheWeekStartsIsTheLocalesCall() {
        XCTAssertEqual(start.dayOfWeek, .monday)
        // Mon 2, Sun 15, Mon 16, Mon 23 March. Weeks begin on Monday: four weeks in a row.
        // Begin them on Sunday and the 15th and 16th share one, leaving a gap after the 2nd.
        let sessions = [attempt(start), attempt(start.plusDays(13)), attempt(start.plusDays(14)), attempt(start.plusDays(21))]
        XCTAssertEqual(start.plusDays(13).dayOfWeek, .sunday)
        XCTAssertTrue(earned(sessions, weekStart: .monday).contains(.weeks4))
        XCTAssertFalse(earned(sessions, weekStart: .sunday).contains(.weeks4))
    }

    // MARK: volume

    /// each rep total is earned at its number and not the rep before
    func testEachRepTotalIsEarnedAtItsNumberAndNotTheRepBefore() {
        let totals: [(Badge, Int)] = [(.reps1000, 1_000), (.reps5000, 5_000), (.reps10000, 10_000)]
        for (badge, n) in totals {
            XCTAssertFalse(earned([attempt(countedReps: n - 1)]).contains(badge), "\(badge) at \(n - 1)")
            XCTAssertTrue(earned([attempt(countedReps: n)]).contains(badge), "\(badge) at \(n)")
        }
    }

    /// reps add up across sessions and the badge belongs to the session that got there
    func testRepsAddUpAcrossSessionsAndTheBadgeBelongsToTheSessionThatGotThere() {
        let first = attempt(start, countedReps: 600)
        let second = attempt(start.plusDays(2), countedReps: 400)
        let third = attempt(start.plusDays(4), countedReps: 400)
        let got = stamps([first, second, third])
        XCTAssertEqual(got[.reps1000], second.atMillis)
    }

    /// every session's reps count, the lower-bound and adaptive ones too
    func testEverySessionsRepsCountTheLowerBoundAndAdaptiveOnesToo() {
        let sessions = [attempt(start, untrackedMs: tolerance, countedReps: 400),
                        attempt(start.plusDays(2), profile: adaptive, countedReps: 300),
                        attempt(start.plusDays(4), profile: nil, countedReps: 300)]
        XCTAssertTrue(earned(sessions).contains(.reps1000))
    }

    // MARK: pace

    /// a round under two minutes
    func testARoundUnderTwoMinutes() {
        XCTAssertTrue(earned([attempt(splitsMs: [119_999])]).contains(.roundUnder2))
        XCTAssertFalse(earned([attempt(splitsMs: [120_000])]).contains(.roundUnder2))
    }

    /// it is the fastest round that counts, not the average
    func testItIsTheFastestRoundThatCountsNotTheAverage() {
        let a = attempt(splitsMs: [200_000, 119_000, 300_000])
        XCTAssertTrue(earned([a]).contains(.roundUnder2))
    }

    /// a round under 45 seconds is under two minutes too
    func testARoundUnder45SecondsIsUnderTwoMinutesToo() {
        let under = earned([attempt(splitsMs: [44_999])])
        XCTAssertTrue(under.contains(.roundUnder45))
        XCTAssertTrue(under.contains(.roundUnder2))

        let over = earned([attempt(splitsMs: [45_000])])
        XCTAssertFalse(over.contains(.roundUnder45))
        XCTAssertTrue(over.contains(.roundUnder2))
    }

    /// no round splits, no pace badge
    func testNoRoundSplitsNoPaceBadge() {
        XCTAssertEqual(family(earned([attempt(rounds: 27)]), .pace), [])
    }

    /// a fast round only counts in an exact standard Cindy
    func testAFastRoundOnlyCountsInAnExactStandardCindy() {
        let fast: [Int64] = [30_000]
        let notClaimed = [attempt(profile: adaptive, splitsMs: fast), attempt(profile: nil, splitsMs: fast),
                          attempt(untrackedMs: tolerance, splitsMs: fast)]
        for a in notClaimed { XCTAssertEqual(family(earned([a]), .pace), []) }
        XCTAssertEqual(family(earned([attempt(splitsMs: fast)]), .pace), [.roundUnder2, .roundUnder45])
    }

    // MARK: craft

    /// A whole clock from a build that counted reps: the only kind of session that can be Every rep seen.
    private func whole(durationMs: Int64 = Progress.fullSessionMs, manualReps: Int = 0, untrackedMs: Int64 = 0,
                       profile: CindyProfile? = CindyProfile.standard, countedReps: Int? = 300) -> Attempt {
        attempt(profile: profile, untrackedMs: untrackedMs, manualReps: manualReps, durationMs: durationMs, countedReps: countedReps)
    }

    /// a whole clock with nothing tapped in earns Every rep seen
    func testAWholeClockWithNothingTappedInEarnsEveryRepSeen() {
        XCTAssertTrue(earned([whole()]).contains(.everyRepSeen))
    }

    /// a second short of the clock is not a whole session
    func testASecondShortOfTheClockIsNotAWholeSession() {
        XCTAssertFalse(earned([whole(durationMs: Progress.fullSessionMs - 1)]).contains(.everyRepSeen))
    }

    /// one rep tapped in spoils it
    func testOneRepTappedInSpoilsIt() {
        XCTAssertFalse(earned([whole(manualReps: 1)]).contains(.everyRepSeen))
    }

    /// a score the camera could not stand behind does not earn it
    func testAScoreTheCameraCouldNotStandBehindDoesNotEarnIt() {
        XCTAssertFalse(earned([whole(untrackedMs: tolerance)]).contains(.everyRepSeen))
        XCTAssertTrue(earned([whole(untrackedMs: tolerance - 1)]).contains(.everyRepSeen))
    }

    /// a whole clock with nothing counted earns nothing
    func testAWholeClockWithNothingCountedEarnsNothing() {
        XCTAssertFalse(earned([whole(countedReps: 0)]).contains(.everyRepSeen))
    }

    /// a session from before reps were counted cannot show that none were tapped in
    func testASessionFromBeforeRepsWereCountedCannotShowThatNoneWereTappedIn() {
        // Such a session decodes with no taps and no blind time because they were not recorded,
        // not because there were none.
        XCTAssertFalse(earned([whole(countedReps: nil)]).contains(.everyRepSeen))
        XCTAssertTrue(earned([whole()]).contains(.everyRepSeen))
    }

    /// it does not have to be a standard Cindy
    func testItDoesNotHaveToBeAStandardCindy() {
        XCTAssertTrue(earned([whole(profile: adaptive)]).contains(.everyRepSeen))
    }

    /// Made it yours is an adaptive session and nothing else
    func testMadeItYoursIsAnAdaptiveSessionAndNothingElse() {
        XCTAssertTrue(earned([attempt(profile: adaptive)]).contains(.madeItYours))
        XCTAssertFalse(earned([attempt(profile: CindyProfile.standard)]).contains(.madeItYours))
        XCTAssertFalse(earned([attempt(profile: nil)]).contains(.madeItYours))
    }

    // MARK: stamps and order

    /// a badge belongs to the session that first earned it, not to a later, better one
    func testABadgeBelongsToTheSessionThatFirstEarnedItNotToALaterBetterOne() {
        let first = attempt(start, rounds: 5)
        let second = attempt(start.plusDays(2), rounds: 12)
        let got = stamps([first, second])
        XCTAssertEqual(got[.novice], first.atMillis)
        XCTAssertEqual(got[.intermediate], second.atMillis)
        XCTAssertEqual(got[.firstCindy], first.atMillis)
    }

    /// the order the sessions are given in changes nothing
    func testTheOrderTheSessionsAreGivenInChangesNothing() {
        let sessions = [attempt(start, rounds: 5),
                        attempt(start.plusDays(1), rounds: 12, profile: adaptive),
                        attempt(start.plusDays(2), rounds: 13, countedReps: 700),
                        attempt(start.plusDays(3), rounds: 28, splitsMs: [40_000]),
                        attempt(start.plusDays(9), rounds: 2)]
        XCTAssertEqual(stamps(sessions), stamps(sessions.reversed()))
        // `java.util.Random(7).shuffle`: for i from the size down to 2, swap i - 1 with nextInt(i).
        var shuffled = sessions
        var random = JavaRandom(seed: 7)
        var i = shuffled.count
        while i > 1 {
            shuffled.swapAt(i - 1, Int(random.nextInt(Int32(i))))
            i -= 1
        }
        XCTAssertEqual(stamps(sessions), stamps(shuffled))
    }

    /// badges come back in catalogue order, each once
    func testBadgesComeBackInCatalogueOrderEachOnce() {
        let sessions = [attempt(start, profile: adaptive), attempt(start.plusDays(1), rounds: 12), attempt(start.plusDays(2), rounds: 12)]
        let list = Badges.earned(sessions, zone: zone, firstDayOfWeek: monday).map { $0.badge }
        XCTAssertEqual(list.sorted { $0.ordinal < $1.ordinal }, list)
        XCTAssertEqual(list.count, Set(list).count)
    }

    // MARK: earnedBy

    /// a first session is credited with its first badges
    func testAFirstSessionIsCreditedWithItsFirstBadges() {
        let first = attempt(start, rounds: 10)
        XCTAssertEqual(Badges.earnedBy([first], first, zone: zone, firstDayOfWeek: monday),
                       [.firstCindy, .firstRound, .novice, .intermediate])
    }

    /// a session is credited with what it added and nothing it found already earned
    func testASessionIsCreditedWithWhatItAddedAndNothingItFoundAlreadyEarned() {
        let first = attempt(start, rounds: 10)
        let second = attempt(start.plusDays(1), rounds: 10)
        let all = [first, second]
        XCTAssertTrue(Badges.earnedBy(all, second, zone: zone, firstDayOfWeek: monday).isEmpty)
        XCTAssertEqual(Badges.earnedBy(all, first, zone: zone, firstDayOfWeek: monday),
                       [.firstCindy, .firstRound, .novice, .intermediate])
    }

    /// the session that completes a run is credited with the streak
    func testTheSessionThatCompletesARunIsCreditedWithTheStreak() {
        let all = everyDay(3)
        XCTAssertEqual(Badges.earnedBy(all, all.last!, zone: zone, firstDayOfWeek: monday), [.streak3])
    }

    /// the session that makes a better score is credited with the next rung only
    func testTheSessionThatMakesABetterScoreIsCreditedWithTheNextRungOnly() {
        let first = attempt(start, rounds: 10)
        let better = attempt(start.plusDays(2), rounds: 17)
        XCTAssertEqual(Badges.earnedBy([first, better], better, zone: zone, firstDayOfWeek: monday), [.advanced])
    }

    /// a session that was never stored is credited with nothing
    func testASessionThatWasNeverStoredIsCreditedWithNothing() {
        let stored = attempt(start, rounds: 5)
        let unsaved = attempt(start.plusDays(1), rounds: 30)
        XCTAssertTrue(Badges.earnedBy([stored], unsaved, zone: zone, firstDayOfWeek: monday).isEmpty)
        XCTAssertTrue(Badges.earnedBy([], unsaved, zone: zone, firstDayOfWeek: monday).isEmpty)
    }

    // MARK: progress

    /// sessions progress counts every session and stops at the target
    func testSessionsProgressCountsEverySessionAndStopsAtTheTarget() {
        XCTAssertEqual(progress(.sessions10, spacedDefault(3)), BadgeProgress(3, 10, "sessions"))
        XCTAssertEqual(progress(.sessions10, spacedDefault(12)), BadgeProgress(10, 10, "sessions"))
    }

    /// rounds progress is the best exact standard session, not a total
    func testRoundsProgressIsTheBestExactStandardSessionNotATotal() {
        let sessions = [attempt(start, rounds: 8),
                        attempt(start.plusDays(2), rounds: 6),
                        attempt(start.plusDays(4), rounds: 12, profile: adaptive),
                        attempt(start.plusDays(6), rounds: 15, untrackedMs: tolerance),
                        attempt(start.plusDays(8), rounds: 15, profile: nil)]
        XCTAssertEqual(progress(.advanced, sessions), BadgeProgress(8, 16, "rounds"))
    }

    /// days progress is the run that is still alive
    func testDaysProgressIsTheRunThatIsStillAlive() {
        let run = everyDay(3)
        let lastDay = start.plusDays(2)
        XCTAssertEqual(progress(.streak7, run, today: lastDay), BadgeProgress(3, 7, "days"))
        // Yesterday still counts: today is not over yet.
        XCTAssertEqual(progress(.streak7, run, today: lastDay.plusDays(1)), BadgeProgress(3, 7, "days"))
        // Two days of nothing ended it, whatever the run once was.
        XCTAssertEqual(progress(.streak7, run, today: lastDay.plusDays(2)), BadgeProgress(0, 7, "days"))
    }

    /// weeks progress is the run that is still alive
    func testWeeksProgressIsTheRunThatIsStillAlive() {
        let run = everyWeek(2)
        let lastWeek = start.plusWeeks(1)
        XCTAssertEqual(progress(.weeks4, run, today: lastWeek), BadgeProgress(2, 4, "weeks"))
        XCTAssertEqual(progress(.weeks4, run, today: lastWeek.plusWeeks(1)), BadgeProgress(2, 4, "weeks"))
        XCTAssertEqual(progress(.weeks4, run, today: lastWeek.plusWeeks(2)), BadgeProgress(0, 4, "weeks"))
    }

    /// weeks progress counts weeks from where the locale starts them
    func testWeeksProgressCountsWeeksFromWhereTheLocaleStartsThem() {
        // The four sessions of the week-start test above, on the Monday after the last of them.
        let sessions = [attempt(start), attempt(start.plusDays(13)), attempt(start.plusDays(14)), attempt(start.plusDays(21))]
        let today = start.plusDays(21)
        XCTAssertEqual(progress(.weeks4, sessions, today: today, weekStart: .monday), BadgeProgress(4, 4, "weeks"))
        XCTAssertEqual(progress(.weeks4, sessions, today: today, weekStart: .sunday), BadgeProgress(2, 4, "weeks"))
    }

    /// days progress counts days on the athlete's calendar
    func testDaysProgressCountsDaysOnTheAthletesCalendar() {
        // 23:50 and 00:10 in Bucharest: two days there, one on the UTC calendar.
        let sessions = [Attempt(rounds: 10, reps: 0, atMillis: millis(start, 23, 50)),
                        Attempt(rounds: 10, reps: 0, atMillis: millis(start.plusDays(1), 0, 10))]
        let today = start.plusDays(1)
        XCTAssertEqual(Badges.progress(.streak3, sessions, today: today, zone: zone, firstDayOfWeek: monday),
                       BadgeProgress(2, 3, "days"))
        XCTAssertEqual(Badges.progress(.streak3, sessions, today: today, zone: Zone("UTC"), firstDayOfWeek: monday),
                       BadgeProgress(1, 3, "days"))
    }

    /// reps progress is worded with thousands separators
    func testRepsProgressIsWordedWithThousandsSeparators() {
        let p = progress(.reps5000, [attempt(countedReps: 1_240)])
        XCTAssertEqual(p, BadgeProgress(1_240, 5_000, "reps"))
        XCTAssertEqual(p!.label, "1,240 of 5,000 reps")
        XCTAssertEqual(BadgeProgress(3, 10, "sessions").label, "3 of 10 sessions")
    }

    /// a badge that is had or not has no progress to report
    func testABadgeThatIsHadOrNotHasNoProgressToReport() {
        let yesOrNo: [Badge] = [.firstCindy, .firstRound, .pastBenchmark, .roundUnder2, .roundUnder45, .everyRepSeen, .madeItYours]
        let history = spacedDefault(3)
        for badge in yesOrNo { XCTAssertNil(progress(badge, history), "\(badge)") }
        // And everything else does have a figure to show.
        for badge in Badge.allCases where !yesOrNo.contains(badge) {
            XCTAssertNotNil(progress(badge, history), "\(badge) has no progress")
        }
    }

    // MARK: the menu's line

    private func held(_ sessions: Attempt...) -> [EarnedBadge] {
        Badges.earned(sessions, zone: zone, firstDayOfWeek: monday)
    }

    /// no badges, nothing to say
    func testNoBadgesNothingToSay() {
        XCTAssertNil(Badges.headline([]))
        XCTAssertNil(Badges.highestLevel([]))
    }

    /// one badge is a badge, not badges
    func testOneBadgeIsABadgeNotBadges() {
        // A few reps and no whole round: First Cindy and nothing else.
        XCTAssertEqual(Badges.headline(held(attempt(rounds: 0, reps: 3))), "1 badge")
    }

    /// the headline counts the badges and names the highest level among them
    func testTheHeadlineCountsTheBadgesAndNamesTheHighestLevelAmongThem() {
        // Ten rounds: First Cindy, First round, Novice and Intermediate.
        let got = held(attempt(rounds: 10))
        XCTAssertEqual(Badges.highestLevel(got), .intermediate)
        XCTAssertEqual(Badges.headline(got), "4 badges · Intermediate")
    }

    /// a later, weaker session does not lower the level
    func testALaterWeakerSessionDoesNotLowerTheLevel() {
        let got = held(attempt(start, rounds: 17), attempt(start.plusDays(2), rounds: 6))
        XCTAssertEqual(Badges.highestLevel(got), .advanced)
    }

    /// no level is named before the first rung is held
    func testNoLevelIsNamedBeforeTheFirstRungIsHeld() {
        // First Cindy and First round, but short of the five rounds of Novice.
        let got = held(attempt(rounds: 4))
        XCTAssertNil(Badges.highestLevel(got))
        XCTAssertEqual(Badges.headline(got), "2 badges")
    }

    /// a session the camera lost the athlete in names no level
    func testASessionTheCameraLostTheAthleteInNamesNoLevel() {
        let got = held(attempt(rounds: 27, untrackedMs: tolerance))
        XCTAssertNil(Badges.highestLevel(got))
        XCTAssertEqual(Badges.headline(got), "1 badge")
    }

    /// the top of the ladder is Legend
    func testTheTopOfTheLadderIsLegend() {
        XCTAssertEqual(Badges.highestLevel(held(attempt(rounds: 30))), .legend)
    }

    // MARK: wording

    /// a day is written the way every screen writes one
    func testADayIsWrittenTheWayEveryScreenWritesOne() {
        XCTAssertEqual(Badges.day(millis(start), zone: zone), "2 Mar 2026")
        XCTAssertEqual(Badges.day(millis(LocalDate(2026, 12, 12)), zone: zone), "12 Dec 2026")
    }

    /// the day is the athlete's own, so ten past midnight is already the new day
    func testTheDayIsTheAthletesOwnSoTenPastMidnightIsAlreadyTheNewDay() {
        let justAfterMidnight = millis(start, 0, 10)
        XCTAssertEqual(Badges.day(justAfterMidnight, zone: zone), "2 Mar 2026")
        XCTAssertEqual(Badges.day(justAfterMidnight, zone: Zone("UTC")), "1 Mar 2026")
    }

    /// the month is in English whatever language the phone speaks
    func testTheMonthIsInEnglishWhateverLanguageThePhoneSpeaks() {
        // Nothing here reads the phone's locale, which is what the Kotlin test sets to France to
        // prove; the months are a table of English abbreviations.
        XCTAssertEqual(Badges.day(millis(start), zone: zone), "2 Mar 2026")
        XCTAssertEqual(DateText.months, ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"])
    }

    /// the sheet says when a badge was earned, how far along it is, or that it is still to come
    func testTheSheetSaysWhenABadgeWasEarnedHowFarAlongItIsOrThatItIsStillToCome() {
        let won = EarnedBadge(.sessions10, millis(start))
        XCTAssertEqual(Badges.status(won, nil, zone: zone), "Earned 2 Mar 2026")
        // Once earned, the progress towards it is beside the point.
        XCTAssertEqual(Badges.status(won, BadgeProgress(10, 10, "sessions"), zone: zone), "Earned 2 Mar 2026")
        XCTAssertEqual(Badges.status(nil, BadgeProgress(3, 10, "sessions"), zone: zone), "3 of 10 sessions")
        XCTAssertEqual(Badges.status(nil, nil, zone: zone), "Not earned yet")
    }

    /// a tile is described in one sentence
    func testATileIsDescribedInOneSentence() {
        let won = EarnedBadge(.sessions10, millis(start))
        XCTAssertEqual(Badges.description(.sessions10, won, nil, zone: zone), "10 sessions, earned 2 Mar 2026")
        XCTAssertEqual(Badges.description(.sessions10, nil, BadgeProgress(3, 10, "sessions"), zone: zone),
                       "10 sessions, locked, 3 of 10 sessions")
        XCTAssertEqual(Badges.description(.firstCindy, nil, nil, zone: zone), "First Cindy, locked")
    }

    /// the profile line says since when, and how many sessions
    func testTheProfileLineSaysSinceWhenAndHowManySessions() {
        XCTAssertEqual(Badges.trainingLine([], zone: zone), "Finish a session and your badges start here.")
        XCTAssertEqual(Badges.trainingLine([attempt(start)], zone: zone), "Training since 2 Mar 2026 · 1 session")
        // Given out of order, the first is still the earliest.
        let three = [attempt(start.plusDays(9)), attempt(start), attempt(start.plusDays(4))]
        XCTAssertEqual(Badges.trainingLine(three, zone: zone), "Training since 2 Mar 2026 · 3 sessions")
    }
}
