import XCTest
@testable import CindyCore

/// What the athlete has said about their body, over `UserDefaults`. The Kotlin `Profile` has no test
/// for these three properties, so these are written for the port: each holds a line of
/// `Profile.kt` (the keys, the clamp, the unknown sex decoding to nil) that the results page leans on.
final class BodyProfileTests: XCTestCase {

    private func fresh() -> (BodyProfile, UserDefaults) {
        let name = "BodyProfileTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return (BodyProfile(defaults: defaults), defaults)
    }

    /// nothing has been said until it is
    func testNothingHasBeenSaidUntilItIs() {
        let (p, _) = fresh()
        XCTAssertEqual(p.bodyWeightKg, 0)
        XCTAssertFalse(p.hasBodyWeight)
        XCTAssertEqual(p.birthYear, 0)
        XCTAssertNil(p.sex)
        XCTAssertNil(p.age(nowYear: 2026))
        XCTAssertEqual(p.body(nowYear: 2026), Body(0))
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

    /// the age is worked out from the year of birth, so it does not go stale
    func testTheAgeIsWorkedOutFromTheYearOfBirth() {
        let (p, defaults) = fresh()
        p.birthYear = 1990
        XCTAssertEqual(defaults.integer(forKey: "birth_year"), 1990)
        XCTAssertEqual(p.age(nowYear: 2026), 36)
        XCTAssertEqual(p.age(nowYear: 2027), 37)
    }

    /// each sex is saved under the name Android saves it under, and none is not a guess
    func testEachSexIsSavedUnderTheNameAndroidSavesItUnder() {
        let (p, defaults) = fresh()
        for (sex, name) in [(Sex.female, "FEMALE"), (.male, "MALE"), (.unstated, "UNSTATED")] {
            p.sex = sex
            XCTAssertEqual(defaults.string(forKey: "sex"), name)
            XCTAssertEqual(p.sex, sex)
        }
        p.sex = nil
        XCTAssertNil(defaults.object(forKey: "sex"))
        XCTAssertNil(p.sex)
    }

    /// a sex this build does not know decodes to none rather than a guessed default
    func testASexThisBuildDoesNotKnowDecodesToNoneRatherThanAGuessedDefault() {
        let (p, defaults) = fresh()
        defaults.set("NONBINARY", forKey: "sex")
        XCTAssertNil(p.sex)
    }

    /// the body is weight, age and sex read together
    func testTheBodyIsWeightAgeAndSexReadTogether() {
        let (p, _) = fresh()
        p.bodyWeightKg = 80
        p.birthYear = 1996
        p.sex = .female
        XCTAssertEqual(p.body(nowYear: 2026), Body(80, age: 30, sex: .female))
    }
}
