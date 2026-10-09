import XCTest
import CindyCore

/// Mirrors `ZoneBarViewTest.kt`: the zone bar on a 1000 wide view. Geometry is read back through
/// `centreOf`, so what is pinned down is the behaviour: a tap holds the zone under it, a second tap
/// lets it go, a sideways drag walks across the zones, and a zone with no time is neither drawn nor
/// a stop. The Android test that only lays the view out and draws it is held by the geometry tests.
final class ZoneBarModelTests: XCTestCase {

    private let width = 1000.0

    /// Z2 has no time. The rest are 1, 2, 3 and 4 minutes.
    private let zones = [
        ZoneTime(zone: .warmUp, ms: 60_000, fromBpm: nil, toBpm: 112),
        ZoneTime(zone: .easy, ms: 0, fromBpm: 113, toBpm: 130),
        ZoneTime(zone: .aerobic, ms: 120_000, fromBpm: 131, toBpm: 149),
        ZoneTime(zone: .threshold, ms: 180_000, fromBpm: 150, toBpm: 168),
        ZoneTime(zone: .maximum, ms: 240_000, fromBpm: 169, toBpm: nil)
    ]
    private var said: [String] { zones.map { "\($0.zone.label) says" } }

    private func loaded() -> ZoneBarModel {
        let model = ZoneBarModel()
        model.setZones(zones, descriptions: said)
        return model
    }

    private func tap(_ model: ZoneBarModel, _ x: Double) {
        model.touchDown(x: x, y: 20)
        model.touchUp(x: x, y: 20, in: width)
    }

    /// it lays out at a finger's height and draws
    func testItLaysOutAtAFingersHeightAndDraws() {
        XCTAssertTrue(ZoneBarModel.touchHeight >= 48)
        let model = loaded()
        let spans = model.spans(in: width)
        XCTAssertEqual(spans.count, 5)
        // The five fill the bar from its left edge to its right, in order, with no gap.
        XCTAssertEqual(spans[0].left, 0)
        XCTAssertEqual(spans[4].right, width, accuracy: 1e-9)
        for i in 1..<5 { XCTAssertEqual(spans[i].left, spans[i - 1].right, accuracy: 1e-9) }
        XCTAssertEqual(spans[1].right - spans[1].left, 0)
        XCTAssertEqual(ZoneBarModel.alpha.count, 5)
    }

    /// a tap holds the zone under it and reports it
    func testATapHoldsTheZoneUnderItAndReportsIt() {
        let model = loaded()
        var received: [Int?] = []
        model.onSelect = { received.append($0) }

        tap(model, model.centreOf(3, in: width))

        XCTAssertEqual(model.selected, 3)
        XCTAssertEqual(received, [3])
    }

    /// tapping the held zone again lets it go
    func testTappingTheHeldZoneAgainLetsItGo() {
        let model = loaded()

        tap(model, model.centreOf(3, in: width))
        tap(model, model.centreOf(3, in: width))

        XCTAssertNil(model.selected)
    }

    /// a tap on empty bar beside a zone with no time picks the nearest zone that has some
    func testATapOnEmptyBarBesideAZoneWithNoTimePicksTheNearestZoneThatHasSome() {
        let model = loaded()

        tap(model, model.centreOf(1, in: width))

        // Z2 has no width, so its centre is the edge Z1 and Z3 share; either neighbour is right,
        // but never Z2 itself.
        XCTAssertTrue(model.selected == 0 || model.selected == 2, "picked \(String(describing: model.selected))")
    }

    /// a sideways drag walks across the zones in order
    func testASidewaysDragWalksAcrossTheZonesInOrder() {
        let model = loaded()
        var received: [Int?] = []
        model.onSelect = { received.append($0) }
        let from = model.centreOf(0, in: width)
        let to = model.centreOf(4, in: width)

        model.touchDown(x: from, y: 20)
        var x = from
        while x < to {
            x = min(x + 20, to)
            model.touchMove(x: x, y: 20, in: width)
        }
        model.touchUp(x: to, y: 20, in: width)

        XCTAssertEqual(received.compactMap { $0 }, [0, 2, 3, 4])
        XCTAssertEqual(model.selected, 4)
    }

    /// talkback gets a stop for each zone that has time, and says what it was given
    func testTalkbackGetsAStopForEachZoneThatHasTimeAndSaysWhatItWasGiven() {
        let model = loaded()

        XCTAssertEqual(model.stopCount, 4)
        XCTAssertEqual(model.stops.count, 4)
        XCTAssertEqual(model.stops[0], "Warm-up says")
        // The empty zone is skipped, so the second stop is the third zone.
        XCTAssertEqual(model.stops[1], "Aerobic says")
        model.activate(stop: 1)
        XCTAssertEqual(model.selected, 2)
    }

    /// a bar with no time draws nothing and takes no touch
    func testABarWithNoTimeDrawsNothingAndTakesNoTouch() {
        let model = ZoneBarModel()
        model.setZones(zones.map { ZoneTime(zone: $0.zone, ms: 0, fromBpm: $0.fromBpm, toBpm: $0.toBpm) }, descriptions: said)
        var received: [Int?] = []
        model.onSelect = { received.append($0) }

        tap(model, 500)

        XCTAssertEqual(model.stopCount, 0)
        XCTAssertTrue(received.isEmpty)
        XCTAssertNil(model.selected)
        XCTAssertFalse(model.hasTime)
    }

    /// new data keeps a held zone that still has time and drops one that lost it
    func testNewDataKeepsAHeldZoneThatStillHasTimeAndDropsOneThatLostIt() {
        let model = loaded()
        model.select(3)

        model.setZones(zones, descriptions: said)
        XCTAssertEqual(model.selected, 3)

        model.setZones(zones.map { $0.zone == .threshold ? ZoneTime(zone: $0.zone, ms: 0, fromBpm: $0.fromBpm, toBpm: $0.toBpm) : $0 },
                       descriptions: said)
        XCTAssertNil(model.selected)
    }

    /// a zone with no time cannot be selected
    func testAZoneWithNoTimeCannotBeSelected() {
        let model = loaded()

        model.select(1)

        XCTAssertNil(model.selected)
    }
}
