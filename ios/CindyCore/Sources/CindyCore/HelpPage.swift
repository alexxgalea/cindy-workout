import Foundation

/// The parts of the app that are built in a later phase, or not in every build. Help describes a
/// part only when it is switched on, because a Help screen that describes something that is not
/// there is worse than none. A build with all of them is the whole of `HelpActivity`'s text.
///
/// `strava` is a build with Strava credentials, as on Android. The other four are the iOS phases
/// that bring them: heart rate (P15), filming (P16), music (P17) and the daily reminder (P18).
public struct HelpFeatures: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let strava = HelpFeatures(rawValue: 1 << 0)
    public static let heartRate = HelpFeatures(rawValue: 1 << 1)
    public static let filming = HelpFeatures(rawValue: 1 << 2)
    public static let music = HelpFeatures(rawValue: 1 << 3)
    public static let reminders = HelpFeatures(rawValue: 1 << 4)

    public static let all: HelpFeatures = [.strava, .heartRate, .filming, .music, .reminders]
}

/// What a row on the Help screen does when it is tapped.
public enum HelpAction: Equatable, Sendable {
    /// The first-launch pages, taken again as a replay.
    case takeTour
    case openLink(String)
    case showLicence(Licences.Licence)
}

/// A row that goes somewhere: a title, one line beneath it, and where it goes.
public struct HelpRow: Equatable, Sendable {
    public let title: String
    public let subtitle: String
    public let action: HelpAction

    /// One sentence for the row, which starts with its title.
    public var spoken: String { "\(title), \(subtitle)" }
}

/// One of CrossFit's score tiers. `reached` is nil for the tier this app cannot judge, which is
/// never ticked and says so.
public struct HelpTier: Equatable, Sendable {
    public let name: String
    public let detail: String
    public let reached: Bool?

    public static let notScored = "not scored"

    public var spoken: String {
        guard let reached else { return "\(name), \(detail), not scored" }
        return reached ? "\(name), \(detail), reached" : "\(name), \(detail), not yet reached"
    }
}

/// One thing on the Help screen. The screen lays these out in order and decides nothing about them.
public enum HelpBlock: Equatable, Sendable {
    case row(HelpRow)
    case heading(String)
    case paragraph(String)
    /// Smaller, dimmer.
    case quiet(String)
    /// CrossFit's words, marked as theirs by the attribution beneath rather than by a coloured bar.
    case quote(String)
    case bullets([String])
    /// The rep scheme beside the mark whose proportions it is.
    case workoutCard(title: String, scheme: [HelpScheme], note: String)
    case scaledCard(title: String, body: String, note: String)
    case tiers([HelpTier])
    /// The placement diagram, in its permanent home: it is offered once before the first setup check
    /// and can be dismissed for good there, so it needs somewhere to live afterwards.
    case diagram
    /// Rows in one group.
    case rows([HelpRow])
}

public struct HelpScheme: Equatable, Sendable {
    public let count: String
    public let name: String
}

public struct HelpPage: Equatable, Sendable {
    public let blocks: [HelpBlock]

    /// Every string the athlete reads, in order: what the Robolectric tests read off the views.
    public var texts: [String] {
        blocks.flatMap { block -> [String] in
            switch block {
            case .row(let r): return [r.title, r.subtitle]
            case .rows(let rs): return rs.flatMap { [$0.title, $0.subtitle] }
            case .heading(let t), .paragraph(let t), .quiet(let t), .quote(let t): return [t]
            case .bullets(let items): return items
            case .workoutCard(let title, let scheme, let note):
                return [title] + scheme.flatMap { [$0.count, $0.name] } + [note]
            case .scaledCard(let title, let body, let note): return [title, body, note]
            case .tiers(let tiers):
                return tiers.flatMap { [$0.name, $0.detail] + ($0.reached == nil ? [HelpTier.notScored] : []) }
            case .diagram: return []
            }
        }
    }

    /// All of it, one string per line, for a test to look through.
    public var text: String { texts.joined(separator: "\n") }
}

public struct HelpInput {
    public var attempts: [Attempt]
    public var features: HelpFeatures
    public var versionName: String
    public var versionCode: String

    public init(attempts: [Attempt], features: HelpFeatures, versionName: String, versionCode: String) {
        self.attempts = attempts
        self.features = features
        self.versionName = versionName
        self.versionCode = versionCode
    }
}

