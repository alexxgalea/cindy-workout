import XCTest
import CindyCore

/// What a session's weight and energy are the size of. Port of `EquivalentsTest.kt`.
final class EquivalentsTests: XCTestCase {

    private let everything = AnyEmojiFont.all

    /// the table is ordered heaviest first
    func testTheTableIsOrderedHeaviestFirst() {
        XCTAssertEqual(Equivalents.animals.sorted { $0.kg > $1.kg }, Equivalents.animals)
        XCTAssertEqual(Equivalents.animals.count, 10)
    }

    /// the count is always between one and twelve, and preferably two to nine
    func testTheCountIsAlwaysBetweenOneAndTwelveAndPreferablyTwoToNine() {
        var kg = 80.0
        while kg < 90_000.0 {
            for rotation in Int64(0)...9 {
                guard let match = Equivalents.animalFor(kg, rotation: rotation, font: everything) else { continue }
                XCTAssertTrue(match.count >= 1.0 && match.count <= 12.0, "\(kg) kg: \(match.count)")
            }
            // Wherever any animal gives a count in [2, 9], that is the one picked.
            let preferredExists = Equivalents.animals.contains { kg / Double($0.kg) >= 2.0 && kg / Double($0.kg) <= 9.0 }
            if preferredExists {
                for rotation in Int64(0)...9 {
                    let match = Equivalents.animalFor(kg, rotation: rotation, font: everything)!
                    XCTAssertTrue(match.count >= 2.0 && match.count <= 9.0, "\(kg) kg: \(match.count)")
                }
            }
            kg *= 1.07
        }
    }

    /// under one panda or over twelve T rexes there is no animal
    func testUnderOnePandaOrOverTwelveTRexesThereIsNoAnimal() {
        XCTAssertNil(Equivalents.animalFor(99.0, rotation: 0, font: everything))
        XCTAssertNil(Equivalents.animalFor(8000.0 * 12.5, rotation: 0, font: everything))
        XCTAssertNil(Equivalents.animalFor(0.0, rotation: 0, font: everything))
    }

    /// consecutive days meet different animals
    func testConsecutiveDaysMeetDifferentAnimals() {
        // 12,940 kg: T. rex 1.6 and giraffe 10.8 fit but are not preferred; the elephant 2.2, rhino
        // 5.6 and hippo 8.6 are, and rotation walks through those.
        let seen = (Int64(0)...2).map { Equivalents.animalFor(12_940.0, rotation: 19_000 + $0, font: everything)!.animal.name }

        XCTAssertEqual(Set(seen), ["African elephant", "white rhino", "hippo"])
    }

    /// the same day always gives the same animal
    func testTheSameDayAlwaysGivesTheSameAnimal() {
        let a = Equivalents.animalFor(12_940.0, rotation: 19_000, font: everything)
        let b = Equivalents.animalFor(12_940.0, rotation: 19_000, font: everything)
        XCTAssertEqual(a, b)
    }

    /// negative rotations are fine
    func testNegativeRotationsAreFine() {
        XCTAssertNotNil(Equivalents.animalFor(12_940.0, rotation: -3, font: everything))
    }

    /// an animal the phone cannot draw is never picked
    func testAnAnimalThePhoneCannotDrawIsNeverPicked() {
        let noHippo = AnyEmojiFont { $0 != "🦛" }
        for rotation in Int64(0)...20 {
            let match = Equivalents.animalFor(13_500.0, rotation: rotation, font: noHippo)!
            XCTAssertNotEqual(match.animal.name, "hippo")
        }
    }

    /// when only an unpreferred animal can be drawn it is still used
    func testWhenOnlyAnUnpreferredAnimalCanBeDrawnItIsStillUsed() {
        // 1,600 kg: the hippo (1.1) and the giraffe (1.3) are the only fits and neither is in
        // [2, 9]; the cow is 2.3 but the phone cannot draw it.
        let onlyHippo = AnyEmojiFont { $0 == "🦛" }
        let match = Equivalents.animalFor(1_600.0, rotation: 0, font: onlyHippo)!

        XCTAssertEqual(match.animal.name, "hippo")
        XCTAssertEqual(match.text, "1.1 hippos")
    }

