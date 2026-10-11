import Foundation

/// What Strava's redirect meant, once `StravaAuth.parseRedirect` has read it.
///
/// There is no "success" case beyond `code`: even a redirect that carries a code is not yet a
/// connection, because the athlete may have unticked the one scope the app needs. Turning that
/// into its own case (`missingWriteScope`) rather than folding it into `code` means the caller
/// cannot forget to check.
public enum RedirectResult: Equatable, Sendable {
    /// A code worth exchanging, and the scopes Strava says were actually granted for it.
    case code(String, scopes: Set<String>)

    /// The athlete declined on Strava's consent page. Not an error, just not connected.
    case denied

    /// The redirect's `state` does not match the one this app minted before it opened the
    /// browser; missing entirely counts as a mismatch, not a separate case. Either there is no
    /// OAuth attempt in flight, or this URL was not the answer to ours: a stale one replayed, or a
    /// link crafted by something else on the phone. It is silently ignored rather than acted on.
    case stateMismatch

    /// The code is genuine, but the athlete unticked `activity:write` on the consent page.
    case missingWriteScope

    /// The redirect could not be read as a URI, or carried neither a code nor an error.
    case malformed
}

/// Strava's reply to a token request could not be read: it was not JSON, or lacked a field the
/// grant needs. Android's `JSONException` out of `StravaAuth`; the upload treats it as worth
/// retrying, like a dropped connection.
public struct StravaResponseError: Error, Equatable, Sendable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }
}

/// OAuth, end to end: the URL that opens Strava's consent screen, the state that ties a redirect
/// back to the request that caused it, what a redirect meant, and the three calls against the
/// token endpoint. Everything here is pure over `HttpTransport`, so `StravaAuthTests` scripts it
/// with `FakeTransport` and no phone.
///
/// `authorizeUri`, `newState` and `parseRedirect` need no network and are static, so a caller that
/// only wants to build a URL or read a redirect never has to construct one of these with a
/// transport just to reach them. `exchange`, `refresh` and `revoke` are the three calls that do
/// reach the network, and are instance methods for exactly that reason.
public struct StravaAuth: Sendable {

    private let transport: HttpTransport
    private let config: StravaConfig

    public init(transport: HttpTransport, config: StravaConfig) {
        self.transport = transport
        self.config = config
    }

    /// `POST {apiBase}/oauth/token`, `grant_type=authorization_code`. The one-time `code` from a
    /// `RedirectResult.code` becomes a `StravaGrant`: the athlete is connected once this returns.
    ///
    /// Any HTTP error throws a plain `StravaAuthError` (`revoked == false`): there is no grant yet
    /// for this call to have revoked.
    public func exchange(_ code: String) async throws -> StravaGrant {
        let response = try await post("\(StravaConfig.apiBase)/oauth/token", [
            ("client_id", config.clientId),
            ("client_secret", config.clientSecret),
            ("code", code),
            ("grant_type", "authorization_code")
        ])
        if response.code >= 400 {
            throw StravaAuthError("Strava could not exchange the code (\(response.code))")
        }
        return try Self.parseGrant(response.body)
    }

    /// `POST {apiBase}/oauth/token`, `grant_type=refresh_token`. Strava rotates the refresh token
    /// on every call, and the old one stops working the moment the new one is issued:
    /// `StravaSession` persists what comes back before it uses the access token inside it.
    ///
    /// A 400 or 401 means the grant itself is gone (revoked from strava.com, or the athlete
    /// disconnected from a different device), so this throws `StravaAuthError(revoked: true)`
    /// rather than the plain form `exchange` throws. `StravaSession` is the one that actually
    /// clears the stored grant; this type never touches `StravaTokenStore`.
    public func refresh(_ refreshToken: String) async throws -> StravaGrant {
        let response = try await post("\(StravaConfig.apiBase)/oauth/token", [
            ("client_id", config.clientId),
            ("client_secret", config.clientSecret),
            ("refresh_token", refreshToken),
            ("grant_type", "refresh_token")
        ])
        if response.code == 400 || response.code == 401 {
            throw StravaAuthError("Strava rejected the refresh token", revoked: true)
        }
        if response.code >= 400 {
            throw StravaAuthError("Strava could not refresh the token (\(response.code))")
        }
        return try Self.parseGrant(response.body)
    }

