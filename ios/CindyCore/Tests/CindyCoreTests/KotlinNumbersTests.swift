import XCTest
@testable import CindyCore

/// `Records.toInt` and `Records.toLong` have to read a number the way Kotlin's `toIntOrNull` and
/// `toLongOrNull` do, because every saved file the app reads goes through them. The expected values
/// are what the JVM gives for each of these strings (Kotlin 2.0).
final class KotlinNumbersTests: XCTestCase {

    private func both(_ text: String, int: Int?, long: Int64?, line: UInt = #line) {
        XCTAssertEqual(Records.toInt(text), int, "toInt(\(text.unicodeScalars.map { String($0.value, radix: 16) }))", line: line)
        XCTAssertEqual(Records.toLong(text), long, "toLong(\(text.unicodeScalars.map { String($0.value, radix: 16) }))", line: line)
    }

    func testPlainNumbersAndSigns() {
        both("123", int: 123, long: 123)
        both("+5", int: 5, long: 5)
        both("-5", int: -5, long: -5)
        both("007", int: 7, long: 7)
        both("-0", int: 0, long: 0)
    }

    func testNotNumbers() {
        for text in ["-", "+", "", "5 ", " 5", "+-5", "--5", "5-", "0x10", "1e3", "5\u{66B}0"] {
            both(text, int: nil, long: nil)
        }
    }

    /// Kotlin reads any Unicode decimal digit, one UTF-16 unit at a time.
    func testAnyDecimalDigitOfTheBasicMultilingualPlane() {
        both("\u{661}\u{662}\u{663}", int: 123, long: 123)     // Arabic-Indic
        both("\u{665}", int: 5, long: 5)
        both("-\u{665}", int: -5, long: -5)
        both("\u{FF15}\u{FF16}", int: 56, long: 56)             // fullwidth
        both("\u{967}\u{968}", int: 12, long: 12)               // Devanagari
        both("\u{665}\u{300}", int: nil, long: nil)             // a digit with a combining mark
        both("\u{1D7D5}", int: nil, long: nil)                  // a digit outside the plane: two UTF-16 units
    }

    /// An `Int` is 32 bits in Kotlin, so a number that fits a `Long` may still not be an `Int`.
    func testRanges() {
        both("2147483647", int: 2_147_483_647, long: 2_147_483_647)
        both("2147483648", int: nil, long: 2_147_483_648)
        both("-2147483648", int: -2_147_483_648, long: -2_147_483_648)
        both("-2147483649", int: nil, long: -2_147_483_649)
        both("9223372036854775807", int: nil, long: Int64.max)
        both("9223372036854775808", int: nil, long: nil)
        both("-9223372036854775808", int: nil, long: Int64.min)
        both("-9223372036854775809", int: nil, long: nil)
    }
}