/// What Cindy is, and what this app is doing while you do it. Port of `HelpActivity`'s `render`.
///
/// The workout half is CrossFit's, quoted rather than paraphrased and attributed on the page: the
/// definition, the scaled version, the score tiers and the pacing advice all come from
/// `AppLinks.crossfitCindy`. Note that CrossFit does *not* publish per-movement range-of-motion
/// standards on that page; it links out to a page per movement. So this screen does not state any
/// either, rather than inventing standards and putting CrossFit's name near them.
///
/// The second half is this app's own, and is the part most worth reading: the camera cannot see
/// what it is not shown, and every hint it gives has a specific cause.
///
/// Where the words differ from Android's it is because the app does: Photos for Movies/Cindy,
/// iCloud Backup for Android's backup, Settings for the speech engine's own screen, a hold on +1
/// for the SKIP button the iOS camera screen does not have. Each is marked `iOS:` where it is made.
public enum HelpBuilder {

    public static let tourTitle = "Take the tour"
    public static let tourSubtitle = "The first-launch pages and a tour of the camera screen"
    public static let privacyPolicyTitle = "Privacy policy"
    public static let privacyPolicySubtitle = "Opens in your browser"
    public static let licenceSubtitle = "Full text"
    public static let crossfitButton = "CROSSFIT.COM"
    public static let crossfitButtonDescription = "Open the CrossFit page for Cindy"

    private static func s(_ parts: String...) -> String { parts.joined() }

