import Foundation

/// What produced an attempt's calorie figure, said in the same words as the results screen.
///
/// `none` means no figure exists at all (no body weight on file), so `StravaActivityText` writes
/// nothing rather than a line about a number that was never computed.
public enum CalorieBasis: Sendable {
    case none, bodyWeight, heartRate
}

/// The name and description Strava shows for a finished Cindy: plain text, reusing exactly the
/// words the results screen already uses for the same facts, because the upload should read like
/// confirmation of that screen, not a second opinion written in different language.
public enum StravaActivityText {

    /// Mirrors the workout screen's private 20-minute length. `Records.benchmark` already carries
    /// the same literal for the same reason: the workout length is a fixed fact of Cindy.
    private static let workoutMs: Int64 = 20 * 60 * 1000

    /// "Cindy — 17 + 12", "Adaptive Cindy — 9", "Cindy — at least 14 + 3".
    public static func name(_ a: Attempt) -> String {
        let mode = a.profile?.mode.label ?? "Cindy"
        let prefix = a.scoreIsLowerBound ? "at least " : ""
        return "\(mode) — \(prefix)\(a.scoreLabel)"
    }

    /// One fact per line, in the order the athlete would want to read them: the score, what was
    /// actually done, the pace, the honesty caveats, and how the calorie figure was reached.
    ///
    /// `heartRateMs` only matters when `calorieBasis` is `.heartRate`: it is the workout-clock time
    /// a watch actually covered, out of `Attempt.durationMs`. Less than the full clock says so,
    /// rather than letting "estimated from heart rate" quietly claim more coverage than there was.
    public static func description(_ a: Attempt, _ calorieBasis: CalorieBasis, heartRateMs: Int64? = nil) -> String {
        var lines: [String] = []

        let roundsPart = a.reps == 0
            ? count(a.rounds, "round")
            : "\(count(a.rounds, "round")) + \(count(a.reps, "rep"))"
        let stoppedSuffix = a.durationMs < workoutMs ? " — stopped early" : ""
        lines.append("\(roundsPart) · \(count(a.totalReps, "rep")) in \(formatDuration(a.durationMs))\(stoppedSuffix)")

        if let profile = a.profile, !profile.isStandard {
            lines.append(profile.changedMovements())
        } else {
            lines.append(a.caption)
        }

        if !a.roundSplitsMs.isEmpty {
            lines.append("Average round \(formatDuration(a.avgRoundMs!)) · "
                + "fastest \(formatDuration(a.fastestRoundMs!)) · slowest \(formatDuration(a.slowestRoundMs!))")
        }

        if a.pausedMs > 0 {
            lines.append("Paused \(formatDuration(a.pausedMs)) · \(formatDuration(a.realTimeMs)) real time")
        }

        if a.manualReps > 0 {
            lines.append("\(a.manualReps) of the \(a.totalReps) reps were added by hand")
        }

        if a.scoreIsLowerBound {
            lines.append("The camera lost you for \(formatDuration(a.untrackedMs)), so the score is a lower bound")
        }

        switch calorieBasis {
        case .none:
            break
        case .bodyWeight:
            // Java's `%.1f` rounds the shortest decimal digits half up, which C's does not.
            lines.append("Calories estimated from body weight (≈ "
                + "\(JavaText.fixed(Calories.met(totalReps: a.totalReps, activeMs: a.durationMs), 1)) METs)")
        case .heartRate:
            if let covered = heartRateMs, covered < a.durationMs {
                lines.append("Calories from heart rate for \(formatDuration(covered)) of "
                    + "\(formatDuration(a.durationMs)), body weight for the rest")
            } else {
                lines.append("Calories estimated from heart rate")
            }
        }

        lines.append("Counted by Cindy Tracker")

        return lines.joined(separator: "\n")
    }

    /// "1 round", "6 rounds": the same care `Coach` takes, since this is read as often as heard.
    private static func count(_ n: Int, _ noun: String) -> String {
        "\(n) \(noun)\(n == 1 ? "" : "s")"
    }
}
