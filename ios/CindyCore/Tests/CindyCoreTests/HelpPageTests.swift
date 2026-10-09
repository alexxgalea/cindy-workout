import XCTest
@testable import CindyCore

/// What Help says has to stay true of the app. Port of `HelpScreenTest.kt`: each phrase below once
/// described a control that has since moved or changed, and a Help screen that describes something
/// that is not there is worse than none. The Kotlin read the text off the inflated activity; this
/// reads it off the `HelpPage` the screen draws, which is the same strings in the same order.
final class HelpPageTests: XCTestCase {

    private func page(_ features: HelpFeatures = .all, attempts: [Attempt] = []) -> HelpPage {
        HelpBuilder.build(HelpInput(attempts: attempts, features: features, versionName: "1.0", versionCode: "7"))
    }

    private func rows(_ page: HelpPage) -> [HelpRow] {
        page.blocks.flatMap { block -> [HelpRow] in
            switch block {
            case .row(let r): return [r]
            case .rows(let rs): return rs
            default: return []
            }
        }
    }

    /// Help no longer describes controls that have moved
    func testHelpNoLongerDescribesControlsThatHaveMoved() {
        let text = page().text
        for stale in [
            // Voice is a menu row with its own language and volume, not a chip on the camera.
            "VOICE turns that off",
            // A paired watch's heart rate now drives the estimate.
            "Without a heart-rate strap there is no honest way",
            // The screen is called Progress, and the ladder is the level on the session page.
            "RECORDS",
            // The scaled movements are counted now.
            "use the +1 and −1 buttons if you are working at the scaled version",
            // Android's own controls and words, which this app does not have.
            "Android", "Movies/Cindy", "SKIP leaves the movement", "Garmin Connect", "Clear storage"
        ] {
            XCTAssertFalse(text.contains(stale), "Help still says: \(stale)")
        }
        // On Android +1 has no long press and SKIP is a control of its own (the Kotlin test pins
        // "Hold +1" as stale). The iOS camera screen has no SKIP button: holding +1 does that, and
        // Help says so.
        XCTAssertTrue(text.contains("holding +1 leaves the movement you are in for the next one"))
    }

    /// Help has a section for each part of the app it describes
    func testHelpHasASectionForEachPartOfTheAppItDescribes() {
        let text = page().text
        for heading in ["VOICE AND MUSIC", "FILMING", "THE SESSION PAGE", "COMPARING SESSIONS",
                        "WHAT YOU LIFTED", "HEART RATE", "YOU AND YOUR BADGES", "REMINDERS", "PRIVACY"] {
            XCTAssertTrue(text.contains(heading), "Help has no \(heading) section")
        }
    }

    /// Help ends with the version the build was made as
    func testHelpEndsWithTheVersionTheBuildWasMadeAs() {
        let last = page().texts.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.last
        XCTAssertEqual(last, "Cindy 1.0 (7)")
        for features in [HelpFeatures(), HelpFeatures.strava] {
            XCTAssertEqual(page(features).texts.last, "Cindy 1.0 (7)")
        }
    }

    /// Help talks about Strava only in a build that has it
    func testHelpTalksAboutStravaOnlyInABuildThatHasIt() {
        let with = page(.all).text
        XCTAssertTrue(with.contains("STRAVA"))
        XCTAssertTrue(with.contains("the calorie estimate and the Strava upload."))
        // The flow Help describes is the one the app has: a sheet first, then Strava's button.
        XCTAssertTrue(with.contains("A sheet first says what each workout will send"))
        XCTAssertTrue(with.contains("tap Connect with Strava there"))
        XCTAssertTrue(with.contains("a View on Strava link to the activity"))

        let without = page(HelpFeatures.all.subtracting(.strava)).text
        XCTAssertFalse(without.contains("STRAVA"), "a build without Strava still has a STRAVA section")
        XCTAssertFalse(without.contains("Strava"), "a build without Strava still mentions it")
        // The sentence it replaces still reads as one.
        XCTAssertTrue(without.contains("how long the camera lost you and the calorie estimate."))
    }

    /// Help says what stays on the phone, and how to delete it
    func testHelpSaysWhatStaysOnThePhoneAndHowToDeleteIt() {
        let text = page().text
        for phrase in [
            "PRIVACY",
            "The camera picture is read on the phone and thrown away. It is never saved or sent.",
            "There are no ads, no analytics, no account and no server of Cindy's.",
            "CLEAR on the Progress screen",
            "REMOVE on the Account screen",
            // iOS: Apple's backup, and where it is switched off.
            "iCloud Backup",
            "deleting the app from your iPhone removes everything else"
        ] {
            XCTAssertTrue(text.contains(phrase), "the PRIVACY section lost: \(phrase)")
        }
    }

