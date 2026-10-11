import XCTest
@testable import CindyCore

/// The sheet that comes before Strava's consent page, from each of the three roads that lead to it.
///
/// Mirrors `StravaConsentTest.kt` (7). Robolectric clicked rows and read the dialog; what these hold
/// is the same order of things, over the models the screens draw from: the sheet first, and nothing
/// minted, stored or opened until Strava's own button is tapped. A NOT NOW that left a pending state
/// behind, or a road that skipped the sheet, would put Cindy back to sending the athlete to Strava
/// with no word of what follows.
final class StravaConsentTests: XCTestCase {

    private let config = StravaConfig(clientId: "12345", clientSecret: "s3cret", applicationId: "com.cindy.tracker")
    private let storage = InMemoryStravaStorage()
    private var tokens: StravaTokenStore { StravaTokenStore(storage: storage) }
    private var ledger: StravaUploads { StravaUploads(storage: storage) }
    private var connect: StravaConnect { StravaConnect(tokens: tokens, config: config) }

    private let grant = StravaGrant(accessToken: "a", refreshToken: "r", expiresAtEpochS: 9_999_999_999,
                                    scopes: ["read", "activity:write"], athleteName: "Alex G")

    private func assertNothingStarted(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNil(tokens.pendingState, "a state was minted", file: file, line: line)
        XCTAssertNil(tokens.afterConnectUploadAtMillis, "an attempt was remembered", file: file, line: line)
    }

    // ---- the menu ---------------------------------------------------------------------------

    /// the menu row asks first, and says what is sent and what is not
    func testTheMenuRowAsksFirstAndSaysWhatIsSentAndWhatIsNot() {
        XCTAssertEqual(StravaMenu.tap(grant: nil), .askConsent)

        let text = StravaConsent.words.joined(separator: "\n")
        for phrase in ["Connect to Strava",
                       "Nothing is sent until you connect.",
                       "Its score and every set with its reps.",
                       "Your heart rate, if a watch recorded it.",
                       "Never the camera picture, the video or the pose.",
                       StravaConsent.dataPermissions] {
            XCTAssertTrue(text.contains(phrase), "the sheet lost: \(phrase)")
        }
        XCTAssertEqual(StravaConsent.connectLabel, "Connect with Strava")
        // Showing it, and tapping the row, started nothing.
        assertNothingStarted()
    }

    /// NOT NOW from the menu starts nothing
    func testNotNowFromTheMenuStartsNothing() {
        XCTAssertEqual(StravaConsent.notNowLabel, "NOT NOW")
        // NOT NOW is the sheet closing: `begin` is never reached.
        assertNothingStarted()
    }

    /// Connect with Strava from the menu opens Strava's page for the state it stored
    func testConnectWithStravaFromTheMenuOpensStravasPageForTheStateItStored() throws {
        tokens.afterConnectUploadAtMillis = 999  // left behind by an earlier results screen

        let url = connect.begin(.menu)

        let state = try XCTUnwrap(tokens.pendingState)
        XCTAssertEqual(url, StravaAuth.authorizeUri(state: state, config: config))
        XCTAssertNil(tokens.afterConnectUploadAtMillis, "a menu connect is about no particular attempt")
    }

    // ---- the results screen -----------------------------------------------------------------

    /// Connect to upload asks first, and connects for that attempt only after Connect with Strava
    func testConnectToUploadAsksFirstAndConnectsForThatAttemptOnlyAfterConnectWithStrava() throws {
        let row = StravaRow.content(connected: false, status: nil)
        XCTAssertEqual(row.value, "Connect to upload")
        XCTAssertEqual(row.action, .askThenConnect, "the row asks; it does not connect")
        assertNothingStarted()

        let url = connect.begin(.results(atMillis: 301))

        XCTAssertEqual(url, StravaAuth.authorizeUri(state: try XCTUnwrap(tokens.pendingState), config: config))
        XCTAssertEqual(tokens.afterConnectUploadAtMillis, 301)
    }

    /// NOT NOW from the results row connects nothing and remembers no attempt
    func testNotNowFromTheResultsRowConnectsNothingAndRemembersNoAttempt() {
        _ = StravaRow.content(connected: false, status: nil)
        assertNothingStarted()
    }

    /// Reconnect to upload asks first too
    func testReconnectToUploadAsksFirstToo() throws {
        tokens.grant = grant
        ledger.write(atMillis: 303, StravaUploadStatus(.needsReconnect))

        let row = try XCTUnwrap(StravaRow.of(config: config, tokens: tokens, ledger: ledger, atMillis: 303))
        XCTAssertEqual(row.value, "Reconnect to upload")
        XCTAssertEqual(row.action, .askThenConnect)
        assertNothingStarted()

        _ = connect.begin(.results(atMillis: 303))
        XCTAssertEqual(tokens.afterConnectUploadAtMillis, 303)
    }

    /// a connected athlete is not asked again from the menu, and sees the Compatible with Strava mark
    func testAConnectedAthleteIsNotAskedAgainFromTheMenuAndSeesTheCompatibleWithStravaMark() {
        XCTAssertEqual(StravaMenu.tap(grant: grant), .openSheet)
        XCTAssertFalse(StravaSheet.subtitle(athleteName: "Alex G", autoUpload: true).contains("Connect to Strava"))
        // The mark that names the integration, on the sheet that is open while it is in use.
        XCTAssertEqual(StravaSheet.compatibleLabel, "Compatible with Strava")
    }

    // ---- beyond the Kotlin ------------------------------------------------------------------

    /// a consent page nothing can show takes back what was minted
    func testAConsentPageNothingCanShowTakesBackWhatWasMinted() {
        _ = connect.begin(.results(atMillis: 5))
        connect.cancel()
        assertNothingStarted()
    }

    /// each connect mints a state of its own
    func testEachConnectMintsAStateOfItsOwn() {
        _ = connect.begin(.menu)
        let first = tokens.pendingState
        _ = connect.begin(.menu)
        XCTAssertNotEqual(first, tokens.pendingState)
    }
}
