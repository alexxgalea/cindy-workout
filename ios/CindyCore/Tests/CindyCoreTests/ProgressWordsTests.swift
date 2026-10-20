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
        for (name, word) in [("title", ProgressWords.title), ("subtitle", ProgressWords.subtitle)] {
            XCTAssertTrue(layout.contains("android:text=\"\(word)\""), "\(name) is not in activity_records.xml: \(word)")
        }
        let inKotlin: [(String, String)] = [
            ("thisWeekTitle", ProgressWords.thisWeekTitle), ("progressTitle", ProgressWords.progressTitle),
            ("peaksTitle", ProgressWords.peaksTitle), ("leaderboardTitle", ProgressWords.leaderboardTitle),
            ("open", ProgressWords.open), ("previousMonth", ProgressWords.previousMonth),
            ("nextMonth", ProgressWords.nextMonth),
        ]
        for (name, word) in inKotlin {
            XCTAssertTrue(kotlin.contains("\"\(word)\""), "\(name) is not in RecordsActivity.kt: \(word)")
        }
    }

    func testTheOldWordsAreGone() throws {
        let view = try read("ios/CindyTracker/ProgressScreen.swift")
        for old in ["sectionTitle(\"THIS WEEK\")", "sectionTitle(\"PROGRESS\")", "sectionTitle(\"PEAKS\")",
                    "sectionTitle(\"LEADERBOARD\")", "\"Previous month\"", "Button(\"OPEN\")"] {
            XCTAssertFalse(view.contains(old), "ProgressScreen.swift still draws: \(old)")
        }
    }
}