    public static func build(_ input: HelpInput) -> HelpPage {
        var out: [HelpBlock] = []
        let has = input.features.contains

        func heading(_ t: String) { out.append(.heading(t)) }
        func paragraph(_ t: String) { out.append(.paragraph(t)) }
        func quiet(_ t: String) { out.append(.quiet(t)) }
        func quote(_ t: String) { out.append(.quote(t)) }
        func bullets(_ items: String...) { out.append(.bullets(items)) }

        // First, because it is the one thing on this screen that is for someone who is lost rather
        // than curious: the pages and the tour of the camera screen, taken again.
        out.append(.rows([HelpRow(title: tourTitle, subtitle: tourSubtitle, action: .takeTour)]))

        heading("THE WORKOUT")
        out.append(.workoutCard(
            title: "AMRAP 20:00",
            scheme: [HelpScheme(count: "5", name: "Pull-ups"), HelpScheme(count: "10", name: "Push-ups"),
                     HelpScheme(count: "15", name: "Air squats")],
            note: s("One round is 30 reps. The score is rounds completed, plus any reps of the ",
                    "round you are part-way through when the clock stops.")))
        quote(s("Complete as many rounds and reps as possible in 20 minutes of: ",
                "5 pull-ups, 10 push-ups, 15 squats"))

        heading("SCALED")
        out.append(.scaledCard(
            title: "AMRAP 12:00",
            body: "3 ring rows\n6 assisted push-ups\n9 squats",
            note: s("CrossFit's beginner version. This app always runs the 20-minute clock and ",
                    "the 5, 10 and 15 reps, so it does not run this rep scheme — but it does count ",
                    "scaled movements. Choose them under Movements in the menu: the camera counts ",
                    "band-assisted pull-ups, push-ups from the knees and box squats, and you tap +1 ",
                    "for the ones it cannot follow, such as inverted rows. Either way the session ",
                    "is saved as an Adaptive Cindy.")))
        bullets(
            s("Pull-ups scale to \"any movement that is an upper-body pulling option\" — ",
              "leg-assisted pull-ups, or ring rows."),
            s("Push-ups scale to \"any bodyweight horizontal pressing movement, like an incline ",
              "push-up or push-up from the knees\"."),
            s("Squats scale on reps, or by squatting \"to a target that could be set above the ",
              "typical full range of motion\"."))
        paragraph(s("Squatting with your heels flat? That is a correct squat too. Choose Heels flat under ",
                    "Movements in the menu. Or turn on Spot heels-flat squats there: after three ",
                    "heels-flat squats Cindy switches to Adaptive Cindy, says so out loud, and counts ",
                    "them, the first three included. It is off by default while it is being tested."))

        heading("WHAT IT TESTS")
        quote(s("Tests athletes' muscular endurance, stamina, and capacity with various low-skill ",
                "gymnastics elements."))
        paragraph(s("Cindy is time-priority: the 20 minutes are fixed and you chase reps inside them. ",
                    "That is why the clock here never stops for a rep and only pauses when you say so."))

        heading("WHAT A GOOD SCORE IS")
        paragraph("CrossFit's tiers, in rounds:")
        let history = input.attempts
        // These tiers describe the prescribed movements, so only a standard Cindy is measured
        // against them. Ticking "Rx'd" off the back of a session run with knee push-ups would be
        // exactly the claim the note below has always refused to make -- the difference now is
        // that the app records which movements were used and can tell.
        let best = Records.bestIn(history, profile: CindyProfile.standard)
        func reached(_ minRounds: Int) -> Bool { best.map { $0.rounds >= minRounds } ?? false }
        // The scaled tier is deliberately never ticked: this app counts the prescribed rep scheme,
        // so it has no idea whether the work was scaled, and a tick there would be a claim it cannot
        // make.
        out.append(.tiers([
            HelpTier(name: "Beginner", detail: "8–10+ rounds, scaled", reached: nil),
            HelpTier(name: "Intermediate", detail: "8–10+ rounds as prescribed", reached: reached(8)),
            HelpTier(name: "Rx'd", detail: "20+ rounds", reached: reached(20)),
            HelpTier(name: "Elite", detail: "25+ rounds", reached: reached(25))
        ]))
        let adaptiveBest = history.filter { $0.profile?.isStandard != true }.max { $0.totalReps < $1.totalReps }
        if let best {
            quiet("Your best so far: \(best.scoreLabel) — \(best.rounds) rounds.")
        } else if let adaptiveBest {
            // Not "no score": they have trained, and saying otherwise to someone whose sessions
            // were all adaptive would be the app pretending they were not there.
            quiet(s("Your best is \(adaptiveBest.scoreLabel) at \(adaptiveBest.caption). These ",
                    "tiers describe the prescribed movements, so it is ranked against your own ",
                    "sessions at the same movements instead."))
        } else {
            quiet("Finish a Cindy and your best will show up against these.")
        }
        quiet(s("The level on your session page, First Steps up to Legend, is this app's own ",
                "ladder and a separate, finer-grained scale. These four are CrossFit's."))

        heading("PACING")
        bullets(
            "\"The fastest athletes will complete rounds in under 45 seconds.\"",
            s("\"Striving to complete each round in under 2 minutes is a great goal for all ",
              "levels to shoot for.\""),
            "The session page charts every round split, stacked by movement, so you can see where the pace went.")
        quote(s("If muscular failure and full range of motion are a concern with push-ups, consider ",
                "breaking up the reps early. For example, many athletes will start this workout ",
                "by performing 5 reps, taking a quick break to shake out their arms, and ",
                "completing the remaining 5 reps."))

        heading("RANGE OF MOTION")
        quote(s("Adhering to the full range of motion in all movements is important for structural ",
                "integrity and joint health."))
        paragraph(s("CrossFit keeps the standards for each movement on its own page rather than on the ",
                    "Cindy page, so this screen does not restate them. Tap CROSSFIT.COM below and ",
                    "follow the links to The Kipping Pull-up, The Push-up and The Air Squat."))

        heading("HOW THIS APP COUNTS")
        paragraph(s("A phone on the floor sees a different shape than one at chest height, so nothing ",
                    "here is a fixed angle. The app learns your range from your own movement and ",
                    "judges reps against that."))
        out.append(.diagram)
        bullets(
            s("Stand the phone so your whole body stays in frame, and leave it there — moving it ",
              "mid-workout invalidates what it has learned, so a pause re-calibrates."),
            s("START runs a setup check first: two slow pull-ups teach it your range. SKIP, ",
              "pressed during the check, asks and then goes straight in, calibrating as you go."),
            s("For pull-ups it works out where your bar is from your dead hangs. The box on screen ",
              "is the bar zone your hands must be inside; the dashed line under it is where ",
              "your head has to drop back below before the next rep can count."),
            s("Push-ups and squats do not start counting until you are actually in position — ",
              "\"Get set on the floor\", \"Stand up to start\". Getting up off the floor after ",
              "push-ups is not a squat."),
            s("When a rep will not count, the status line says why, and says it out loud if ",
              "nothing changes. The voice can be turned off under Voice in the menu."),
            // iOS: the camera screen has no SKIP button; holding +1 does what it does.
            s("−1 and +1 fix a miscount while the clock is running. Once it has started, holding +1 ",
              "leaves the movement you are in for the next one: the reps you did in it stay counted, and ",
              "the rest are not made up."),
            s("Once the clock has started, the stop button takes FLIP's place. It asks first, ",
              "then ends the workout early and saves your score so far."))

        voiceAndMusic(&out, music: has(.music))
        if has(.filming) { filming(&out) }
        sessionPage(&out, strava: has(.strava))
        comparing(&out)
        lifted(&out)
        if has(.heartRate) { heartRate(&out) }

        heading("CALORIES AND STREAKS")
        paragraph(s("The calorie figure on the session page is an estimate, and it is labelled as one. ",
                    "With no watch there is no honest way to measure this, so it uses the standard ",
                    "MET equation that every strapless tracker uses underneath: ",
                    "kcal = MET × 3.5 × your weight in kg ÷ 200, per minute."))
        bullets(
            s("The Compendium of Physical Activities puts vigorous calisthenics and general ",
              "circuit training at 8 METs. That is taken to describe ten rounds in the ",
              "twenty minutes."),
            s("Cindy is an AMRAP, so eight rounds and twenty-five rounds are not the same effort. ",
              "The MET is scaled by the rate you actually worked at, and capped at both ends — ",
              "no one sustains more than 14 METs for twenty minutes."),
            "Paused time is excluded. Resting with the clock stopped is not work.",
            s("Nothing is shown until you enter your body weight, under Body weight in the menu ",
              "or from the session page, because a guessed weight would produce a confident ",
              "number that is wrong by however far the guess missed. It is stored on this ",
              "phone only."))
        if has(.heartRate) {
            paragraph(s("A watch changes the method. When a paired watch was sending during the workout, ",
                        "and your birth year and sex are set as well as your weight, the minutes it ",
                        "covered use the Keytel et al. (2005) heart-rate equation, fitted separately ",
                        "for women and men from measured energy expenditure. Any minute the watch did ",
                        "not cover — a dropped connection, a reading that cannot be right — falls back ",
                        "to the MET model for exactly that stretch, and the note under the figure says ",
                        "how much came from which."))
            bullets(
                s("Heart rate makes it a better estimate, not a measurement, and it stays labelled ",
                  "as one."),
                s("A session recorded with a watch before your details were set can use it once you ",
                  "add them: the session page offers to, and the figure is worked out again."),
                s("On the timeline the same estimate builds up across the workout, solid where your ",
                  "heart rate measured a stretch and dashed where your reps estimated it. It ends ",
                  "on the figure in Details."))
        }
        paragraph(s("The streak on the Progress screen counts consecutive days on which you trained, in ",
                    "your own time zone. It does not break the moment midnight passes — a day you ",
                    "have not finished living yet still counts as alive, so training this evening ",
                    "keeps it going. The weekly streak does the same for weeks with at least one ",
                    "session."))

        profileAndBadges(&out)
        if has(.reminders) { reminders(&out) }
        if has(.strava) { strava(&out) }
        privacy(&out, features: input.features)
        licences(&out)

        heading("SOURCE")
        paragraph(s("The workout, the scaled version, the score tiers and the pacing quotes on this ",
                    "screen are from CrossFit's own page for Cindy."))
        quiet(AppLinks.crossfitCindy)
        quiet(s("Everything from HOW THIS APP COUNTS to this credit is this app's own, ",
                "not CrossFit's."))
        quiet(s("Cindy Tracker is an independent app. It is not affiliated with or endorsed by ",
                "CrossFit, LLC. CrossFit is a registered trademark of CrossFit, LLC."))

        // Last, so it is the line a tester reads out when they report a problem. A debug build
        // carries its own suffix here, which is how the two builds are told apart on a phone.
        quiet("Cindy \(input.versionName) (\(input.versionCode))")

        return HelpPage(blocks: out)
    }

