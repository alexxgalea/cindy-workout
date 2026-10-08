import XCTest
import CindyCore

/// Mirrors `HeartRateMeasurementTest.kt`.
final class HeartRateMeasurementTests: XCTestCase {

    private func parse(_ bytes: UInt8...) -> HeartRateReading? { HeartRateMeasurement.parse(bytes) }

    /// a plain uint8 reading with the contact bit clear reports unsupported
    func testAPlainUint8ReadingWithTheContactBitClearReportsUnsupported() {
        let r = parse(0x00, 0x48)!
        XCTAssertEqual(r.bpm, 72)
        XCTAssertEqual(r.contact, .unsupported)
    }

    /// bit 0 set means a uint16 little-endian reading
    func testBit0SetMeansAUint16LittleEndianReading() {
        let r = parse(0x01, 0x9A, 0x00)!
        XCTAssertEqual(r.bpm, 154)
    }

    /// contact bit set and detected
    func testContactBitSetAndDetected() {
        XCTAssertEqual(parse(0x06, 0x50)!.contact, .detected)
    }

    /// contact bit set and not detected
    func testContactBitSetAndNotDetected() {
        XCTAssertEqual(parse(0x04, 0x50)!.contact, .notDetected)
    }

    /// energy expended and RR bits are ignored, and nothing past the HR byte is read
    func testEnergyExpendedAndRRBitsAreIgnoredAndNothingPastTheHRByteIsRead() {
        XCTAssertEqual(parse(0x18, 0x50, 0x10, 0x00, 0x00, 0x04)!.bpm, 80)
    }

    /// too short to hold a reading yields null
    func testTooShortToHoldAReadingYieldsNull() {
        XCTAssertNil(HeartRateMeasurement.parse([]))
        XCTAssertNil(parse(0x00))
        XCTAssertNil(parse(0x01, 0x9A))
    }

    /// plausible rejects sensor junk, never effort
    func testPlausibleRejectsSensorJunkNeverEffort() {
        XCTAssertFalse(HeartRateMeasurement.plausible(HeartRateReading(0, .unsupported)))
        XCTAssertFalse(HeartRateMeasurement.plausible(HeartRateReading(29, .unsupported)))
        XCTAssertFalse(HeartRateMeasurement.plausible(HeartRateReading(231, .unsupported)))
        XCTAssertFalse(HeartRateMeasurement.plausible(HeartRateReading(120, .notDetected)))

        XCTAssertTrue(HeartRateMeasurement.plausible(HeartRateReading(30, .unsupported)))
        XCTAssertTrue(HeartRateMeasurement.plausible(HeartRateReading(230, .unsupported)))
        XCTAssertTrue(HeartRateMeasurement.plausible(HeartRateReading(120, .unsupported)))
    }

    // MARK: written for the port

    /// the high byte of a uint16 reading counts for 256 each
    func testTheHighByteOfAUint16ReadingCountsFor256Each() {
        XCTAssertEqual(parse(0x01, 0x2C, 0x01)!.bpm, 300)
        XCTAssertEqual(parse(0x01, 0x00, 0x02)!.bpm, 512)
        XCTAssertEqual(parse(0x01, 0xFF, 0xFF)!.bpm, 65_535)
    }
}
