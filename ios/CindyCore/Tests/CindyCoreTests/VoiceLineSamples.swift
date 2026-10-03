import CindyCore

/// A representative instance of every `VoiceLine`, for the tests that must hold across all of them.
///
/// Each phrasebook is an exhaustive `switch`, so the compiler already refuses a language that lacks
/// a line. What it cannot refuse is a line nobody wrote a *test* for, which is what `kinds` is for:
/// it is the number of kinds of line there are, and `all` has to cover exactly that many.
///
/// Mirrors `VoiceLineSamples.kt`.
enum VoiceLineSamples {

    /// The number of kinds of `VoiceLine`. Adding one means adding it to `all` and bumping this.
    static let kinds = 20

    /// The case a line is, without what it carries: Kotlin's `it.javaClass`.
    static func kind(of line: VoiceLine) -> String {
        String(String(describing: line).prefix { $0 != "(" })
    }

    static let all: [VoiceLine] = {
        var lines: [VoiceLine] = [.count(reps: 3)]
        lines += Exercise.allCases.map { .movement($0) }
        lines += [
            .roundDone(round: 3, splitMs: 80_000),
            .phoneMoved,
            .setUp,
            .go(calibrated: true),
            .go(calibrated: false),
            .resume,
            .finished(early: true),
            .finished(early: false),
            .score(rounds: 6, totalReps: 185),
            .score(rounds: 0, totalReps: 12),
            .averaging(roundMs: 80_000),
            .beatBenchmark(name: "Tom Holland"),
            .ready,
            .fault(hint: "Get on the bar")
        ]
        for mark in ClockMark.allCases {
            lines.append(.clock(mark: mark, rounds: 6, totalReps: 185, projectedRounds: 12))
            lines.append(.clock(mark: mark, rounds: 0, totalReps: 12, projectedRounds: nil))
        }
        lines += [
            .sample,
            .volumeCheck,
            .recordingSoon(seconds: 3),
            .recordingStarted,
            .recordingFailed,
            .adaptiveHeelsFlat
        ]
        return lines
    }()
}
