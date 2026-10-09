import XCTest
@testable import CindyCore

/// The profile screen and the places that point at it, ported from `AccountScreenTest.kt`.
///
/// Robolectric inflated `AccountActivity` and read its views; the same facts are read here off the
/// `AccountPage` the screen draws. What a badge is, and when it is earned, is tested without a view
/// in `BadgesTests`; the name and the photo's arithmetic in `AvatarTests`. What is tested here is the
/// part an athlete meets: a screen that builds empty and with a history, tiles that read as earned
/// or locked, sheets that open, a name that is kept only when they say SAVE, and a menu that leads
/// here. Each test is named after the Kotlin one it comes from. The ones that start a screen, draw
/// a view or measure one stay with the SwiftUI layer, as `PARITY.md` says.
final class AccountPageTests: XCTestCase {

    private let zone = Zone("Europe/Bucharest")
    private let today = LocalDate(2026, 10, 8)
    private let day = LocalDate(2026, 3, 2)

    private func fresh() -> Profile {
        let name = "AccountPageTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return Profile(defaults: defaults)
    }

    private func session(on date: LocalDate? = nil, rounds: Int = 10) -> Attempt {
        Attempt(rounds: rounds, reps: 0, atMillis: zone.epochMs(date ?? day, hour: 12), durationMs: 10 * 60_000)
    }

    private func page(_ attempts: [Attempt] = [], profile: Profile? = nil, hasPhoto: Bool = false) -> AccountPage {
        AccountBuilder.build(profile: profile ?? fresh(), hasPhoto: hasPhoto, attempts: attempts, zone: zone,
                             firstDayOfWeek: .monday, today: today)
    }

    private func tiles(_ p: AccountPage) -> [BadgeTile] { p.families.flatMap { $0.tiles } }

    private func tile(_ p: AccountPage, startingWith prefix: String) -> BadgeTile? {
        tiles(p).first { $0.spoken.hasPrefix(prefix) }
    }

    // MARK: the screen, empty

    /// the screen builds with nothing recorded, and every badge is locked
    func testTheScreenBuildsWithNothingRecordedAndEveryBadgeIsLocked() {
        let p = page()

        XCTAssertEqual(p.header.nameSpoken, "Add your name")
        XCTAssertEqual(p.header.photoSpoken, "Add a photo")
        XCTAssertEqual(p.header.title, "Add your name")
        XCTAssertEqual(p.header.trainingLine, "Finish a session and your badges start here.")
        XCTAssertEqual(p.badgesTitle, "BADGES · 0 OF 26")
        for badge in Badge.allCases {
            XCTAssertNotNil(tile(p, startingWith: "\(badge.title), locked"), "no tile for \(badge.title)")
        }
        XCTAssertEqual(tiles(p).count, 26)
    }

    /// the screen measures and lays out: here, a history builds a page whose tiles all have a name
    func testTheScreenBuildsWithAHistory() {
        let p = page([session()])
        XCTAssertEqual(tiles(p).count, 26)
        XCTAssertTrue(tiles(p).allSatisfy { !$0.title.isEmpty && !$0.face.isEmpty && !$0.spoken.isEmpty })
        XCTAssertEqual(AccountPage.columns, 3)
    }

    /// every family has its heading
    func testEveryFamilyHasItsHeading() {
        let p = page()
        XCTAssertEqual(p.families.map { $0.heading }, BadgeFamily.allCases.map { $0.label.uppercased() })
        XCTAssertEqual(p.families.map { $0.heading }, ["SESSIONS", "ROUNDS", "STREAKS", "VOLUME", "PACE", "CRAFT"])
    }

    // MARK: the screen, with a history

