import XCTest
import CindyCore

/// The upload endpoint: the request it sends and how every answer is classified.
///
/// Mirrors `StravaApiTest.kt`.
final class StravaApiTests: XCTestCase {

    private func tokenOf(_ value: String) -> StravaAccessToken { ClosureAccessToken { value } }

    private func boundaryOf(_ request: HttpRequest) throws -> String {
        let contentType = try XCTUnwrap(request.contentType)
        let marker = try XCTUnwrap(contentType.range(of: "boundary="))
        return String(contentType[marker.upperBound...])
    }

    private func text(_ data: Data) -> String { String(decoding: data, as: UTF8.self) }

    private func isTransient(_ outcome: UploadOutcome) -> Bool {
        if case .transient = outcome { return true }
        return false
    }

    private let accepted = HttpResponse(201, [:], #"{"id_str":"1","error":null,"activity_id":null}"#)

    // ---- upload: request shape -------------------------------------------------------------

    /// upload posts to base uploads with the bearer header
    func testUploadPostsToBaseUploadsWithTheBearerHeader() async throws {
        let transport = FakeTransport()
        transport.enqueue(accepted)

        _ = try await StravaApi(transport: transport, token: tokenOf("tok-123"))
            .upload(json: "{}", name: "name", description: "desc", externalId: "cindy-1")

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.url, "https://www.strava.com/api/v3/uploads")
        XCTAssertEqual(request.headers["Authorization"], "Bearer tok-123")
    }

    /// upload sends the exact multipart fields, in the order Strava documents them
    func testUploadSendsTheExactMultipartFieldsInTheOrderStravaDocumentsThem() async throws {
        let transport = FakeTransport()
        transport.enqueue(accepted)
        let json = #"{"version":"1.0","elapsed_time":1200}"#

        _ = try await StravaApi(transport: transport, token: tokenOf("t"))
            .upload(json: json, name: "Cindy — 17 + 12", description: "Counted by Cindy Tracker",
                    externalId: "cindy-1700000000000")

        let request = try XCTUnwrap(transport.requests.first)
        let boundary = try boundaryOf(request)
        let body = text(try XCTUnwrap(request.body))
        let expected = [
            "--\(boundary)\r\n" +
                "Content-Disposition: form-data; name=\"file\"; filename=\"cindy-1700000000000.json\"\r\n" +
                "Content-Type: application/json\r\n" +
                "\r\n" + json + "\r\n",
            "--\(boundary)\r\nContent-Disposition: form-data; name=\"data_type\"\r\n\r\njson\r\n",
            "--\(boundary)\r\nContent-Disposition: form-data; name=\"sport_type\"\r\n\r\nCrossfit\r\n",
            // The em dash proves the field survives as real UTF-8, not just ASCII.
            "--\(boundary)\r\nContent-Disposition: form-data; name=\"name\"\r\n\r\nCindy — 17 + 12\r\n",
            "--\(boundary)\r\nContent-Disposition: form-data; name=\"description\"\r\n\r\nCounted by Cindy Tracker\r\n",
            "--\(boundary)\r\nContent-Disposition: form-data; name=\"external_id\"\r\n\r\ncindy-1700000000000\r\n",
            "--\(boundary)--\r\n"
        ].joined()
        XCTAssertEqual(body, expected)
    }

    /// upload carries the payload json through byte for byte
    func testUploadCarriesThePayloadJsonThroughByteForByte() async throws {
        let transport = FakeTransport()
        transport.enqueue(accepted)
        // Bytes a naive text copy could mangle: a CRLF-like sequence and a multibyte character.
        let json = "{\"note\":\"line1\\r\\nline2 café\"}"

        _ = try await StravaApi(transport: transport, token: tokenOf("t"))
            .upload(json: json, name: "n", description: "d", externalId: "cindy-2")

        let body = text(try XCTUnwrap(transport.requests.first?.body))
        XCTAssertTrue(body.contains(json))
    }

    // ---- status: request shape --------------------------------------------------------------

