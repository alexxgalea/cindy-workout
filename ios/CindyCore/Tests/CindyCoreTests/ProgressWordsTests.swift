import XCTest
@testable import CindyCore

/// The Progress screen's own words, held to the Kotlin's. Mirrors `RecordsActivity.kt` and
/// `activity_records.xml`: a title the iPhone screen draws is the literal Android draws.
final class ProgressWordsTests: XCTestCase {

    private let root: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    private func read(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    func testEveryWordIsTheKotlins() throws {
        let kotlin = try read("app/src/main/java/com/cindy/tracker/RecordsActivity.kt")
        let layout = try read("app/src/main/res/layout/activity_records.xml")
        // Since #147 the title is the top bar's `app:title`.
        XCTAssertTrue(layout.contains("app:title=\"\(ProgressWords.title)\""),
                      "title is not the top bar's title in activity_records.xml: \(ProgressWords.title)")
        let inKotlin: [(String, String)] = [
            ("thisWeekTitle", ProgressWords.thisWeekTitle),
            ("peaksTitle", ProgressWords.peaksTitle), ("leaderboardTitle", ProgressWords.leaderboardTitle),
            ("open", ProgressWords.open), ("previousMonth", ProgressWords.previousMonth),
            ("nextMonth", ProgressWords.nextMonth),
        ]
        for (name, word) in inKotlin {
            XCTAssertTrue(kotlin.contains("\"\(word)\""), "\(name) is not in RecordsActivity.kt: \(word)")
        }
    }

    /// Two words the iPhone's Progress screen draws that Android no longer does: the sentence under
    /// the title (dropped in 4d0ec12, since the top bar names the page) and the PROGRESS section title
    /// (dropped in d3a9b32, when the score chart went straight after the week's card). They were held
    /// to the Kotlin's; the iPhone keeps them until its port (#155; ADR 0003, ADR 0007).
    func testTheWordsAndroidDroppedAreStillTheKotlins() throws {
        try XCTSkipIf(true, "Skipped until the iPhone port of the polished interface (#155): Android dropped "
            + "the Progress subtitle and the PROGRESS section title, and the iPhone app keeps them until its port.")
        let kotlin = try read("app/src/main/java/com/cindy/tracker/RecordsActivity.kt")
        let layout = try read("app/src/main/res/layout/activity_records.xml")
        XCTAssertTrue(layout.contains("android:text=\"\(ProgressWords.subtitle)\""),
                      "subtitle is not in activity_records.xml: \(ProgressWords.subtitle)")
        XCTAssertTrue(kotlin.contains("\"\(ProgressWords.progressTitle)\""),
                      "progressTitle is not in RecordsActivity.kt: \(ProgressWords.progressTitle)")
    }

    func testTheOldWordsAreGone() throws {
        // The cards live in ProgressCards.swift now; both files are held to it.
        for file in ["ios/CindyTracker/ProgressScreen.swift", "ios/CindyTracker/ProgressCards.swift"] {
            let view = try read(file)
            for old in ["sectionTitle(\"THIS WEEK\")", "sectionTitle(\"PROGRESS\")", "sectionTitle(\"PEAKS\")",
                        "sectionTitle(\"LEADERBOARD\")", "SectionTitle(\"THIS WEEK\")", "SectionTitle(\"PROGRESS\")",
                        "SectionTitle(\"PEAKS\")", "SectionTitle(\"LEADERBOARD\")", "\"Previous month\"",
                        "Button(\"OPEN\")"] {
                XCTAssertFalse(view.contains(old), "\(file) still draws: \(old)")
            }
        }
    }
}
