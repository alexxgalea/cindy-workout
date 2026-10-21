import XCTest
@testable import CindyCore

/// The menu's and the You screen's own words, held to the Kotlin's. Mirrors `activity_menu.xml` and
/// `activity_account.xml`: a title the iPhone screen draws is the literal Android draws.
final class MenuWordsTests: XCTestCase {

    private let root: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    private func read(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    func testEveryWordIsTheKotlins() throws {
        let menu = try read("app/src/main/res/layout/activity_menu.xml")
        let account = try read("app/src/main/res/layout/activity_account.xml")
        for (name, word) in [("menuTitle", MenuWords.menuTitle), ("menuSubtitle", MenuWords.menuSubtitle)] {
            XCTAssertTrue(menu.contains("android:text=\"\(word)\""), "\(name) is not in activity_menu.xml: \(word)")
        }
        for (name, word) in [("youTitle", MenuWords.youTitle), ("youSubtitle", MenuWords.youSubtitle)] {
            XCTAssertTrue(account.contains("android:text=\"\(word)\""), "\(name) is not in activity_account.xml: \(word)")
        }
    }

    func testTheOldWordsAreGone() throws {
        for file in ["ios/CindyTracker/MenuScreen.swift", "ios/CindyTracker/AccountScreen.swift"] {
            let view = try read(file)
            for old in ["Color.dim", "Ink.", ".system(size:"] {
                XCTAssertFalse(view.contains(old), "\(file) still draws with: \(old)")
            }
        }
    }
}
