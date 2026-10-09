import Foundation

/// Everything the athlete does not need while they are on the bar.
///
/// The split is not by importance but by *when*: what changes state mid-set stays on the camera
/// screen; navigation and configuration are settled before the clock starts, and they live here.
/// This is deliberately not a home screen: the app still opens straight to the camera.
///
/// Each row carries its current value as a subtitle, so the answer to "what am I set to?" does not
/// require opening the row to find out. Port of `MenuActivity`'s `render` and its subtitles; the
/// screen draws what `MenuBuilder.build` returns and decides nothing of its own.
public enum MenuRowID: CaseIterable, Sendable {
    case movements, progress, reminder, bodyWeight, heartRate, strava, voice, music, help
}

/// What a Strava row reports, in the builds that have Strava at all.
public enum StravaStatus: Equatable, Sendable {
    case notConnected
    case connected(athleteName: String?)
}

public struct MenuRow: Equatable, Sendable {
    public let id: MenuRowID
    public let title: String
    public let subtitle: String
    /// One sentence for the row: "Voice, On · 100% · Español".
    public var spoken: String { "\(title), \(subtitle)" }
}

/// The card that leads: who the scores belong to, and what they have earned so far.
public struct MenuProfileCard: Equatable, Sendable {
    public let title: String
    public let value: String
    public let name: String?
    public let hasPhoto: Bool
    public var spoken: String { "\(title), \(value)" }
}

public struct MenuPage: Equatable, Sendable {
    public let card: MenuProfileCard
    public let rows: [MenuRow]
    /// Said beside the Movements row while a workout is live, because it explains why that row will
    /// refuse rather than reporting the refusal after the fact.
    public let footnote: String?
    /// Whether tapping Movements is refused.
    public let movementsRefused: Bool

    /// How long each row waits behind the one above it as the list settles in. Every row is dealt on
    /// one running count with the profile card first, so the list carries on from it.
    public static let staggerMs = 34

    /// The delay of the `index`th thing on the screen, the profile card being the 0th.
    public static func delayMs(_ index: Int) -> Int { index * staggerMs }
}

public struct MenuInput {
    public var profile: Profile
    public var attempts: [Attempt]
    public var zone: Zone
    public var firstDayOfWeek: DayOfWeek
    public var today: LocalDate
    public var is24Hour: Bool
    /// Whether the photo file exists.
    public var hasPhoto: Bool
    /// A workout is live: the movements are refused until it is reset.
    public var workoutLive: Bool
    /// Whether a notification can be posted, for the reminder row to be honest about.
    public var notificationsAllowed: Bool
    /// The name of a chosen track, or nil when it can no longer be opened.
    public var trackName: (String) -> String?
    /// Nil in a build that has no Strava credentials: the row is absent rather than greyed out.
    public var strava: StravaStatus?
    /// The rows this build can open. A row whose screen arrives in a later phase is left out.
    public var shown: Set<MenuRowID>

    public init(profile: Profile, attempts: [Attempt], zone: Zone, firstDayOfWeek: DayOfWeek, today: LocalDate,
                is24Hour: Bool = true, hasPhoto: Bool = false, workoutLive: Bool = false,
                notificationsAllowed: Bool = true, trackName: @escaping (String) -> String? = { $0 },
                strava: StravaStatus? = nil, shown: Set<MenuRowID> = Set(MenuRowID.allCases)) {
        self.profile = profile
        self.attempts = attempts
        self.zone = zone
        self.firstDayOfWeek = firstDayOfWeek
        self.today = today
        self.is24Hour = is24Hour
        self.hasPhoto = hasPhoto
        self.workoutLive = workoutLive
        self.notificationsAllowed = notificationsAllowed
        self.trackName = trackName
        self.strava = strava
        self.shown = shown
    }
}

public enum MenuBuilder {

    public static let helpSubtitle = "What Cindy is, how it is scored, and where to stand"
    public static let liveFootnote = "Movements can only be changed between workouts — they have to mean one "
        + "thing for the whole score."