    /// status polls the upload by id with the bearer header
    func testStatusPollsTheUploadByIdWithTheBearerHeader() async throws {
        let transport = FakeTransport()
        transport.enqueue(HttpResponse(200, [:], #"{"id_str":"555","error":null,"activity_id":null}"#))

        _ = try await StravaApi(transport: transport, token: tokenOf("secret-token")).status("555")

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(request.url, "https://www.strava.com/api/v3/uploads/555")
        XCTAssertEqual(request.headers["Authorization"], "Bearer secret-token")
    }

    /// a custom base is honoured for both endpoints
    func testACustomBaseIsHonouredForBothEndpoints() async throws {
        let transport = FakeTransport()
        let reply = HttpResponse(200, [:], #"{"id_str":"1","error":null,"activity_id":null}"#)
        transport.enqueue(reply)
        transport.enqueue(reply)
        let api = StravaApi(transport: transport, token: tokenOf("t"), base: "https://example.invalid/api/v3")

        _ = try await api.status("1")
        _ = try await api.upload(json: "{}", name: "n", description: "d", externalId: "cindy-1")

        XCTAssertEqual(transport.requests[0].url, "https://example.invalid/api/v3/uploads/1")
        XCTAssertEqual(transport.requests[1].url, "https://example.invalid/api/v3/uploads")
    }

    // ---- activityUrl -----------------------------------------------------------------------------

    /// activityUrl points at strava's own activity page
    func testActivityUrlPointsAtStravasOwnActivityPage() {
        let url = StravaApi(transport: FakeTransport(), token: tokenOf("t")).activityUrl(21234316)
        XCTAssertEqual(url, "https://www.strava.com/activities/21234316")
        XCTAssertEqual(StravaApi.activityUrl(21234316), url)
    }

    // ---- classification: success ------------------------------------------------------------------

    private func status(_ response: HttpResponse, id: String = "1") async throws -> UploadOutcome {
        let transport = FakeTransport()
        transport.enqueue(response)
        return try await StravaApi(transport: transport, token: tokenOf("t")).status(id)
    }

    /// no error and no activity id means still processing, keyed by the 64-bit id_str
    func testNoErrorAndNoActivityIdMeansStillProcessingKeyedByThe64BitIdStr() async throws {
        let bigId = "12345678901234567"  // outside Int range, and precise only as a string
        let outcome = try await status(
            HttpResponse(200, [:], #"{"id":\#(bigId),"id_str":"\#(bigId)","error":null,"activity_id":null}"#), id: bigId)
        XCTAssertEqual(outcome, .processing(uploadId: bigId))
    }

    /// a 201 with no activity id is processing too
    func testA201WithNoActivityIdIsProcessingToo() async throws {
        let outcome = try await status(accepted)
        XCTAssertEqual(outcome, .processing(uploadId: "1"))
    }

    /// an activity id means the upload is ready
    func testAnActivityIdMeansTheUploadIsReady() async throws {
        let outcome = try await status(HttpResponse(200, [:], #"{"id_str":"1","error":null,"activity_id":21234316}"#))
        XCTAssertEqual(outcome, .ready(activityId: 21234316))
    }

    // ---- classification: duplicate -----------------------------------------------------------------

    /// a duplicate error names the existing activity
    func testADuplicateErrorNamesTheExistingActivity() async throws {
        let outcome = try await status(HttpResponse(
            200, [:], #"{"id_str":"1","error":"club.gpx duplicate of activity 21234316","activity_id":null}"#))
        XCTAssertEqual(outcome, .duplicate(activityId: 21234316))
    }

    /// a duplicate error given as an html link still yields the activity id
    func testADuplicateErrorGivenAsAnHtmlLinkStillYieldsTheActivityId() async throws {
        let outcome = try await status(HttpResponse(
            200, [:], #"{"id_str":"1","error":"Duplicate of <a href='/activities/123'>this activity</a>","activity_id":null}"#))
        XCTAssertEqual(outcome, .duplicate(activityId: 123))
    }

    /// a duplicate error with no parsable id is still a duplicate, not a rejection
    func testADuplicateErrorWithNoParsableIdIsStillADuplicateNotARejection() async throws {
        let outcome = try await status(HttpResponse(
            200, [:], #"{"id_str":"1","error":"This file is a duplicate of a previous upload","activity_id":null}"#))
        XCTAssertEqual(outcome, .duplicate(activityId: nil))
    }

    // ---- classification: rejected, unauthorized, rate-limited ----------------------------------------

    /// a non-duplicate error rejects with strava's own message
    func testANonDuplicateErrorRejectsWithStravasOwnMessage() async throws {
        let outcome = try await status(HttpResponse(
            200, [:], #"{"id_str":"1","error":"There was an error processing your activity.","activity_id":null}"#))
        XCTAssertEqual(outcome, .rejected(message: "There was an error processing your activity."))
    }

    /// 401 is unauthorized, not a permanent rejection
    func testA401IsUnauthorizedNotAPermanentRejection() async throws {
        let outcome = try await status(HttpResponse(401, [:], #"{"message":"Authorization Error"}"#))
        XCTAssertEqual(outcome, .unauthorized)
    }

    /// 429 reads Retry-After even when the header name's casing differs
    func testA429ReadsRetryAfterEvenWhenTheHeaderNamesCasingDiffers() async throws {
        let outcome = try await status(HttpResponse(429, ["retry-after": ["120"]], "{}"))
        XCTAssertEqual(outcome, .rateLimited(retryAfterS: 120))
    }

    /// 429 also reads a fully upper-cased Retry-After header
    func testA429AlsoReadsAFullyUpperCasedRetryAfterHeader() async throws {
        let outcome = try await status(HttpResponse(429, ["RETRY-AFTER": ["30"]], "{}"))
        XCTAssertEqual(outcome, .rateLimited(retryAfterS: 30))
    }

    /// 429 with no Retry-After header still rate-limits, with no known wait
    func testA429WithNoRetryAfterHeaderStillRateLimitsWithNoKnownWait() async throws {
        let outcome = try await status(HttpResponse(429, [:], "{}"))
        XCTAssertEqual(outcome, .rateLimited(retryAfterS: nil))
    }

    /// a 404 rejects using the body's own message
    func testA404RejectsUsingTheBodysOwnMessage() async throws {
        let outcome = try await status(HttpResponse(404, [:], #"{"message":"Record Not Found"}"#), id: "999")
        XCTAssertEqual(outcome, .rejected(message: "Record Not Found"))
    }

    /// a 4xx with no usable body message falls back to the http code
    func testA4xxWithNoUsableBodyMessageFallsBackToTheHttpCode() async throws {
        let outcome = try await status(HttpResponse(403, [:], "not json"))
        XCTAssertEqual(outcome, .rejected(message: "HTTP 403"))
    }

    // ---- classification: redirects, server errors, transport failures, malformed bodies ----------------

    /// a redirect is refused rather than silently chased or mistaken for something else
    func testARedirectIsRefusedRatherThanSilentlyChasedOrMistakenForSomethingElse() async throws {
        let outcome = try await status(HttpResponse(302, ["Location": ["https://example.invalid"]], ""))
        XCTAssertEqual(outcome, .rejected(message: "Unexpected redirect (HTTP 302)"))
    }

    /// a 5xx is transient, worth retrying later
    func testA5xxIsTransientWorthRetryingLater() async throws {
        let outcome = try await status(HttpResponse(503, [:], "Service Unavailable"))
        XCTAssertEqual(outcome, .transient(reason: "HTTP 503"))
    }

    /// an IOException from the transport is transient
    func testATransportErrorFromTheTransportIsTransient() async throws {
        let transport = FakeTransport()
        transport.enqueueFailure(HttpTransportError("no network"))

        let outcome = try await StravaApi(transport: transport, token: tokenOf("t")).status("1")

        XCTAssertEqual(outcome, .transient(reason: "no network"))
    }

    /// a malformed 2xx body is transient, not a permanent rejection
    func testAMalformed2xxBodyIsTransientNotAPermanentRejection() async throws {
        let outcome = try await status(HttpResponse(200, [:], "not valid json {"))
        XCTAssertTrue(isTransient(outcome))
    }

    // ---- the token seam ------------------------------------------------------------------------------------

    /// a revoked token propagates from status, and no request is sent
    func testARevokedTokenPropagatesFromStatusAndNoRequestIsSent() async {
        let transport = FakeTransport()
        let revoked = ClosureAccessToken { throw StravaAuthError(revoked: true) }

        let error = await thrownError { _ = try await StravaApi(transport: transport, token: revoked).status("1") }

        XCTAssertEqual((error as? StravaAuthError)?.revoked, true)
        XCTAssertTrue(transport.requests.isEmpty)
    }

    /// a token that cannot produce one propagates from upload too, with nothing sent
    func testATokenThatCannotProduceOnePropagatesFromUploadTooWithNothingSent() async {
        let transport = FakeTransport()
        let notConnected = ClosureAccessToken { throw StravaAuthError() }

        let error = await thrownError {
            _ = try await StravaApi(transport: transport, token: notConnected)
                .upload(json: "{}", name: "n", description: "d", externalId: "cindy-1")
        }

        XCTAssertEqual(error as? StravaAuthError, StravaAuthError())
        XCTAssertTrue(transport.requests.isEmpty)
    }

    // ---- beyond the Kotlin: how Android's JSON reader answers what Strava could send ------------------------

    private func outcomes(_ responses: [HttpResponse]) async throws -> [UploadOutcome] {
        var out: [UploadOutcome] = []
        for response in responses { out.append(try await status(response)) }
        return out
    }

    /// a body that is valid JSON but not an object is no activity
    func testABodyThatIsValidJsonButNotAnObjectIsNoActivity() async throws {
        let got = try await outcomes([
            HttpResponse(200, [:], "[1,2]"), HttpResponse(200, [:], ""), HttpResponse(400, [:], "[1,2]")
        ])
        XCTAssertTrue(isTransient(got[0]))
        XCTAssertTrue(isTransient(got[1]))
        XCTAssertEqual(got[2], .rejected(message: "HTTP 400"))
    }

    /// a success body with neither an activity id nor an id_str is transient
    func testASuccessBodyWithNeitherAnActivityIdNorAnIdStrIsTransient() async throws {
        let got = try await outcomes([HttpResponse(200, [:], #"{"error":null}"#)])
        XCTAssertTrue(isTransient(got[0]))
    }

    /// an activity id sent as a string, or as a number with a fraction, still reads as one
    func testAnActivityIdSentAsAStringOrAsANumberWithAFractionStillReadsAsOne() async throws {
        let got = try await outcomes([
            HttpResponse(200, [:], #"{"id_str":"1","activity_id":"77"}"#),
            HttpResponse(200, [:], #"{"id_str":"1","activity_id":77.9}"#),
            HttpResponse(200, [:], #"{"id_str":"1","activity_id":"abc"}"#),
            HttpResponse(200, [:], #"{"id_str":"1","activity_id":true}"#)
        ])
        XCTAssertEqual(got[0], .ready(activityId: 77))
        XCTAssertEqual(got[1], .ready(activityId: 77))
        XCTAssertTrue(isTransient(got[2]))
        XCTAssertTrue(isTransient(got[3]))
    }

    /// a 4xx prefers message over error, and an error that is not text is read as its text
    func testA4xxPrefersMessageOverErrorAndAnErrorThatIsNotTextIsReadAsItsText() async throws {
        let got = try await outcomes([
            HttpResponse(422, [:], #"{"message":"m","error":"e"}"#),
            HttpResponse(422, [:], #"{"message":null,"error":"e"}"#),
            HttpResponse(422, [:], #"{"error":42}"#)
        ])
        XCTAssertEqual(got, [.rejected(message: "m"), .rejected(message: "e"), .rejected(message: "42")])
    }

    /// a Retry-After that is not a whole number is no wait at all
    func testARetryAfterThatIsNotAWholeNumberIsNoWaitAtAll() async throws {
        let got = try await outcomes([
            HttpResponse(429, ["Retry-After": ["soon"]], "{}"), HttpResponse(429, ["Retry-After": ["1.5"]], "{}")
        ])
        XCTAssertEqual(got, [.rateLimited(retryAfterS: nil), .rateLimited(retryAfterS: nil)])
    }
}