    /// earned badges read as earned and the others say how far along they are
    func testEarnedBadgesReadAsEarnedAndTheOthersSayHowFarAlongTheyAre() {
        let p = page([session(rounds: 10)])

        XCTAssertEqual(p.badgesTitle, "BADGES · 4 OF 26")
        XCTAssertEqual(p.header.trainingLine, "Training since 2 Mar 2026 · 1 session")
        for earned in ["First Cindy", "First round", "Novice", "Intermediate"] {
            XCTAssertNotNil(tile(p, startingWith: "\(earned), earned 2 Mar 2026"), "\(earned) is not earned")
        }
        // Ten rounds is ten of the sixteen Advanced asks for, and one of the ten sessions.
        XCTAssertNotNil(tile(p, startingWith: "Advanced, locked, 10 of 16 rounds"))
        XCTAssertNotNil(tile(p, startingWith: "10 sessions, locked, 1 of 10 sessions"))
        // A badge with nothing to count says only that it is locked.
        XCTAssertNotNil(tile(p, startingWith: "Past Tom Holland, locked"))
        XCTAssertNil(tile(p, startingWith: "Past Tom Holland, locked, "))
    }

    /// a session the camera lost the athlete in earns nothing but the first session
    func testASessionTheCameraLostTheAthleteInEarnsNothingButTheFirstSession() {
        let lost = Attempt(rounds: 27, reps: 0, atMillis: zone.epochMs(day, hour: 12), durationMs: 10 * 60_000,
                           untrackedMs: Records.untrackedToleranceMs)
        let p = page([lost])

        XCTAssertEqual(p.badgesTitle, "BADGES · 1 OF 26")
        XCTAssertNotNil(tile(p, startingWith: "First Cindy, earned"))
        XCTAssertNotNil(tile(p, startingWith: "Legend, locked"))
    }

    // MARK: sheets

    /// a locked tile opens a sheet with what it asks for and how far along it is
    func testALockedTileOpensASheetWithWhatItAsksForAndHowFarAlongItIs() {
        let sheet = tile(page([session(rounds: 10)]), startingWith: "Advanced, locked")!.sheet

        XCTAssertEqual(sheet.title, "Advanced")
        XCTAssertEqual(sheet.requirement, "16 rounds in a standard Cindy.")
        XCTAssertEqual(sheet.status, "10 of 16 rounds")
        XCTAssertFalse(sheet.earned)
    }

    /// an earned tile opens a sheet with the day it was earned
    func testAnEarnedTileOpensASheetWithTheDayItWasEarned() {
        let sheet = tile(page([session(rounds: 10)]), startingWith: "Intermediate, earned")!.sheet

        XCTAssertEqual(sheet.title, "Intermediate")
        XCTAssertEqual(sheet.status, "Earned 2 Mar 2026")
        XCTAssertTrue(sheet.earned)
    }

    /// a badge with nothing to count says it is not earned yet
    func testABadgeWithNothingToCountSaysItIsNotEarnedYet() {
        let sheet = tile(page(), startingWith: "Made it yours, locked")!.sheet

        XCTAssertEqual(sheet.requirement, "Finish an Adaptive Cindy.")
        XCTAssertEqual(sheet.status, "Not earned yet")
    }

    // MARK: the name

    /// saving a name keeps it, and the screen says it
    func testSavingANameKeepsItAndTheScreenSaysIt() {
        let profile = fresh()
        NameForm.save("  Alex   Galea ", to: profile)

        XCTAssertEqual(profile.displayName, "Alex Galea")
        let header = page(profile: profile).header
        XCTAssertEqual(header.nameSpoken, "Your name, Alex Galea, tap to change")
        XCTAssertEqual(header.title, "Alex Galea")
        XCTAssertEqual(header.name, "Alex Galea")
    }

    /// the name sheet starts with the name already there
    func testTheNameSheetStartsWithTheNameAlreadyThere() {
        let profile = fresh()
        profile.displayName = "Alex"
        XCTAssertEqual(page(profile: profile).header.nameSpoken, "Your name, Alex, tap to change")
        XCTAssertEqual(profile.displayName, "Alex", "the field starts from what is kept")
    }

