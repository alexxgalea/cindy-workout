import XCTest
@testable import CindyCore

/// What the athlete has said about themselves, over `UserDefaults`. Ports `ProfileHeartRateTest.kt`
/// (8) and `ProfileVoiceLanguageTest.kt` (5); the Kotlin `Profile` has no test for the rest, so
/// those are written for the port, each holding a line of `Profile.kt`: the keys, the clamps, and
/// what a value this build does not know decodes to.
final class ProfileTests: XCTestCase {

    private func fresh() -> (Profile, UserDefaults) {
        let name = "ProfileTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return (Profile(defaults: defaults), defaults)
    }

    // MARK: ProfileHeartRateTest

    /// birth year round trips
    func testBirthYearRoundTrips() {
        let (p, defaults) = fresh()
        XCTAssertEqual(p.birthYear, 0)
        p.birthYear = 1990
        XCTAssertEqual(p.birthYear, 1990)
        XCTAssertEqual(defaults.integer(forKey: "birth_year"), 1990)
    }

    /// sex round trips
    func testSexRoundTrips() {
        let (p, defaults) = fresh()
        XCTAssertNil(p.sex)
        p.sex = .female
        XCTAssertEqual(p.sex, .female)
        p.sex = .unstated
        XCTAssertEqual(p.sex, .unstated)
        // Each is kept under the name Android keeps it under.
        for (sex, name) in [(Sex.female, "FEMALE"), (.male, "MALE"), (.unstated, "UNSTATED")] {
            p.sex = sex
            XCTAssertEqual(defaults.string(forKey: "sex"), name)
        }
        p.sex = nil
        XCTAssertNil(defaults.object(forKey: "sex"))
    }

    /// heart-rate device round trips
    func testHeartRateDeviceRoundTrips() {
        let (p, _) = fresh()
        XCTAssertNil(p.heartRateDevice)
        let device = HeartRateDevice(address: "AA:BB:CC:DD:EE:FF", name: "Polar H10")
        p.heartRateDevice = device
        XCTAssertEqual(p.heartRateDevice, device)
    }

    /// clearing the device removes both keys
    func testClearingTheDeviceRemovesBothKeys() {
        let (p, defaults) = fresh()
        p.heartRateDevice = HeartRateDevice(address: "AA:BB", name: "Strap")
        p.heartRateDevice = nil
        XCTAssertNil(p.heartRateDevice)
        XCTAssertNil(defaults.object(forKey: "hr_device_address"))
        XCTAssertNil(defaults.object(forKey: "hr_device_name"))
    }

    /// An address with no name, or a name with no address, is no device at all.
    func testHalfADeviceIsNoDevice() {
        let (p, defaults) = fresh()
        defaults.set("AA:BB", forKey: "hr_device_address")
        XCTAssertNil(p.heartRateDevice)
        defaults.removeObject(forKey: "hr_device_address")
        defaults.set("Strap", forKey: "hr_device_name")
        XCTAssertNil(p.heartRateDevice)
    }

    /// an unknown sex name decodes to null
    func testAnUnknownSexNameDecodesToNil() {
        let (p, defaults) = fresh()
        defaults.set("NONBINARY_FORMULA_FROM_THE_FUTURE", forKey: "sex")
        XCTAssertNil(p.sex)
    }

    /// age is computed from the birth year
    func testAgeIsComputedFromTheBirthYear() {
        let (p, _) = fresh()
        p.birthYear = 1990
        XCTAssertEqual(p.age(nowYear: 2026), 36)
        XCTAssertEqual(p.age(nowYear: 2027), 37)
    }

    /// age is null when the birth year has not been said
    func testAgeIsNilWhenTheBirthYearHasNotBeenSaid() {
        let (p, _) = fresh()
        XCTAssertNil(p.age(nowYear: 2026))
        XCTAssertEqual(p.body(nowYear: 2026), Body(0))
    }

    /// body carries weight, age and sex together
    func testBodyCarriesWeightAgeAndSexTogether() {
        let (p, _) = fresh()
        p.bodyWeightKg = 70.0
        p.birthYear = 1990
        p.sex = .male
        let body = p.body(nowYear: 2026)
        XCTAssertEqual(body.weightKg, 70.0)
        XCTAssertEqual(body.age, 36)
        XCTAssertEqual(body.sex, .male)
    }

