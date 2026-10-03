import Foundation

/// What the voice sheet's language list says, kept apart from the views that show it.
///
/// Free of platform types on purpose: whether a row tells the athlete the truth about their phone
/// — that a voice is ready, or is on its way, or has been on its way suspiciously long — is the
/// whole point of the list, and is only worth checking if it can be checked without a screen.
public enum VoiceLanguageText {

    /// How long a download may go without its voice turning up before the row says so. The engine
    /// reports no progress, so time is the only sign there is: one that is asked for on mobile
    /// data it has been told to avoid can wait indefinitely, and looks exactly like one that is
    /// merely slow.
    public static let stuckAfterMs: Int64 = 2 * 60_000

    /// How long to wait for the engine to answer at all before saying it isn't.
    public static let noAnswerAfterMs: Int64 = 6_000

    private static let notAnswering = "This phone's voice engine isn't answering"
    private static let notOffered = "Not offered by this phone's voice engine"

    /// The second line of a language's row: where it stands on this phone.
    ///
    /// `state` is `nil` until the engine has answered. `downloadingMs` is how long ago a download
    /// was asked for, if one was, and `waitedMs` how long the list has been open.
    public static func caption(_ state: PackState?, downloadingMs: Int64?, waitedMs: Int64) -> String {
        switch state {
        case nil: return waitedMs >= noAnswerAfterMs ? notAnswering : "Checking…"
        case .ready: return "Ready"
        case .downloading:
            return stuck(downloadingMs)
                ? "Still waiting. The voice engine may need Wi-Fi. Tap to retry."
                : "Downloading…"
        case .downloadable: return "Tap to download"
        case .onlineOnly: return "Online voice only. Counting stays in English."
        case .unsupported: return notOffered
        }
    }

    private static func stuck(_ downloadingMs: Int64?) -> Bool { (downloadingMs ?? 0) >= stuckAfterMs }

    /// Whether choosing the row should ask the engine for its voice.
    ///
    /// A language that is not on the phone, of course. And one whose request has gone unanswered
    /// for `stuckAfterMs` too: the engine never says that a request was dropped, or cancelled in
    /// its own screen, so asking again is the only way out of a row that would otherwise say
    /// "downloading" until the sheet is closed. A request still fresh is left alone, since asking
    /// again would only restart its clock.
    public static func asksForDownload(_ state: PackState?, downloadingMs: Int64?) -> Bool {
        state == .downloadable || (state == .downloading && stuck(downloadingMs))
    }

    /// Whether the row can be chosen.
    ///
    /// A language nobody knows the state of yet can: refusing it because the engine is slow to
    /// answer would make the list unusable for the first moment. One the engine does not speak
    /// at all cannot, since choosing it would mean counting in English while the row says otherwise.
    public static func selectable(_ state: PackState?) -> Bool { state != .unsupported }

    /// What to say when a preview starts, if it is not the voice a workout would use.
    ///
    /// A language that is not on the phone can only be previewed over the network, and the
    /// athlete should know that is what they are hearing: it is a sample of the language, in a
    /// voice they will not get until it has been downloaded. Nothing for a language the engine
    /// does not speak, since nothing plays.
    public static func previewNote(_ state: PackState?) -> String? {
        switch state {
        case nil, .ready, .unsupported: return nil
        default: return "Playing an online preview"
        }
    }

    /// What to say when a preview does not play.
    public static func previewFailure(_ failure: SpeechFailure, _ pack: VoicePack) -> String {
        switch failure {
        case .network: return "The \(pack.englishName) preview needs an internet connection"
        case .notInstalled: return "The \(pack.englishName) voice is still downloading"
        case .unavailable: return "This phone's voice engine can't play \(pack.englishName)"
        case .other: return "The preview didn't play"
        }
    }

    /// What to say when the athlete asks the engine for something before it has answered at all:
    /// that it is on its way, or, once it has had long enough, that it may not be.
    public static func engineSilent(waitedMs: Int64) -> String {
        waitedMs >= noAnswerAfterMs ? notAnswering : "The voice engine is still starting. Try again in a moment."
    }

    /// What a screen reader reads for a row: the language, how it stands, and whether it is the one.
    public static func description(_ pack: VoicePack, _ caption: String, chosen: Bool) -> String {
        "\(pack.nativeName), \(pack.englishName), \(caption)" + (chosen ? ", selected" : "")
    }

    /// What a screen reader reads for a row's preview button.
    ///
    /// The row's other half says when a language is not offered, and this half should not sound
    /// like a button that works.
    public static func previewDescription(_ pack: VoicePack, _ state: PackState?) -> String {
        "Hear \(pack.englishName)" + (state == .unsupported ? ", \(notOffered.lowercased())" : "")
    }

    /// Why a row that cannot be chosen says so when it is tapped.
    public static func unsupportedNotice(_ pack: VoicePack) -> String {
        "This phone's voice engine doesn't speak \(pack.englishName). " +
            "Another engine in the phone's speech settings might."
    }
}