    /// an emptied name is taken back
    func testAnEmptiedNameIsTakenBack() {
        let profile = fresh()
        profile.displayName = "Alex"
        NameForm.save("   ", to: profile)

        XCTAssertNil(profile.displayName)
        XCTAssertEqual(page(profile: profile).header.nameSpoken, "Add your name")
    }

    /// cancelling leaves the name alone
    func testCancellingLeavesTheNameAlone() {
        let profile = fresh()
        profile.displayName = "Alex"
        // The athlete types "Someone else" and says CANCEL: nothing is saved, because only SAVE does.
        _ = NameForm.limited("Someone else")
        XCTAssertEqual(profile.displayName, "Alex")
    }

    /// a name is never longer than the limit, however it got there
    func testANameIsNeverLongerThanTheLimitHoweverItGotThere() {
        XCTAssertEqual(NameForm.limited(String(repeating: "A", count: 60)).utf16.count, Avatar.maxName)
        XCTAssertEqual(NameForm.limited("Alex"), "Alex")
        // Half a character is not kept: a pair that would straddle the limit stays out.
        let atTheEdge = String(repeating: "A", count: Avatar.maxName - 1) + "😀"
        XCTAssertEqual(NameForm.limited(atTheEdge), String(repeating: "A", count: Avatar.maxName - 1))
        let fits = String(repeating: "A", count: Avatar.maxName - 2) + "😀"
        XCTAssertEqual(NameForm.limited(fits), fits)
    }

    // MARK: the photo

    /// without a photo the sheet offers to choose one or to cancel, and never to remove
    func testWithoutAPhotoTheSheetOffersToChooseOneOrToCancelAndNeverToRemove() {
        let titles = PhotoSheet.actions(hasPhoto: false).map { $0.title }
        XCTAssertEqual(titles, ["CHOOSE PHOTO", "CANCEL"])
        XCTAssertFalse(titles.contains("REMOVE"))
        XCTAssertEqual(page().header.photoSpoken, "Add a photo")
    }

    /// with a photo the sheet offers to remove it
    func testWithAPhotoTheSheetOffersToRemoveIt() {
        let actions = PhotoSheet.actions(hasPhoto: true)
        XCTAssertEqual(actions.map { $0.title }, ["CHOOSE PHOTO", "REMOVE"])
        XCTAssertTrue(actions[1].destructive)
        XCTAssertFalse(actions[0].destructive)
        XCTAssertEqual(page(hasPhoto: true).header.photoSpoken, "Your photo, tap to change")
        XCTAssertEqual(PhotoSheet.title, "Your photo")
    }

    // MARK: the menu's profile card

    private func menu(_ profile: Profile, _ attempts: [Attempt] = [], hasPhoto: Bool = false) -> MenuPage {
        MenuBuilder.build(MenuInput(profile: profile, attempts: attempts, zone: zone, firstDayOfWeek: .monday,
                                    today: today, hasPhoto: hasPhoto))
    }

    /// the menu leads with a profile card that invites a name and a photo
    func testTheMenuLeadsWithAProfileCardThatInvitesANameAndAPhoto() {
        XCTAssertEqual(menu(fresh()).card.spoken, "You, Add your name and photo")
    }

    /// the profile card names the athlete, their badges and their level
    func testTheProfileCardNamesTheAthleteTheirBadgesAndTheirLevel() {
        let profile = fresh()
        profile.displayName = "Alex"
        XCTAssertEqual(menu(profile, [session(rounds: 10)]).card.spoken, "Alex, 4 badges · Intermediate")
    }

    /// a name with no sessions yet points at the first badge
    func testANameWithNoSessionsYetPointsAtTheFirstBadge() {
        let profile = fresh()
        profile.displayName = "Alex"
        XCTAssertEqual(menu(profile).card.spoken, "Alex, Finish a session to earn your first badge")
    }

    /// A photo with no name has been given something, so the invitation is not repeated.
    func testAPhotoWithNoNameIsNotInvitedAgain() {
        XCTAssertEqual(menu(fresh(), hasPhoto: true).card.spoken, "You, Finish a session to earn your first badge")
    }