    /// the privacy policy row opens the policy in a browser
    func testThePrivacyPolicyRowOpensThePolicyInABrowser() throws {
        let row = try XCTUnwrap(rows(page()).first { $0.spoken.hasPrefix("Privacy policy") }, "no Privacy policy row")
        XCTAssertEqual(row.action, .openLink(AppLinks.privacyPolicy))
        XCTAssertEqual(AppLinks.privacyPolicy, "https://alexxgalea.github.io/cindy-privacy/")
        XCTAssertEqual(row.subtitle, "Opens in your browser")
    }

    /// the Strava paragraph of the privacy section is there when the build has Strava, and not otherwise
    func testTheStravaParagraphOfThePrivacySectionIsThereWhenTheBuildHasStravaAndNotOtherwise() {
        let marker = "Strava is the one thing that leaves the phone"

        XCTAssertFalse(page(HelpFeatures.all.subtracting(.strava)).text.contains(marker))

        let text = page(.all).text
        XCTAssertTrue(text.contains(marker))
        // What an upload carries, in the words the policy uses.
        XCTAssertTrue(text.contains("the heart-rate trace if a watch recorded one"))
        XCTAssertTrue(text.contains("Never video, never the pose."))
    }

    /// Help credits what it is built on, and a licence row shows the full text
    func testHelpCreditsWhatItIsBuiltOnAndALicenceRowShowsTheFullText() throws {
        let page = page()
        XCTAssertTrue(page.text.contains("LICENCES"))
        for credit in Licences.credits {
            XCTAssertTrue(page.texts.contains(credit.line), "no credit for \(credit.what)")
            XCTAssertTrue(page.text.contains("\(credit.what). \(credit.by). "))
        }

        let row = try XCTUnwrap(rows(page).first { $0.spoken.hasPrefix("SIL Open Font License 1.1") },
                                "no SIL Open Font License 1.1 row")
        XCTAssertEqual(row.action, .showLicence(Licences.ofl))
        // What the sheet then shows is the shipped text.
        guard case .showLicence(let licence) = row.action else { return XCTFail() }
        XCTAssertTrue(try LicencesTests.text(licence).contains("PERMISSION & CONDITIONS"))
    }

    /// Help says Cindy is independent of CrossFit and is not a medical device
    func testHelpSaysCindyIsIndependentOfCrossFitAndIsNotAMedicalDevice() {
        let text = page().text
        XCTAssertTrue(text.contains(
            "Cindy Tracker is an independent app. It is not affiliated with or endorsed by " +
            "CrossFit, LLC. CrossFit is a registered trademark of CrossFit, LLC."))
        XCTAssertTrue(text.contains(
            "Heart rate, zones and calories here are training estimates. Cindy is not a medical device."))
    }

    /// CrossFit's words are still quoted as they were
    func testCrossFitsWordsAreStillQuotedAsTheyWere() {
        let text = page().text
        for quote in [
            "Complete as many rounds and reps as possible in 20 minutes of: 5 pull-ups, 10 push-ups, 15 squats",
            "The fastest athletes will complete rounds in under 45 seconds.",
            "Adhering to the full range of motion in all movements is important for structural integrity and joint health."
        ] {
            XCTAssertTrue(text.contains(quote), "a CrossFit quotation changed: \(quote)")
        }
    }

    // MARK: not in the Kotlin: the tiers

    private func tiers(_ page: HelpPage) -> [HelpTier] {
        for case .tiers(let t) in page.blocks { return t }
        return []
    }

    private func best(_ rounds: Int, reps: Int = 0, profile: CindyProfile? = CindyProfile.standard,
                      at: Int64 = 1) -> Attempt {
        Attempt(rounds: rounds, reps: reps, atMillis: at, profile: profile)
    }

    /// the scaled tier is never ticked, whatever the best is
    func testTheScaledTierIsNeverTickedWhateverTheBestIs() {
        for attempts in [[], [best(30)]] {
            let first = tiers(page(attempts: attempts)).first
            XCTAssertEqual(first?.name, "Beginner")
            XCTAssertNil(first?.reached)
            XCTAssertEqual(first?.spoken, "Beginner, 8–10+ rounds, scaled, not scored")
        }
    }