    /// `POST {oauthBase}/revoke`, Basic-authenticated with the app's own credentials rather than
    /// the athlete's token. `tokenTypeHint` is `"access_token"` or `"refresh_token"`, naming which
    /// of the two `token` is; Strava revokes the whole grant either way.
    ///
    /// Callers treat this as best-effort: DISCONNECT clears the local grant even when this throws,
    /// because an athlete who is offline or has already removed the app from strava.com must not
    /// be stuck looking connected.
    public func revoke(_ token: String, tokenTypeHint: String) async throws {
        let credentials = "\(config.clientId):\(config.clientSecret)"
        let basic = Data(credentials.utf8).base64EncodedString()
        let response = try await transport.execute(HttpRequest(
            method: "POST",
            url: "\(StravaConfig.oauthBase)/revoke",
            headers: ["Authorization": "Basic \(basic)"],
            body: FormBody.encode([("token", token), ("token_type_hint", tokenTypeHint)]),
            contentType: FormBody.contentType))
        if response.code >= 400 {
            throw StravaAuthError("Strava could not revoke the grant (\(response.code))")
        }
    }

    private func post(_ url: String, _ fields: [(String, String)]) async throws -> HttpResponse {
        try await transport.execute(HttpRequest(
            method: "POST", url: url, body: FormBody.encode(fields), contentType: FormBody.contentType))
    }

    /// Reads the token endpoint's response. `scope` is documented as space-delimited since
    /// 2026-04-23, but this splits on both spaces and commas: cheap insurance against an older or
    /// reverted API build, and the same tolerance `parseRedirect` applies to the redirect's own
    /// `scope` parameter.
    ///
    /// The athlete's name keeps Android's reading of a missing or `null` name: a missing one is
    /// empty, and a `null` is the word "null" (`optString` on a JSON `null`), so a reply with
    /// `"firstname": null` shows as "null Smith". Strava sends strings, so it is only worth knowing.
    private static func parseGrant(_ body: String) throws -> StravaGrant {
        do {
            let json = try JsonObject(parsing: body)
            let athleteName = json.optJSONObject("athlete").flatMap { athlete -> String? in
                let joined = [athlete.optString("firstname"), athlete.optString("lastname")]
                    .filter { !isBlank($0) }
                    .joined(separator: " ")
                return isBlank(joined) ? nil : joined
            }
            return StravaGrant(
                accessToken: try json.getString("access_token"),
                refreshToken: try json.getString("refresh_token"),
                expiresAtEpochS: try json.getLong("expires_at"),
                scopes: splitScopes(json.optString("scope", "")),
                athleteName: athleteName)
        } catch let error as JsonObject.JsonError {
            throw StravaResponseError(error.message)
        }
    }

    // ---- no network ------------------------------------------------------------------------

    /// 128 random bits, hex-encoded: long enough that guessing one is not a real attack.
    public static func newState() -> String {
        var generator = SystemRandomNumberGenerator()
        return (0..<16).map { _ in String(format: "%02x", UInt8.random(in: 0...255, using: &generator)) }.joined()
    }

    /// Strava's mobile authorize URL, for the Strava app when it is installed (the caller picks
    /// that route, P20) and for a web authentication session otherwise.
    ///
    /// `approval_prompt=auto` skips a re-consent screen for an athlete who already granted this app
    /// access and only disconnected on our side.
    public static func authorizeUri(state: String, config: StravaConfig) -> String {
        let params = [
            ("client_id", config.clientId),
            ("redirect_uri", config.redirectUri),
            ("response_type", "code"),
            ("approval_prompt", "auto"),
            ("scope", StravaConfig.scope),
            ("state", state)
        ]
        let query = params.map { "\($0.0)=\(FormBody.encodePart($0.1))" }.joined(separator: "&")
        return "\(StravaConfig.oauthBase)/mobile/authorize?\(query)"
    }

    /// What a redirect to `StravaConfig.redirectUri` meant. `expectedState` is the value
    /// `StravaTokenStore.pendingState` held when the athlete left for Strava's consent page.
    ///
    /// The state check runs before anything else, including before noticing `error=`: a denial for
    /// someone else's request is not this app's business to report either.
    public static func parseRedirect(_ uri: String, expectedState: String) -> RedirectResult {
        guard let query = rawQuery(of: uri), let params = parseQuery(query) else { return .malformed }
        if params["state"] != expectedState { return .stateMismatch }
        if params["error"] != nil { return .denied }

        guard let code = params["code"] else { return .malformed }
        let scopes = splitScopes(params["scope"] ?? "")
        if !scopes.contains("activity:write") { return .missingWriteScope }
        return .code(code, scopes: scopes)
    }

