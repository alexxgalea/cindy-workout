import XCTest
@testable import CindyCore

/// The Strava row and sheet in the menu, the redirect, and the results screen's row.
///
/// Mirrors `StravaScreenTest.kt` (18). Robolectric built each activity and read its views; these read
/// the same facts off the models the screens draw from: `MenuPage`, `StravaSheet`, `StravaRedirectHandler`
/// and `StravaRow`. The seam Android needs (`StravaConfig.availableForTest`) is a config built with or
/// without credentials.
final class StravaScreenTests: XCTestCase {

    private let withStrava = StravaConfig(clientId: "12345", clientSecret: "s3cret", applicationId: "com.cindy.tracker")
    private let withoutStrava = StravaConfig(clientId: "", clientSecret: "", applicationId: "com.cindy.tracker")

    private let storage = InMemoryStravaStorage()
    private var tokens: StravaTokenStore { StravaTokenStore(storage: storage) }
    private var ledger: StravaUploads { StravaUploads(storage: storage) }

    private func testGrant() -> StravaGrant {
        StravaGrant(accessToken: "a", refreshToken: "r", expiresAtEpochS: 9_999_999_999,
                    scopes: ["read", "activity:write"], athleteName: "Alex G")
    }

    // ---- the menu ---------------------------------------------------------------------------

    private func menu(_ config: StravaConfig) -> MenuPage {
        let defaults = UserDefaults(suiteName: "StravaScreenTests-\(UUID().uuidString)")!
        let status = StravaMenu.status(config: config, tokens: tokens)
        return MenuBuilder.build(MenuInput(
            profile: Profile(defaults: defaults), attempts: [], zone: Zone("Europe/Bucharest"), firstDayOfWeek: .monday,
            today: LocalDate(2026, 10, 8), strava: status))
    }

    private func stravaRow(_ page: MenuPage) -> String? { page.rows.first { $0.id == .strava }?.spoken }

    /// the menu builds with Strava unavailable, and has no Strava row
    func testTheMenuBuildsWithStravaUnavailableAndHasNoStravaRow() {
        XCTAssertNil(stravaRow(menu(withoutStrava)))
    }

    /// the menu builds with Strava not connected
    func testTheMenuBuildsWithStravaNotConnected() throws {
        let row = try XCTUnwrap(stravaRow(menu(withStrava)))
        XCTAssertTrue(row.hasPrefix("Strava, Not connected"), row)
    }

    /// the menu builds with Strava connected, and the sheet offers DONE and DISCONNECT
    func testTheMenuBuildsWithStravaConnectedAndTheSheetOffersDoneAndDisconnect() throws {
        tokens.grant = testGrant()
        let row = try XCTUnwrap(stravaRow(menu(withStrava)))
        XCTAssertTrue(row.hasPrefix("Strava, Connected · Alex G"), row)

        XCTAssertEqual(StravaMenu.tap(grant: tokens.grant), .openSheet)
        XCTAssertEqual(StravaSheet.title, "Strava")
        XCTAssertEqual(StravaSheet.doneLabel, "DONE")
        XCTAssertEqual(StravaSheet.disconnectLabel, "DISCONNECT")
        XCTAssertEqual(StravaSheet.toggleLabel, "Upload automatically")
    }

    /// the connected sheet says heart rate needs Strava's Data Permissions
    func testTheConnectedSheetSaysHeartRateNeedsStravasDataPermissions() {
        XCTAssertTrue(StravaSheet.note.contains("Data Permissions"))
        XCTAssertEqual(StravaSheet.note, StravaConsent.dataPermissions, "the two sheets must say one thing")
    }

    /// an unavailable build mentions Strava nowhere on the menu
    func testAnUnavailableBuildMentionsStravaNowhereOnTheMenu() {
        let page = menu(withoutStrava)
        var said = page.rows.flatMap { [$0.title, $0.subtitle, $0.spoken] } + [page.card.title, page.card.value]
        said.append(page.footnote ?? "")
        XCTAssertFalse(said.contains { $0.contains("Strava") }, "some menu text still says Strava")
    }

    // ---- the redirect -----------------------------------------------------------------------

