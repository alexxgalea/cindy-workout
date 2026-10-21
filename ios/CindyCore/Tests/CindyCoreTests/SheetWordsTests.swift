import XCTest
@testable import CindyCore

/// The sheets' own words, held to the Kotlin's. Mirrors `MenuActivity.kt`, `Dialogs.kt`,
/// `AccountActivity.kt` and `LanguageGroup.kt`: a label the iPhone sheets draw is the literal
/// Android draws.
final class SheetWordsTests: XCTestCase {

    private let root: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    private func read(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    func testEveryWordIsTheKotlins() throws {
        let kotlin = try ["MenuActivity.kt", "Dialogs.kt", "AccountActivity.kt", "LanguageGroup.kt"]
            .map { try read("app/src/main/java/com/cindy/tracker/\($0)") }.joined(separator: "\n")
        let words: [(String, String)] = [
            ("save", SheetWords.save), ("cancel", SheetWords.cancel), ("done", SheetWords.done),
            ("notNow", SheetWords.notNow), ("hearIt", SheetWords.hearIt), ("forget", SheetWords.forget),
            ("openSettings", SheetWords.openSettings), ("language", SheetWords.language),
            ("volume", SheetWords.volume),
        ]
        for (name, word) in words {
            XCTAssertTrue(kotlin.contains("\"\(word)\""), "\(name) is not in the Kotlin sheets: \(word)")
        }
    }

    func testTheOldWordsAreGone() throws {
        let files = ["MenuScreen", "AccountScreen", "ProfileSheets", "VoiceSheet", "MusicSheet", "HeartRateSheet",
                     "ReminderSheet", "StravaSheets", "ResultsView", "TutorialScreen"]
        try XCTSkipIf(true, "the menu's sheets are still the system's")
        for file in files {
            let view = try read("ios/CindyTracker/\(file).swift")
            for old in [".sheet(", ".alert(", ".confirmationDialog(", ".presentationDetents(", "Form {",
                        ".ultraThinMaterial", "Color.warn", "Color.dim", ".system(size:"] {
                XCTAssertFalse(view.contains(old), "\(file).swift still draws with: \(old)")
            }
        }
    }
}
