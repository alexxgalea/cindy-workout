import XCTest
@testable import CindyCore

/// The sheets that change what the athlete has told the app, decided apart from how they look:
/// `Dialogs.kt`'s body-weight prompt, heart-rate details and movement picker. Their one Robolectric
/// test, "the heart-rate details sheet builds" (`ScreenSmokeTest`), is the first of
/// `HeartRateDetailsFormTests` here; the rest are written for the port, each holding a line of the
/// Kotlin: what the sheet refuses, what it keeps, and the words it says.
final class ProfileFormsTests: XCTestCase {

    private func fresh() -> Profile {
        let name = "ProfileFormsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return Profile(defaults: defaults)
    }

    // MARK: the body weight

    /// A plausible weight is kept and reported; anything else is refused with the message.
    func testAPlausibleWeightIsKeptAndAnythingElseIsRefused() {
        let profile = fresh()

        XCTAssertEqual(BodyWeightForm.save("72.5", to: profile), .saved(72.5))
        XCTAssertEqual(profile.bodyWeightKg, 72.5)

        for text in ["", "abc", "19.9", "400.1", "0", "-70", "1e2e", "nan", "inf", "7 0"] {
            XCTAssertEqual(BodyWeightForm.save(text, to: profile), .refused("Enter a weight between 20 and 400 kg"), "\"\(text)\"")
        }
        XCTAssertEqual(profile.bodyWeightKg, 72.5, "a refusal keeps what was there")
    }

    /// The limits themselves are allowed, and the whitespace round the number is not part of it.
    func testTheLimitsThemselvesAreAllowed() {
        let profile = fresh()
        XCTAssertEqual(BodyWeightForm.save("20", to: profile), .saved(20))
        XCTAssertEqual(BodyWeightForm.save("400", to: profile), .saved(400))
        XCTAssertEqual(BodyWeightForm.save("  81  ", to: profile), .saved(81))
    }

    /// A comma stands for the point, because the number pad of a phone set to many languages types one.
    func testACommaStandsForThePoint() {
        let profile = fresh()
        XCTAssertEqual(BodyWeightForm.save("72,5", to: profile), .saved(72.5))
    }

    /// The field starts with the weight already kept, to be replaced, and empty when there is none.
    func testTheFieldStartsWithTheWeightAlreadyKept() {
        let profile = fresh()
        XCTAssertEqual(BodyWeightForm.initialText(profile), "")
        profile.bodyWeightKg = 72.6
        XCTAssertEqual(BodyWeightForm.initialText(profile), "73")
    }

    // MARK: the heart-rate details

    /// the heart-rate details sheet builds: its words, and a sex that has never been chosen
    func testTheHeartRateDetailsSheetBuilds() {
        XCTAssertEqual(HeartRateDetailsForm.title, "For heart rate")
        XCTAssertEqual(HeartRateDetailsForm.hint, "Year of birth")
        XCTAssertEqual(HeartRateDetailsForm.sexTitle, "SEX")
        XCTAssertTrue(HeartRateDetailsForm.subtitle.hasSuffix("it stays on this phone."))
        XCTAssertEqual(Sex.allCases.map { $0.label }, ["Female", "Male", "Prefer not to say"])
        XCTAssertNil(HeartRateDetailsForm.note(for: .female))
        XCTAssertNil(HeartRateDetailsForm.note(for: .male))
        XCTAssertEqual(HeartRateDetailsForm.note(for: .unstated), "uses the average of both formulas")
        XCTAssertEqual(HeartRateDetailsForm.initialYear(fresh()), "")
    }

    /// Both are kept once both are valid, and the year is checked first.
    func testBothAreKeptOnceBothAreValidAndTheYearIsCheckedFirst() {
        let profile = fresh()

        XCTAssertEqual(HeartRateDetailsForm.save(year: "1990", sex: .female, nowYear: 2026, to: profile), .saved)
        XCTAssertEqual(profile.birthYear, 1990)
        XCTAssertEqual(profile.sex, .female)
        XCTAssertEqual(HeartRateDetailsForm.initialYear(profile), "1990")

        // Both wrong: the year is what is said.
        XCTAssertEqual(HeartRateDetailsForm.save(year: "", sex: nil, nowYear: 2026, to: profile),
                       .refused("Enter a birth year that makes you 13 to 100"))
        XCTAssertEqual(HeartRateDetailsForm.save(year: "1990", sex: nil, nowYear: 2026, to: profile),
                       .refused("Choose one — the formula needs it"))
        XCTAssertEqual(profile.sex, .female, "a refusal keeps what was there")
    }