    // MARK: this app's own sections

    private static func voiceAndMusic(_ out: inout [HelpBlock], music: Bool) {
        out.append(.heading(music ? "VOICE AND MUSIC" : "VOICE"))
        out.append(.paragraph(s("Voice, under Voice in the menu, counts each rep out loud, calls the movement ",
                                "changes and the clock, and says when you are in a position that will score. ",
                                "It has a switch and a volume, and HEAR IT plays a sample.")))
        out.append(.bullets([
            s("It speaks English, Spanish, French, German, Italian, Portuguese (Brazil), Dutch, ",
              "Polish, Romanian, Turkish or Russian. The screens stay in English; only what ",
              "is said aloud changes."),
            // iOS: an app cannot ask iOS to download a voice; Settings is where they are added.
            s("The voices belong to your iPhone, not to Cindy. iOS cannot be asked to fetch one for an ",
              "app, so a better voice is added in Settings, under Accessibility, Spoken Content, ",
              "Voices, and Manage voices takes you to Settings."),
            s("A workout only uses voices stored on the phone, so counting works offline. If ",
              "your language is not there yet it counts in English and a note says so as ",
              "the workout starts."),
            "A language the phone has no voice for at all is dimmed and cannot be chosen.",
            "The wording in the languages other than English has not been read by native speakers yet."
        ]))
        if music {
            out.append(.paragraph(s("Music, under Music in the menu, is one track you already have on the phone. It ",
                                    "plays while the clock runs, pauses when you pause, and drops in volume ",
                                    "whenever the voice speaks. Nothing is uploaded.")))
        }
    }

