import XCTest
import CindyCore

/// Mirrors `StravaHttpTest.kt`: the form and multipart bodies, and the scripted transport that every
/// other Strava test stands on.
final class StravaHttpTests: XCTestCase {

    private func text(_ data: Data) -> String { String(decoding: data, as: UTF8.self) }

    // ---- FormBody ------------------------------------------------------------------------

    /// a single field encodes as name equals value
    func testASingleFieldEncodesAsNameEqualsValue() {
        XCTAssertEqual(text(FormBody.encode([("client_id", "12345")])), "client_id=12345")
    }

    /// multiple fields join with an ampersand, in order
    func testMultipleFieldsJoinWithAnAmpersandInOrder() {
        let body = FormBody.encode([("grant_type", "authorization_code"), ("code", "abc")])
        XCTAssertEqual(text(body), "grant_type=authorization_code&code=abc")
    }

    /// reserved characters are percent-encoded, and a space becomes a plus
    func testReservedCharactersArePercentEncodedAndASpaceBecomesAPlus() {
        // Exactly the characters a redirect's state or code could plausibly contain.
        let body = FormBody.encode([("value", "a b&c=d+e/f?g#h")])
        XCTAssertEqual(text(body), "value=a+b%26c%3Dd%2Be%2Ff%3Fg%23h")
    }

    /// non-ascii text encodes as its utf-8 percent sequence
    func testNonAsciiTextEncodesAsItsUtf8PercentSequence() {
        XCTAssertEqual(text(FormBody.encode([("name", "café")])), "name=caf%C3%A9")
    }

    /// an empty field list encodes as an empty body
    func testAnEmptyFieldListEncodesAsAnEmptyBody() {
        XCTAssertEqual(text(FormBody.encode([])), "")
    }

    // ---- Multipart -----------------------------------------------------------------------

    /// a text field is framed with the boundary and a blank line before its value
    func testATextFieldIsFramedWithTheBoundaryAndABlankLineBeforeItsValue() {
        let multipart = Multipart(boundary: "TEST")
        multipart.field("data_type", "json")
        XCTAssertEqual(
            text(multipart.build()),
            "--TEST\r\n" +
                "Content-Disposition: form-data; name=\"data_type\"\r\n" +
                "\r\n" +
                "json\r\n" +
                "--TEST--\r\n")
    }

    /// a file part carries filename and content-type headers
    func testAFilePartCarriesFilenameAndContentTypeHeaders() {
        let multipart = Multipart(boundary: "TEST")
        multipart.file("file", filename: "cindy-123.json", contentType: "application/json", bytes: Data("{}".utf8))
        XCTAssertEqual(
            text(multipart.build()),
            "--TEST\r\n" +
                "Content-Disposition: form-data; name=\"file\"; filename=\"cindy-123.json\"\r\n" +
                "Content-Type: application/json\r\n" +
                "\r\n" +
                "{}\r\n" +
                "--TEST--\r\n")
    }

    /// fields and a file combine with one boundary before each part and a closing boundary
    func testFieldsAndAFileCombineWithOneBoundaryBeforeEachPartAndAClosingBoundary() {
        let multipart = Multipart(boundary: "TEST")
        multipart.field("data_type", "json")
        multipart.field("sport_type", "Crossfit")
        multipart.file("file", filename: "cindy-1.json", contentType: "application/json", bytes: Data("{}".utf8))
        let expected = [
            "--TEST\r\nContent-Disposition: form-data; name=\"data_type\"\r\n\r\njson\r\n",
            "--TEST\r\nContent-Disposition: form-data; name=\"sport_type\"\r\n\r\nCrossfit\r\n",
            "--TEST\r\nContent-Disposition: form-data; name=\"file\"; " +
                "filename=\"cindy-1.json\"\r\nContent-Type: application/json\r\n\r\n{}\r\n",
            "--TEST--\r\n"
        ].joined()
        XCTAssertEqual(text(multipart.build()), expected)
    }