    /// An age outside thirteen to a hundred is a typo, at the edges included.
    func testAnAgeOutsideThirteenToAHundredIsATypo() {
        let profile = fresh()
        let refused = HeartRateDetailsForm.Outcome.refused("Enter a birth year that makes you 13 to 100")

        XCTAssertEqual(HeartRateDetailsForm.save(year: "2014", sex: .male, nowYear: 2026, to: profile), refused)
        XCTAssertEqual(HeartRateDetailsForm.save(year: "1925", sex: .male, nowYear: 2026, to: profile), refused)
        XCTAssertEqual(HeartRateDetailsForm.save(year: "2013", sex: .male, nowYear: 2026, to: profile), .saved)
        XCTAssertEqual(HeartRateDetailsForm.save(year: "1926", sex: .male, nowYear: 2026, to: profile), .saved)
        XCTAssertEqual(HeartRateDetailsForm.save(year: "abc", sex: .male, nowYear: 2026, to: profile), refused)
        XCTAssertEqual(HeartRateDetailsForm.save(year: "  1990 ", sex: .male, nowYear: 2026, to: profile), .saved)
        // A year in the future is a negative age.
        XCTAssertEqual(HeartRateDetailsForm.save(year: "2030", sex: .male, nowYear: 2026, to: profile), refused)
    }

    /// The third choice is kept as itself, and the profile reports the body from it.
    func testTheThirdChoiceIsKeptAsItself() {
        let profile = fresh()
        profile.bodyWeightKg = 70
        XCTAssertEqual(HeartRateDetailsForm.save(year: "1990", sex: .unstated, nowYear: 2026, to: profile), .saved)
        XCTAssertEqual(profile.sex, .unstated)
        XCTAssertTrue(profile.body(nowYear: 2026).canUseHeartRate)
    }

    // MARK: movements

    /// The sheet starts from what is kept, and each choice says when it is tapped in.
    func testTheSheetStartsFromWhatIsKeptAndEachChoiceSaysWhenItIsTappedIn() {
        let chosen = CindyProfile(pull: .bandAssistedPullUp, push: .kneePushUp, squat: .boxSquat)
        let form = MovementsForm(current: chosen, smartSquats: true)
        XCTAssertEqual(form.chosen, chosen)
        XCTAssertTrue(form.smart)

        XCTAssertEqual(MovementsForm.pullOptions.map { $0.label }, PullVariant.allCases.map { $0.label })
        let manual = (MovementsForm.pullOptions + MovementsForm.pushOptions + MovementsForm.squatOptions).filter { $0.note != nil }
        XCTAssertFalse(manual.isEmpty)
        XCTAssertTrue(manual.allSatisfy { $0.note == "you tap +1" && $0.spokenNote == "you tap plus one" })
        let auto = MovementsForm.pullOptions[0]
        XCTAssertNil(auto.note)
        XCTAssertEqual(auto.spoken, auto.label)
        XCTAssertEqual(manual[0].spoken, manual[0].label + ", you tap plus one")
    }

    /// SAVE keeps the choices and the setting; the setting does not move the choices.
    func testSaveKeepsTheChoicesAndTheSetting() {
        let profile = fresh()
        var form = MovementsForm(current: .standard, smartSquats: false)
        form.pull = .strictPullUp
        form.push = .inclinePushUp
        form.squat = .supportedSquat
        form.smart = true

        let saved = form.save(to: profile)

        XCTAssertEqual(saved, CindyProfile(pull: .strictPullUp, push: .inclinePushUp, squat: .supportedSquat))
        XCTAssertEqual(profile.movements, saved)
        XCTAssertTrue(profile.smartSquats)
        XCTAssertEqual(MovementsForm.title, "Make Cindy yours")
    }
}