    public static func build(_ input: MenuInput) -> MenuPage {
        let profile = input.profile
        let name = profile.displayName
        let earned = Badges.earned(input.attempts, zone: input.zone, firstDayOfWeek: input.firstDayOfWeek)
        let card = MenuProfileCard(
            title: name ?? "You",
            value: Badges.headline(earned) ?? (name == nil && !input.hasPhoto
                ? "Add your name and photo" : "Finish a session to earn your first badge"),
            name: name, hasPhoto: input.hasPhoto)

        var rows: [MenuRow] = []
        func add(_ id: MenuRowID, _ title: String, _ subtitle: String) {
            if input.shown.contains(id) { rows.append(MenuRow(id: id, title: title, subtitle: subtitle)) }
        }
        add(.movements, "Movements", movementsSubtitle(profile))
        add(.progress, "Progress", progressSubtitle(input))
        add(.reminder, "Daily reminder", reminderSubtitle(input))
        add(.bodyWeight, "Body weight", bodyWeightSubtitle(profile))
        add(.heartRate, "Heart rate", heartRateSubtitle(input))
        if let strava = input.strava { add(.strava, "Strava", stravaSubtitle(strava)) }
        add(.voice, "Voice", voiceSubtitle(profile))
        add(.music, "Music", musicSubtitle(input))
        add(.help, "Help", helpSubtitle)
        return MenuPage(card: card, rows: rows, footnote: input.workoutLive ? liveFootnote : nil,
                        movementsRefused: input.workoutLive)
    }

    /// What the row says underneath "Movements": what was chosen, and whether the squats may switch
    /// themselves to heels flat. The second half is said only for the air squat, the one choice the
    /// setting does anything to: said beside a box squat it would promise something that never happens.
    public static func movementsSubtitle(_ profile: Profile) -> String {
        movementsSubtitle(profile.movements, smartSquats: profile.smartSquats)
    }

    public static func movementsSubtitle(_ movements: CindyProfile, smartSquats: Bool) -> String {
        smartSquats && movements.squat == .airSquat ? "\(movements.label()) · spots heels flat" : movements.label()
    }

    static func progressSubtitle(_ input: MenuInput) -> String {
        let sessions = input.attempts.count
        let streak = Streak.current(Streak.daysTrained(input.attempts, zone: input.zone), today: input.today)
        let count: String
        switch sessions {
        case 0: count = "No sessions yet"
        case 1: count = "1 session"
        default: count = "\(sessions) sessions"
        }
        return count + (streak >= 1 ? " · \(streak)-day streak" : "")
    }

    /// A reminder that is switched on but cannot be delivered says so, rather than promising a nudge
    /// that will never come.
    static func reminderSubtitle(_ input: MenuInput) -> String {
        if !input.profile.reminderOn { return "Off" }
        if !input.notificationsAllowed { return "Blocked \u{2014} notifications are off for Cindy" }
        return "Daily at \(Reminder.formatTime(input.profile.reminderMinute, is24Hour: input.is24Hour)) \u{00B7} not on days you train"
    }

    static func bodyWeightSubtitle(_ profile: Profile) -> String {
        profile.hasBodyWeight ? "\(JavaText.fixed(profile.bodyWeightKg, 0)) kg" : "Not set — calories need it"
    }

    /// Whether a watch is paired, and by name.
    static func heartRateSubtitle(_ input: MenuInput) -> String {
        guard let device = input.profile.heartRateDevice else { return "No watch paired" }
        return input.profile.body(nowYear: input.today.year).canUseHeartRate
            ? device.name : "\(device.name) · add your age for calories"
    }

    /// What the heart-rate sheet's "Your details" row says.
    public static func heartRateDetailsSubtitle(_ profile: Profile, nowYear: Int) -> String {
        let body = profile.body(nowYear: nowYear)
        return body.canUseHeartRate ? "\(body.sex!.label) · \(body.age!) y" : "Needed for heart-rate calories"
    }

    public static func voiceSubtitle(_ profile: Profile) -> String {
        profile.voiceOn
            ? "On · \(percent(profile.voiceVolume)) · \(VoicePacks.of(profile.voiceLanguage).nativeName)" : "Off"
    }

    public static func percent(_ value: Float) -> String { "\(Int(value * 100))%" }

    /// A name that cannot be read means the grant behind the track has gone, and the honest thing is
    /// to say so here rather than leave the athlete wondering mid-workout why the music never started.
    static func musicSubtitle(_ input: MenuInput) -> String {
        guard let uri = input.profile.musicTrack else { return "No track chosen" }
        guard let name = input.trackName(uri) else { return "That track can no longer be opened" }
        return input.profile.musicOn ? "\(name) · \(percent(input.profile.musicVolume))" : "Off · \(name)"
    }

    static func stravaSubtitle(_ status: StravaStatus) -> String {
        switch status {
        case .notConnected: return "Not connected — upload workouts"
        case .connected(let name): return "Connected · \(name ?? "Strava")"
        }
    }
}