    private static func filming(_ out: inout [HelpBlock]) {
        out.append(.heading("FILMING"))
        // iOS: the film is saved to Photos, with add-only access and no album.
        out.append(.paragraph(s("REC films the workout to Photos on your iPhone, after a three-second ",
                                "countdown that the voice counts too. The skeleton, clock, round, movement and ",
                                "rep count are burned into the picture, with a CINDY watermark. There is no ",
                                "sound.")))
        out.append(.bullets([
            s("Filming through the setup check shows it for what it is. The clock panel says ",
              "SETUP, the round panel says CALIBRATION, and the movement is marked NOT ",
              "SCORED, with its count against the two calibration reps. They are not the ",
              "first two reps of a round."),
            s("When the check passes, a CALIBRATED · 2 REPS banner is burned in for three ",
              "seconds as the clock starts. If you skipped the check it says CALIBRATION ",
              "SKIPPED instead.")
        ]))
    }

    private static func sessionPage(_ out: inout [HelpBlock], strava: Bool) {
        out.append(.heading("THE SESSION PAGE"))
        out.append(.paragraph(s("Every workout ends on its session page. Any session can be opened again from ",
                                "Progress, as it was: tap a row on the leaderboard, tap a session in a day on ",
                                "the calendar, or select a session on the chart and tap OPEN. Opened again it ",
                                "is headed by its date, shows a single DONE, and has no streak, because a ",
                                "streak describes today.")))
        out.append(.bullets([
            s("Six tiles sit under the score: rounds, reps, time, average round, fastest and ",
              "slowest. Each says what it is made of, and a tile with nothing to say shows ",
              "a dash, never a zero."),
            s("ROUND BY ROUND has a pill for every round, split into pull-ups, push-ups and ",
              "squats in the 5:10:15 proportions of the scheme, in the same three ",
              "brightnesses as the card at the top of this screen. It is filled by what you ",
              "actually did, so a round with a skipped set is hollow where it was skipped. ",
              "Tap a pill, or drag along them, to read one."),
            s("MOVEMENTS gives each movement's reps, its time, its average finished set and its ",
              "share of the set time, in your own movement words: \"knee push-ups\", not ",
              "\"push-ups\"."),
            s("TIMELINE draws the session across its 20 minutes: your reps climbing, and your ",
              "heart rate and the calorie estimate beneath when there are any. Touch it or ",
              "drag along it and one cursor crosses every line, reading out the clock, the ",
              "round and movement, your reps by then, your heart rate, and how far ahead or ",
              "behind you were against the session you are comparing with."),
            s("ROUND SPLITS is a bar for each round, stacked by movement. Taller is slower. ",
              "Tap or drag across the bars to read one, with a tick over each bar marking ",
              "the same round in the session you are comparing with. An outlined bar is a ",
              "round still under way when the clock stopped."),
            strava
                ? s("DETAILS, at the foot, holds paused and real time, reps added by hand, how ",
                    "long the camera lost you, the calorie estimate and the Strava upload.")
                : s("DETAILS, at the foot, holds paused and real time, reps added by hand, how ",
                    "long the camera lost you and the calorie estimate.")
        ]))
        out.append(.paragraph(s("Only what was recorded is shown, and nothing is worked out from the round count ",
                                "to fill a gap. A session from before sets or rep times were kept shows less: ",
                                "the tiles, and per-set steps on the timeline where that is all there is, with ",
                                "a note under the chart saying so. Reps you tapped in count, and are named as ",
                                "tapped in wherever they appear. A score the camera could not fully see says ",
                                "\"at least\" wherever a figure comes from it.")))
    }

