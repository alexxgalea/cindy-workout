import Foundation

/// What the voice has always said, and still says byte for byte.
///
/// The wording lived in the app and in `Coach` as string literals and moved here unchanged;
/// `PhrasebookEnTests` pins each one, so making the voice multilingual could not quietly change
/// it. It is also the language the speaker falls back to when the chosen voice cannot be used, and
/// the one the screen-reader descriptions borrow `duration` from.
public struct PhrasebookEn: Phrasebook {

    public init() {}

    public let tag = "en"

    public func say(_ line: VoiceLine) -> String {
        switch line {
        case .count(let reps): return "\(reps)"
        case .movement(let exercise): return exercise.spoken
        case .roundDone(let round, let splitMs): return "Round \(round) in \(duration(splitMs))"
        case .phoneMoved: return "Phone moved. Check the framing."
        case .setUp: return "Get in frame, then do two slow pull ups"
        case .go(let calibrated): return calibrated ? "Calibrated. Go." : "Go. Pull ups"
        case .resume: return "Resume"
        case .finished(let early): return early ? "Stopped." : "Time."
        case .score(let rounds, let totalReps): return score(rounds, totalReps)
        case .averaging(let roundMs): return "Averaging \(duration(roundMs)) a round"
        case .beatBenchmark(let name): return "You beat \(name)"
        case .ready: return "Ready"
        case .fault(let hint): return hint
        case .clock(let mark, let rounds, let totalReps, let projectedRounds):
            return clock(mark, rounds, totalReps, projectedRounds)
        case .sample: return "Three. Four. Five. Push ups."
        case .volumeCheck: return "Three"
        case .recordingSoon(let seconds): return "Recording in \(seconds)"
        case .recordingStarted: return "Recording"
        case .recordingFailed: return "Recording failed"
        case .adaptiveHeelsFlat: return "Adaptive Cindy activated for heels-flat squats."
        }
    }

    /// "one minute twenty" — TTS makes a mess of "1:20".
    public func duration(_ ms: Int64) -> String {
        let (m, sec) = minutesAndSeconds(ms)
        if m == 0 { return "\(sec) seconds" }
        if sec == 0 { return "\(m) minute\(m == 1 ? "" : "s")" }
        return "\(m) minute\(m == 1 ? "" : "s") \(sec)"
    }

    private func clock(_ mark: ClockMark, _ rounds: Int, _ totalReps: Int, _ projectedRounds: Int?) -> String {
        switch mark {
        case .tenSecondsLeft: return "Ten seconds. Everything you have."
        case .oneMinuteLeft:
            return "One minute left. \(roundsText(rounds)) down — finish the one you're in."
        case .twoMinutesLeft: return "Two minutes. " + push(rounds, totalReps)
        case .fiveMinutesLeft: return "Five minutes left. " + pace(rounds, projectedRounds)
        case .halfway: return "Halfway. " + pace(rounds, projectedRounds)
        case .fiveMinutesIn: return "Five minutes in. " + pace(rounds, projectedRounds)
        }
    }

    /// Rounds so far, and where that rate lands at twenty minutes. Falls back to the plain
    /// encouragement before there is a projection, where a figure off a fraction of a round would
    /// be a wild number stated confidently.
    private func pace(_ rounds: Int, _ projectedRounds: Int?) -> String {
        if let projected = projectedRounds { return "\(roundsText(rounds)) — on for \(projected)." }
        return "Keep the pace you're on."
    }

    private func push(_ rounds: Int, _ totalReps: Int) -> String {
        score(rounds, totalReps) + (rounds < 1 ? ". Keep going." : ". Hold the pace.")
    }

    private func score(_ rounds: Int, _ totalReps: Int) -> String {
        let reps = "\(totalReps) rep\(totalReps == 1 ? "" : "s")"
        return rounds < 1 ? reps : "\(roundsText(rounds)) — \(reps) in total"
    }

    /// "1 round", "6 rounds" — said often enough to be worth getting right.
    private func roundsText(_ rounds: Int) -> String { "\(rounds) round\(rounds == 1 ? "" : "s")" }
}
