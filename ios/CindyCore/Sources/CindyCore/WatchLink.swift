import Foundation

/// What the link to the paired heart-rate device is doing at this moment. Port of `WatchLink.kt`.
public enum WatchLink: Sendable {
    /// No device is paired, so there is no link to judge.
    case notPaired

    /// It is sending: a reading came in the last few seconds.
    case live

    /// It is not sending, whatever the reason: still connecting, broadcast off, Bluetooth off.
    case silent
}

/// What the athlete is asked, if anything, when they tap START.
public enum WatchPrompt: Sendable {
    case none

    /// No watch is paired: offer to pair one, since nothing else in the app does.
    case offerToPair

    /// A watch is paired but no heart rate is coming in: say so before a session starts without it.
    case askAboutSilentWatch
}

/// The rules for the heart-rate question at START, kept free of platform types so they can be tested
/// on their own: the screen that asks needs a phone, and getting these wrong is silent.
///
/// Nothing on iOS asks the question until the Bluetooth link exists (P15); the rules are here so the
/// two apps cannot disagree about them in the meantime.
public enum WatchLinks {

    /// How recent a reading has to be for the watch to count as sending.
    ///
    /// A healthy watch sends about one a second, so five is a long gap. There is deliberately no
    /// allowance for a link that is still being made: if no heart rate is arriving when START is
    /// tapped, a session that starts now starts without one, and the athlete is told. Starting
    /// anyway costs one tap.
    public static let silentAfterMs: Int64 = 5_000

    /// Judges the link from when it last spoke, on the monotonic clock the readings are stamped with.
    ///
    /// Never having spoken is silent: a reading of 0 is a long time ago on any clock.
    public static func judge(paired: Bool, lastReadingAt: Int64, now: Int64) -> WatchLink {
        if !paired { return .notPaired }
        if now - lastReadingAt <= silentAfterMs { return .live }
        return .silent
    }

    /// What to ask when START is tapped.
    ///
    /// `bleAvailable` is whether the phone can talk to a watch at all: there is no point offering one
    /// to a phone that cannot. `offerSilenced` is the athlete having said not to ask again. A silent
    /// watch is always asked about, since that one cannot be turned off: it is a watch the athlete
    /// chose, which is not doing what they chose it for.
    public static func promptAtStart(_ link: WatchLink, bleAvailable: Bool, offerSilenced: Bool) -> WatchPrompt {
        switch link {
        case .notPaired: return bleAvailable && !offerSilenced ? .offerToPair : .none
        case .silent: return .askAboutSilentWatch
        case .live: return .none
        }
    }

    /// The first line of the sheet that asks about a silent watch: what is wrong, if it is known.
    public static func why(_ status: HeartRateStatus) -> String {
        switch status {
        case .bluetoothOff: return "Bluetooth is off on this phone."
        case .noPermission: return "Cindy is not allowed to use Bluetooth."
        default: return "It is paired but has sent no heart rate. Is heart-rate broadcast on?"
        }
    }
}
