import Foundation

/// The Strava feature's fixed facts: the API hosts, the OAuth scope, and whether this particular
/// build was given credentials to use any of it.
///
/// Android reads the credentials from `BuildConfig` in an `object`. Here they are a value the app
/// builds once from its own `Strava.xcconfig` (P20), so a test builds a config with credentials, or
/// without, instead of flipping a static and having to put it back. `available` turns the fact the
/// credentials are present into the one the rest of the app should act on: a build with none does
/// not have the feature, so the menu has no Strava row, Help and the tutorial do not mention it,
/// and the app never reaches for a client secret that was never there.
public struct StravaConfig: Equatable, Sendable {

    public let clientId: String
    public let clientSecret: String
    /// The build's own bundle identifier, which is the redirect's scheme (D5).
    public let applicationId: String

    public init(clientId: String, clientSecret: String, applicationId: String) {
        self.clientId = clientId
        self.clientSecret = clientSecret
        self.applicationId = applicationId
    }

    /// False for CI and a fresh clone with no `Strava.xcconfig`. The whole feature hides.
    public var available: Bool { !Self.isBlank(clientId) && !Self.isBlank(clientSecret) }

    /// A reverse-DNS scheme (RFC 8252) with host `localhost`, which Strava whitelists as an
    /// Authorization Callback Domain without our own web server to receive it.
    ///
    /// The scheme is the build's own bundle identifier, so a debug build and a release build on one
    /// phone each catch only their own redirect, instead of the phone offering a chooser between two
    /// apps that both claim the scheme. Strava stores only the callback *domain*, `localhost`, so
    /// nothing changes on its dashboard.
    public var redirectUri: String { "\(applicationId)://localhost/strava" }

    /// The v3 API host. Strava opens `https://api-v3.strava.com` as an alternative on 2027-01-04.
    /// Keep the base in this one constant, so that moving to it, if it ever happens, is a one-line
    /// change instead of a search-and-replace across the feature.
    public static let apiBase = "https://www.strava.com/api/v3"

    public static let oauthBase = "https://www.strava.com/oauth"

    /// `activity:write` is what the upload needs; `read` is what shows the athlete's name back.
    public static let scope = "read,activity:write"

    private static func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
