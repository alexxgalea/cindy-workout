import XCTest
import CindyCore

/// `PlacementFacts.kt` builds Android views and has no test of its own; the facts it holds are the
/// part worth pinning, because two screens read them. The guide's own words are held to the
/// literals in `MainActivity.showPlacementGuide`.
final class PlacementFactsTests: XCTestCase {

    private let root: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    private func read(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// there are three, one line each, and the last is the warning
    func testThereAreThreeOneLineEachAndTheLastIsTheWarning() {
        XCTAssertEqual(PlacementFacts.all.count, 3)
        for fact in PlacementFacts.all {
            XCTAssertFalse(fact.text.contains("\n"))
            XCTAssertTrue(fact.text.hasSuffix("."))
        }
        XCTAssertEqual(PlacementFacts.all.map { $0.warning }, [false, false, true])
    }

    /// they say what Android says
    func testTheySayWhatAndroidSays() {
        XCTAssertEqual(PlacementFacts.all.map { $0.text }, [
            "Stand the phone up rather than laying it flat.",
            "Keep your head and your feet both in shot.",
            "Then leave it there — moving it mid-workout resets what it has learned."
        ])
    }

    /// each fact carries the drawable Android gives it, in Android's order, and the one Android
    /// tints as a caution is the warning
    func testTheIconsAreTheDrawablesAndroidNames() throws {
        let kotlin = try read("app/src/main/java/com/cindy/tracker/PlacementFacts.kt")
        var from = kotlin.startIndex
        for fact in PlacementFacts.all {
            guard let hit = kotlin.range(of: "R.drawable.\(fact.icon)", range: from..<kotlin.endIndex) else {
                return XCTFail("\(fact.icon) is not in PlacementFacts.kt, or is out of order")
            }
            from = hit.upperBound
        }
        XCTAssertEqual(PlacementFacts.all.filter { $0.warning }.map { $0.icon }, ["ic_dont_move"])
        XCTAssertTrue(kotlin.contains("if (icon == R.drawable.ic_dont_move) R.color.state_caution"),
                      "Android tints ic_dont_move as the caution")
    }

    /// the guide's title, line, toggle and two buttons are the literals of `showPlacementGuide`
    func testTheGuideSaysWhatAndroidSays() throws {
        let kotlin = try read("app/src/main/java/com/cindy/tracker/MainActivity.kt")
        let literals: [(String, String, String)] = [
            ("title", PlacementWords.title, "title = \"\(PlacementWords.title)\""),
            ("subtitle", PlacementWords.subtitle, "subtitle = \"\(PlacementWords.subtitle)\""),
            ("dontShowAgain", PlacementWords.dontShowAgain, "sheet.toggle(\"\(PlacementWords.dontShowAgain)\""),
            ("start", PlacementWords.start, "primary = \"\(PlacementWords.start)\""),
            ("notNow", PlacementWords.notNow, "secondary = \"\(PlacementWords.notNow)\"")
        ]
        for (name, word, literal) in literals {
            XCTAssertTrue(kotlin.contains(literal), "\(name) is not in MainActivity.kt: \(word)")
        }
    }
}
