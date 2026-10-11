import XCTest
@testable import CindyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The real transport, against a stub `URLProtocol` so that nothing leaves the machine.
///
/// No Kotlin test: Android's `UrlConnectionTransport` is not exercised by any (every Strava test
/// uses `FakeTransport`). What is pinned here is what its KDoc promises: https only, a redirect is
/// answered rather than followed, a failure is a `HttpTransportError`, and what goes out and comes
/// back is what the request and the response say.
final class URLSessionTransportTests: XCTestCase {

    /// Serves whatever `StubProtocol.handler` says, and writes down what it was asked.
    final class StubProtocol: URLProtocol {
        struct Reply {
            var status = 200
            var headers: [String: String] = [:]
            var body = ""
            var failure: Error?
        }

        nonisolated(unsafe) static var handler: ((URLRequest) -> Reply)?
        nonisolated(unsafe) static var seen: [URLRequest] = []
        private static let lock = NSLock()

        static func reset(_ handler: @escaping (URLRequest) -> Reply) {
            lock.lock()
            defer { lock.unlock() }
            self.handler = handler
            seen = []
        }

        static var requests: [URLRequest] {
            lock.lock()
            defer { lock.unlock() }
            return seen
        }

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            Self.lock.lock()
            Self.seen.append(request)
            let handler = Self.handler
            Self.lock.unlock()
            let reply = handler?(request) ?? Reply(status: 500)
            if let failure = reply.failure {
                client?.urlProtocol(self, didFailWithError: failure)
                return
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1",
                                           headerFields: reply.headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(reply.body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    private func transport() -> URLSessionTransport {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return URLSessionTransport(configuration: configuration)
    }

    /// a request goes out with its method, headers, content type and body
    func testARequestGoesOutWithItsMethodHeadersContentTypeAndBody() async throws {
        StubProtocol.reset { _ in .init(status: 201, headers: ["X-One": "1"], body: #"{"ok":true}"#) }

        let response = try await transport().execute(HttpRequest(
            method: "POST", url: "https://www.strava.com/api/v3/uploads",
            headers: ["Authorization": "Bearer t"], body: Data("payload".utf8), contentType: "text/plain"))

        let sent = try XCTUnwrap(StubProtocol.requests.first)
        XCTAssertEqual(sent.httpMethod, "POST")
        XCTAssertEqual(sent.url?.absoluteString, "https://www.strava.com/api/v3/uploads")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "Authorization"), "Bearer t")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "Content-Type"), "text/plain")
        XCTAssertEqual(response.code, 201)
        XCTAssertEqual(response.body, #"{"ok":true}"#)
        XCTAssertEqual(response.headers.first { $0.key.lowercased() == "x-one" }?.value, ["1"])
    }

    /// an error status comes back as an ordinary response, with its body
    func testAnErrorStatusComesBackAsAnOrdinaryResponseWithItsBody() async throws {
        StubProtocol.reset { _ in .init(status: 429, headers: ["Retry-After": "60"], body: #"{"message":"slow down"}"#) }

        let response = try await transport().execute(HttpRequest(method: "GET", url: "https://www.strava.com/api/v3/uploads/1"))

        XCTAssertEqual(response.code, 429)
        XCTAssertEqual(response.body, #"{"message":"slow down"}"#)
        XCTAssertEqual(response.headers.first { $0.key.lowercased() == "retry-after" }?.value, ["60"])
    }

    /// a request to anything but https is refused before it is sent
    func testARequestToAnythingButHttpsIsRefusedBeforeItIsSent() async {
        StubProtocol.reset { _ in .init() }
        for url in ["http://www.strava.com/api/v3/uploads", "ftp://example.invalid/x", "not a url", ""] {
            let error = await thrownError { _ = try await transport().execute(HttpRequest(method: "GET", url: url)) }
            // Not an HttpTransportError: that means "the network failed, send it again".
            XCTAssertEqual(error as? HttpRequestRefused, HttpRequestRefused(url: url), url)
        }
        XCTAssertTrue(StubProtocol.requests.isEmpty)
    }

    /// a redirect comes back as the response it is, with its Location, and nothing is sent after it
    func testARedirectComesBackAsTheResponseItIsWithItsLocationAndNothingIsSentAfterIt() async throws {
        StubProtocol.reset { _ in
            .init(status: 302, headers: ["Location": "https://elsewhere.invalid/steal"], body: "")
        }

        let response = try await transport().execute(HttpRequest(
            method: "POST", url: "https://www.strava.com/api/v3/uploads",
            headers: ["Authorization": "Bearer t"], body: Data("secret upload".utf8)))

        XCTAssertEqual(response.code, 302)
        XCTAssertEqual(response.headers.first { $0.key.lowercased() == "location" }?.value, ["https://elsewhere.invalid/steal"])
        XCTAssertEqual(StubProtocol.requests.count, 1)
    }

    /// the session's redirect hook answers no, which is what keeps the bearer token on its own host
    func testTheSessionsRedirectHookAnswersNoWhichIsWhatKeepsTheBearerTokenOnItsOwnHost() throws {
        // swift-corelibs-foundation cannot be made to redirect through a stub protocol (it stops
        // with "doesn't currently handle redirects directly"), so the hook is called as the session
        // would call it. Apple's URLSession calls it for a real 3xx; that is Still owed on a device.
        let url = try XCTUnwrap(URL(string: "https://www.strava.com/api/v3/uploads"))
        let task = URLSession(configuration: .ephemeral).dataTask(with: url)
        let response = try XCTUnwrap(HTTPURLResponse(
            url: url, statusCode: 302, httpVersion: "HTTP/1.1",
            headerFields: ["Location": "https://elsewhere.invalid/steal"]))
        var answer: URLRequest? = URLRequest(url: url)
        var answered = false

        RefuseRedirects().urlSession(
            URLSession(configuration: .ephemeral), task: task, willPerformHTTPRedirection: response,
            newRequest: URLRequest(url: try XCTUnwrap(URL(string: "https://elsewhere.invalid/steal")))
        ) { request in
            answer = request
            answered = true
        }

        XCTAssertTrue(answered)
        XCTAssertNil(answer, "a non-nil answer would tell the session to follow the redirect")
    }

    /// a connection failure is a transport error, not a response
    func testAConnectionFailureIsATransportErrorNotAResponse() async {
        StubProtocol.reset { _ in .init(failure: URLError(.notConnectedToInternet)) }

        let error = await thrownError {
            _ = try await transport().execute(HttpRequest(method: "GET", url: "https://www.strava.com/api/v3/uploads/1"))
        }

        XCTAssertNotNil(error as? HttpTransportError)
    }
}