    /// Strava documents the token endpoint's `scope` as space-delimited; the redirect's own `scope`
    /// parameter was comma-delimited before that. Accepting both costs nothing.
    private static func splitScopes(_ raw: String) -> Set<String> {
        Set(raw.split(whereSeparator: { $0 == "," || $0 == " " })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty })
    }

    private static func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // ---- reading a URI the way Java does -----------------------------------------------------

    /// `URI(uri).rawQuery`, or nil where Java's `URI` constructor would throw or the URI has no
    /// query to give (an opaque `scheme:rest` has none).
    ///
    /// Written out rather than asked of `URL(string:)`, which on current Apple systems repairs
    /// what it is given (a space becomes `%20`), so a string the Android app refuses as malformed
    /// would be accepted here, and differently on Linux. What a redirect may contain is the same
    /// rule as `java.net.URI`'s: no space, control, `"<>\^`{|}` or second `#`, no square bracket in the
    /// path, and every `%` followed by two hex digits.
    private static func rawQuery(of uri: String) -> String? {
        let scalars = Array(uri.unicodeScalars)
        var seenHash = false
        for (i, scalar) in scalars.enumerated() {
            switch scalar.value {
            case 0x00...0x20, 0x7F, 0x22, 0x3C, 0x3E, 0x5C, 0x5E, 0x60, 0x7B, 0x7C, 0x7D:
                return nil
            case 0x23:
                if seenHash { return nil }
                seenHash = true
            case 0x25:
                guard i + 2 < scalars.count, isHex(scalars[i + 1]), isHex(scalars[i + 2]) else { return nil }
            case 0x80...:
                switch scalar.properties.generalCategory {
                case .control, .spaceSeparator, .lineSeparator, .paragraphSeparator: return nil
                default: break
                }
            default:
                break
            }
        }

        // A scheme is what comes before the first ':' when that comes before any '/', '?' or '#'.
        var rest = Substring(uri)
        if let stop = uri.firstIndex(where: { ":/?#".contains($0) }), uri[stop] == ":" {
            let scheme = uri[..<stop]
            guard let first = scheme.unicodeScalars.first, isAsciiLetter(first),
                  scheme.unicodeScalars.allSatisfy({ isAsciiLetter($0) || isAsciiDigit($0) || "+-.".unicodeScalars.contains($0) })
            else { return nil }
            rest = uri[uri.index(after: stop)...]
            if rest.isEmpty { return nil }
            // `scheme:something` with nothing hierarchical after the colon is opaque, and has no query.
            if !rest.hasPrefix("/") { return nil }
        }

        let beforeFragment = rest.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
        let mark = beforeFragment.firstIndex(of: "?")

        // Square brackets are legal in a query and a fragment, and in a host, but not in a path.
        var path = mark.map { beforeFragment[..<$0] } ?? beforeFragment
        if path.hasPrefix("//") { path = path.dropFirst(2).drop(while: { $0 != "/" }) }
        if path.contains("[") || path.contains("]") { return nil }

        guard let mark = mark else { return nil }
        return String(beforeFragment[beforeFragment.index(after: mark)...])
    }

    private static func isHex(_ s: Unicode.Scalar) -> Bool {
        (s.value >= 0x30 && s.value <= 0x39) || (s.value >= 0x41 && s.value <= 0x46) || (s.value >= 0x61 && s.value <= 0x66)
    }

    private static func isAsciiLetter(_ s: Unicode.Scalar) -> Bool {
        (s.value >= 0x41 && s.value <= 0x5A) || (s.value >= 0x61 && s.value <= 0x7A)
    }

    private static func isAsciiDigit(_ s: Unicode.Scalar) -> Bool { s.value >= 0x30 && s.value <= 0x39 }

    /// `name=value` pairs split on `&`, each side decoded as `URLDecoder` does (a plus is a space,
    /// `%hh` is a byte of UTF-8). A pair with no `=` is skipped, and a name that comes twice keeps
    /// its last value, as Kotlin's `toMap()` does. Nil only for a `%` that is not followed by two
    /// hex digits, which `rawQuery` has already refused.
    private static func parseQuery(_ query: String) -> [String: String]? {
        var params: [String: String] = [:]
        for pair in query.split(separator: "&", omittingEmptySubsequences: false) {
            guard let equals = pair.firstIndex(of: "=") else { continue }
            guard let key = urlDecode(pair[..<equals]), let value = urlDecode(pair[pair.index(after: equals)...]) else {
                return nil
            }
            params[key] = value
        }
        return params
    }

    private static func urlDecode(_ text: Substring) -> String? {
        var bytes: [UInt8] = []
        let input = Array(text.utf8)
        var i = 0
        while i < input.count {
            switch input[i] {
            case UInt8(ascii: "+"):
                bytes.append(UInt8(ascii: " "))
                i += 1
            case UInt8(ascii: "%"):
                guard i + 2 < input.count, let high = hexValue(input[i + 1]), let low = hexValue(input[i + 2]) else {
                    return nil
                }
                bytes.append(UInt8(high << 4 | low))
                i += 3
            default:
                bytes.append(input[i])
                i += 1
            }
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func hexValue(_ byte: UInt8) -> Int? {
        switch byte {
        case 0x30...0x39: return Int(byte) - 0x30
        case 0x41...0x46: return Int(byte) - 0x41 + 10
        case 0x61...0x66: return Int(byte) - 0x61 + 10
        default: return nil
        }
    }
}
