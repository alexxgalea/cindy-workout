import Foundation

/// One connected grant: the tokens, when the access token expires, the scopes Strava actually
/// gave, and the athlete's name for the menu row and the "Connected to Strava as …" line.
///
/// `expiresAtEpochS` is epoch **seconds**, matching Strava's own `expires_at` field, not the
/// millisecond epoch the rest of the app uses for `atMillis`: converting at the one place that
/// reads it (`StravaSession`) is cheaper than a wrong unit compiling silently everywhere else.
public struct StravaGrant: Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresAtEpochS: Int64
    public let scopes: Set<String>
    public let athleteName: String?

    public init(accessToken: String, refreshToken: String, expiresAtEpochS: Int64,
                scopes: Set<String>, athleteName: String?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAtEpochS = expiresAtEpochS
        self.scopes = scopes
        self.athleteName = athleteName
    }
}
