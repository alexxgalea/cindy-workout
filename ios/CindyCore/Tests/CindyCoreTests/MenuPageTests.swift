import XCTest
@testable import CindyCore

/// The menu's rows and what each says underneath, ported from the menu parts of
/// `ScreenSmokeTest.kt` (the menu builds, mid-workout, with a track chosen, with a watch paired,
/// with the reminder on; the voice row naming its language). Robolectric inflated `MenuActivity`
/// and read its views; the same facts are read here off the `MenuPage` the screen draws. The tests
/// that open a sheet stay with the phase that builds the sheet: the heart-rate sheets with the
/// Bluetooth link (P15), the music sheet with the player (P17), the reminder sheet with the
/// scheduler (P18), the Strava sheet with Strava (P20).
final class MenuPageTests: XCTestCase {

    private let zone = Zone("Europe/Bucharest")
    private let today = LocalDate(2026, 10, 8)
    private lazy var now = zone.epochMs(today, hour: 12)

    private func fresh() -> Profile {
        let name = "MenuPageTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return Profile(defaults: defaults)
    }

    private func page(_ profile: Profile, attempts: [Attempt] = [], live: Bool = false, notifications: Bool = true,
                      is24Hour: Bool = true, strava: StravaStatus? = nil, trackName: @escaping (String) -> String? = { $0 },
                      shown: Set<MenuRowID> = Set(MenuRowID.allCases)) -> MenuPage {
        MenuBuilder.build(MenuInput(profile: profile, attempts: attempts, zone: zone, firstDayOfWeek: .monday, today: today,
                                    is24Hour: is24Hour, workoutLive: live, notificationsAllowed: notifications,
                                    trackName: trackName, strava: strava, shown: shown))
    }

    private func row(_ p: MenuPage, _ id: MenuRowID) -> String? { p.rows.first { $0.id == id }?.spoken }

    // MARK: the menu builds

    /// the menu builds
    func testTheMenuBuilds() {
        let p = page(fresh())

        XCTAssertEqual(p.rows.map { $0.id }, [.movements, .progress, .reminder, .bodyWeight, .heartRate, .voice, .music, .help])
        XCTAssertEqual(p.rows.map { $0.title }, ["Movements", "Progress", "Daily reminder", "Body weight", "Heart rate",
                                                  "Voice", "Music", "Help"])
        XCTAssertNil(p.footnote)
        XCTAssertFalse(p.movementsRefused)
        XCTAssertEqual(row(p, .movements), "Movements, Cindy")
        XCTAssertEqual(row(p, .progress), "Progress, No sessions yet")
        XCTAssertEqual(row(p, .reminder), "Daily reminder, Off")
        XCTAssertEqual(row(p, .bodyWeight), "Body weight, Not set — calories need it")
        XCTAssertEqual(row(p, .heartRate), "Heart rate, No watch paired")
        XCTAssertEqual(row(p, .voice), "Voice, On · 100% · English")
        XCTAssertEqual(row(p, .music), "Music, No track chosen")
        XCTAssertEqual(row(p, .help), "Help, What Cindy is, how it is scored, and where to stand")
    }

    /// the menu builds mid-workout: it refuses the movement picker, and says so in an extra row
    func testTheMenuBuildsMidWorkout() {
        let p = page(fresh(), live: true)
        XCTAssertTrue(p.movementsRefused)
        XCTAssertEqual(p.footnote, "Movements can only be changed between workouts — they have to mean one thing for the whole score.")
        XCTAssertEqual(MovementsForm.refusedWhileLive, "Reset the workout first to change movements")
    }

    /// A row whose screen is not built yet is left out, not greyed.
    func testARowWhoseScreenIsNotBuiltYetIsLeftOut() {
        let p = page(fresh(), shown: [.movements, .progress, .bodyWeight, .voice])
        XCTAssertEqual(p.rows.map { $0.id }, [.movements, .progress, .bodyWeight, .voice])
    }

    /// Strava is absent in a build that has none, and present, saying so, in one that has.
    func testStravaIsAbsentInABuildThatHasNone() {
        XCTAssertNil(row(page(fresh()), .strava))
        XCTAssertEqual(row(page(fresh(), strava: .notConnected), .strava), "Strava, Not connected — upload workouts")
        XCTAssertEqual(row(page(fresh(), strava: .connected(athleteName: "Alex G")), .strava), "Strava, Connected · Alex G")
        XCTAssertEqual(row(page(fresh(), strava: .connected(athleteName: nil)), .strava), "Strava, Connected · Strava")
    }

    // MARK: progress

    private func session(daysAgo: Int) -> Attempt {
        Attempt(rounds: 10, reps: 0, atMillis: now - Int64(daysAgo) * 86_400_000, durationMs: 20 * 60_000, profile: .standard)
    }

    /// Progress says how many sessions, and the streak once there is one.
    func testProgressSaysHowManySessionsAndTheStreakOnceThereIsOne() {
        XCTAssertEqual(row(page(fresh(), attempts: [session(daysAgo: 5)]), .progress), "Progress, 1 session")
        XCTAssertEqual(row(page(fresh(), attempts: [session(daysAgo: 5), session(daysAgo: 4)]), .progress), "Progress, 2 sessions")
        XCTAssertEqual(row(page(fresh(), attempts: [session(daysAgo: 1), session(daysAgo: 0)]), .progress),
                       "Progress, 2 sessions · 2-day streak")
        XCTAssertEqual(row(page(fresh(), attempts: [session(daysAgo: 0)]), .progress), "Progress, 1 session · 1-day streak")
    }

