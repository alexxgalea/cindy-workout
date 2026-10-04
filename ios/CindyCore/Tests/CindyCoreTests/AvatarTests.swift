import XCTest
import CindyCore

/// What a name and a profile photo turn into. Port of `AvatarTest.kt`.
///
/// Strings are compared scalar by scalar: Swift's `==` calls "é" and "e" with a combining accent the
/// same string, and half of what is tested here is the difference between them.
final class AvatarTests: XCTestCase {

    private func same(_ a: String?, _ b: String?, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.map { Array($0.unicodeScalars.map { $0.value }) }, b.map { Array($0.unicodeScalars.map { $0.value }) },
                       message, file: file, line: line)
    }

    // MARK: cleanName

    /// a name is kept as it was typed
    func testANameIsKeptAsItWasTyped() {
        same(Avatar.cleanName("Alexandru Galea"), "Alexandru Galea")
    }

    /// nothing, or only space, is no name
    func testNothingOrOnlySpaceIsNoName() {
        XCTAssertNil(Avatar.cleanName(nil))
        XCTAssertNil(Avatar.cleanName(""))
        XCTAssertNil(Avatar.cleanName("   "))
        XCTAssertNil(Avatar.cleanName(" \t\n "))
        XCTAssertNil(Avatar.cleanName("\u{00A0} \u{2003}"), "a no-break space is still only space")
    }

    /// the ends are trimmed and runs of space become one
    func testTheEndsAreTrimmedAndRunsOfSpaceBecomeOne() {
        same(Avatar.cleanName("  Ana   Maria \t Popescu \n"), "Ana Maria Popescu")
        same(Avatar.cleanName("Ana\u{00A0}\u{00A0}Popescu"), "Ana Popescu")
    }

    /// a long name is cut to thirty characters
    func testALongNameIsCutToThirtyCharacters() {
        let long = String(repeating: "A", count: 45)
        XCTAssertEqual(Avatar.cleanName(long)!.utf16.count, 30)
        same(Avatar.cleanName(long), String(repeating: "A", count: 30))
        same(Avatar.cleanName(String(repeating: "B", count: 30)), String(repeating: "B", count: 30))
        XCTAssertEqual(Avatar.maxName, 30)
    }

    /// a cut never leaves a trailing space
    func testACutNeverLeavesATrailingSpace() {
        // The 30th character is the space between the words.
        let name = String(repeating: "A", count: 29) + " " + String(repeating: "B", count: 10)
        same(Avatar.cleanName(name), String(repeating: "A", count: 29))
    }

    /// a cut never splits a surrogate pair
    func testACutNeverSplitsASurrogatePair() {
        let face = "\u{1F600}"   // one character, two UTF-16 units
        let name = String(repeating: "A", count: 29) + face
        let cleaned = Avatar.cleanName(name)!
        same(cleaned, String(repeating: "A", count: 29))
        XCTAssertFalse(cleaned.utf16.contains { UTF16.isLeadSurrogate($0) })

        // Whole emoji that fit are kept.
        same(Avatar.cleanName(String(repeating: "A", count: 28) + face), String(repeating: "A", count: 28) + face)
    }

    /// cleaning a clean name changes nothing
    func testCleaningACleanNameChangesNothing() {
        for raw in ["Ana", "Ana Popescu", "  x  ", "\u{C9}lise  \u{C5}ngstr\u{F6}m", String(repeating: "A", count: 99)] {
            let once = Avatar.cleanName(raw)
            same(Avatar.cleanName(once), once)
        }
    }

    // MARK: initials

    /// two words give the first letter of each
    func testTwoWordsGiveTheFirstLetterOfEach() { same(Avatar.initials("Alexandru Galea"), "AG") }

    /// one word gives one letter
    func testOneWordGivesOneLetter() { same(Avatar.initials("alex"), "A") }

    /// three words give the first and the last
    func testThreeWordsGiveTheFirstAndTheLast() {
        same(Avatar.initials("Mary Jane Watson"), "MW")
        same(Avatar.initials("Ludwig van Beethoven"), "LB")
    }

    /// initials are capitals whatever was typed
    func testInitialsAreCapitalsWhateverWasTyped() { same(Avatar.initials("alexandru galea"), "AG") }

    /// no name, no initials
    func testNoNameNoInitials() {
        same(Avatar.initials(nil), "")
        same(Avatar.initials(""), "")
        same(Avatar.initials("  "), "")
    }

    /// space around a name does not matter
    func testSpaceAroundANameDoesNotMatter() { same(Avatar.initials("  alexandru    galea  "), "AG") }

    /// a hyphen or apostrophe inside a word is not its start
    func testAHyphenOrApostropheInsideAWordIsNotItsStart() {
        same(Avatar.initials("Jean-Luc Picard"), "JP")
        same(Avatar.initials("O'Connor Brien"), "OB")
    }

    /// accented letters keep their accents
    func testAccentedLettersKeepTheirAccents() {
        same(Avatar.initials("\u{E9}lise \u{E5}ngstr\u{F6}m"), "\u{C9}\u{C5}")
        // An accent written as a letter and a combining mark stays with its letter.
        same(Avatar.initials("e\u{0301}lise"), "E\u{0301}")
    }

    /// letters of other scripts are letters
    func testLettersOfOtherScriptsAreLetters() {
        same(Avatar.initials("\u{0430}\u{043B}\u{0435}\u{043A}\u{0441} \u{0431}\u{043E}\u{0440}\u{0438}\u{0441}"), "\u{0410}\u{0411}")
        same(Avatar.initials("\u{5C71}\u{7530}"), "\u{5C71}")
    }

    /// a word with no letter in it is skipped, not shown
    func testAWordWithNoLetterInItIsSkippedNotShown() {
        same(Avatar.initials("Alex -"), "A")
        same(Avatar.initials("\u{1F3CB} Alex"), "A")
        same(Avatar.initials("- -"), "")
    }

    /// a digit will do for a letter
    func testADigitWillDoForALetter() { same(Avatar.initials("7"), "7") }

    // MARK: squareCrop

    /// a portrait photo is cut from the middle of its height
    func testAPortraitPhotoIsCutFromTheMiddleOfItsHeight() {
        XCTAssertEqual(Avatar.squareCrop(600, 800), Square(0, 100, 600))
    }

    /// a landscape photo is cut from the middle of its width
    func testALandscapePhotoIsCutFromTheMiddleOfItsWidth() {
        XCTAssertEqual(Avatar.squareCrop(1000, 600), Square(200, 0, 600))
    }

    /// a square photo is taken whole
    func testASquarePhotoIsTakenWhole() {
        XCTAssertEqual(Avatar.squareCrop(500, 500), Square(0, 0, 500))
    }

    /// an odd margin rounds towards the top and the left
    func testAnOddMarginRoundsTowardsTheTopAndTheLeft() {
        XCTAssertEqual(Avatar.squareCrop(3, 4), Square(0, 0, 3))
        XCTAssertEqual(Avatar.squareCrop(6, 3), Square(1, 0, 3))
    }

    /// the crop always fits inside the picture
    func testTheCropAlwaysFitsInsideThePicture() {
        for w in [1, 2, 319, 320, 321, 1080, 4000] {
            for h in [1, 2, 319, 320, 321, 1920, 3000] {
                let s = Avatar.squareCrop(w, h)
                XCTAssertTrue(s.left >= 0 && s.top >= 0 && s.size > 0, "\(w) x \(h)")
                XCTAssertTrue(s.left + s.size <= w && s.top + s.size <= h, "\(w) x \(h)")
                XCTAssertEqual(s.size, min(w, h), "\(w) x \(h)")
            }
        }
    }

    /// an empty picture has no square
    func testAnEmptyPictureHasNoSquare() {
        XCTAssertEqual(Avatar.squareCrop(0, 100), Square(0, 0, 0))
        XCTAssertEqual(Avatar.squareCrop(100, -1), Square(0, 0, 0))
    }

    // MARK: sampleSize

    /// a photo no bigger than the target is not shrunk while decoding
    func testAPhotoNoBiggerThanTheTargetIsNotShrunkWhileDecoding() {
        XCTAssertEqual(Avatar.sampleSize(200, 300), 1)
        XCTAssertEqual(Avatar.sampleSize(320, 320), 1)
    }

    /// the sample is the biggest power of two that leaves the short side at the target
    func testTheSampleIsTheBiggestPowerOfTwoThatLeavesTheShortSideAtTheTarget() {
        // 639 / 2 = 319, below 320, so it has to stay whole; 640 / 2 is exactly 320.
        XCTAssertEqual(Avatar.sampleSize(639, 4000), 1)
        XCTAssertEqual(Avatar.sampleSize(640, 4000), 2)
        XCTAssertEqual(Avatar.sampleSize(1279, 4000), 2)
        XCTAssertEqual(Avatar.sampleSize(1280, 4000), 4)
    }

    /// a twelve megapixel photo is decoded at an eighth
    func testATwelveMegapixelPhotoIsDecodedAtAnEighth() {
        // 3024 x 4032: 3024 / 8 = 378, still over 320; 3024 / 16 = 189 is not.
        XCTAssertEqual(Avatar.sampleSize(3024, 4032), 8)
    }

    /// it is the short side that decides, in either orientation
    func testItIsTheShortSideThatDecidesInEitherOrientation() {
        XCTAssertEqual(Avatar.sampleSize(3024, 4032), Avatar.sampleSize(4032, 3024))
        // A panorama is thin, so it may not be shrunk at all.
        XCTAssertEqual(Avatar.sampleSize(12000, 500), 1)
    }

    /// the sample is always a power of two and never takes the short side under the target
    func testTheSampleIsAlwaysAPowerOfTwoAndNeverTakesTheShortSideUnderTheTarget() {
        for short in [100, 320, 321, 500, 640, 641, 1080, 2160, 3024, 6000] {
            let sample = Avatar.sampleSize(short, short * 2)
            XCTAssertEqual(sample & (sample - 1), 0, "\(short)")
            XCTAssertTrue(short / sample >= min(short, Avatar.sizePx), "\(short)")
        }
    }

    /// a different target is respected
    func testADifferentTargetIsRespected() {
        XCTAssertEqual(Avatar.sampleSize(1000, 1000, target: 200), 4)
        XCTAssertEqual(Avatar.sampleSize(1000, 1000, target: 100), 8)
    }

    /// a photo with no size is not shrunk
    func testAPhotoWithNoSizeIsNotShrunk() {
        XCTAssertEqual(Avatar.sampleSize(0, 0), 1)
    }

    // MARK: upright

    /// an ordinary photo is left alone
    func testAnOrdinaryPhotoIsLeftAlone() { XCTAssertEqual(Avatar.upright(1), Upright(0, false)) }

    /// no tag, and a tag the standard does not define, leave the photo alone
    func testNoTagAndATagTheStandardDoesNotDefineLeaveThePhotoAlone() {
        for tag in [0, -1, 9, 99] { XCTAssertEqual(Avatar.upright(tag), Upright(0, false), "\(tag)") }
    }

    /// a portrait photo taken on a phone is turned a quarter
    func testAPortraitPhotoTakenOnAPhoneIsTurnedAQuarter() {
        XCTAssertEqual(Avatar.upright(6), Upright(90, false))
        XCTAssertEqual(Avatar.upright(8), Upright(270, false))
        XCTAssertEqual(Avatar.upright(3), Upright(180, false))
    }

    /// the mirrored tags mirror after turning
    func testTheMirroredTagsMirrorAfterTurning() {
        XCTAssertEqual(Avatar.upright(2), Upright(0, true))
        XCTAssertEqual(Avatar.upright(4), Upright(180, true))
        XCTAssertEqual(Avatar.upright(5), Upright(90, true))
        XCTAssertEqual(Avatar.upright(7), Upright(270, true))
    }

    /// the eight tags are eight different orientations
    func testTheEightTagsAreEightDifferentOrientations() {
        XCTAssertEqual(Set((1...8).map { Avatar.upright($0) }).count, 8)
    }

    /// A 2 x 3 picture, marked at its top-left pixel, put through `Upright` the way a matrix does it:
    /// turn clockwise, then mirror. Where the mark ends up is the test of which tag is which.
    private func markAfter(_ tag: Int) -> [Int] {
        let u = Avatar.upright(tag)
        var w = 2, h = 3, x = 0, y = 0
        for _ in 0..<(u.degrees / 90) {
            // A clockwise quarter turn: the top-left pixel goes to the top-right.
            let nx = h - 1 - y
            let ny = x
            x = nx; y = ny
            swap(&w, &h)
        }
        if u.mirrored { x = w - 1 - x }
        return [w, h, x, y]
    }

    /// the tags put the marked corner where the standard says it belongs
    func testTheTagsPutTheMarkedCornerWhereTheStandardSaysItBelongs() {
        // The standard names each tag by where the stored picture's first row and column sit.
        // Turned upright, the stored top-left pixel of a 2 x 3 picture must land here:
        //   1 top-left; 2 top-right; 3 bottom-right; 4 bottom-left;
        //   5 top-left of the transposed picture; 6 top-right of it; 7 bottom-right; 8 bottom-left.
        XCTAssertEqual(markAfter(1), [2, 3, 0, 0])
        XCTAssertEqual(markAfter(2), [2, 3, 1, 0])
        XCTAssertEqual(markAfter(3), [2, 3, 1, 2])
        XCTAssertEqual(markAfter(4), [2, 3, 0, 2])
        XCTAssertEqual(markAfter(5), [3, 2, 0, 0])
        XCTAssertEqual(markAfter(6), [3, 2, 2, 0])
        XCTAssertEqual(markAfter(7), [3, 2, 2, 1])
        XCTAssertEqual(markAfter(8), [3, 2, 0, 1])
    }
}
