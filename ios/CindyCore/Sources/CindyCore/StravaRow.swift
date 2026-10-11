import Foundation

/// The results screen's Strava row: where this attempt's upload has got to, or an offer to start one.
///
/// Hidden entirely in a build with no Strava credentials, because there is nothing honest it could
/// say. Otherwise the screen redraws it as the ledger changes, so it has to notice rather than only
/// answer. Port of `ResultsActivity.stravaRowContent`.
public struct StravaRow: Equatable, Sendable {

    public enum Action: Equatable, Sendable {
        /// Queue this attempt and send it.
        case upload
        /// Say what is sent, then connect for this attempt.
        case askThenConnect
        /// Open the finished activity on Strava.
        case openActivity(Int64)
    }

    public static let label = "Strava"
    public static let viewOnStrava = "View on Strava"

    public let value: String
    /// Strava's guidelines want the link to its activity bold, underlined or Strava orange. Bold,
    /// because the orange is next to the app's own achievement orange, which means only that the
    /// athlete earned something.
    public let isLink: Bool
    public let action: Action?

    public init(_ value: String, link: Bool = false, action: Action? = nil) {
        self.value = value
        self.isLink = link
        self.action = action
    }

    /// The row for an attempt, or nil in a build that has no Strava.
    public static func of(config: StravaConfig, tokens: StravaTokenStore, ledger: StravaUploads,
                          atMillis: Int64) -> StravaRow? {
        guard config.available else { return nil }
        return content(connected: tokens.connected, status: ledger.status(atMillis: atMillis))
    }

    /// The row's value and tap, for whichever state applies right now.
    public static func content(connected: Bool, status: StravaUploadStatus?) -> StravaRow {
        if !connected { return StravaRow("Connect to upload", action: .askThenConnect) }
        guard let status = status else { return StravaRow("Upload", action: .upload) }
        switch status.state {
        case .queued, .processing:
            return StravaRow("Uploading…")
        case .done:
            if let id = status.activityId { return StravaRow(viewOnStrava, link: true, action: .openActivity(id)) }
            return StravaRow("Uploaded")
        case .failed:
            return StravaRow("Couldn't upload — tap to retry", action: .upload)
        case .needsReconnect:
            return StravaRow("Reconnect to upload", action: .askThenConnect)
        case .unavailable:
            return StravaRow("Not available for this attempt")
        }
    }
}