    // MARK: body weight

    /// Body weight is shown to the kilo, or asks for it.
    func testBodyWeightIsShownToTheKiloOrAsksForIt() {
        let profile = fresh()
        profile.bodyWeightKg = 72.6
        XCTAssertEqual(row(page(profile), .bodyWeight), "Body weight, 73 kg")
    }

    // MARK: voice

    /// choosing a language and saving stores it, and the Voice row names it
    func testChoosingALanguageAndSavingStoresItAndTheVoiceRowNamesIt() {
        let profile = fresh()
        profile.voiceLanguage = "en"
        var form = VoiceForm(profile)

        form.language = "es"
        XCTAssertEqual(profile.voiceLanguage, "en", "nothing is kept until SAVE")
        form.save(to: profile)

        XCTAssertEqual(profile.voiceLanguage, "es")
        XCTAssertTrue(row(page(profile), .voice)!.hasPrefix("Voice, On"))
        XCTAssertTrue(row(page(profile), .voice)!.hasSuffix("Español"))
    }

    /// dismissing the voice sheet without saving leaves the language alone
    func testDismissingTheVoiceSheetWithoutSavingLeavesTheLanguageAlone() {
        let profile = fresh()
        profile.voiceLanguage = "en"
        var form = VoiceForm(profile)
        form.language = "de"
        form.on = false
        form.volume = 0.2
        // Dismissing never calls `save`.
        XCTAssertEqual(profile.voiceLanguage, "en")
        XCTAssertTrue(profile.voiceOn)
        XCTAssertEqual(profile.voiceVolume, 1)
    }

    /// The row says off when the voice is off, and the volume as a whole percent otherwise.
    func testTheVoiceRowSaysOffOrTheVolumeAsAWholePercent() {
        let profile = fresh()
        profile.voiceVolume = 0.555
        XCTAssertEqual(row(page(profile), .voice), "Voice, On · 55% · English")
        profile.voiceOn = false
        XCTAssertEqual(row(page(profile), .voice), "Voice, Off")
    }

    /// The sheet starts from what is kept.
    func testTheVoiceSheetStartsFromWhatIsKept() {
        let profile = fresh()
        profile.voiceOn = false
        profile.voiceVolume = 0.4
        profile.voiceLanguage = "ro"
        XCTAssertEqual(VoiceForm(profile), VoiceForm.init(profile))
        let form = VoiceForm(profile)
        XCTAssertEqual([form.on, form.volume == 0.4, form.language == "ro"], [false, true, true])
    }

    // MARK: music

    /// the menu builds with a track chosen
    func testTheMenuBuildsWithATrackChosen() {
        let profile = fresh()
        profile.musicTrack = "content://fake/track.mp3"
        profile.musicOn = false
        XCTAssertEqual(row(page(profile, trackName: { _ in "track.mp3" }), .music), "Music, Off · track.mp3")

        profile.musicOn = true
        profile.musicVolume = 0.7
        XCTAssertEqual(row(page(profile, trackName: { _ in "track.mp3" }), .music), "Music, track.mp3 · 70%")
    }

    /// A track whose grant has gone says so rather than leave the athlete wondering.
    func testATrackThatCanNoLongerBeOpenedSaysSo() {
        let profile = fresh()
        profile.musicTrack = "content://gone"
        XCTAssertEqual(row(page(profile, trackName: { _ in nil }), .music), "Music, That track can no longer be opened")
    }

    // MARK: heart rate

    /// the menu builds with a watch paired, which drops the "add your age" clause once the details are set too
    func testTheMenuBuildsWithAWatchPaired() {
        let profile = fresh()
        profile.heartRateDevice = HeartRateDevice(address: "AA:BB:CC:DD:EE:FF", name: "Test Strap")
        XCTAssertEqual(row(page(profile), .heartRate), "Heart rate, Test Strap · add your age for calories")

        profile.bodyWeightKg = 70
        profile.birthYear = 1990
        profile.sex = .female
        XCTAssertEqual(row(page(profile), .heartRate), "Heart rate, Test Strap")
    }

    /// The details row says what is kept, or what is needed.
    func testTheDetailsRowSaysWhatIsKeptOrWhatIsNeeded() {
        let profile = fresh()
        XCTAssertEqual(MenuBuilder.heartRateDetailsSubtitle(profile, nowYear: 2026), "Needed for heart-rate calories")
        profile.bodyWeightKg = 70
        profile.birthYear = 1990
        profile.sex = .unstated
        XCTAssertEqual(MenuBuilder.heartRateDetailsSubtitle(profile, nowYear: 2026), "Prefer not to say · 36 y")
    }

    // MARK: reminder

    /// the menu builds with the reminder on
    func testTheMenuBuildsWithTheReminderOn() {
        let profile = fresh()
        profile.reminderOn = true
        XCTAssertEqual(row(page(profile), .reminder), "Daily reminder, Daily at 18:00 \u{00B7} not on days you train")
        XCTAssertEqual(row(page(profile, is24Hour: false), .reminder), "Daily reminder, Daily at 6:00 PM \u{00B7} not on days you train")
        XCTAssertEqual(row(page(profile, notifications: false), .reminder),
                       "Daily reminder, Blocked \u{2014} notifications are off for Cindy")
        profile.reminderOn = false
        XCTAssertEqual(row(page(profile, notifications: false), .reminder), "Daily reminder, Off")
    }
}
