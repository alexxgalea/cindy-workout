import XCTest
import CindyCore

/// Mirrors `HeartRateStatsTest.kt`.
final class HeartRateStatsTests: XCTestCase {

    private let twentyMinutes: Int64 = 20 * 60 * 1000

    private func trace(_ samples: (Int64, Int)...) -> HeartRateTrace { trace(samples) }

    private func trace(_ samples: [(Int64, Int)]) -> HeartRateTrace {
        HeartRateTrace(startedAtMillis: 0, samples: samples.map { HeartRateSample($0.0, $0.1) }, pauses: [])
    }

    /// A reading a second for `seconds` seconds from `fromSecond`, all at `bpm`.
    private func steady(_ fromSecond: Int, _ seconds: Int, _ bpm: Int) -> [(Int64, Int)] {
        (fromSecond..<fromSecond + seconds).map { (Int64($0) * 1000, bpm) }
    }

    private func roundsOf(_ ends: Int64...) -> [RoundSpan] {
        var start: Int64 = 0
        return ends.enumerated().map { i, end in
            defer { start = end }
            return RoundSpan(number: i + 1, startMs: start, endMs: end, complete: true)
        }
    }

    private func summary(_ t: HeartRateTrace?, duration: Int64? = nil, rounds: [RoundSpan] = [],
                         age: Int? = 30) -> HeartRateSummary? {
        HeartRateStats.of(t, durationMs: duration ?? twentyMinutes, rounds: rounds, age: age)
    }

    private func round(_ x: Double) -> Int { Int(JavaText.roundToLong(x)) }

    // MARK: coverage, average, maximum

    /// no trace, or nothing usable in it, says nothing
    func testNoTraceOrNothingUsableInItSaysNothing() {
        XCTAssertNil(summary(nil))
        XCTAssertNil(summary(trace()))
        XCTAssertNil(summary(trace((0, 10), (1_000, 300))))
        XCTAssertNil(summary(trace((0, 150)), duration: 0))
    }

    /// a reading holds until the next one, so the average is weighted by time
    func testAReadingHoldsUntilTheNextOneSoTheAverageIsWeightedByTime() {
        // 100 bpm for 4 s, then 160 bpm for the 5 s hold: (100 x 4 + 160 x 5) / 9.
        let s = summary(trace((0, 100), (4_000, 160)), duration: 60_000)!
        XCTAssertEqual(s.coveredMs, 9_000)
        XCTAssertEqual(s.avgBpm, round((400.0 + 800.0) / 9.0))
        XCTAssertEqual(s.maxBpm, 160)
    }

    /// an average of readings alone would be wrong where the spacing is uneven
    func testAnAverageOfReadingsAloneWouldBeWrongWhereTheSpacingIsUneven() {
        // Ten quick 180s then one lone 100: by count the mean is 172, by time it is far lower.
        let samples: [(Int64, Int)] = (0..<10).map { (Int64($0) * 100, 180) } + [(1_000, 100)]
        let s = summary(trace(samples), duration: 60_000)!
        // 1 s at 180, then 5 s at 100.
        XCTAssertEqual(s.avgBpm, round((180.0 * 1 + 100.0 * 5) / 6.0))
    }

    /// a gap wider than the hold is not covered and not averaged in
    func testAGapWiderThanTheHoldIsNotCoveredAndNotAveragedIn() {
        let s = summary(trace((0, 150), (60_000, 150)), duration: 120_000)!
        XCTAssertEqual(s.coveredMs, 10_000)
        XCTAssertEqual(s.avgBpm, 150)
    }

    /// a reading never covers past the end of the clock
    func testAReadingNeverCoversPastTheEndOfTheClock() {
        let s = summary(trace((58_000, 150)), duration: 60_000)!
        XCTAssertEqual(s.coveredMs, 2_000)
    }

    /// readings outside the clock or outside a plausible range are ignored
    func testReadingsOutsideTheClockOrOutsideAPlausibleRangeAreIgnored() {
        let s = summary(trace((0, 150), (2_000, 29), (3_000, 231), (70_000, 190)), duration: 60_000)!
        XCTAssertEqual(s.maxBpm, 150)
        XCTAssertEqual(s.coveredMs, 5_000)
    }