    /// a tier is ticked once a standard best reaches it, and not before
    func testATierIsTickedOnceAStandardBestReachesItAndNotBefore() {
        func reached(_ rounds: Int) -> [Bool?] { tiers(page(attempts: [best(rounds)])).map { $0.reached } }
        XCTAssertEqual(reached(7), [nil, false, false, false])
        XCTAssertEqual(reached(8), [nil, true, false, false])
        XCTAssertEqual(reached(19), [nil, true, false, false])
        XCTAssertEqual(reached(20), [nil, true, true, false])
        XCTAssertEqual(reached(25), [nil, true, true, true])
        XCTAssertEqual(tiers(page(attempts: [best(8)]))[1].spoken, "Intermediate, 8–10+ rounds as prescribed, reached")
        XCTAssertEqual(tiers(page(attempts: [best(7)]))[1].spoken, "Intermediate, 8–10+ rounds as prescribed, not yet reached")
    }

    /// a session at other movements ticks nothing, and is named rather than ignored
    func testASessionAtOtherMovementsTicksNothingAndIsNamedRatherThanIgnored() {
        let knee = CindyProfile(pull: .strictPullUp, push: .kneePushUp, squat: .airSquat)
        let p = page(attempts: [best(30, profile: knee)])

        XCTAssertEqual(tiers(p).map { $0.reached }, [nil, false, false, false])
        XCTAssertTrue(p.texts.contains { $0.hasPrefix("Your best is 30 at ") && $0.contains("ranked against your own sessions") })
        XCTAssertFalse(p.text.contains("Your best so far"))
    }

    /// with no sessions it says to finish one, and with a standard one it names the best
    func testWithNoSessionsItSaysToFinishOneAndWithAStandardOneItNamesTheBest() {
        XCTAssertTrue(page().texts.contains("Finish a Cindy and your best will show up against these."))
        let p = page(attempts: [best(9, reps: 4, at: 1), best(11, reps: 2, at: 2), best(11, reps: 6, at: 3)])
        XCTAssertTrue(p.texts.contains("Your best so far: 11 + 6 — 11 rounds."))
    }

    // MARK: not in the Kotlin: what a build without a part says nothing about

    /// a part that is not built says nothing at all
    func testAPartThatIsNotBuiltSaysNothingAtAll() {
        let none = page([]).text
        for heading in ["FILMING", "HEART RATE", "REMINDERS", "STRAVA", "VOICE AND MUSIC"] {
            XCTAssertFalse(none.contains(heading), heading)
        }
        XCTAssertTrue(none.contains("VOICE"))
        for phrase in ["Music, under Music", "FIND MY WATCH", "Daily reminder in the menu", "A watch changes the method",
                       "Bluetooth is used only", "burned into the picture", "Keytel", "Photos"] {
            XCTAssertFalse(none.contains(phrase), phrase)
        }
        // What is always true is still said, and the voice is still the phone's.
        XCTAssertTrue(none.contains("The voice is your iPhone's own speech synthesiser"))
        XCTAssertTrue(none.contains("it never leaves the phone"))
    }

    /// each part is described exactly when it is switched on
    func testEachPartIsDescribedExactlyWhenItIsSwitchedOn() {
        let parts: [(HelpFeatures, String)] = [
            (.heartRate, "HEART RATE"), (.filming, "FILMING"), (.music, "VOICE AND MUSIC"),
            (.reminders, "REMINDERS"), (.strava, "STRAVA")
        ]
        for (feature, heading) in parts {
            XCTAssertTrue(page(feature).text.contains(heading), heading)
            XCTAssertFalse(page(HelpFeatures.all.subtracting(feature)).text.contains(heading), heading)
        }
    }

    /// the rows are the tour, the policy and one per licence, each with its action
    func testTheRowsAreTheTourThePolicyAndOnePerLicenceEachWithItsAction() {
        XCTAssertEqual(rows(page()).map { $0.action }, [
            .takeTour, .openLink(AppLinks.privacyPolicy), .showLicence(Licences.ofl)
        ])
        XCTAssertEqual(HelpBuilder.crossfitButton, "CROSSFIT.COM")
        XCTAssertEqual(AppLinks.crossfitCindy, "https://www.crossfit.com/cindy")
        XCTAssertTrue(page().texts.contains(AppLinks.crossfitCindy))
    }

    /// the same inputs build the same page
    func testTheSameInputsBuildTheSamePage() {
        XCTAssertEqual(page(attempts: [best(9)]), page(attempts: [best(9)]))
        XCTAssertNotEqual(page(attempts: [best(9)]), page(attempts: []))
    }
}