    private static func comparing(_ out: inout [HelpBlock]) {
        out.append(.heading("COMPARING SESSIONS"))
        out.append(.paragraph(s("COMPARED WITH sets the session against your best or your last time. A card gives ",
                                "that session's date, score and reps, and how this one went: reps ahead or ",
                                "behind, rounds, and how much faster or slower the average round was. Tap the ",
                                "card to open that session. The choice also draws the dashed line on the ",
                                "timeline and the ticks on the round splits.")))
        out.append(.bullets([
            s("Only sessions at the same movements are compared. A band-assisted session is ",
              "never set against a strict one."),
            s("Only earlier sessions are. A session is never measured against one that had not ",
              "happened yet, so opening an old one cannot credit it with a comparison a later ",
              "session earned."),
            s("With no earlier session at the same movements there is no card, and the timeline ",
              "and splits are drawn on their own.")
        ]))
    }

    private static func lifted(_ out: inout [HelpBlock]) {
        out.append(.heading("WHAT YOU LIFTED"))
        out.append(.paragraph(s("Between the level and the comparison, one card puts the session in things you ",
                                "can picture: how heavy it was in animals, and how much energy it burned in ",
                                "cups of tea, phone charges or hours of an LED bulb. Never in food. The animal ",
                                "changes from day to day, and a session opened again shows the one it showed ",
                                "the first time.")))
        out.append(.paragraph(s("Both are estimates, and a footnote on the card says how. A rep does not lift ",
                                "all of your weight, only a share of it:")))
        out.append(.bullets([
            "Pull-ups: 95%, because your hands and forearms stay on the bar.",
            "Push-ups: 64%, or 49% from the knees (Ebben et al., 2011).",
            "Air, heels-flat and box squats: 88%, the body above the knees.",
            s("The total is your weight, times that share, times the reps you banked, added ",
              "up. Reps you tapped in count, and the card says so."),
            s("Left out, and named on the card rather than guessed: band-assisted, foot-assisted ",
              "and negative pull-ups, inverted rows, incline push-ups and supported squats. ",
              "There is no share of your weight the app can stand behind for them."),
            "The energy is the calorie estimate from Details, so the two never disagree."
        ]))
        out.append(.paragraph(s("A session the camera could not fully see says \"at least\". A session from ",
                                "before sets were timed shows the energy but no weight lifted. With no body ",
                                "weight on file the card is one row asking for it.")))
    }

    private static func heartRate(_ out: inout [HelpBlock]) {
        out.append(.heading("HEART RATE"))
        out.append(.paragraph(s("Cindy can read the heart rate a watch or chest strap broadcasts, and uses it for ",
                                "calories and on the session page. There is no heart-rate number on the camera ",
                                "screen. It appears afterwards.")))
        // iOS: the Android bullets about a Garmin already linked through Garmin Connect, and about
        // Location on Android 11 and older, are Android's alone. P15 builds the pairing screens and
        // is the place to say what iOS shows.
        out.append(.bullets([
            s("Pair it under Heart rate in the menu, with FIND MY WATCH. The scan lasts twelve ",
              "seconds, you tap your device once, and after that it reconnects by itself ",
              "whenever the camera screen is open."),
            s("Broadcast has to be on first. Garmin: Broadcast Heart Rate. Polar: share heart ",
              "rate with other devices. Chest straps broadcast whenever they are worn. Apple ",
              "Watch and most smartwatches do not broadcast a standard heart rate."),
            "iOS asks for Bluetooth permission the first time you pair.",
            s("Right after pairing it asks for your birth year and sex, if it does not have them. The calorie formula is ",
              "fitted separately for women and men and shifts with age, and the zones are ",
              "measured against a maximum worked out from your age. Prefer not to say uses ",
              "the average of the two formulas. Change them under Your details in the same ",
              "sheet."),
            s("If a watch is paired but silent when you start, a note says calories will use ",
              "your reps until it arrives.")
        ]))
        out.append(.paragraph(s("The heart-rate card on the session page gives your average and maximum, how much ",
                                "of the clock the watch covered, your time in each of five zones, and your ",
                                "hardest round: the finished round with the highest average among those the ",
                                "watch saw for at least thirty seconds. The timeline gains a heart-rate line. ",
                                "Average, maximum and zone time count only the time the watch covered. A gap is ",
                                "left out, not averaged in as zero.")))
        out.append(.bullets([
            s("Zones are shares of a maximum heart rate worked out from your age as ",
              "208 − 0.7 × age (Tanaka et al., 2001). That is an estimate, not a maximum ",
              "measured on you. Under 60% is Warm-up, then Easy from 60%, Aerobic from 70%, ",
              "Threshold from 80% and Maximum from 90%, with each zone's range printed beside it."),
            s("Without your birth year the card keeps its figures and offers to ask for it, ",
              "rather than guessing an age."),
            "A watch can lag your effort by a few seconds.",
            s("A session with no heart rate shows no card at all, and an older one shows ",
              "nothing rather than a guess.")
        ]))
        out.append(.paragraph(s("Heart rate, zones and calories here are training estimates. Cindy is not a ",
                                "medical device.")))
    }