    private func handler(_ transport: FakeTransport = FakeTransport(), _ config: StravaConfig? = nil) -> StravaRedirectHandler {
        StravaRedirectHandler(config: config ?? withStrava, transport: transport, tokens: tokens, ledger: ledger)
    }

    private var redirect: String { withStrava.redirectUri }

    /// the redirect activity ignores an intent with no pending state, and stores nothing
    func testTheRedirectIgnoresALinkWithNoPendingStateAndStoresNothing() async {
        tokens.pendingState = nil
        let transport = FakeTransport()
        let result = await handler(transport).handle("\(redirect)?state=whatever&code=somecode&scope=read,activity:write")

        XCTAssertEqual(result, .ignored)
        XCTAssertNil(tokens.grant)
        XCTAssertTrue(transport.requests.isEmpty, "nothing was exchanged")
    }

    /// the redirect activity ignores a bad state without crashing or storing anything
    func testTheRedirectIgnoresABadStateWithoutCrashingOrStoringAnything() async {
        tokens.pendingState = "expected"
        let transport = FakeTransport()
        let result = await handler(transport).handle("\(redirect)?state=wrong&code=somecode&scope=read,activity:write")

        XCTAssertEqual(result, .ignored)
        XCTAssertNil(tokens.grant)
        // The mismatch must not have cancelled the real pending attempt either.
        XCTAssertEqual(tokens.pendingState, "expected")
        XCTAssertTrue(transport.requests.isEmpty)
    }

    /// the redirect activity clears the pending state on a denial
    func testTheRedirectClearsThePendingStateOnADenial() async {
        tokens.pendingState = "expected"
        let result = await handler().handle("\(redirect)?state=expected&error=access_denied")

        XCTAssertEqual(result, .finished(message: "Not connected to Strava", connected: false))
        XCTAssertNil(tokens.grant)
        XCTAssertNil(tokens.pendingState)
    }

