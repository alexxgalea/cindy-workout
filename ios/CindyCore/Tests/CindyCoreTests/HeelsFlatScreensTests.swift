import XCTest
@testable import CindyCore

/// The screens behind heels-flat squats: the setting that lets a session switch itself, and the
/// results row that says it did. Ported from `HeelsFlatScreensTest.kt`.
///
/// The counting is tested without a view in `HeelsFlatSquatTests` and `SmartSquatTests`. What is
/// tested here is the part an athlete meets: a setting that is off until they turn it on, that is
/// kept only when they say SAVE, that the menu reports honestly, and a results screen that says why
/// a standard Cindy came back as an Adaptive one and offers to make it permanent. Robolectric opened
/// the sheets and clicked; here `MovementsForm` and `HeelsFlatSheet` hold what they say and do, and
/// `MenuBuilder` what the row reads.
final class HeelsFlatScreensTests: XCTestCase {

    private let zone = Zone("Europe/Bucharest")
    private let today = LocalDate(2026, 10, 8)

    private func fresh() -> Profile {
        let name = "HeelsFlatScreensTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return Profile(defaults: defaults)
    }

    private func movementsRow(_ profile: Profile) -> String {
        let page = MenuBuilder.build(MenuInput(profile: profile, attempts: [], zone: zone, firstDayOfWeek: .monday, today: today))
        return page.rows.first { $0.id == .movements }!.spoken
    }

    // MARK: the setting

    /// smart squats are off on a fresh install
    func testSmartSquatsAreOffOnAFreshInstall() {
        XCTAssertFalse(fresh().smartSquats)
    }

    /// the Movements sheet offers the setting, off
    func testTheMovementsSheetOffersTheSettingOff() {
        let form = MovementsForm(current: fresh().movements, smartSquats: fresh().smartSquats)
        XCTAssertEqual(form.spotSpoken, "Spot heels-flat squats, off")
        XCTAssertEqual(MovementsForm.spotTitle, "Spot heels-flat squats")
    }

    /// switching it on and saving keeps it, and the Movements row says so
    func testSwitchingItOnAndSavingKeepsItAndTheMovementsRowSaysSo() {
        let profile = fresh()
        var form = MovementsForm(current: profile.movements, smartSquats: profile.smartSquats)

        form.smart = true
        XCTAssertEqual(form.spotSpoken, "Spot heels-flat squats, on", "the switch moves at once")
        XCTAssertFalse(profile.smartSquats, "but nothing is kept until SAVE")

        form.save(to: profile)

        XCTAssertTrue(profile.smartSquats)
        XCTAssertEqual(movementsRow(profile), "Movements, Cindy · spots heels flat")
    }

    /// saving says what was saved, even when only the setting changed
    func testSavingSaysWhatWasSavedEvenWhenOnlyTheSettingChanged() {
        let profile = fresh()
        var form = MovementsForm(current: profile.movements, smartSquats: profile.smartSquats)
        form.smart = true

        let saved = form.save(to: profile)

        // The movements did not change, so their name alone would be a toast about nothing.
        XCTAssertEqual(MenuBuilder.movementsSubtitle(saved, smartSquats: profile.smartSquats), "Cindy · spots heels flat")
    }

    /// cancelling leaves the setting alone
    func testCancellingLeavesTheSettingAlone() {
        let profile = fresh()
        var form = MovementsForm(current: profile.movements, smartSquats: profile.smartSquats)
        form.smart = true
        // CANCEL, or dismissing the sheet any other way, never calls `save`.
        XCTAssertFalse(profile.smartSquats)
        XCTAssertEqual(profile.movements, .standard)
    }

    /// the Movements row says it spots heels flat only where that can happen
    func testTheMovementsRowSaysItSpotsHeelsFlatOnlyWhereThatCanHappen() {
        let profile = fresh()
        profile.smartSquats = true
        XCTAssertEqual(movementsRow(profile), "Movements, Cindy · spots heels flat")

        // A box squat has a depth of its own, so the setting does nothing there and is not claimed.
        profile.movements = CindyProfile(squat: .boxSquat)
        XCTAssertEqual(movementsRow(profile), "Movements, Adaptive Cindy · box squats")

        profile.smartSquats = false
        profile.movements = .standard
        XCTAssertEqual(movementsRow(profile), "Movements, Cindy")
    }

    // MARK: the results screen

    private let heelsFlat = CindyProfile(squat: .heelsFlat)

    private func results(spotted: Bool) -> ResultsPage {
        let a = Attempt(rounds: 9, reps: 4, atMillis: zone.epochMs(today, hour: 12), durationMs: 20 * 60_000, profile: heelsFlat)
        return ResultsPageBuilder.build(ResultsInput(attempt: a, heelsFlatSpotted: spotted, records: [a], body: Body(0),
                                                     zone: zone, firstDayOfWeek: .monday, today: today))
    }

    /// the results screen explains an automatic switch
    func testTheResultsScreenExplainsAnAutomaticSwitch() {
        let p = results(spotted: true)

        XCTAssertNotNil(p.stats.first { $0.label == "Squats" }, "no row says why")
        XCTAssertEqual(p.stats.first { $0.label == "Squats" }?.action, .explainHeelsFlat)
        XCTAssertEqual(p.level.title, "Adaptive Cindy")
        XCTAssertEqual(p.level.blurb, "heels-flat squats")
    }

    /// the results screen says nothing about it when the choice was the athlete's own
    func testTheResultsScreenSaysNothingAboutItWhenTheChoiceWasTheAthletesOwn() {
        XCTAssertNil(results(spotted: false).stats.first { $0.label == "Squats" }, "there is nothing to explain")
    }

    /// the row opens a sheet, and SET HEELS FLAT makes the choice permanent
    func testTheRowOpensASheetAndSetHeelsFlatMakesTheChoicePermanent() {
        let profile = fresh()
        XCTAssertEqual(HeelsFlatSheet.title, "Adaptive Cindy activated")
        XCTAssertTrue(HeelsFlatSheet.subtitle.hasPrefix("Your squats were heels flat"))
        XCTAssertTrue(HeelsFlatSheet.note.contains("stand side-on to the phone, or raise it"))
        XCTAssertEqual(HeelsFlatSheet.primary, "SET HEELS FLAT")

        HeelsFlatSheet.setHeelsFlat(on: profile)

        XCTAssertEqual(profile.movements.squat, .heelsFlat)
        XCTAssertEqual(HeelsFlatSheet.done, "Squats set to heels flat")
    }

    /// SET HEELS FLAT changes the squat and nothing else the athlete chose.
    func testSetHeelsFlatKeepsTheOtherTwoMovements() {
        let profile = fresh()
        profile.movements = CindyProfile(pull: .bandAssistedPullUp, push: .kneePushUp, squat: .airSquat)

        HeelsFlatSheet.setHeelsFlat(on: profile)

        XCTAssertEqual(profile.movements, CindyProfile(pull: .bandAssistedPullUp, push: .kneePushUp, squat: .heelsFlat))
    }

    /// NOT NOW leaves the choice as it was
    func testNotNowLeavesTheChoiceAsItWas() {
        let profile = fresh()
        XCTAssertEqual(HeelsFlatSheet.secondary, "NOT NOW")
        // NOT NOW never calls `setHeelsFlat`.
        XCTAssertEqual(profile.movements.squat, .airSquat)
    }
}
