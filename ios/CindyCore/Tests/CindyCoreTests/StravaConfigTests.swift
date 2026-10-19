import XCTest
import CindyCore

/// Whether a build has Strava at all, and where its redirect lands.
///
/// No Kotlin test: Android's `StravaConfig` reads `BuildConfig`, so its tests flip a static
/// (`availableForTest`) or run under `NoStravaCredentials`. Here the credentials are a value, and
/// "a build with none has no Strava" is a plain assertion.
final class StravaConfigTests: XCTestCase {

    /// a build with both credentials has Strava
    func testABuildWithBothCredentialsHasStrava() {
        XCTAssertTrue(StravaConfig(clientId: "12345", clientSecret: "s3cret", applicationId: "com.cindy.tracker").available)
    }

    /// a build missing either credential, or with a blank one, has no Strava
    func testABuildMissingEitherCredentialOrWithABlankOneHasNoStrava() {
        for (id, secret) in [("", ""), ("12345", ""), ("", "s3cret"), ("  ", "s3cret"), ("12345", "\n\t ")] {
            XCTAssertFalse(StravaConfig(clientId: id, clientSecret: secret, applicationId: "com.cindy.tracker").available,
                           "\(id.debugDescription) / \(secret.debugDescription)")
        }
    }

    /// the redirect is the bundle identifier as a scheme, on localhost
    func testTheRedirectIsTheBundleIdentifierAsASchemeOnLocalhost() {
        XCTAssertEqual(StravaConfig(clientId: "1", clientSecret: "s", applicationId: "com.cindy.tracker").redirectUri,
                       "com.cindy.tracker://localhost/strava")
        XCTAssertEqual(StravaConfig(clientId: "1", clientSecret: "s", applicationId: "com.cindy.tracker.debug").redirectUri,
                       "com.cindy.tracker.debug://localhost/strava")
    }

    /// the hosts and the scope are the ones Strava documents
    func testTheHostsAndTheScopeAreTheOnesStravaDocuments() {
        XCTAssertEqual(StravaConfig.apiBase, "https://www.strava.com/api/v3")
        XCTAssertEqual(StravaConfig.oauthBase, "https://www.strava.com/oauth")
        XCTAssertEqual(StravaConfig.scope, "read,activity:write")
    }
}
