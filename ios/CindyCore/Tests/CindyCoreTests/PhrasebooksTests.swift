import XCTest
import CindyCore

/// What must hold for every language at once.
///
/// The compiler already refuses a phrasebook that lacks a line or a hint. What it cannot refuse is
/// a line that compiles and is wrong in a way that only a voice reveals: a blank, a template that
/// leaked into the sentence, English left in the middle of Spanish, or a number followed by a full
/// stop, which some engines read as an ordinal ("12." as "twelfth") in the middle of a score.
///
/// Language-specific grammar is pinned in each language's own test; this is the floor under all of
/// them, and the first place a new language is checked.
///
/// Mirrors `PhrasebooksTest.kt`.
final class PhrasebooksTests: XCTestCase {

    private let others = VoicePacks.all.filter { $0.tag != "en" }

    /// Counts where languages change their mind, run through every line that carries one.
    private let counts = [0, 1, 2, 3, 4, 5, 11, 12, 14, 19, 20, 21, 22, 25, 101, 111, 112, 121]

    /// Every line that takes a number, at every one of those numbers, plus the fixed samples.
    private lazy var lines: [VoiceLine] = {
        var all = VoiceLineSamples.all
        for n in counts {
            all += [
                .score(rounds: n, totalReps: n * 30),
                .score(rounds: 0, totalReps: n),
                .roundDone(round: n, splitMs: Int64(n) * 7_000),
                .roundDone(round: n, splitMs: Int64(n) * 61_000),
                .averaging(roundMs: Int64(n) * 9_000),
                .recordingSoon(seconds: n)
            ]
            for mark in ClockMark.allCases {
                all.append(.clock(mark: mark, rounds: n, totalReps: n * 30, projectedRounds: n + 1))
                all.append(.clock(mark: mark, rounds: n, totalReps: n * 30, projectedRounds: nil))
            }
        }
        return all
    }()

    private func forEveryLine(_ check: (VoicePack, VoiceLine, String) -> Void) {
        for pack in VoicePacks.all {
            for line in lines { check(pack, line, pack.phrasebook.say(line)) }
        }
    }

