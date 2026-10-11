import Foundation
import XCTest
import CindyCore

/// A scripted `HttpTransport` for tests: queue up what `execute` should return (or throw) next,
/// then assert on what was actually sent.
///
/// This is the one test double for all of Strava: the OAuth exchange, refresh and revoke, the
/// upload and poll classification, and the upload worker all script a sequence of responses here and
/// read `requests` back to check the exact method, url, headers and body that went out.
///
/// An `execute` call with nothing left in the script throws `FakeTransportError` naming the request
/// that had nothing queued for it. That is a bug in the test, not one of the two things this class
/// exists to simulate, so it is never mistaken for a scripted `HttpTransportError`.
///
/// Mirrors `FakeTransport.kt`.
final class FakeTransport: HttpTransport, @unchecked Sendable {

    struct FakeTransportError: Error, Equatable {
        let message: String
    }

    private let lock = NSLock()
    private var script: [() throws -> HttpResponse] = []
    private var sent: [HttpRequest] = []

    /// Every request `execute` has received so far, oldest first.
    var requests: [HttpRequest] {
        lock.lock()
        defer { lock.unlock() }
        return sent
    }

    /// The next `execute` call returns this response.
    func enqueue(_ response: HttpResponse) {
        lock.lock()
        defer { lock.unlock() }
        script.append { response }
    }

    /// The next `execute` call throws this instead of returning, simulating a network failure.
    func enqueueFailure(_ error: HttpTransportError) {
        lock.lock()
        defer { lock.unlock() }
        script.append { throw error }
    }

    func execute(_ request: HttpRequest) async throws -> HttpResponse {
        lock.lock()
        sent.append(request)
        let next = script.isEmpty ? nil : script.removeFirst()
        lock.unlock()
        guard let step = next else {
            throw FakeTransportError(
                message: "FakeTransport got \(request.method) \(request.url) with nothing scripted for it")
        }
        return try step()
    }
}

extension XCTestCase {

    /// The error `body` throws, or a failure when it throws nothing. `XCTAssertThrowsError` takes a
    /// synchronous autoclosure and so cannot await the calls these tests make.
    @discardableResult
    func thrownError(file: StaticString = #filePath, line: UInt = #line,
                     _ body: () async throws -> Void) async -> Error? {
        do {
            try await body()
            XCTFail("expected an error to be thrown", file: file, line: line)
            return nil
        } catch {
            return error
        }
    }
}
