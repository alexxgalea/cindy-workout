import XCTest
@testable import CindyCore

/// The pure half of "FIND MY WATCH": which advertisements count, and the order the sheet lists.
/// Port of `HeartRateAdvertTest.kt` (9) and `BleHeartRateSourceTest.kt` (1).
final class HeartRateAdvertTests: XCTestCase {

    private let battery = UUID(uuidString: "0000180f-0000-1000-8000-00805f9b34fb")!

    /// an advert listing the heart rate service matches
    func testAnAdvertListingTheHeartRateServiceMatches() {
        XCTAssertTrue(HeartRateAdvert.matches(serviceUuids: [battery, HeartRateGatt.service], manufacturerIds: []))
    }

    /// a garmin advert matches without the service listed
    func testAGarminAdvertMatchesWithoutTheServiceListed() {
        XCTAssertTrue(HeartRateAdvert.matches(serviceUuids: nil, manufacturerIds: [HeartRateAdvert.garminCompanyId]))
        XCTAssertEqual(HeartRateAdvert.garminCompanyId, 0x0087)
    }

    /// anything else does not
    func testAnythingElseDoesNot() {
        XCTAssertFalse(HeartRateAdvert.matches(serviceUuids: [battery], manufacturerIds: [0x004C]))
        XCTAssertFalse(HeartRateAdvert.matches(serviceUuids: nil, manufacturerIds: []))
    }

    /// connected devices come first, then the rest in the order first heard
    func testConnectedDevicesComeFirstThenTheRestInTheOrderFirstHeard() {
        let watch = FoundDevice("AA", "fenix 7X", rssi: nil, connected: true)
        let strap = FoundDevice("BB", "HRM-Pro", rssi: -80)
        let near = FoundDevice("CC", "Polar H10", rssi: -50)
        XCTAssertEqual(HeartRateAdvert.merge(connected: [watch], advertising: [strap, near]), [watch, strap, near])
    }

    /// a stronger packet does not move a device up the list
    func testAStrongerPacketDoesNotMoveADeviceUpTheList() {
        let first = FoundDevice("BB", "HRM-Pro", rssi: -80)
        let second = FoundDevice("CC", "Polar H10", rssi: -70)
        let before = HeartRateAdvert.merge(connected: [], advertising: [first, second])
        let after = HeartRateAdvert.merge(connected: [], advertising: [first.with(rssi: -85), second.with(rssi: -40)])
        XCTAssertEqual(before.map { $0.address }, after.map { $0.address })
    }

    /// a name once heard is kept when a later packet has none
    func testANameOnceHeardIsKeptWhenALaterPacketHasNone() {
        let named = HeartRateAdvert.heard(previous: nil, address: "AA", name: "fenix 7X", rssi: -60)
        let next = HeartRateAdvert.heard(previous: named, address: "AA", name: nil, rssi: -62)
        XCTAssertEqual(next, FoundDevice("AA", "fenix 7X", rssi: -62))
    }

    /// an unnamed device is called a heart-rate sensor until it names itself
    func testAnUnnamedDeviceIsCalledAHeartRateSensorUntilItNamesItself() {
        let unnamed = HeartRateAdvert.heard(previous: nil, address: "AA", name: nil, rssi: -60)
        XCTAssertEqual(unnamed.name, HeartRateAdvert.unnamed)
        XCTAssertEqual(HeartRateAdvert.heard(previous: unnamed, address: "AA", name: "fenix 7X", rssi: -60).name, "fenix 7X")
    }

    /// a signal change keeps the rows, anything else rebuilds them
    func testASignalChangeKeepsTheRowsAnythingElseRebuildsThem() {
        let watch = FoundDevice("AA", "fenix 7X", rssi: -60)
        let strap = FoundDevice("BB", "HRM-Pro", rssi: -80)
        let shown = [watch, strap]
        XCTAssertTrue(HeartRateAdvert.sameRows(shown: shown, next: [watch.with(rssi: -90), strap.with(rssi: -40)]))
        XCTAssertTrue(HeartRateAdvert.sameRows(shown: [], next: []))
        XCTAssertFalse(HeartRateAdvert.sameRows(shown: shown, next: [watch]))
        XCTAssertFalse(HeartRateAdvert.sameRows(shown: shown, next: [strap, watch]))
        XCTAssertFalse(HeartRateAdvert.sameRows(shown: shown, next: [watch.with(name: "fenix"), strap]))
        XCTAssertFalse(HeartRateAdvert.sameRows(shown: shown, next: [watch.with(connected: true), strap]))
    }

    /// a connected device also heard advertising is listed once with its signal
    func testAConnectedDeviceAlsoHeardAdvertisingIsListedOnceWithItsSignal() {
        let watch = FoundDevice("AA", "fenix 7X", rssi: nil, connected: true)
        let heard = FoundDevice("AA", "fenix 7X", rssi: -55)
        XCTAssertEqual(HeartRateAdvert.merge(connected: [watch], advertising: [heard]), [watch.with(rssi: -55)])
    }

    /// backs off then caps at ten seconds
    func testBacksOffThenCapsAtTenSeconds() {
        XCTAssertEqual(HeartRateReconnect.delayMs(1), 1_000)
        XCTAssertEqual(HeartRateReconnect.delayMs(2), 2_000)
        XCTAssertEqual(HeartRateReconnect.delayMs(3), 4_000)
        XCTAssertEqual(HeartRateReconnect.delayMs(4), 8_000)
        XCTAssertEqual(HeartRateReconnect.delayMs(5), 10_000)
        XCTAssertEqual(HeartRateReconnect.delayMs(9), 10_000)
    }

    // MARK: not in the Kotlin

    /// the first retry is a second, and so is anything before it
    func testTheFirstRetryIsASecondAndSoIsAnythingBeforeIt() {
        XCTAssertEqual(HeartRateReconnect.delayMs(0), 1_000)
        XCTAssertEqual(HeartRateReconnect.delayMs(-3), 1_000)
    }

    /// the windows are the Kotlin's
    func testTheWindowsAreTheKotlins() {
        XCTAssertEqual(HeartRateReconnect.scanWindowMs, 12_000)
        XCTAssertEqual(HeartRateReconnect.lookWindowMs, 10_000)
        XCTAssertEqual(HeartRateReconnect.failuresBeforeLooking, 2)
    }

    /// a device listed twice among the advertisers is listed once
    func testADeviceHeardTwiceKeepsItsFirstPlace() {
        let a = FoundDevice("AA", "a", rssi: -70)
        let b = FoundDevice("BB", "b", rssi: -70)
        // The scanner keys what it has heard by address, so a repeat replaces in place; merge keeps
        // whatever order it is handed.
        XCTAssertEqual(HeartRateAdvert.merge(connected: [], advertising: [a, b]).map { $0.address }, ["AA", "BB"])
    }
}
