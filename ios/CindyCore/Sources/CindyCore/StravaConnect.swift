import Foundation

/// The sheet that comes before Strava's own consent page.
///
/// Strava's page says what Strava will let Cindy do. It does not say what Cindy will send, and that
/// is the part an app store's user-data policy wants said in the app, in plain words, before anything
/// leaves the phone, with a choice that is not a tap on a button that does it anyway. So every road
/// that starts OAuth comes through here: the menu row, the results row's "Connect to upload", and its
/// "Reconnect to upload". Nothing is minted, stored or opened until the athlete taps Strava's own
/// "Connect with Strava" button; NOT NOW, and a swipe down, all leave without having started anything.
///
/// The list of what is sent is `StravaPayload` and `StravaActivityText` in words. If one of those
/// gains a field, this changes in the same commit, or the sheet is promising less than the upload
/// does. Port of `StravaConsent.kt`'s words; the sheet itself is drawn by the app.
public enum StravaConsent {

    /// Strava keeps heart rate behind a per-athlete switch that no API permission can turn on. The
    /// connected sheet carries this too, so the two cannot drift into saying different things.
    public static let dataPermissions =
        "Heart rate reaches Strava only once you allow it there: on strava.com, open "
        + "Settings, then Data Permissions, then Allow Access. Until then Strava drops "
        + "it from every upload."

    public static let connectLabel = "Connect with Strava"
    public static let compatibleLabel = "Compatible with Strava"
    public static let notNowLabel = "NOT NOW"

    public static let title = "Connect to Strava"
    public static let subtitle = "Cindy can upload each finished workout to your Strava account. "
        + "Nothing is sent until you connect."
    public static let eyebrow = "EACH WORKOUT SENDS"
    public static let sends = "Its score and every set with its reps. When it started, and how long it took "
        + "on the clock, paused and in real time. Calories, if you have set a body "
        + "weight. Your heart rate, if a watch recorded it. A title and a short "
        + "description, such as the score and the pace."
    public static let never = "Never the camera picture, the video or the pose. After you connect, each "
        + "workout uploads by itself; there is a switch for that in the Strava "
        + "sheet, and DISCONNECT there takes the connection off the phone."

    /// Everything the sheet says, in order, for a test to read and for a screen reader to be given.
    public static var words: [String] { [title, subtitle, eyebrow, sends, never, dataPermissions] }
}

/// Where the athlete started connecting from, which decides whether an upload follows.
public enum StravaOrigin: Equatable, Sendable {
    /// The menu's row. About no particular attempt.
    case menu
    /// The results screen's row. This attempt uploads once connected.
    case results(atMillis: Int64)
}

/// Starts OAuth, once the athlete has tapped Strava's own button and not before.
public struct StravaConnect: Sendable {

    private let tokens: StravaTokenStore
    private let config: StravaConfig

    public init(tokens: StravaTokenStore, config: StravaConfig) {
        self.tokens = tokens
        self.config = config
    }

    /// Mints a fresh state, remembers it, and gives the URL of Strava's own consent page for it.
    ///
    /// `afterConnectUploadAtMillis` is set for a results road and cleared for the menu's. A connect
    /// started from the menu is not about any particular attempt; without clearing it, connecting
    /// from the menu long after leaving a results screen would silently re-fire whatever request
    /// that screen had left pending.
    public func begin(_ origin: StravaOrigin) -> String {
        switch origin {
        case .menu: tokens.afterConnectUploadAtMillis = nil
        case .results(let atMillis): tokens.afterConnectUploadAtMillis = atMillis
        }
        let state = StravaAuth.newState()
        tokens.pendingState = state
        return StravaAuth.authorizeUri(state: state, config: config)
    }

    /// Nothing could show the consent page (no Strava app, no browser). Takes back what `begin` left.
    public func cancel() {
        tokens.pendingState = nil
        tokens.afterConnectUploadAtMillis = nil
    }
}

/// What the athlete's return from Strava came to, for the app to say and act on.
public enum StravaRedirectResult: Equatable, Sendable {
    /// Not an answer to anything this app asked, or not one it can read. Nothing is said or changed.
    case ignored
    /// Said to the athlete. `connected` is whether there are now attempts to send.
    case finished(message: String, connected: Bool)
}

/// Reads Strava's redirect back to the app, and finishes connecting. Port of `StravaAuthActivity`'s
/// `handleRedirect` and `exchange`.
public struct StravaRedirectHandler: Sendable {

    private let tokens: StravaTokenStore
    private let ledger: StravaUploads
    private let auth: StravaAuth

