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
        // Since #147 the titles are the top bar's `app:title`; the lines under them are still text.
        XCTAssertTrue(menu.contains("app:title=\"\(MenuWords.menuTitle)\""),
                      "menuTitle is not the top bar's title in activity_menu.xml: \(MenuWords.menuTitle)")
        XCTAssertTrue(menu.contains("android:text=\"\(MenuWords.menuSubtitle)\""),
                      "menuSubtitle is not in activity_menu.xml: \(MenuWords.menuSubtitle)")
        XCTAssertTrue(account.contains("app:title=\"\(MenuWords.youTitle)\""),
                      "youTitle is not the top bar's title in activity_account.xml: \(MenuWords.youTitle)")
        XCTAssertTrue(account.contains("android:text=\"\(MenuWords.youSubtitle)\""),
                      "youSubtitle is not in activity_account.xml: \(MenuWords.youSubtitle)")
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
