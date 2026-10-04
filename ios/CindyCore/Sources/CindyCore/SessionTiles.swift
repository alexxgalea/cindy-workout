import Foundation

/// One figure of the session at a glance: a label, a value and one line saying what it is made of.
///
/// `speech` is what a screen reader says for the whole tile, so the label, the value and the
/// footnote arrive as one sentence rather than three unrelated fragments.
public struct StatTile: Equatable, Sendable {
    public let label: String
    public let value: String
    public let footnote: String
    public let speech: String

    public init(label: String, value: String, footnote: String, speech: String) {
        self.label = label
        self.value = value
        self.footnote = footnote
        self.speech = speech
    }
}

/// The six figures under the score, built from the attempt's own totals. The pure half of
/// `StatTiles.kt`; the grid and the movement card that draw them are the results screen's.
public enum SessionTiles {

    /// No data is a dash, not a zero: nothing was timed, which is not the same as taking no time.
    public static let none = "—"

    /// ROUNDS, REPS, TIME, then AVG ROUND, FASTEST, SLOWEST.
    ///
    /// `stats` is optional: without set times (an older record) the tiles still say everything the
    /// attempt's own totals can, and nothing more. The rounds tile's footnote then falls back to
    /// `Attempt.reps`, the same loose count the headline already shows.
    public static func of(_ a: Attempt, _ stats: SessionStats?) -> [StatTile] {
        let splits = a.roundSplitsMs
        let fastest = splits.min()
        let slowest = splits.max()
        return [
            rounds(a, stats),
            reps(a),
            time(a),
            average(a),
            extreme("FASTEST", "Fastest round", fastest, fastest.flatMap { splits.firstIndex(of: $0) } ?? -1),
            extreme("SLOWEST", "Slowest round", slowest, slowest.flatMap { splits.firstIndex(of: $0) } ?? -1)
        ]
    }

    private static func rounds(_ a: Attempt, _ stats: SessionStats?) -> StatTile {
        let leftover = stats.map { $0.unfinished?.reps ?? 0 } ?? a.reps
        // The reps into the next round come from the score, so a floor says "at least" here too,
        // on the tile and in the sentence read out for it.
        let atLeast = a.scoreIsLowerBound ? "at least " : ""
        let into = "\(leftover) \(repWord(leftover)) into round \(a.rounds + 1)"
        let footnote: String
        if leftover > 0 { footnote = "\(atLeast)+\(into)" }
        else if a.rounds == 0 { footnote = "none finished" }
        else { footnote = "all finished" }
        let speech = leftover > 0 ? "Rounds: \(a.rounds), plus \(atLeast)\(into)" : "Rounds: \(a.rounds), \(footnote)"
        return StatTile(label: "ROUNDS", value: "\(a.rounds)", footnote: footnote, speech: speech)
    }

    private static func reps(_ a: Attempt) -> StatTile {
        let pace = SessionStats.repsPerMinute(a)
        let atLeast = a.scoreIsLowerBound
        // A floor says so on the tile and in the sentence read out for it: the camera lost the
        // athlete, so the true figure, and the pace made from it, can only be higher.
        let rate = pace.map { "\(javaFixed($0, 1)) reps/min" }
        var parts: [String] = []
        if let rate { parts.append(atLeast ? "at least \(rate)" : rate) }
        else if atLeast { parts.append("at least") }
        if a.manualReps > 0 { parts.append("\(a.manualReps) tapped") }
        let footnote = parts.joined(separator: " · ")
        var speech = atLeast ? "Reps: at least \(a.totalReps)" : "Reps: \(a.totalReps)"
        if let pace {
            speech += ", \(atLeast ? "at least " : "")\(javaFixed(pace, 1)) reps a minute"
        }
        if a.manualReps > 0 { speech += ", \(a.manualReps) of them tapped in" }
        return StatTile(label: "REPS", value: "\(a.totalReps)", footnote: footnote.isEmpty ? "banked" : footnote, speech: speech)
    }

    private static func time(_ a: Attempt) -> StatTile {
        let footnote = a.pausedMs > 0 ? "plus \(formatDuration(a.pausedMs)) paused" : "on the clock"
        return StatTile(label: "TIME", value: formatDuration(a.durationMs), footnote: footnote,
                        speech: "Time: \(formatDuration(a.durationMs)) on the clock"
                            + (a.pausedMs > 0 ? ", plus \(formatDuration(a.pausedMs)) paused" : ""))
    }

    private static func average(_ a: Attempt) -> StatTile {
        guard let avg = a.avgRoundMs else {
            return StatTile(label: "AVG", value: none, footnote: "no full round", speech: "Average round: no full round yet")
        }
        // Without round splits the figure is the clock over the rounds, which charges the unfinished
        // round to the average, and says so rather than passing as a mean of rounds.
        let footnote = a.roundSplitsMs.isEmpty
            ? "clock over rounds"
            : "over \(a.roundSplitsMs.count) \(roundWord(a.roundSplitsMs.count))"
        return StatTile(label: "AVG", value: formatDuration(avg), footnote: footnote,
                        speech: "Average round: \(formatDuration(avg)), \(footnote)")
    }

    private static func extreme(_ label: String, _ spoken: String, _ ms: Int64?, _ index: Int) -> StatTile {
        guard let ms else { return StatTile(label: label, value: none, footnote: "no full round", speech: "\(spoken): no full round yet") }
        let footnote = "round \(index + 1)"
        return StatTile(label: label, value: formatDuration(ms), footnote: footnote,
                        speech: "\(spoken): \(formatDuration(ms)), \(footnote)")
    }

    private static func repWord(_ n: Int) -> String { n == 1 ? "rep" : "reps" }
    private static func roundWord(_ n: Int) -> String { n == 1 ? "round" : "rounds" }
}