    private static func profileAndBadges(_ out: inout [HelpBlock]) {
        out.append(.heading("YOU AND YOUR BADGES"))
        out.append(.paragraph(s("The card at the top of the menu opens You: a name, a photo, and the badges your ",
                                "sessions have earned. There is no account. Nothing is signed in to, and the ",
                                "app uploads neither.")))
        out.append(.bullets([
            "Your name is used on the leaderboard, and \"You\" stands in until there is one.",
            s("Your photo comes from the system photo picker, which needs no permission. The app ",
              "keeps its own small copy, so deleting the original loses nothing. Without one ",
              "the circle shows your initials."),
            s("There are 26 badges in six families: sessions, rounds, streaks, volume, pace and ",
              "craft. Each is worked out from the sessions you have recorded, never handed ",
              "out for opening the app. A locked one says how far along you are, and a tap ",
              "opens what it asks for and when you won it."),
            s("Badges for a score, the rounds and the pace, are earned only by a standard Cindy ",
              "the camera could stand behind, as a record is. The two pace badges are the ",
              "marks quoted under PACING. A session at other movements is a different ",
              "workout, not a lower score, and earns the badge for making it yours."),
            s("The session page names up to three badges a session just earned, and counts the ",
              "rest."),
            "Clearing your records removes the badges with them, and keeps your name and photo."
        ]))
    }

    private static func reminders(_ out: inout [HelpBlock]) {
        out.append(.heading("REMINDERS"))
        out.append(.paragraph(s("Off until you ask. Daily reminder in the menu sets the time, six in the evening ",
                                "to start with, and TRY IT sends one now. There is at most one a day, and none ",
                                "on a day you have already trained. It names the streak at stake, or the best ",
                                "score to chase when there is none, and it never appears during a workout.")))
        // iOS: Android's "up to fifteen minutes late" is its scheduler's. P18 builds the iOS one
        // and is the place to say whether it is also inexact.
        out.append(.bullets([
            s("iOS asks to allow notifications when you switch it on. If they ",
              "are off the row says Blocked and offers Settings."),
            "It is worked out on the phone. Nothing leaves it."
        ]))
    }

    private static func strava(_ out: inout [HelpBlock]) {
        out.append(.heading("STRAVA"))
        out.append(.paragraph(s("Strava, in the menu, connects your Strava account. A sheet first says what each ",
                                "workout will send; tap Connect with Strava there and Strava's own page opens, ",
                                "in the Strava app if you have it. Nothing is sent before you connect, and no ",
                                "video or pose data is ever sent.")))
        out.append(.bullets([
            s("Once connected, each finished workout uploads by itself as a Crossfit activity: ",
              "the score, every movement as a set with the reps actually banked, clock, ",
              "paused and real time, and calories when you have a body weight set, from ",
              "your heart rate when a watch recorded one. The heart-rate trace goes with it."),
            s("Upload automatically is a switch in the Strava sheet, on by default. With it off ",
              "the Strava row under Details offers \"Upload\" instead. Finish a workout before ",
              "connecting and it offers \"Connect to upload\", which links the account and then ",
              "sends that workout."),
            s("That row shows where the upload has got to: uploading, then a View on Strava ",
              "link to the activity. If it fails it says so and you tap to retry, and if Strava needs ",
              "you to connect again it says that. The upload carries on in the background, ",
              "waits for a connection and retries by itself."),
            s("Sessions from before you connected are not sent on their own; open one and use ",
              "its Strava row. One recorded before reps and sets were banked cannot be ",
              "described honestly, and says it is not available."),
            s("DISCONNECT clears the connection from the phone at once and asks Strava to end ",
              "it. If Strava still lists Cindy Tracker at strava.com/settings/apps ",
              "afterwards, remove it there too.")
        ]))
    }