    /// duplicate and out-of-order readings are sorted and do not double count
    func testDuplicateAndOutOfOrderReadingsAreSortedAndDoNotDoubleCount() {
        let s = summary(trace((3_000, 140), (1_000, 120), (1_000, 130)), duration: 60_000)!
        // 1..3 s is held by the later duplicate (2 s), and the 140 at 3 s holds for the full 5 s.
        XCTAssertEqual(s.coveredMs, 2_000 + 5_000)
        XCTAssertEqual(s.maxBpm, 140)
    }

    // MARK: Tanaka and the zone boundaries

    /// the estimated maximum is Tanaka, 208 minus 0·7 times age, rounded
    func testTheEstimatedMaximumIsTanaka208Minus07TimesAgeRounded() {
        XCTAssertEqual(HeartRateStats.estimatedMax(30), 187)
        XCTAssertEqual(HeartRateStats.estimatedMax(38), 181) // 181.4
        XCTAssertEqual(HeartRateStats.estimatedMax(43), 178) // 177.9
        XCTAssertEqual(HeartRateStats.estimatedMax(100), 138)
    }

    /// zone edges sit exactly on 60, 70, 80 and 90 percent of the maximum
    func testZoneEdgesSitExactlyOn60708090PercentOfTheMaximum() {
        // Age 30: max 187, so the edges are 112.2, 130.9, 149.6 and 168.3.
        let max = 187
        XCTAssertEqual(HeartRateStats.zoneOf(112, max), .warmUp)
        XCTAssertEqual(HeartRateStats.zoneOf(113, max), .easy)
        XCTAssertEqual(HeartRateStats.zoneOf(130, max), .easy)
        XCTAssertEqual(HeartRateStats.zoneOf(131, max), .aerobic)
        XCTAssertEqual(HeartRateStats.zoneOf(149, max), .aerobic)
        XCTAssertEqual(HeartRateStats.zoneOf(150, max), .threshold)
        XCTAssertEqual(HeartRateStats.zoneOf(168, max), .threshold)
        XCTAssertEqual(HeartRateStats.zoneOf(169, max), .maximum)
    }

    /// a share that lands exactly on an edge belongs to the zone above it
    func testAShareThatLandsExactlyOnAnEdgeBelongsToTheZoneAboveIt() {
        // Max 150: 60% is 90, 70% is 105, 80% is 120, 90% is 135, all whole numbers.
        XCTAssertEqual(HeartRateStats.zoneOf(89, 150), .warmUp)
        XCTAssertEqual(HeartRateStats.zoneOf(90, 150), .easy)
        XCTAssertEqual(HeartRateStats.zoneOf(105, 150), .aerobic)
        XCTAssertEqual(HeartRateStats.zoneOf(120, 150), .threshold)
        XCTAssertEqual(HeartRateStats.zoneOf(135, 150), .maximum)
    }

    /// a reading above the estimated maximum is still the top zone
    func testAReadingAboveTheEstimatedMaximumIsStillTheTopZone() {
        XCTAssertEqual(HeartRateStats.zoneOf(200, 187), .maximum)
    }

    /// each zone says the beats per minute it spans, with no gap or overlap
    func testEachZoneSaysTheBeatsPerMinuteItSpansWithNoGapOrOverlap() {
        let s = summary(trace((0, 150)), age: 30)!
        let zones = s.zones!
        XCTAssertEqual(s.estimatedMaxBpm, 187)
        let expected: [(Int?, Int?)] = [(nil, 112), (113, 130), (131, 149), (150, 168), (169, nil)]
        XCTAssertEqual(zones.map { $0.fromBpm }, expected.map { $0.0 })
        XCTAssertEqual(zones.map { $0.toBpm }, expected.map { $0.1 })
        // Every whole bpm falls in exactly the zone whose printed range holds it.
        for bpm in 30...230 {
            let range = zones[HeartRateStats.zoneOf(bpm, 187).rawValue]
            XCTAssertTrue(range.fromBpm == nil || bpm >= range.fromBpm!, "\(bpm)")
            XCTAssertTrue(range.toBpm == nil || bpm <= range.toBpm!, "\(bpm)")
        }
    }

