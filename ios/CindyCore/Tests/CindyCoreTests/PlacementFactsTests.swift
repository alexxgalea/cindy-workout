import XCTest
import CindyCore

/// `PlacementFacts.kt` builds Android views and has no test of its own; the facts it holds are the
/// part worth pinning, because two screens read them.
final class PlacementFactsTests: XCTestCase {

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
}