    /// the menu deals in every card on one running count, the profile card first
    func testTheMenuDealsInEveryCardOnOneRunningCountTheProfileCardFirst() {
        let page = menu(fresh())
        let delays = (0...page.rows.count).map { MenuPage.delayMs($0) }

        XCTAssertEqual(delays[0], 0, "the profile card arrives first")
        XCTAssertTrue(delays[1] > delays[0], "the settings follow the profile card: \(delays)")
        XCTAssertTrue(zip(delays, delays.dropFirst()).allSatisfy { $0 < $1 }, "each row follows the one before: \(delays)")
        XCTAssertEqual(delays.last, page.rows.count * 34)
    }

    // MARK: the results screen

    private func results(_ a: Attempt, _ all: [Attempt]) -> ResultsPage {
        ResultsPageBuilder.build(ResultsInput(attempt: a, records: all, body: Body(0), zone: zone,
                                              firstDayOfWeek: .monday, today: today))
    }

    /// a first session names its three best new badges and counts the rest
    func testAFirstSessionNamesItsThreeBestNewBadgesAndCountsTheRest() {
        let first = session(rounds: 10)
        let box = results(first, [first]).celebration!

        // Four badges, hardest first. First Cindy is the easiest, so it is the one that is counted,
        // and it is the one the line above already said.
        let texts = box.rows.map { $0.text }
        XCTAssertTrue(texts.contains("New badge: Intermediate"))
        XCTAssertTrue(texts.contains("New badge: Novice"))
        XCTAssertTrue(texts.contains("New badge: First round"))
        XCTAssertFalse(texts.contains("New badge: First Cindy"))
        XCTAssertEqual(box.more, "+1 more in your profile")
    }

    /// nothing is counted when every new badge is named
    func testNothingIsCountedWhenEveryNewBadgeIsNamed() {
        let first = session(rounds: 4)
        let box = results(first, [first]).celebration!

        let texts = box.rows.map { $0.text }
        XCTAssertTrue(texts.contains("New badge: First round"))
        XCTAssertTrue(texts.contains("New badge: First Cindy"))
        XCTAssertNil(box.more)
    }

    /// a session that earns no badge says nothing about badges
    func testASessionThatEarnsNoBadgeSaysNothingAboutBadges() {
        let stronger = session(rounds: 10)
        let weaker = Attempt(rounds: 8, reps: 0, atMillis: stronger.atMillis + 60 * 60_000, durationMs: 10 * 60_000)

        XCTAssertNil(results(weaker, [stronger, weaker]).celebration, "no celebration box at all")
    }

    /// a badge earned with a record or a streak line shares the box with it
    func testABadgeEarnedWithARecordOrAStreakLineSharesTheBoxWithIt() {
        // Second day, a personal record: a line for the record, and the badge for the rung it reached.
        let first = session(on: day, rounds: 5)
        let better = session(on: day.plusDays(1), rounds: 10)
        let texts = results(better, [first, better]).celebration!.rows.map { $0.text }

        XCTAssertTrue(texts.contains("New personal record."))
        XCTAssertTrue(texts.contains("New badge: Intermediate"))
    }

    // MARK: the record board

    /// clearing the records takes the badges with them and leaves the name and photo
    func testClearingTheRecordsTakesTheBadgesWithThemAndLeavesTheNameAndPhoto() throws {
        let name = "AccountPageTests-clear-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let profile = Profile(defaults: defaults)
        let photo = AvatarFiles(directory: directory)
        let store = RecordStore(defaults: defaults)
        profile.displayName = "Alex"
        XCTAssertTrue(photo.store(Data([1, 2, 3])))
        XCTAssertTrue(store.add(session(rounds: 10)))

        store.clear()

        XCTAssertTrue(store.all().isEmpty)
        XCTAssertTrue(Badges.earned(store.all(), zone: zone, firstDayOfWeek: .monday).isEmpty)
        XCTAssertEqual(profile.displayName, "Alex")
        XCTAssertTrue(photo.exists)
    }
}
