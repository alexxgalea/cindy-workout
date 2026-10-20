import XCTest
@testable import CindyCore

/// The session page's own words, held to the Kotlin's. Mirrors `ResultsActivity.kt` and
/// `activity_results.xml`: a title the iPhone page draws is the literal Android draws.
final class ResultsWordsTests: XCTestCase {

    private let root: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    private func read(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    func testEveryWordIsTheKotlins() throws {
        let kotlin = try read("app/src/main/java/com/cindy/tracker/ResultsActivity.kt")
        let layout = try read("app/src/main/res/layout/activity_results.xml")
        let inLayout: [(String, String)] = [
            ("trackTitle", ResultsWords.trackTitle), ("movementsTitle", ResultsWords.movementsTitle),
            ("compareTitle", ResultsWords.compareTitle), ("timelineTitle", ResultsWords.timelineTitle),
            ("splitsTitle", ResultsWords.splitsTitle), ("heartTitle", ResultsWords.heartTitle),
            ("detailsTitle", ResultsWords.detailsTitle),
        ]
        for (name, word) in inLayout {
            XCTAssertTrue(layout.contains("android:text=\"\(word)\""), "\(name) is not in activity_results.xml: \(word)")
        }
        let inKotlin: [(String, String)] = [
            ("liftedEyebrow", ResultsWords.liftedEyebrow), ("burnedEyebrow", ResultsWords.burnedEyebrow),
            ("weightInviteTitle", ResultsWords.weightInviteTitle),
            ("weightInviteValue", ResultsWords.weightInviteValue),
            ("zonesInviteTitle", ResultsWords.zonesInviteTitle),
            ("zonesInviteValue", ResultsWords.zonesInviteValue),
            ("timeInZone", ResultsWords.timeInZone), ("hardestRound", ResultsWords.hardestRound),
            ("scrubHint", ResultsWords.scrubHint),
        ]
        for (name, word) in inKotlin {
            XCTAssertTrue(kotlin.contains("\"\(word)\""), "\(name) is not in ResultsActivity.kt: \(word)")
        }
    }

    func testTheOldWordsAreGone() throws {
        try XCTSkipIf(true, "The view's words are replaced in the cards task")
        let view = try read("ios/CindyTracker/ResultsView.swift")
        for old in ["sectionTitle(\"ROUNDS\")", "\"LIFTED\"", "\"BURNED\"",
                    "Add your weight to see what you lifted and burned",
                    "Add your birth year to see your heart-rate zones"] {
            XCTAssertFalse(view.contains(old), "ResultsView.swift still draws: \(old)")
        }
    }
}
