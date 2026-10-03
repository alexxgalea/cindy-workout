import XCTest
import CindyCore

/// The plural rules, checked against the Unicode CLDR tables at the counts where languages change
/// their mind: 0, 1, 2, 4, 5, the teens, and the same run again after each hundred and each ten.
///
/// Mirrors `PluralsTest.kt`.
final class PluralsTests: XCTestCase {

    private func check(_ rule: (Int) -> Plural, _ expected: [Int: Plural], line: UInt = #line) {
        for (n, form) in expected { XCTAssertEqual(rule(n), form, "for \(n)", line: line) }
    }

    /// one or other
    func testOneOrOther() {
        check(Plurals.oneOther, [0: .other, 1: .one, 2: .other, 5: .other, 11: .other, 21: .other, 101: .other])
    }

    /// nought and one are both singular in French and Portuguese
    func testNoughtAndOneAreBothSingularInFrenchAndPortuguese() {
        check(Plurals.zeroOrOne, [0: .one, 1: .one, 2: .other, 5: .other, 21: .other, 101: .other])
    }

    /// Polish
    func testPolish() {
        check(Plurals.polish, [
            0: .many, 1: .one, 2: .few, 3: .few, 4: .few, 5: .many,
            11: .many, 12: .many, 13: .many, 14: .many, 15: .many, 19: .many,
            20: .many, 21: .many, 22: .few, 23: .few, 24: .few, 25: .many,
            100: .many, 101: .many, 102: .few, 111: .many, 112: .many, 121: .many,
            122: .few
        ])
    }

    /// Romanian
    func testRomanian() {
        check(Plurals.romanian, [
            0: .few, 1: .one, 2: .few, 3: .few, 12: .few, 19: .few,
            20: .other, 21: .other, 22: .other, 25: .other, 100: .other,
            101: .few, 102: .few, 111: .few, 119: .few, 120: .other, 121: .other
        ])
    }

    /// Russian
    func testRussian() {
        check(Plurals.russian, [
            0: .many, 1: .one, 2: .few, 3: .few, 4: .few, 5: .many,
            11: .many, 12: .many, 13: .many, 14: .many, 15: .many, 19: .many,
            20: .many, 21: .one, 22: .few, 23: .few, 24: .few, 25: .many,
            100: .many, 101: .one, 102: .few, 111: .many, 112: .many, 121: .one,
            122: .few
        ])
    }

    /// every count up to a thousand has a form in every rule
    func testEveryCountUpToAThousandHasAFormInEveryRule() {
        // Total functions: no count falls through, and the rules that never produce OTHER for a
        // whole number really never do.
        for n in 0...1000 {
            for rule in [Plurals.oneOther, Plurals.zeroOrOne, Plurals.polish, Plurals.romanian, Plurals.russian] {
                _ = rule(n)
            }
            XCTAssertNotEqual(Plurals.polish(n), .other, "Polish has no 'other' for whole numbers (\(n))")
            XCTAssertNotEqual(Plurals.russian(n), .other, "Russian has no 'other' for whole numbers (\(n))")
        }
    }
}