    /// when nothing can be drawn there is no animal
    func testWhenNothingCanBeDrawnThereIsNoAnimal() {
        let nothing = AnyEmojiFont { _ in false }
        XCTAssertNil(Equivalents.animalFor(12_940.0, rotation: 0, font: nothing))
        XCTAssertNil(Equivalents.energyFor(312.0, rotation: 0, font: nothing))
    }

    /// counts read with one decimal below three and whole from three up
    func testCountsReadWithOneDecimalBelowThreeAndWholeFromThreeUp() {
        let hippo = Equivalents.animals.first { $0.name == "hippo" }!
        XCTAssertEqual(Equivalents.countText(1.4, hippo), "1.4 hippos")
        XCTAssertEqual(Equivalents.countText(2.54, hippo), "2.5 hippos")
        XCTAssertEqual(Equivalents.countText(8.6, hippo), "9 hippos")
        XCTAssertEqual(Equivalents.countText(3.0, hippo), "3 hippos")
        XCTAssertEqual(Equivalents.countText(11.5, hippo), "12 hippos")
    }

    /// rounding never produces a decimal three or a plural one
    func testRoundingNeverProducesADecimalThreeOrAPluralOne() {
        let hippo = Equivalents.animals.first { $0.name == "hippo" }!
        XCTAssertEqual(Equivalents.countText(2.97, hippo), "3 hippos")
        XCTAssertEqual(Equivalents.countText(1.02, hippo), "1 hippo")
    }

    /// counts are rounded the way Java rounds them, on the shortest digits, not on the binary value
    func testCountsAreRoundedTheWayJavaRoundsThem() {
        let hippo = Equivalents.animals.first { $0.name == "hippo" }!
        // Each read off the Kotlin on a JVM. C would say "0.9 hippos", "1.9 hippos" and "2.0 hippos".
        XCTAssertEqual(Equivalents.countText(0.95, hippo), "1 hippo")
        XCTAssertEqual(Equivalents.countText(1.95, hippo), "2.0 hippos")
        XCTAssertEqual(Equivalents.countText(2.05, hippo), "2.1 hippos")
        XCTAssertEqual(Equivalents.countText(1.45, hippo), "1.5 hippos")
    }

    /// the sentence says at least for a lower bound
    func testTheSentenceSaysAtLeastForALowerBound() {
        let match = Equivalents.animalFor(12_940.0, rotation: 0, font: everything)!
        XCTAssertEqual(Equivalents.heavySentence(match, atLeast: false), "As heavy as \(match.text).")
        XCTAssertEqual(Equivalents.heavySentence(match, atLeast: true), "At least as heavy as \(match.text).")
    }

    /// no more than five emoji are drawn
    func testNoMoreThanFiveEmojiAreDrawn() {
        XCTAssertEqual(Equivalents.emojiCount(1.2), 1)
        XCTAssertEqual(Equivalents.emojiCount(2.4), 2)
        XCTAssertEqual(Equivalents.emojiCount(2.6), 3)
        XCTAssertEqual(Equivalents.emojiCount(5.2), 5)
        XCTAssertEqual(Equivalents.emojiCount(9.0), 5)
    }

    /// energy counts are whole numbers from one to sixty
    func testEnergyCountsAreWholeNumbersFromOneToSixty() {
        var kcal = 1.0
        while kcal < 2_000.0 {
            for rotation in Int64(0)...5 {
                guard let match = Equivalents.energyFor(kcal, rotation: rotation, font: everything) else { continue }
                XCTAssertTrue((1...60).contains(match.count), "\(kcal) kcal: \(match.count)")
            }
            kcal *= 1.1
        }
        XCTAssertNil(Equivalents.energyFor(3.0, rotation: 0, font: everything))
        XCTAssertNil(Equivalents.energyFor(0.0, rotation: 0, font: everything))
    }

