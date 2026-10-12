import Foundation

/// One HTTP request, transport-agnostic so that every Strava call (OAuth, upload, poll) can be
/// built as plain data and either sent for real or handed to a scripted transport in a test.
///
/// Android's data class compares its `ByteArray` by reference, which its KDoc warns about. Swift's
/// `Data` compares by content, so two requests with equal bodies are equal here; nothing relies on
/// that either way, and the tests still read the fields.
public struct HttpRequest: Equatable, Sendable {
    public let method: String
    public let url: String
    public let headers: [String: String]
    public let body: Data?
    public let contentType: String?

    public init(method: String, url: String, headers: [String: String] = [:],
                body: Data? = nil, contentType: String? = nil) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
        self.contentType = contentType
    }
}

/// One HTTP response. `body` is always text: every Strava response is JSON, never binary.
public struct HttpResponse: Equatable, Sendable {
    public let code: Int
    /// Whatever casing the server sent, so a lookup has to ignore case.
    public let headers: [String: [String]]
    public let body: String

    public init(_ code: Int, _ headers: [String: [String]], _ body: String) {
        self.code = code
        self.headers = headers
        self.body = body
    }
}

/// A network failure: no connection, a timeout, a reset. Android's `IOException`.
///
/// An HTTP error status is not one. It comes back as an ordinary `HttpResponse` with `code >= 400`,
/// for the caller to classify (see `StravaApi`'s `UploadOutcome`).
public struct HttpTransportError: Error, Equatable, Sendable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }
}

/// How an `HttpRequest` is actually sent. The real implementation is `URLSessionTransport`; the
/// tests' `FakeTransport` stands in for it everywhere else in the Strava suite.
///
/// `execute` throws `HttpTransportError` on a network failure.
public protocol HttpTransport: Sendable {
    func execute(_ request: HttpRequest) async throws -> HttpResponse
}

/// `application/x-www-form-urlencoded` bodies, for the OAuth token endpoint.
public enum FormBody {

    public static let contentType = "application/x-www-form-urlencoded; charset=utf-8"

    /// UTF-8, percent-encoded, `&`-joined: the encoding every OAuth form field needs.
    public static func encode(_ fields: [(String, String)]) -> Data {
        Data(fields.map { "\(encodePart($0.0))=\(encodePart($0.1))" }.joined(separator: "&").utf8)
    }

    /// `URLEncoder.encode(value, "UTF-8")`: letters, digits and `.-*_` stay, a space is a plus, and
    /// every other byte is `%` and two capital hex digits. Not `addingPercentEncoding`, whose
    /// allowed sets keep `~` and turn a space into `%20`.
    static func encodePart(_ value: String) -> String {
        var out = ""
        for byte in value.utf8 {
            switch byte {
            case UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "A")...UInt8(ascii: "Z"),
                 UInt8(ascii: "0")...UInt8(ascii: "9"),
                 UInt8(ascii: "."), UInt8(ascii: "-"), UInt8(ascii: "*"), UInt8(ascii: "_"):
                out.unicodeScalars.append(Unicode.Scalar(byte))
            case UInt8(ascii: " "):
                out += "+"
            default:
                out += String(format: "%%%02X", byte)
            }
        }
        return out
    }
}

/// A `multipart/form-data` body, for the upload endpoint's `file` plus its plain fields
/// (`data_type`, `sport_type`, `name`, `description`, `external_id`).
///
/// Usage is write-only and one-shot: add every `field` and `file`, then call `build` exactly
/// once to get the finished, boundary-terminated bytes.
public final class Multipart: @unchecked Sendable {

    private let boundary: String
    private var buffer = Data()

    /// A boundary of the caller's choosing (the tests pin one), or a fresh random one.
    public init(boundary: String? = nil) {
        self.boundary = boundary
            ?? "CindyStrava" + UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
    }

    /// The request's `Content-Type` header: the boundary must match what was written.
    public var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    /// A plain text field, such as `data_type` or `sport_type`.
    public func field(_ name: String, _ value: String) {
        writePartHeader(name, filename: nil, contentType: nil)
        writeText(value)
        writeText("\r\n")
    }

    /// A binary part: the activity JSON goes here as `file`.
    public func file(_ name: String, filename: String, contentType: String, bytes: Data) {
        writePartHeader(name, filename: filename, contentType: contentType)
        buffer.append(bytes)
        writeText("\r\n")
    }

    /// The finished body. Call once, after every `field` and `file`.
    public func build() -> Data {
        writeText("--\(boundary)--\r\n")
        return buffer
    }

    private func writePartHeader(_ name: String, filename: String?, contentType: String?) {
        writeText("--\(boundary)\r\n")
        writeText("Content-Disposition: form-data; name=\"\(escape(name))\"")
        if let filename = filename { writeText("; filename=\"\(escape(filename))\"") }
        writeText("\r\n")
        if let contentType = contentType { writeText("Content-Type: \(contentType)\r\n") }
        writeText("\r\n")
    }

    private func writeText(_ text: String) {
        buffer.append(Data(text.utf8))
    }

    private func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "\"", with: "\\\"")
    }
}

/// The athlete is not connected to Strava, or Strava revoked the grant since they were.
///
/// `revoked` tells the caller which: true means a refresh was attempted and rejected, so the
/// stored grant is already cleared and reconnecting is the only way forward; false means there
/// was never a grant to use in the first place. Android's `StravaAuthException`.
public struct StravaAuthError: Error, Equatable, Sendable {
    public let message: String
    public let revoked: Bool

    public init(_ message: String = "Not connected to Strava", revoked: Bool = false) {
        self.message = message
        self.revoked = revoked
    }
}

/// The seam between OAuth, which implements this, and every API call, which only consumes it.
/// `get` returns a currently-valid bearer token, refreshing first when it was close to expiry,
/// and throws `StravaAuthError` when there is nothing to hand back.
public protocol StravaAccessToken: Sendable {
    func get() async throws -> String
}

/// A token from a closure: Android's `StravaAccessToken { "value" }` for the tests and for callers
/// that already hold one.
public struct ClosureAccessToken: StravaAccessToken {
    private let body: @Sendable () async throws -> String

    public init(_ body: @escaping @Sendable () async throws -> String) {
        self.body = body
    }

    public func get() async throws -> String { try await body() }
}