    private func isBlank(_ s: String) -> Bool { s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// nothing is blank or padded
    func testNothingIsBlankOrPadded() {
        forEveryLine { pack, line, said in
            XCTAssertFalse(isBlank(said), "\(pack.tag): \(line) was blank")
            XCTAssertEqual(said.trimmingCharacters(in: .whitespacesAndNewlines), said,
                           "\(pack.tag): \(line) has stray space in \"\(said)\"")
            XCTAssertFalse(said.contains("  "), "\(pack.tag): \(line) has a double space in \"\(said)\"")
        }
    }

    /// no template or null leaks into a sentence
    func testNoTemplateOrNullLeaksIntoASentence() {
        forEveryLine { pack, line, said in
            for leak in ["null", "nil", "$", "{", "}", "@", "\\("] {
                XCTAssertFalse(said.contains(leak), "\(pack.tag): \(line) said \"\(said)\"")
            }
        }
    }

    /// no sentence ends a number with a full stop
    func testNoSentenceEndsANumberWithAFullStop() {
        // English is exempt: its lines are pinned byte for byte and "on for 12." is one of them.
        for pack in others {
            for line in lines {
                let said = pack.phrasebook.say(line)
                XCTAssertNil(said.range(of: "\\d\\.", options: .regularExpression),
                             "\(pack.tag): \"\(said)\" has a number before a full stop")
            }
        }
    }

    /// no line is long enough to lose the athlete
    func testNoLineIsLongEnoughToLoseTheAthlete() {
        forEveryLine { pack, _, said in
            // Kotlin's length is UTF-16 units, so that is what is counted here.
            XCTAssertLessThanOrEqual(said.utf16.count, 160, "\(pack.tag): \"\(said)\" is \(said.utf16.count) characters")
        }
    }

    /// a count is the bare number in every language
    func testACountIsTheBareNumberInEveryLanguage() {
        for pack in VoicePacks.all {
            for n in counts { XCTAssertEqual(pack.phrasebook.say(.count(reps: n)), "\(n)", pack.tag) }
        }
    }

    /// no language answers in English
    func testNoLanguageAnswersInEnglish() {
        let english = PhrasebookEn()
        for pack in others {
            // Counts are numerals and some movements are borrowed words ("squats"), so both are
            // allowed to match; everything else in another language is not English.
            for line in VoiceLineSamples.all {
                switch line {
                case .count, .movement: continue
                default:
                    XCTAssertNotEqual(english.say(line), pack.phrasebook.say(line),
                                      "\(pack.tag) speaks English for \(line)")
                }
            }
        }
    }

    /// every hint has words, and none of them is the English
    func testEveryHintHasWordsAndNoneOfThemIsTheEnglish() {
        for pack in others {
            for hint in Hint.allCases {
                let said = pack.phrasebook.say(.fault(hint: hint.english))
                XCTAssertFalse(isBlank(said), "\(pack.tag): \(hint) was blank")
                XCTAssertNotEqual(said, hint.english, "\(pack.tag) leaves \(hint) in English")
            }
        }
    }

    /// hints are each said their own way
    func testHintsAreEachSaidTheirOwnWay() {
        for pack in others {
            let said = Hint.allCases.map { pack.phrasebook.say(.fault(hint: $0.english)) }
            // "Hang from the bar" is both a hint and a start cue, and is one entry; the rest are
            // different instructions and must not collapse into the same sentence.
            XCTAssertEqual(said.count, Set(said).count, "\(pack.tag) says two hints the same")
        }
    }

    /// an uncatalogued hint is a generic prompt in the language, never the English
    func testAnUncataloguedHintIsAGenericPromptInTheLanguageNeverTheEnglish() {
        for pack in others {
            let said = pack.phrasebook.say(.fault(hint: "Something nobody catalogued"))
            XCTAssertFalse(isBlank(said), "\(pack.tag) was blank")
            XCTAssertNotEqual(said, "Something nobody catalogued", "\(pack.tag) echoed the English")
        }
    }

    /// the lines that differ in meaning differ in words
    func testTheLinesThatDifferInMeaningDifferInWords() {
        for pack in VoicePacks.all {
            let book = pack.phrasebook
            func distinct(_ what: String, _ lines: [VoiceLine]) {
                let said = lines.map { book.say($0) }
                XCTAssertEqual(said.count, Set(said).count, "\(pack.tag): \(what) collapsed into one sentence")
            }
            distinct("movements", Exercise.allCases.map { .movement($0) })
            distinct("the recording announcements", [.recordingSoon(seconds: 3), .recordingStarted, .recordingFailed])
            distinct("the start", [.go(calibrated: true), .go(calibrated: false)])
            distinct("the end", [.finished(early: true), .finished(early: false)])
            distinct("the clock marks",
                     ClockMark.allCases.map { .clock(mark: $0, rounds: 6, totalReps: 185, projectedRounds: 12) })
        }
    }

    /// a round's number and its seconds are both in the sentence
    func testARoundsNumberAndItsSecondsAreBothInTheSentence() {
        // 95 seconds is a minute and 35. The minute is written out in most languages, but the 35
        // is a digit in all of them.
        for pack in VoicePacks.all {
            let said = pack.phrasebook.say(.roundDone(round: 7, splitMs: 95_000))
            XCTAssertTrue(said.contains("7"), "\(pack.tag): \"\(said)\" lost the round number")
            XCTAssertTrue(said.contains("35"), "\(pack.tag): \"\(said)\" lost the seconds")
        }
    }

    /// the benchmark's name arrives untouched
    func testTheBenchmarksNameArrivesUntouched() {
        for pack in VoicePacks.all {
            let said = pack.phrasebook.say(.beatBenchmark(name: "Tom Holland"))
            XCTAssertTrue(said.contains("Tom Holland"), "\(pack.tag): \"\(said)\"")
        }
    }
}