    /// What stays on the phone and what does not. Every line here is a claim about the code, and
    /// the stores hold the app to it: the Data safety and privacy answers and the published policy
    /// say the same things, so a line is changed in all three or in none.
    private static func privacy(_ out: inout [HelpBlock], features: HelpFeatures) {
        let has = features.contains
        out.append(.heading("PRIVACY"))
        out.append(.paragraph(s("Cindy counts from the camera on your phone, and nearly everything it knows stays ",
                                "there.")))
        var items: [String] = []
        // iOS: a film is saved to Photos when filming exists; until then it stays in the app.
        items.append(has(.filming)
            ? s("The camera picture is read on the phone and thrown away. It is never saved or sent. ",
                "Video exists only if you tap REC, and it is saved to Photos on the phone ",
                "like any other video.")
            : s("The camera picture is read on the phone and thrown away. It is never saved or sent. ",
                "Video exists only if you tap REC, and it never leaves the phone."))
        // iOS: iCloud Backup in place of Android's backup, and where its control is.
        items.append(s("Your sessions, rep times, heart-rate traces, name, photo, body weight, birth year, ",
                       "sex and settings are kept on the phone. If iCloud Backup is on for this iPhone it may ",
                       "copy them to your iCloud, and to a new iPhone when you restore; that is Apple's ",
                       "backup, and you control it in Settings, under your name, iCloud, iCloud Backup."))
        if has(.heartRate) {
            items.append(s("Bluetooth is used only to find and read a heart-rate strap or watch. Cindy never ",
                           "asks for, or reads, your location."))
        }
        items.append(has(.music)
            ? s("Music is a track you pick. Cindy plays it and does not copy or send it. The voice ",
                "is your iPhone's own speech synthesiser: Cindy asks it for a voice installed on the ",
                "phone and gives it nothing but the words to say.")
            : s("The voice is your iPhone's own speech synthesiser: Cindy asks it for a voice installed on the ",
                "phone and gives it nothing but the words to say."))
        items.append("There are no ads, no analytics, no account and no server of Cindy's.")
        out.append(.bullets(items))
        if has(.strava) {
            out.append(.bullets([
                s("Strava is the one thing that leaves the phone, and only after you connect it. ",
                  "Each finished workout then sends Strava its score and sets with their reps, ",
                  "when it started, how long it took on the clock, paused and in real time, ",
                  "calories if a body weight is set, and the heart-rate trace if a watch ",
                  "recorded one. Never video, never the pose. Strava keeps what it receives ",
                  "under its own privacy policy.")
            ]))
        }
        // iOS: deleting the app is Android's Clear storage and uninstalling in one.
        out.append(.bullets([
            s("To delete: CLEAR on the Progress screen removes your sessions with their rep times ",
              "and heart-rate traces; REMOVE on the Account screen removes the photo; ",
              "deleting the app from your iPhone removes everything else.",
              has(.filming) ? " Videos in Photos are yours to delete." : "")
        ]))
        out.append(.rows([HelpRow(title: privacyPolicyTitle, subtitle: privacyPolicySubtitle,
                                  action: .openLink(AppLinks.privacyPolicy))]))
    }

    /// Credit where it is owed, and the licence texts the licences ask to travel with the app. The
    /// credits are in `Licences`, beside the texts they point at.
    private static func licences(_ out: inout [HelpBlock]) {
        out.append(.heading("LICENCES"))
        out.append(.paragraph("Cindy is built on other people's work, shared under these licences."))
        out.append(.bullets(Licences.credits.map { $0.line }))
        out.append(.rows(Licences.all.map {
            HelpRow(title: $0.name, subtitle: licenceSubtitle, action: .showLicence($0))
        }))
    }
}