    // MARK: ProfileVoiceLanguageTest

    /// it is English until another is chosen
    func testItIsEnglishUntilAnotherIsChosen() {
        XCTAssertEqual(fresh().0.voiceLanguage, "en")
    }

    /// a chosen language is remembered
    func testAChosenLanguageIsRemembered() {
        let (p, _) = fresh()
        p.voiceLanguage = "es"
        XCTAssertEqual(p.voiceLanguage, "es")
    }

    /// a language this version does not have reads back as English
    func testALanguageThisVersionDoesNotHaveReadsBackAsEnglish() {
        let (p, defaults) = fresh()
        defaults.set("xx", forKey: "voice_language")
        XCTAssertEqual(p.voiceLanguage, "en")
    }

    /// a language with a region is stored as the language
    func testALanguageWithARegionIsStoredAsTheLanguage() {
        let (p, defaults) = fresh()
        p.voiceLanguage = "pt-BR"
        XCTAssertEqual(p.voiceLanguage, "pt")
        XCTAssertEqual(defaults.string(forKey: "voice_language"), "pt")
    }

    /// setting something nobody has stores English rather than the junk
    func testSettingSomethingNobodyHasStoresEnglishRatherThanTheJunk() {
        let (p, defaults) = fresh()
        p.voiceLanguage = "klingon"
        XCTAssertEqual(p.voiceLanguage, "en")
        XCTAssertEqual(defaults.string(forKey: "voice_language"), "en")
    }

    // MARK: written for the port: the body weight

    /// nothing has been said until it is
    func testNothingHasBeenSaidUntilItIs() {
        let (p, _) = fresh()
        XCTAssertEqual(p.bodyWeightKg, 0)
        XCTAssertFalse(p.hasBodyWeight)
        XCTAssertNil(p.displayName)
        XCTAssertNil(p.musicTrack)
        XCTAssertFalse(p.hasMusic)
    }

    /// the weight is kept as a float, as Android keeps it
    func testTheWeightIsKeptAsAFloat() {
        let (p, defaults) = fresh()
        p.bodyWeightKg = 72.5
        XCTAssertEqual(p.bodyWeightKg, 72.5)
        XCTAssertEqual(defaults.float(forKey: "body_weight_kg"), 72.5)
        XCTAssertTrue(p.hasBodyWeight)
    }

    /// a weight is clamped to nothing and the heaviest a typo may say
    func testAWeightIsClampedToNothingAndTheHeaviestATypoMaySay() {
        let (p, _) = fresh()
        p.bodyWeightKg = 4_000
        XCTAssertEqual(p.bodyWeightKg, 400)
        p.bodyWeightKg = -5
        XCTAssertEqual(p.bodyWeightKg, 0)
        XCTAssertFalse(p.hasBodyWeight)
    }

    // MARK: written for the port: movements

    /// The movements are the standard three until chosen, and what is chosen is remembered.
    func testMovementsAreStandardUntilChosen() {
        let (p, defaults) = fresh()
        XCTAssertEqual(p.movements, .standard)
        let chosen = CindyProfile(pull: .bandAssistedPullUp, push: .kneePushUp, squat: .boxSquat)
        p.movements = chosen
        XCTAssertEqual(p.movements, chosen)
        XCTAssertEqual(defaults.string(forKey: "movement_profile"), "BAND_ASSISTED_PULL_UP|KNEE_PUSH_UP|BOX_SQUAT")
    }

    /// A choice this build does not know is the standard three, which claims nothing about the past.
    func testAnUnknownMovementChoiceIsTheStandardThree() {
        let (p, defaults) = fresh()
        defaults.set("FROM|THE|FUTURE", forKey: "movement_profile")
        XCTAssertEqual(p.movements, CindyProfile.standard)
        defaults.set("garbage", forKey: "movement_profile")
        XCTAssertEqual(p.movements, CindyProfile.standard)
    }

    /// Smart squats are off until asked for.
    func testSmartSquatsAreOffUntilAskedFor() {
        let (p, _) = fresh()
        XCTAssertFalse(p.smartSquats)
        p.smartSquats = true
        XCTAssertTrue(p.smartSquats)
    }