    /// the redirect URI resolves to the redirect activity, and only for this build's own scheme
    func testTheRedirectUriIsTheBuildsOwnBundleIdentifierAndNothingElse() throws {
        // The project's URL scheme is `$(PRODUCT_BUNDLE_IDENTIFIER)` and the constant is built from
        // the bundle identifier. If either is edited alone, Strava's redirect would stop reaching
        // the app, and nothing else in the suite would notice.
        let project = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("project.yml"), encoding: .utf8)
        let schemes = try XCTUnwrap(project.range(of: #"CFBundleURLSchemes:\s*\[([^\]]*)\]"#, options: .regularExpression)
            .map { String(project[$0]) })
        XCTAssertTrue(schemes.contains("$(PRODUCT_BUNDLE_IDENTIFIER)"), schemes)
        XCTAssertEqual(schemes.filter { $0 == "," }.count, 0, "one scheme, not a wildcard or a list: \(schemes)")

        let id = try XCTUnwrap(project.range(of: #"(?m)^\s*PRODUCT_BUNDLE_IDENTIFIER:\s*(\S+)\s*$"#, options: .regularExpression)
            .map { String(project[$0]).split(separator: ":")[1].trimmingCharacters(in: .whitespaces) })
        XCTAssertEqual(StravaConfig(clientId: "1", clientSecret: "s", applicationId: id).redirectUri, "\(id)://localhost/strava")
        // Another build's id, which is what a debug and a release build are to each other, must not match.
        XCTAssertNotEqual(StravaConfig(clientId: "1", clientSecret: "s", applicationId: "\(id).elsewhere").redirectUri,
                          "\(id)://localhost/strava")
    }

    // ---- the results screen's Strava row ----------------------------------------------------

    private func row(_ config: StravaConfig, atMillis: Int64) -> StravaRow? {
        StravaRow.of(config: config, tokens: tokens, ledger: ledger, atMillis: atMillis)
    }

    /// the results row is absent when Strava is unavailable
    func testTheResultsRowIsAbsentWhenStravaIsUnavailable() {
        XCTAssertNil(row(withoutStrava, atMillis: 101), "no Strava row must appear in a build with no credentials")
    }

    /// the results row offers to connect when not connected
    func testTheResultsRowOffersToConnectWhenNotConnected() {
        XCTAssertEqual(row(withStrava, atMillis: 102)?.value, "Connect to upload")
    }

    /// the results row offers a manual upload once connected with nothing queued
    func testTheResultsRowOffersAManualUploadOnceConnectedWithNothingQueued() {
        tokens.grant = testGrant()
        let offered = row(withStrava, atMillis: 103)
        XCTAssertEqual(offered?.value, "Upload")
        XCTAssertEqual(offered?.action, .upload)
    }

    /// the results row follows a queued upload in place, as one row
    func testTheResultsRowFollowsAQueuedUploadInPlaceAsOneRow() {
        tokens.grant = testGrant()
        XCTAssertEqual(row(withStrava, atMillis: 110)?.value, "Upload")

        ledger.queue(atMillis: 110)

        // The same call, one row, now saying where it has got to.
        XCTAssertEqual(row(withStrava, atMillis: 110)?.value, "Uploading…")
        XCTAssertNil(row(withStrava, atMillis: 110)?.action)
        XCTAssertEqual(StravaRow.label, "Strava")
    }

    /// the results row says uploading while queued or processing
    func testTheResultsRowSaysUploadingWhileQueuedOrProcessing() {
        tokens.grant = testGrant()
        ledger.write(atMillis: 104, StravaUploadStatus(.processing))
        XCTAssertEqual(row(withStrava, atMillis: 104)?.value, "Uploading…")
        ledger.write(atMillis: 111, StravaUploadStatus(.queued))
        XCTAssertEqual(row(withStrava, atMillis: 111)?.value, "Uploading…")
    }

    /// the results row links to the activity once done
    func testTheResultsRowLinksToTheActivityOnceDone() {
        tokens.grant = testGrant()
        ledger.write(atMillis: 105, StravaUploadStatus(.done, activityId: 42))
        let link = row(withStrava, atMillis: 105)
        XCTAssertEqual(link?.value, "View on Strava", "Strava asks for the link to read 'View on Strava'")
        // Strava's guidelines want the link bold, underlined or orange.
        XCTAssertEqual(link?.isLink, true)
        XCTAssertEqual(link?.action, .openActivity(42))
    }

    /// the results row offers a retry once failed
    func testTheResultsRowOffersARetryOnceFailed() {
        tokens.grant = testGrant()
        ledger.write(atMillis: 106, StravaUploadStatus(.failed, message: "nope"))
        let failed = row(withStrava, atMillis: 106)
        XCTAssertEqual(failed?.value, "Couldn't upload — tap to retry")
        XCTAssertEqual(failed?.action, .upload)
    }

    /// the results row asks to reconnect once the grant is gone
    func testTheResultsRowAsksToReconnectOnceTheGrantIsGone() {
        tokens.grant = testGrant()
        ledger.write(atMillis: 107, StravaUploadStatus(.needsReconnect))
        XCTAssertEqual(row(withStrava, atMillis: 107)?.value, "Reconnect to upload")
    }

    /// the results row says an old attempt cannot be uploaded
    func testTheResultsRowSaysAnOldAttemptCannotBeUploaded() {
        tokens.grant = testGrant()
        ledger.write(atMillis: 108, StravaUploadStatus(.unavailable))
        let old = row(withStrava, atMillis: 108)
        XCTAssertEqual(old?.value, "Not available for this attempt")
        XCTAssertNil(old?.action)
    }

    // ---- beyond the Kotlin: the redirect through to a connected athlete ---------------------

    private let grantReply = HttpResponse(200, [:], """
        {"access_token":"a1","refresh_token":"r1","expires_at":1700000000,"scope":"read,activity:write",
         "athlete":{"firstname":"Alex","lastname":"G"}}
        """)

    /// a good redirect connects, requeues what waited for it, and uploads the attempt that sent the athlete here
    func testAGoodRedirectConnectsRequeuesWhatWaitedForItAndUploadsTheAttemptThatSentTheAthleteHere() async {
        tokens.pendingState = "expected"
        tokens.afterConnectUploadAtMillis = 303
        ledger.write(atMillis: 100, StravaUploadStatus(.needsReconnect))
        ledger.write(atMillis: 200, StravaUploadStatus(.done, activityId: 5))
        let transport = FakeTransport()
        transport.enqueue(grantReply)

        let result = await handler(transport).handle("\(redirect)?state=expected&code=thecode&scope=read,activity:write")

        XCTAssertEqual(result, .finished(message: "Connected to Strava as Alex G", connected: true))
        XCTAssertEqual(tokens.grant?.accessToken, "a1")
        XCTAssertNil(tokens.pendingState)
        XCTAssertNil(tokens.afterConnectUploadAtMillis)
        XCTAssertEqual(ledger.status(atMillis: 100)?.state, .queued)
        XCTAssertEqual(ledger.status(atMillis: 303)?.state, .queued)
        XCTAssertEqual(ledger.status(atMillis: 200)?.state, .done)
        XCTAssertTrue(String(decoding: transport.requests[0].body ?? Data(), as: UTF8.self).contains("code=thecode"))
    }

    /// a redirect that cannot be exchanged says so once and stores nothing
    func testARedirectThatCannotBeExchangedSaysSoOnceAndStoresNothing() async {
        for reply in [HttpResponse(400, [:], "{}"), HttpResponse(200, [:], "not json")] {
            tokens.pendingState = "expected"
            let transport = FakeTransport()
            transport.enqueue(reply)
            let result = await handler(transport).handle("\(redirect)?state=expected&code=c&scope=activity:write")
            XCTAssertEqual(result, .finished(message: StravaRedirectHandler.couldNotConnect, connected: false))
            XCTAssertNil(tokens.grant)
            XCTAssertNil(tokens.pendingState, "the attempt is over either way")
        }
        let offline = FakeTransport()
        offline.enqueueFailure(HttpTransportError("offline"))
        tokens.pendingState = "expected"
        let result = await handler(offline).handle("\(redirect)?state=expected&code=c&scope=activity:write")
        XCTAssertEqual(result, .finished(message: StravaRedirectHandler.couldNotConnect, connected: false))
    }

    /// a redirect without the write scope says what is needed
    func testARedirectWithoutTheWriteScopeSaysWhatIsNeeded() async {
        tokens.pendingState = "expected"
        let result = await handler().handle("\(redirect)?state=expected&code=c&scope=read")
        XCTAssertEqual(result, .finished(message: "Strava needs permission to upload activities to connect", connected: false))
        XCTAssertNil(tokens.pendingState)
        XCTAssertNil(tokens.grant)
    }

    /// disconnecting forgets the grant first, and asks Strava best-effort with the refresh token
    func testDisconnectingForgetsTheGrantFirstAndAsksStravaBestEffortWithTheRefreshToken() async throws {
        tokens.grant = testGrant()
        let transport = FakeTransport()
        transport.enqueue(HttpResponse(200, [:], ""))
        let auth = StravaAuth(transport: transport, config: withStrava)

        await StravaDisconnect.run(tokens: tokens, auth: auth)

        XCTAssertNil(tokens.grant)
        let sent = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(sent.url, "\(StravaConfig.oauthBase)/revoke")
        let form = String(decoding: sent.body ?? Data(), as: UTF8.self)
        XCTAssertTrue(form.contains("token=r") && form.contains("token_type_hint=refresh_token"), form)

        // Offline, or already removed on strava.com: the phone still lets go.
        tokens.grant = testGrant()
        let offline = FakeTransport()
        offline.enqueueFailure(HttpTransportError("offline"))
        await StravaDisconnect.run(tokens: tokens, auth: StravaAuth(transport: offline, config: withStrava))
        XCTAssertNil(tokens.grant)
    }

    /// the connected sheet says only what the switch makes true
    func testTheConnectedSheetSaysOnlyWhatTheSwitchMakesTrue() {
        XCTAssertEqual(StravaSheet.subtitle(athleteName: "Alex G", autoUpload: true),
                       "Connected as Alex G. Each finished workout uploads to Strava on its own.")
        XCTAssertEqual(StravaSheet.subtitle(athleteName: nil, autoUpload: false),
                       "Connected. Automatic upload is off — upload from a workout's results screen instead.")
    }
}