    /// a binary body survives byte for byte, even bytes that look like a boundary or crlf
    func testABinaryBodySurvivesByteForByteEvenBytesThatLookLikeABoundaryOrCrlf() {
        // 0x2d is '-', so two of them look like a boundary dash; 13 and 10 are CR and LF.
        let bytes = Data([0, 1, 2, 0x2d, 0x2d, 13, 10, 255])
        let multipart = Multipart(boundary: "TEST")
        multipart.file("file", filename: "blob.bin", contentType: "application/octet-stream", bytes: bytes)
        let built = multipart.build()
        let header = Data((
            "--TEST\r\nContent-Disposition: form-data; name=\"file\"; filename=\"blob.bin\"\r\n" +
                "Content-Type: application/octet-stream\r\n\r\n").utf8)
        let trailer = Data("\r\n--TEST--\r\n".utf8)
        XCTAssertEqual(built.count, header.count + bytes.count + trailer.count)
        XCTAssertEqual(built.prefix(header.count), header)
        XCTAssertEqual(built.dropFirst(header.count).prefix(bytes.count), bytes)
        XCTAssertEqual(built.suffix(trailer.count), trailer)
    }

    /// a quote in a field name is escaped so the header stays well-formed
    func testAQuoteInAFieldNameIsEscapedSoTheHeaderStaysWellFormed() {
        let multipart = Multipart(boundary: "TEST")
        multipart.field("weird\"name", "value")
        XCTAssertTrue(text(multipart.build()).contains("name=\"weird\\\"name\""))
    }

    /// content type reports the same boundary the body was framed with
    func testContentTypeReportsTheSameBoundaryTheBodyWasFramedWith() {
        XCTAssertEqual(Multipart(boundary: "TEST").contentType, "multipart/form-data; boundary=TEST")
    }

    /// a boundary is generated when none is given, and two instances do not collide
    func testABoundaryIsGeneratedWhenNoneIsGivenAndTwoInstancesDoNotCollide() {
        XCTAssertNotEqual(Multipart().contentType, Multipart().contentType)
    }

    // ---- FakeTransport -------------------------------------------------------------------

    /// FakeTransport records the exact request it received
    func testFakeTransportRecordsTheExactRequestItReceived() async throws {
        let transport = FakeTransport()
        transport.enqueue(HttpResponse(200, [:], "{}"))
        let request = HttpRequest(
            method: "POST",
            url: "https://www.strava.com/api/v3/oauth/token",
            headers: ["Authorization": "Bearer xyz"],
            body: Data("grant_type=refresh_token".utf8),
            contentType: FormBody.contentType)

        _ = try await transport.execute(request)

        XCTAssertEqual(transport.requests.count, 1)
        let recorded = transport.requests[0]
        XCTAssertEqual(recorded.method, "POST")
        XCTAssertEqual(recorded.url, "https://www.strava.com/api/v3/oauth/token")
        XCTAssertEqual(recorded.headers["Authorization"], "Bearer xyz")
        XCTAssertEqual(recorded.contentType, FormBody.contentType)
        XCTAssertEqual(text(recorded.body!), "grant_type=refresh_token")
    }

    /// FakeTransport replays scripted responses in the order they were queued
    func testFakeTransportReplaysScriptedResponsesInTheOrderTheyWereQueued() async throws {
        let transport = FakeTransport()
        transport.enqueue(HttpResponse(202, [:], "first"))
        transport.enqueue(HttpResponse(200, [:], "second"))
        let get = HttpRequest(method: "GET", url: "https://example.invalid")

        let first = try await transport.execute(get)
        let second = try await transport.execute(get)
        XCTAssertEqual(first.body, "first")
        XCTAssertEqual(second.body, "second")
        XCTAssertEqual(transport.requests.count, 2)
    }

    /// FakeTransport replays a scripted IOException instead of a response
    func testFakeTransportReplaysAScriptedTransportErrorInsteadOfAResponse() async {
        let transport = FakeTransport()
        transport.enqueueFailure(HttpTransportError("no network"))

        let error = await thrownError {
            _ = try await transport.execute(HttpRequest(method: "GET", url: "https://example.invalid"))
        }
        XCTAssertEqual(error as? HttpTransportError, HttpTransportError("no network"))
    }

    /// FakeTransport fails loudly on a call with nothing scripted, instead of guessing a response
    func testFakeTransportFailsLoudlyOnACallWithNothingScriptedInsteadOfGuessingAResponse() async {
        let transport = FakeTransport()

        let error = await thrownError {
            _ = try await transport.execute(HttpRequest(method: "GET", url: "https://example.invalid/unscripted"))
        }
        let fake = error as? FakeTransport.FakeTransportError
        XCTAssertNotNil(fake, "a scripted network failure is not what a missing script looks like")
        XCTAssertTrue(fake?.message.contains("https://example.invalid/unscripted") ?? false)
    }
}