    // MARK: written for the port: voice, music, reminder, name

    /// The voice is on and at full until changed; the music plays at seventy percent.
    func testTheDefaultMix() {
        let (p, _) = fresh()
        XCTAssertTrue(p.voiceOn)
        XCTAssertEqual(p.voiceVolume, 1)
        XCTAssertTrue(p.musicOn)
        XCTAssertEqual(p.musicVolume, 0.7)
        XCTAssertFalse(p.reminderOn)
        XCTAssertEqual(p.reminderMinute, 18 * 60)
    }

    /// A volume is held between nothing and full, whatever it is set to or was stored as.
    func testAVolumeIsHeldBetweenNothingAndFull() {
        let (p, defaults) = fresh()
        p.voiceVolume = 3
        XCTAssertEqual(p.voiceVolume, 1)
        p.voiceVolume = -1
        XCTAssertEqual(p.voiceVolume, 0)
        p.musicVolume = 2
        XCTAssertEqual(p.musicVolume, 1)
        p.musicVolume = -0.5
        XCTAssertEqual(p.musicVolume, 0)
        defaults.set(Float(9), forKey: "voice_volume")
        XCTAssertEqual(p.voiceVolume, 1, "a stored value out of range reads back in range")
        defaults.set(Float(-9), forKey: "music_volume")
        XCTAssertEqual(p.musicVolume, 0)
    }

    /// The switches are kept, and a switched-off voice stays off.
    func testTheSwitchesAreKept() {
        let (p, defaults) = fresh()
        p.voiceOn = false
        p.musicOn = false
        p.reminderOn = true
        XCTAssertFalse(p.voiceOn)
        XCTAssertFalse(p.musicOn)
        XCTAssertTrue(p.reminderOn)
        XCTAssertEqual(defaults.object(forKey: "voice_on") as? Bool, false)
    }

    /// The reminder's minute stays inside the day.
    func testTheReminderMinuteStaysInsideTheDay() {
        let (p, defaults) = fresh()
        p.reminderMinute = 7 * 60 + 30
        XCTAssertEqual(p.reminderMinute, 450)
        p.reminderMinute = 5_000
        XCTAssertEqual(p.reminderMinute, 1439)
        p.reminderMinute = -3
        XCTAssertEqual(p.reminderMinute, 0)
        defaults.set(99_999, forKey: "reminder_minute")
        XCTAssertEqual(p.reminderMinute, 1439)
    }

    /// The track is kept as a string and taken back by clearing it.
    func testTheTrackIsKeptAndTakenBackByClearingIt() {
        let (p, defaults) = fresh()
        p.musicTrack = "file:///track.mp3"
        XCTAssertEqual(p.musicTrack, "file:///track.mp3")
        XCTAssertTrue(p.hasMusic)
        p.musicTrack = nil
        XCTAssertNil(p.musicTrack)
        XCTAssertNil(defaults.object(forKey: "music_uri"))
    }

    /// The name is tidied on the way in and again on the way out, and emptying it takes it back.
    func testTheNameIsTidiedOnTheWayInAndOut() {
        let (p, defaults) = fresh()
        p.displayName = "  Alex   Galea "
        XCTAssertEqual(p.displayName, "Alex Galea")
        XCTAssertEqual(defaults.string(forKey: "display_name"), "Alex Galea")

        defaults.set("  Sam    Q ", forKey: "display_name")
        XCTAssertEqual(p.displayName, "Sam Q", "what a backup restored from another build is tidied too")

        p.displayName = "   "
        XCTAssertNil(p.displayName)
        XCTAssertNil(defaults.object(forKey: "display_name"))
        p.displayName = String(repeating: "A", count: 60)
        XCTAssertEqual(p.displayName?.count, Avatar.maxName)
    }

    /// Two profiles over the same defaults see each other's changes: the keys have one owner.
    func testTwoProfilesOverTheSameDefaultsAgree() {
        let (a, defaults) = fresh()
        let b = Profile(defaults: defaults)
        a.bodyWeightKg = 80
        XCTAssertEqual(b.bodyWeightKg, 80)
    }
}