    /// time is put in the zone each reading was in
    func testTimeIsPutInTheZoneEachReadingWasIn() {
        // Age 30: 100 bpm is warm-up, 160 is threshold, 175 maximum.
        let s = summary(trace((0, 100), (10_000, 160), (20_000, 175), (25_000, 175)), duration: 60_000)!
        var ms: [HeartZone: Int64] = [:]
        for z in s.zones! { ms[z.zone] = z.ms }
        XCTAssertEqual(ms[.warmUp], 5_000)
        XCTAssertEqual(ms[.threshold], 5_000)
        XCTAssertEqual(ms[.maximum], 10_000)
        XCTAssertEqual(ms[.easy], 0)
        XCTAssertEqual(s.zones!.reduce(0) { $0 + $1.ms }, s.coveredMs)
    }

    // MARK: the verdict

    /// the verdict names the zone that held the most time
    func testTheVerdictNamesTheZoneThatHeldTheMostTime() {
        let t = trace(steady(0, 100, 100) + steady(100, 400, 160))
        let s = summary(t, duration: 600_000)!
        XCTAssertEqual(s.verdict, "Longest in Z4 Threshold: 6:44 of the 8:24 your watch covered.")
    }

    /// a tie goes to the harder zone
    func testATieGoesToTheHarderZone() {
        let t = trace(steady(0, 60, 100) + steady(60, 60, 160))
        let s = summary(t, duration: 600_000)!
        XCTAssertTrue(s.verdict!.hasPrefix("Longest in Z4 Threshold"))
    }

    // MARK: no age

    /// without an age there are no zones, no maximum and no verdict, but the rest stands
    func testWithoutAnAgeThereAreNoZonesNoMaximumAndNoVerdictButTheRestStands() {
        let s = summary(trace((0, 150), (5_000, 170)), age: nil)!
        XCTAssertNil(s.zones)
        XCTAssertNil(s.estimatedMaxBpm)
        XCTAssertNil(s.verdict)
        XCTAssertEqual(s.maxBpm, 170)
        XCTAssertEqual(s.coveredMs, 10_000)
    }

    // MARK: the hardest round

    /// the hardest round is the highest time-weighted average
    func testTheHardestRoundIsTheHighestTimeWeightedAverage() {
        let t = trace(steady(0, 60, 140) + steady(60, 60, 170) + steady(120, 60, 155))
        let s = summary(t, duration: 180_000, rounds: roundsOf(60_000, 120_000, 180_000))!
        XCTAssertEqual(s.hardestRound, HardestRound(number: 2, avgBpm: 170, coveredMs: 60_000))
    }

    /// a round the watch saw for under thirty seconds cannot be the hardest
    func testARoundTheWatchSawForUnderThirtySecondsCannotBeTheHardest() {
        // Round 2 averages the most but only 10 s of it was heard.
        let t = trace(steady(0, 60, 140) + steady(60, 10, 200))
        let s = summary(t, duration: 120_000, rounds: roundsOf(60_000, 120_000))!
        XCTAssertEqual(s.hardestRound!.number, 1)
    }

    /// exactly thirty seconds is enough
    func testExactlyThirtySecondsIsEnough() {
        let t = trace(steady(0, 60, 140) + steady(60, 26, 200))
        let s = summary(t, duration: 120_000, rounds: roundsOf(60_000, 120_000))!
        // 26 readings a second apart, the last held for the full five seconds: 25 + 5.
        XCTAssertEqual(s.hardestRound, HardestRound(number: 2, avgBpm: 200, coveredMs: 30_000))
    }

    /// a reading that straddles a round end is shared between the two
    func testAReadingThatStraddlesARoundEndIsSharedBetweenTheTwo() {
        let t = trace((0, 100), (58_000, 180), (120_000, 100))
        // 180 bpm holds 58..63 s: 2 s in round 1, 3 s in round 2. Neither has 30 s.
        let s = summary(t, duration: 180_000, rounds: roundsOf(60_000, 120_000, 180_000))!
        XCTAssertNil(s.hardestRound)
    }

    /// equal rounds go to the earlier one
    func testEqualRoundsGoToTheEarlierOne() {
        let t = trace(steady(0, 60, 150) + steady(60, 60, 150))
        let s = summary(t, duration: 120_000, rounds: roundsOf(60_000, 120_000))!
        XCTAssertEqual(s.hardestRound!.number, 1)
    }

    /// no rounds means no hardest round
    func testNoRoundsMeansNoHardestRound() {
        XCTAssertNil(summary(trace(steady(0, 60, 150)), duration: 60_000)!.hardestRound)
        XCTAssertNotNil(summary(trace(steady(0, 60, 150)), duration: 60_000))
    }
}