    public init(config: StravaConfig, transport: HttpTransport, tokens: StravaTokenStore, ledger: StravaUploads) {
        self.tokens = tokens
        self.ledger = ledger
        auth = StravaAuth(transport: transport, config: config)
    }

    public static let denied = "Not connected to Strava"
    public static let needsWriteScope = "Strava needs permission to upload activities to connect"
    public static let couldNotConnect = "Couldn't connect to Strava — check your connection and try again"

    public func handle(_ url: String?) async -> StravaRedirectResult {
        // No attempt in flight, or no data at all: there is nothing this could be an answer to, so it
        // is dropped without a word rather than guessed at.
        guard let expected = tokens.pendingState, let url = url else { return .ignored }

        switch StravaAuth.parseRedirect(url, expectedState: expected) {
        case .code(let code, _):
            tokens.pendingState = nil
            return await exchange(code)
        case .denied:
            tokens.pendingState = nil
            return .finished(message: Self.denied, connected: false)
        case .missingWriteScope:
            tokens.pendingState = nil
            return .finished(message: Self.needsWriteScope, connected: false)
        // Neither one is this app's own pending request; the real one (if any) is left untouched so
        // it can still complete when it actually arrives.
        case .stateMismatch, .malformed:
            return .ignored
        }
    }

    private func exchange(_ code: String) async -> StravaRedirectResult {
        let grant: StravaGrant
        do {
            grant = try await auth.exchange(code)
        } catch {
            // The athlete is told once; a 200 whose body is not the grant Strava documents, a
            // refusal, and a dropped connection are all "nothing to store".
            return .finished(message: Self.couldNotConnect, connected: false)
        }
        tokens.grant = grant
        // Whatever was waiting on a connection gets its turn now: attempts stuck asking to reconnect,
        // and the one particular attempt (if any) that sent the athlete here from its own results
        // screen rather than the menu.
        _ = ledger.requeueNeedingReconnect()
        if let atMillis = tokens.afterConnectUploadAtMillis {
            tokens.afterConnectUploadAtMillis = nil
            ledger.queue(atMillis: atMillis)
        }
        return .finished(message: "Connected to Strava" + (grant.athleteName.map { " as \($0)" } ?? ""), connected: true)
    }
}

/// The menu's Strava row and what a tap on it does.
public enum StravaMenu {

    /// Nil in a build with no credentials, so the row is absent and nothing else mentions Strava.
    public static func status(config: StravaConfig, tokens: StravaTokenStore) -> StravaStatus? {
        guard config.available else { return nil }
        return tokens.grant.map { .connected(athleteName: $0.athleteName) } ?? .notConnected
    }

    public enum Tap: Equatable, Sendable {
        /// Not connected: the sheet that says what is sent comes first.
        case askConsent
        /// Connected: the Strava sheet.
        case openSheet
    }

    public static func tap(grant: StravaGrant?) -> Tap { grant == nil ? .askConsent : .openSheet }
}

/// The sheet a connected athlete sees: one switch, a note, a mark, DONE and DISCONNECT.
public enum StravaSheet {

    public static let title = "Strava"
    public static let toggleLabel = "Upload automatically"
    public static let doneLabel = "DONE"
    public static let disconnectLabel = "DISCONNECT"
    public static let note = StravaConsent.dataPermissions
    public static let compatibleLabel = StravaConsent.compatibleLabel

    /// The switch is what makes this true or not, so the two must agree: saying "uploads on its own"
    /// while the switch under it is off would be exactly the kind of confident wrong statement this
    /// app's screens otherwise refuse to make.
    public static func subtitle(athleteName: String?, autoUpload: Bool) -> String {
        let connectedAs = "Connected\(athleteName.map { " as \($0)" } ?? "")."
        return autoUpload
            ? "\(connectedAs) Each finished workout uploads to Strava on its own."
            : "\(connectedAs) Automatic upload is off — upload from a workout's results screen instead."
    }
}

/// DISCONNECT.
public enum StravaDisconnect {

    public static let toast = "Disconnected. If Strava still lists Cindy Tracker, remove it at strava.com/settings/apps"

    /// Forgets the grant on the phone at once, then asks Strava to end it, best-effort.
    ///
    /// The athlete may be offline, or may have already removed Cindy Tracker from strava.com
    /// themselves; neither should leave the menu row still claiming to be connected. The refresh
    /// token is what is sent, rather than the access token: it does not expire on its own, so it is
    /// the more likely of the two to still be valid.
    public static func run(tokens: StravaTokenStore, auth: StravaAuth) async {
        guard let grant = tokens.grant else { return }
        tokens.clearGrant()
        try? await auth.revoke(grant.refreshToken, tokenTypeHint: "refresh_token")
    }
}