    /// energy is compared with tea, a phone and a lamp, never with food
    func testEnergyIsComparedWithTeaAPhoneAndALampNeverWithFood() {
        XCTAssertEqual(Equivalents.energyReferences.map { $0.emoji }, ["☕", "🔋", "💡"])
        XCTAssertEqual(Equivalents.energyReferences[0].kcal, 20.0, accuracy: 0.0)
        XCTAssertEqual(Equivalents.energyReferences[1].kcal, 13.0, accuracy: 0.0)
        XCTAssertEqual(Equivalents.energyReferences[2].kcal, 7.7, accuracy: 0.0)
    }

    /// the tea sentence reads as the card promises
    func testTheTeaSentenceReadsAsTheCardPromises() {
        let tea = Equivalents.energyFor(312.0, rotation: 0, font: AnyEmojiFont { $0 == "☕" })!
        XCTAssertEqual(tea.count, 16)
        XCTAssertEqual(tea.reference.sentence(tea.count, atLeast: false), "Enough to boil water for 16 cups of tea.")
        XCTAssertEqual(tea.reference.sentence(tea.count, atLeast: true), "At least enough to boil water for 16 cups of tea.")
    }

    /// energy sentences handle one
    func testEnergySentencesHandleOne() {
        let tea = Equivalents.energyReferences[0]
        let phone = Equivalents.energyReferences[1]
        let bulb = Equivalents.energyReferences[2]
        XCTAssertEqual(tea.sentence(1, atLeast: false), "Enough to boil water for 1 cup of tea.")
        XCTAssertEqual(phone.sentence(1, atLeast: false), "Enough to charge a phone fully once.")
        XCTAssertEqual(phone.sentence(24, atLeast: false), "Enough to charge a phone fully 24 times.")
        XCTAssertEqual(bulb.sentence(41, atLeast: false), "Enough to run a 9 W LED bulb for 41 hours.")
        XCTAssertEqual(bulb.sentence(1, atLeast: false), "Enough to run a 9 W LED bulb for 1 hour.")
    }

    /// energy rotates among the references that fit
    func testEnergyRotatesAmongTheReferencesThatFit() {
        let seen = (Int64(0)...2).map { Equivalents.energyFor(312.0, rotation: $0, font: everything)!.reference.emoji }
        XCTAssertEqual(Set(seen).count, 3)
    }

    /// an energy reference the phone cannot draw is skipped
    func testAnEnergyReferenceThePhoneCannotDrawIsSkipped() {
        let noBattery = AnyEmojiFont { $0 != "🔋" }
        for rotation in Int64(0)...5 {
            let match = Equivalents.energyFor(312.0, rotation: rotation, font: noBattery)!
            XCTAssertNotEqual(match.reference.emoji, "🔋")
        }
    }

    /// exactly one animal's weight is one of them
    func testExactlyOneAnimalsWeightIsOneOfThem() {
        let match = Equivalents.animalFor(100.0, rotation: 0, font: everything)!
        XCTAssertEqual(match.animal.name, "giant panda")
        XCTAssertEqual(match.text, "1 giant panda")
        XCTAssertEqual(Equivalents.animalFor(8000.0 * 12.0, rotation: 0, font: everything)?.animal.name, "T. rex")
    }

    /// a negative rotation wraps round to the same animal as the positive one it is congruent to
    func testANegativeRotationWrapsRoundToTheSameAnimalAsTheCongruentPositiveOne() {
        for rotation in Int64(-7)...(-1) {
            let pool = 3   // 12,940 kg has three preferred animals
            let wrapped = ((rotation % Int64(pool)) + Int64(pool)) % Int64(pool)
            XCTAssertEqual(Equivalents.animalFor(12_940.0, rotation: rotation, font: everything),
                           Equivalents.animalFor(12_940.0, rotation: wrapped, font: everything), "\(rotation)")
            XCTAssertEqual(Equivalents.energyFor(312.0, rotation: rotation, font: everything)?.reference.emoji,
                           Equivalents.energyFor(312.0, rotation: ((rotation % 3) + 3) % 3, font: everything)?.reference.emoji, "\(rotation)")
        }
    }
}
