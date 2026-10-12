import Foundation

/// What happened to one upload, whether just posted or polled. The upload acts on this instead of
/// re-deriving meaning from a status code or an `error` string itself.
public enum UploadOutcome: Equatable, Sendable {
    /// Strava has the file and is still working on it. Poll `uploadId` again shortly.
    case processing(uploadId: String)

    /// The activity exists.
    case ready(activityId: Int64)

    /// Strava already had this file. Treat it as done. `activityId` is nil only when Strava's own
    /// message did not say which activity, which still means "do not retry".
    case duplicate(activityId: Int64?)

    /// Strava refused the upload for good. Retrying would not change the outcome.
    case rejected(message: String)

    /// The token was not accepted. The caller refreshes or asks the athlete to reconnect.
    case unauthorized

    /// Too many requests. `retryAfterS` is Strava's own `Retry-After`, when it sent one.
    case rateLimited(retryAfterS: Int64?)

    /// A transient failure on Strava's side or ours: worth retrying later, unlike `rejected`.
    case transient(reason: String)
}

/// The Strava upload endpoint, over `HttpTransport` and `StravaAccessToken` only.
///
/// `token.get()` runs before anything is sent, on every call. When the athlete is not connected,
/// or the grant was revoked, it throws `StravaAuthError`. This type does not catch that: it
/// propagates to the caller and no request goes out. Reconnecting or refreshing is the upload's
/// job, not this one's; `UploadOutcome.unauthorized` only covers a 401 that gets past a token that
/// looked good when it was fetched (for example, revoked moments earlier on Strava's side).
public struct StravaApi: Sendable {

    private let transport: HttpTransport
    private let token: StravaAccessToken
    private let base: String

    public init(transport: HttpTransport, token: StravaAccessToken, base: String = StravaConfig.apiBase) {
        self.transport = transport
        self.token = token
        self.base = base
    }

    /// `POST $base/uploads`, multipart: `file` (named `"$externalId.json"`, `application/json`),
    /// `data_type=json`, `sport_type=Crossfit` (case-sensitive: Strava's own docs say it overrides
    /// whatever the file itself would suggest), `name`, `description`, `external_id`.
    public func upload(json: String, name: String, description: String, externalId: String) async throws -> UploadOutcome {
        let bearer = try await token.get()
        let body = Multipart()
        body.file("file", filename: "\(externalId).json", contentType: "application/json", bytes: Data(json.utf8))
        body.field("data_type", "json")
        body.field("sport_type", "Crossfit")
        body.field("name", name)
        body.field("description", description)
        body.field("external_id", externalId)
        return try await send(HttpRequest(
            method: "POST",
            url: "\(base)/uploads",
            headers: ["Authorization": "Bearer \(bearer)"],
            body: body.build(),
            contentType: body.contentType))
    }

    /// `GET $base/uploads/{uploadId}`. See the classification rules on `UploadOutcome`.
    public func status(_ uploadId: String) async throws -> UploadOutcome {
        let bearer = try await token.get()
        return try await send(HttpRequest(
            method: "GET",
            url: "\(base)/uploads/\(uploadId)",
            headers: ["Authorization": "Bearer \(bearer)"]))
    }

    /// Where the athlete can look at the finished activity in a browser.
    public func activityUrl(_ id: Int64) -> String { Self.activityUrl(id) }

    /// Same URL as the instance method above, for a caller (the results screen's Strava row) that
    /// wants to format one without needing a transport or a token just to get an instance.
    public static func activityUrl(_ id: Int64) -> String { "https://www.strava.com/activities/\(id)" }

    /// Only a network failure becomes an outcome, as only `IOException` does on Android. Anything
    /// else a transport throws is a bug in it, and escapes.
    private func send(_ request: HttpRequest) async throws -> UploadOutcome {
        do {
            return Self.classify(try await transport.execute(request))
        } catch let error as HttpTransportError {
            // A network failure carries no Strava semantics at all -- always worth retrying.
            return .transient(reason: error.message)
        }
    }

    // ---- classification --------------------------------------------------------------------
    //
    // Kept apart from `send`: classifying an `HttpResponse` needs nothing from the request, and
    // keeping it separate makes the status-code table easy to read start to finish.

    private static func classify(_ response: HttpResponse) -> UploadOutcome {
        let code = response.code
        switch code {
        case 200...299:
            return classifySuccess(response)
        case 401:
            return .unauthorized
        case 429:
            return .rateLimited(retryAfterS: header(response, "Retry-After").flatMap(Records.toLong))
        // The transport never follows redirects (see StravaHttp.swift), so a 3xx here means Strava
        // sent one and it was refused rather than blindly chased to a host we did not choose.
        case 300...399:
            return .rejected(message: "Unexpected redirect (HTTP \(code))")
        case 400...499:
            return .rejected(message: bodyMessage(response) ?? "HTTP \(code)")
        default:
            return .transient(reason: "HTTP \(code)")
        }
    }

    private static func classifySuccess(_ response: HttpResponse) -> UploadOutcome {
        let json: JsonObject
        do {
            json = try JsonObject(parsing: response.body)
        } catch {
            // Strava had a hiccup rendering its own response. Not our fault and not permanent.
            return .transient(reason: "Malformed response body")
        }
        do {
            if let error = try optNullableString(json, "error") {
                return classifyError(error)
            }
            if let activityId = try optNullableLong(json, "activity_id") {
                return .ready(activityId: activityId)
            }
            return .processing(uploadId: try json.getString("id_str"))
        } catch {
            return .transient(reason: "Malformed response body")
        }
    }

    private static func classifyError(_ error: String) -> UploadOutcome {
        if error.range(of: "duplicate", options: .caseInsensitive) == nil { return .rejected(message: error) }
        let id = firstGroup(duplicateOfActivity, in: error) ?? firstGroup(activityLink, in: error)
        return .duplicate(activityId: id.flatMap(Records.toLong))
    }

    private static let duplicateOfActivity = try! NSRegularExpression(
        pattern: "duplicate of activity ([0-9]+)", options: .caseInsensitive)
    private static let activityLink = try! NSRegularExpression(pattern: "/activities/([0-9]+)")

    private static func firstGroup(_ regex: NSRegularExpression, in text: String) -> String? {
        let whole = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: whole),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    /// Strava's general error shape carries `message`; the uploads endpoint carries `error`. Either
    /// is a fair "why" for a 4xx that is not a 401 or a 429.
    private static func bodyMessage(_ response: HttpResponse) -> String? {
        guard let json = try? JsonObject(parsing: response.body) else { return nil }
        return (try? optNullableString(json, "message")) ?? (try? optNullableString(json, "error"))
    }

    /// `HttpResponse.headers` keeps whatever casing the server sent (see StravaHttp.swift), so a name
    /// match has to ignore case instead of assuming Strava capitalises it one particular way.
    private static func header(_ response: HttpResponse, _ name: String) -> String? {
        response.headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value.first
    }

    private static func optNullableString(_ json: JsonObject, _ name: String) throws -> String? {
        json.has(name) && !json.isNull(name) ? try json.getString(name) : nil
    }

    private static func optNullableLong(_ json: JsonObject, _ name: String) throws -> Int64? {
        json.has(name) && !json.isNull(name) ? try json.getLong(name) : nil
    }
}
