import XCTest
import CindyCore

/// Where Swift's text handling could part from Kotlin's while reading the shared line format.
/// Not in the Kotlin tests: they cannot differ there.
final class RecordsFormatTests: XCTestCase {

    private let line = "v7|12|7|100|1000|0||STRICT_PULL_UP|STANDARD_PUSH_UP|AIR_SQUAT|0|367|0|"

    /// Swift reads `\r\n` as one character, Kotlin's `lineSequence()` as a line break
    func testWindowsLineEndingsSplitLines() {
        XCTAssertEqual(Records.decode("12,7,1000\r\n14,0,2000").count, 2)
        XCTAssertEqual(Records.decode("12,7,1000\r14,0,2000").count, 2)
        XCTAssertEqual(Records.decode("12,7,1000\n\n14,0,2000\n").count, 2, "blank lines are skipped")
    }

    /// a v7 line with no sets ends in an empty field, which is still a field
    func testATrailingEmptyFieldIsStillAField() {
        let back = Records.decode(line)
        XCTAssertEqual(back.count, 1)
        XCTAssertEqual(back[0].setSplits, [])
    }

    /// Kotlin's `Int` is 32 bits, so a round count that does not fit is a corrupt line
    func testACountTooBigForAnIntIsCorrupt() {
        XCTAssertEqual(Records.decode("2147483648,7,1000"), [])
        XCTAssertEqual(Records.decode("2147483647,7,1000").count, 1)
    }

    /// `countedReps` left empty reads back as unknown, not as zero
    func testAnEmptyCountedRepsReadsBackAsUnknown() {
        let a = Attempt(rounds: 3, reps: 4, atMillis: 9)
        let back = Records.decode(Records.encode([a]))[0]
        XCTAssertNil(back.countedReps)
        XCTAssertEqual(back.totalReps, 94)
    }

    /// whitespace alone is not a record board
    func testBlankTextIsNoRecords() {
        XCTAssertEqual(Records.decode("  \n\t "), [])
    }
}
