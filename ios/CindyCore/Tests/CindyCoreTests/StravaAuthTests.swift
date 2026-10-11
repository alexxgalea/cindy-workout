import XCTest
import CindyCore

/// OAuth: the URL that opens the consent page, what a redirect meant, and the three token calls.
///
/// Mirrors `StravaAuthTest.kt`. The credentials are made up here; on Android the test reads whatever
/// the build was given, which is empty in CI.
final class StravaAuthTests: XCTestCase {

    private let config = StravaConfig(clientId: "12345", clientSecret: "s3cret", applicationId: "com.cindy.tracker")

    private func text(_ data: Data?) -> String { String(decoding: data ?? Data(), as: UTF8.self) }

    /// `URLDecoder.decode(value, "UTF-8")`.
    private func formDecode(_ value: String) -> String {
        value.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? value
    }

    // ---- authorizeUri -----------------------------------------------------------------------

    /// the authorize URL carries every required param
    func testTheAuthorizeUrlCarriesEveryRequiredParam() {
        let uri = StravaAuth.authorizeUri(state: "abc123", config: config)
        XCTAssertTrue(uri.hasPrefix("https://www.strava.com/oauth/mobile/authorize?"))
        var query: [String: String] = [:]
        for pair in uri.split(separator: "?", maxSplits: 1)[1].split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            query[String(parts[0])] = String(parts[1])
        }
        XCTAssertEqual(query["client_id"], "12345")
        XCTAssertEqual(query["response_type"], "code")
        XCTAssertEqual(query["approval_prompt"], "auto")
        XCTAssertEqual(formDecode(query["scope"]!), StravaConfig.scope)
        XCTAssertEqual(formDecode(query["redirect_uri"]!), config.redirectUri)
        XCTAssertEqual(query["state"], "abc123")
    }

    // ---- newState -----------------------------------------------------------------------------

    /// newState is 32 hex characters, and two calls do not collide
    func testNewStateIs32HexCharactersAndTwoCallsDoNotCollide() {
        let a = StravaAuth.newState()
        let b = StravaAuth.newState()
        XCTAssertEqual(a.count, 32)
        XCTAssertNotNil(a.range(of: "^[0-9a-f]{32}$", options: .regularExpression))
        XCTAssertNotEqual(a, b)
    }

    // ---- parseRedirect --------------------------------------------------------------------------

    private var redirect: String { config.redirectUri }

    private func parse(_ uri: String, _ expected: String = "xyz") -> RedirectResult {
        StravaAuth.parseRedirect(uri, expectedState: expected)
    }

    /// a matching state with a code and the write scope parses as Code
    func testAMatchingStateWithACodeAndTheWriteScopeParsesAsCode() {
        let result = parse("\(redirect)?state=xyz&code=abc123&scope=read,activity:write")
        XCTAssertEqual(result, .code("abc123", scopes: ["read", "activity:write"]))
    }

    /// a space-delimited scope is accepted the same as a comma-delimited one
    func testASpaceDelimitedScopeIsAcceptedTheSameAsACommaDelimitedOne() {
        let result = parse("\(redirect)?state=xyz&code=abc123&scope=read%20activity:write")
        XCTAssertEqual(result, .code("abc123", scopes: ["read", "activity:write"]))
    }

    /// a wrong state is a mismatch even when the rest of the redirect is well-formed
    func testAWrongStateIsAMismatchEvenWhenTheRestOfTheRedirectIsWellFormed() {
        XCTAssertEqual(parse("\(redirect)?state=wrong&code=abc123&scope=read,activity:write"), .stateMismatch)
    }

    /// a missing state is a mismatch, not malformed
    func testAMissingStateIsAMismatchNotMalformed() {
        XCTAssertEqual(parse("\(redirect)?code=abc123"), .stateMismatch)
    }

    /// a denial is reported only once the state has been checked
    func testADenialIsReportedOnlyOnceTheStateHasBeenChecked() {
        XCTAssertEqual(parse("\(redirect)?state=xyz&error=access_denied"), .denied)
    }

    /// a denial with the wrong state is a mismatch, not reported as a denial
    func testADenialWithTheWrongStateIsAMismatchNotReportedAsADenial() {
        XCTAssertEqual(parse("\(redirect)?state=wrong&error=access_denied"), .stateMismatch)
    }

    /// a matching state with no write scope is reported so, not as a plain Code
    func testAMatchingStateWithNoWriteScopeIsReportedSoNotAsAPlainCode() {
        XCTAssertEqual(parse("\(redirect)?state=xyz&code=abc123&scope=read"), .missingWriteScope)
    }

    /// a matching state with neither a code nor an error is malformed
    func testAMatchingStateWithNeitherACodeNorAnErrorIsMalformed() {
        XCTAssertEqual(parse("\(redirect)?state=xyz"), .malformed)
    }

    /// a redirect with no query at all is malformed
    func testARedirectWithNoQueryAtAllIsMalformed() {
        XCTAssertEqual(parse(redirect), .malformed)
    }

    /// a bad percent-escape is malformed rather than throwing
    func testABadPercentEscapeIsMalformedRatherThanThrowing() {
        XCTAssertEqual(parse("\(redirect)?state=%zz&code=abc123"), .malformed)
    }

    /// an unparseable uri is malformed rather than throwing
    func testAnUnparseableUriIsMalformedRatherThanThrowing() {
        XCTAssertEqual(parse("not a uri at all ??"), .malformed)
    }

    // ---- exchange ----------------------------------------------------------------------------------

    /// exchange posts the authorization_code grant and reads the grant back
    func testExchangePostsTheAuthorizationCodeGrantAndReadsTheGrantBack() async throws {
        let transport = FakeTransport()
        transport.enqueue(HttpResponse(200, [:], """
            {"access_token":"a1","refresh_token":"r1","expires_at":1700000000,
             "scope":"read,activity:write","athlete":{"firstname":"Alex","lastname":"G"}}
            """))

        let grant = try await StravaAuth(transport: transport, config: config).exchange("thecode")

        let sent = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(sent.method, "POST")
        XCTAssertEqual(sent.url, "\(StravaConfig.apiBase)/oauth/token")
        let form = text(sent.body)
        XCTAssertTrue(form.contains("grant_type=authorization_code"))
        XCTAssertTrue(form.contains("code=thecode"))
        XCTAssertTrue(form.contains("client_id=12345"))
        XCTAssertTrue(form.contains("client_secret=s3cret"))
        XCTAssertEqual(grant.accessToken, "a1")
        XCTAssertEqual(grant.refreshToken, "r1")
        XCTAssertEqual(grant.expiresAtEpochS, 1700000000)
        XCTAssertEqual(grant.scopes, ["read", "activity:write"])
        XCTAssertEqual(grant.athleteName, "Alex G")
    }

    /// exchange tolerates a response with no athlete object
    func testExchangeToleratesAResponseWithNoAthleteObject() async throws {
        let transport = FakeTransport()
        transport.enqueue(HttpResponse(
            200, [:], #"{"access_token":"a1","refresh_token":"r1","expires_at":1700000000,"scope":"read"}"#))
        let grant = try await StravaAuth(transport: transport, config: config).exchange("thecode")
        XCTAssertNil(grant.athleteName)
    }

    /// exchange throws a plain auth exception on an http error, never marked revoked
    func testExchangeThrowsAPlainAuthErrorOnAnHttpErrorNeverMarkedRevoked() async {
        let transport = FakeTransport()
        transport.enqueue(HttpResponse(400, [:], #"{"message":"Bad Request"}"#))
        let error = await thrownError { _ = try await StravaAuth(transport: transport, config: config).exchange("thecode") }
        XCTAssertEqual((error as? StravaAuthError)?.revoked, false)
    }

    // ---- refresh -------------------------------------------------------------------------------------

    /// refresh posts the refresh_token grant
    func testRefreshPostsTheRefreshTokenGrant() async throws {
        let transport = FakeTransport()
        transport.enqueue(HttpResponse(
            200, [:], #"{"access_token":"a2","refresh_token":"r2","expires_at":1700003600,"scope":"read,activity:write"}"#))
        let grant = try await StravaAuth(transport: transport, config: config).refresh("oldRefresh")
        let form = text(transport.requests.first?.body)
        XCTAssertTrue(form.contains("grant_type=refresh_token"))
        XCTAssertTrue(form.contains("refresh_token=oldRefresh"))
        XCTAssertEqual(grant.accessToken, "a2")
        XCTAssertEqual(grant.refreshToken, "r2")
    }

    /// refresh on a 401 throws a revoked auth exception
    func testRefreshOnA401ThrowsARevokedAuthError() async {
        let transport = FakeTransport()
        transport.enqueue(HttpResponse(401, [:], #"{"message":"Unauthorized"}"#))
        let error = await thrownError { _ = try await StravaAuth(transport: transport, config: config).refresh("oldRefresh") }
        XCTAssertEqual((error as? StravaAuthError)?.revoked, true)
    }

    /// refresh on a 400 also throws a revoked auth exception
    func testRefreshOnA400AlsoThrowsARevokedAuthError() async {
        let transport = FakeTransport()
        transport.enqueue(HttpResponse(400, [:], #"{"message":"Bad Request"}"#))
        let error = await thrownError { _ = try await StravaAuth(transport: transport, config: config).refresh("oldRefresh") }
        XCTAssertEqual((error as? StravaAuthError)?.revoked, true)
    }

    /// refresh on a 500 throws a plain, non-revoked auth exception
    func testRefreshOnA500ThrowsAPlainNonRevokedAuthError() async {
        let transport = FakeTransport()
        transport.enqueue(HttpResponse(500, [:], "oops"))
        let error = await thrownError { _ = try await StravaAuth(transport: transport, config: config).refresh("oldRefresh") }
        XCTAssertEqual((error as? StravaAuthError)?.revoked, false)
    }

    /// a network failure during refresh propagates as an IOException, not swallowed
    func testANetworkFailureDuringRefreshPropagatesAsATransportErrorNotSwallowed() async {
        let transport = FakeTransport()
        transport.enqueueFailure(HttpTransportError("no network"))
        let error = await thrownError { _ = try await StravaAuth(transport: transport, config: config).refresh("oldRefresh") }
        XCTAssertEqual(error as? HttpTransportError, HttpTransportError("no network"))
    }

    // ---- revoke --------------------------------------------------------------------------------------

    /// revoke sends Basic auth and the token plus its hint as form fields
    func testRevokeSendsBasicAuthAndTheTokenPlusItsHintAsFormFields() async throws {
        let transport = FakeTransport()
        transport.enqueue(HttpResponse(200, [:], ""))

        try await StravaAuth(transport: transport, config: config).revoke("sometoken", tokenTypeHint: "refresh_token")

        let sent = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(sent.method, "POST")
        XCTAssertEqual(sent.url, "\(StravaConfig.oauthBase)/revoke")
        let authorization = try XCTUnwrap(sent.headers["Authorization"])
        XCTAssertTrue(authorization.hasPrefix("Basic "))
        let decoded = String(decoding: try XCTUnwrap(Data(base64Encoded: String(authorization.dropFirst("Basic ".count)))),
                             as: UTF8.self)
        XCTAssertEqual(decoded, "12345:s3cret")
        let form = text(sent.body)
        XCTAssertTrue(form.contains("token=sometoken"))
        XCTAssertTrue(form.contains("token_type_hint=refresh_token"))
    }

    /// revoke throws on an http error, so a best-effort caller can catch and ignore it
    func testRevokeThrowsOnAnHttpErrorSoABestEffortCallerCanCatchAndIgnoreIt() async {
        let transport = FakeTransport()
        transport.enqueue(HttpResponse(401, [:], #"{"message":"Unauthorized"}"#))
        let error = await thrownError {
            try await StravaAuth(transport: transport, config: config).revoke("sometoken", tokenTypeHint: "access_token")
        }
        // The caller decides what "best-effort" means, not this type.
        XCTAssertNotNil(error as? StravaAuthError)
    }

    // ---- beyond the Kotlin: the parts Java's URI and org.json did for it ----------------------------------

    /// with no attempt in flight nothing matches, not even an empty state
    func testWithNoAttemptInFlightNothingMatchesNotEvenAnEmptyState() {
        let crafted = "\(redirect)?state=&code=attacker&scope=read,activity:write"
        XCTAssertEqual(StravaAuth.parseRedirect(crafted, expectedState: nil), .stateMismatch)
        XCTAssertEqual(StravaAuth.parseRedirect(crafted, expectedState: ""), .stateMismatch)
        XCTAssertEqual(StravaAuth.parseRedirect("\(redirect)?code=attacker", expectedState: nil), .stateMismatch)
        // A redirect that is not even a URI is still malformed, whatever is expected.
        XCTAssertEqual(StravaAuth.parseRedirect("not a uri ??", expectedState: nil), .malformed)
    }

    /// a fragment after the query is not part of it, and a second one makes the URI malformed
    func testAFragmentAfterTheQueryIsNotPartOfItAndASecondOneMakesTheUriMalformed() {
        XCTAssertEqual(parse("\(redirect)?state=xyz&code=abc&scope=activity:write#done"),
                       .code("abc", scopes: ["activity:write"]))
        XCTAssertEqual(parse("\(redirect)?state=xyz&code=abc#a#b"), .malformed)
    }

    /// a name that comes twice keeps its last value, and a plus in a value is a space
    func testANameThatComesTwiceKeepsItsLastValueAndAPlusInAValueIsASpace() {
        XCTAssertEqual(parse("\(redirect)?state=old&state=xyz&code=a+b&scope=activity:write"),
                       .code("a b", scopes: ["activity:write"]))
    }

    /// an opaque uri has no query, so it is malformed however much it looks like one
    func testAnOpaqueUriHasNoQuerySoItIsMalformedHoweverMuchItLooksLikeOne() {
        XCTAssertEqual(parse("com.cindy.tracker:strava?state=xyz&code=abc&scope=activity:write"), .malformed)
        XCTAssertEqual(parse(":?state=xyz"), .malformed)
        XCTAssertEqual(parse("1x://localhost/strava?state=xyz"), .malformed)
    }

    /// a character Java's URI refuses makes a redirect malformed, and one it allows does not
    func testACharacterJavasUriRefusesMakesARedirectMalformedAndOneItAllowsDoesNot() {
        XCTAssertEqual(parse("\(redirect)?state=xyz&code=a|b"), .malformed)
        XCTAssertEqual(parse("\(redirect)?state=xyz&code=a\"b"), .malformed)
        XCTAssertEqual(parse("\(redirect)?state=xyz&code=a%"), .malformed)
        XCTAssertEqual(parse("\(redirect)?state=xyz&code=a[b]&scope=activity:write"),
                       .code("a[b]", scopes: ["activity:write"]))
        // Checked against java.net.URI: a no-break space and a bracket in the path are refused,
        // an accented letter and a bracket in the query are not.
        XCTAssertEqual(parse("\(redirect)?state=xyz&code=a\u{A0}b"), .malformed)
        XCTAssertEqual(parse("com.cindy.tracker://localhost/a[b]?state=xyz&code=c&scope=activity:write"), .malformed)
        XCTAssertEqual(parse("\(redirect)?state=xyz&code=caf\u{E9}&scope=activity:write"),
                       .code("café", scopes: ["activity:write"]))
        XCTAssertEqual(parse("com.cindy.tracker:"), .malformed)
    }

    /// a token reply that is not JSON, or lacks a token, is unreadable rather than a grant
    func testATokenReplyThatIsNotJsonOrLacksATokenIsUnreadableRatherThanAGrant() async {
        for body in ["not json", "[]", #"{"refresh_token":"r","expires_at":1}"#, #"{"access_token":"a","refresh_token":"r"}"#] {
            let transport = FakeTransport()
            transport.enqueue(HttpResponse(200, [:], body))
            let error = await thrownError { _ = try await StravaAuth(transport: transport, config: config).exchange("c") }
            XCTAssertNotNil(error as? StravaResponseError, body)
        }
    }

    /// the athlete's name joins what is there, and Android reads a null name as the word null
    func testTheAthletesNameJoinsWhatIsThereAndAndroidReadsANullNameAsTheWordNull() async throws {
        func name(_ athlete: String) async throws -> String? {
            let transport = FakeTransport()
            transport.enqueue(HttpResponse(
                200, [:], #"{"access_token":"a","refresh_token":"r","expires_at":1,"athlete":\#(athlete)}"#))
            return try await StravaAuth(transport: transport, config: config).exchange("c").athleteName
        }
        let first = try await name(#"{"firstname":"Alex","lastname":""}"#)
        let last = try await name(#"{"firstname":" ","lastname":"G"}"#)
        let none = try await name(#"{"firstname":"","lastname":""}"#)
        let null = try await name(#"{"firstname":null,"lastname":"G"}"#)
        XCTAssertEqual(first, "Alex")
        XCTAssertEqual(last, "G")
        XCTAssertNil(none)
        XCTAssertEqual(null, "null G")
    }
}
