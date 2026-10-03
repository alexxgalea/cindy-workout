import XCTest
import CindyCore
import CindyFixtures

/// The two knobs `RepCounter` grew for the heels-flat squat, and the promise that turning neither
/// changes anything else.
///
/// Pull-ups, push-ups and air squats are counted by the same class, and their parity trace is what
/// keeps the desktop harness honest. So the first test is the one that matters most: a counter
/// given the defaults explicitly must be indistinguishable from one built the way every caller
/// built it before.
///
/// Mirrors `RepCounterMarginsTest.kt`.
final class RepCounterMarginsTests: XCTestCase {

    /// Feeds one value repeatedly so the smoother settles, returning how many reps were booked.
    @discardableResult
    private func hold(_ c: RepCounter, _ value: Float, _ startMs: Int64, frames: Int = 10) -> Int {
        var reps = 0
        for i in 0..<frames where c.update(value, now: startMs + Int64(i) * 100) { reps += 1 }
        return reps
    }

    /// The sort of band a heels-flat squat is counted against.
    private func heelsFlat(bottomMargin: Float = 0.6, minTravel: Float = 35) -> RepCounter {
        RepCounter(downBelow: 120, upAbove: 158, minRepMs: 350, minRange: 35,
                   bottomMargin: bottomMargin, minTravel: minTravel)
    }

    /// A wide band, taught by one deep rep, for the tests below to work against.
    private func afterOneDeepRep(_ c: RepCounter) -> Int64 {
        var t: Int64 = 0
        hold(c, 175, t); t += 1000
        hold(c, 60, t); t += 1000
        hold(c, 175, t); t += 1000
        XCTAssertEqual(c.count, 1, "the deep rep should have counted")
        return t
    }

    /// The defaults, given explicitly, count exactly what the old constructor counted.
    func testTheDefaultsGivenExplicitlyCountExactlyWhatTheOldConstructorCounted() {
        let old = RepCounter(downBelow: 100, upAbove: 158, minRepMs: 350, minRange: 55)
        let explicit = RepCounter(downBelow: 100, upAbove: 158, minRepMs: 350, minRange: 55,
                                  bottomMargin: 0.30, minTravel: 0)

        // A long, untidy run: swings of every size, noise on top, and stretches of standing still.
        var noise = JavaRandom(seed: 7)
        var now: Int64 = 0
        var booked = 0
        for set in 0..<40 {
            let low = 60 + Float(noise.nextInt(60))
            let high = 140 + Float(noise.nextInt(40))
            for step in 0..<30 {
                let t = Float(step) / 29
                let wave = t < 0.5 ? t * 2 : (1 - t) * 2
                let raw = high - (high - low) * wave + (noise.nextFloat() - 0.5) * 6
                let a = old.update(raw, now: now)
                let b = explicit.update(raw, now: now)
                XCTAssertEqual(a, b, "set \(set) step \(step): a rep booked differently")
                XCTAssertEqual(old.count, explicit.count)
                XCTAssertEqual(old.phase, explicit.phase)
                XCTAssertEqual(old.learnedRange, explicit.learnedRange, accuracy: 0)
                XCTAssertEqual(old.smoothed, explicit.smoothed, accuracy: 0)
                if a { booked += 1 }
                now += 70
            }
        }
        XCTAssertGreaterThan(booked, 10, "the run booked nothing, so it proved nothing")
    }

    /// A minimum travel refuses a wobble that a wide band would otherwise accept.
    func testAMinimumTravelRefusesAWobbleThatAWideBandWouldOtherwiseAccept() {
        // After a deep rep the band is about 115 degrees wide, so a bottom zone of 60% arms below
        // about 129 and the top zone starts near 140: a shake between the two is 12 degrees.
        let without = heelsFlat(minTravel: 0)
        let with = heelsFlat(minTravel: 35)
        var t = afterOneDeepRep(without)
        _ = afterOneDeepRep(with)

        for _ in 0..<4 {
            hold(without, 126, t); hold(with, 126, t); t += 1000
            hold(without, 146, t); hold(with, 146, t); t += 1000
        }

        XCTAssertGreaterThan(without.count, 1, "without a floor the wobble counts")
        XCTAssertEqual(with.count, 1, "with one it does not")
    }

    /// A wider bottom zone arms a rep that stops higher than the band's deepest.
    func testAWiderBottomZoneArmsARepThatStopsHigherThanTheBandsDeepest() {
        let narrow = heelsFlat(bottomMargin: 0.30)
        let wide = heelsFlat(bottomMargin: 0.60)
        var t = afterOneDeepRep(narrow)
        _ = afterOneDeepRep(wide)

        // 120 is well above the bottom 30% of a band that reaches down to 60, and inside 60%.
        for _ in 0..<3 {
            hold(narrow, 120, t); hold(wide, 120, t); t += 1000
            hold(narrow, 175, t); hold(wide, 175, t); t += 1000
        }

        XCTAssertEqual(narrow.count, 1, "a rep that never reached the narrow bottom does not arm")
        XCTAssertEqual(wide.count, 4, "the wider zone counts all three")
    }

    /// A heels-flat counter still refuses a climb short of its minimum after a shallow start.
    func testAHeelsFlatCounterStillRefusesAClimbShortOfItsMinimumAfterAShallowStart() {
        // No deep rep to widen the band: shallow reps teach a narrow one, and 25 degrees of
        // travel is under the floor however the zones fall.
        let c = heelsFlat()
        var t: Int64 = 0
        for _ in 0..<6 {
            hold(c, 150, t); t += 1000
            hold(c, 175, t); t += 1000
        }
        XCTAssertEqual(c.count, 0)
    }
}
