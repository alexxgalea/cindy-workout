import Foundation

/// What one movement of one round actually banked.
///
/// This is the unit Strava's JSON `sets` array wants, and the only one honest to give it: `reps`
/// is a figure `StravaSets.from` reads straight off `Attempt.setSplits` — the record of what each
/// movement scored — never a movement's target. `round` counts from 1, matching how the app
/// already talks about rounds everywhere else.
///
/// Lives here rather than with the Strava payload because the session screens read the same sets.
public struct WorkoutSet: Equatable, Sendable {
    public let round: Int
    public let exercise: Exercise
    public let reps: Int

    public init(_ round: Int, _ exercise: Exercise, _ reps: Int) {
        self.round = round
        self.exercise = exercise
        self.reps = reps
    }
}

/// Rebuilds the set list from an attempt's own record, rather than a second store kept beside it.
///
/// `Attempt.setSplits` already banks every movement the workout left behind: `SplitBook` files
/// one on every `exerciseDone` and `roundDone`, at the count `WorkoutEngine` had actually reached,
/// and unwinds one with `stepBack()` on an undo that crosses a movement boundary. What that
/// record cannot contain is the movement still running when the clock stopped — it never reached
/// an event of its own, so `SplitBook` never filed it. `from` adds that last set back in, and
/// refuses to guess at a set list when the record does not add up to a movement it can trust.
public enum StravaSets {

    /// The attempt's sets, oldest first, or `nil` when the record cannot be trusted.
    ///
    /// The final set, if there is one, is the movement in progress at finish. Its reps are
    /// `a.totalReps - setSplits.sum(reps)`, and that subtraction is honest only because *both*
    /// sides are banks, not a target and a bank: `Attempt.totalReps` is what the engine actually
    /// counted from the first rep to the last, and the splits are every movement that same count
    /// has already been paid out to. What is left over is exactly the movement still running when
    /// the clock stopped — never an inference from rounds or targets, which is the line the rest
    /// of the app holds for every rep it reports.
    public static func from(_ a: Attempt) -> [WorkoutSet]? {
        // Nil means this attempt predates a counted total (pre-V5) and totalReps falls back to
        // rounds * 30 + reps — an inferred tally, not a bank. Strava never sees one.
        guard let counted = a.countedReps else { return nil }

        // advance() only ever moves pull-up -> push-up -> squat -> pull-up..., starting at the
        // pull-up, so this is the one order a genuine set of splits can be in.
        var expected = Exercise.pullup
        var sets: [WorkoutSet] = []
        for (index, split) in a.setSplits.enumerated() {
            // A split that is not the movement its position in the cycle requires means the
            // record it came from was cut short, reordered, or otherwise not the cycle the
            // engine actually ran. Building a set list on top of that would be a guess wearing
            // banked numbers, so nothing is returned instead.
            if split.movement != expected { return nil }
            sets.append(WorkoutSet(index / 3 + 1, split.movement, split.reps))
            expected = expected.next
        }

        // The movement that follows the last one SplitBook closed off is the one running when
        // the clock stopped — or the pull-up, for an attempt that stopped before its first
        // movement was ever left.
        let inProgress = a.setSplits.last?.movement.next ?? .pullup
        let remainder = counted - sets.reduce(0) { $0 + $1.reps }
        // A movement that had already reached its target would have advanced and been banked
        // by SplitBook, so it can never still be "in progress" — a remainder at or past the
        // target, or negative, means the splits and the total disagree with each other, which
        // is a broken record rather than an unfinished movement.
        if !(0..<inProgress.target).contains(remainder) { return nil }
        // A movement in progress at zero reps banked nothing yet, so it is not a set.
        if remainder > 0 { sets.append(WorkoutSet(a.setSplits.count / 3 + 1, inProgress, remainder)) }

        // Belt and braces: the arithmetic above is built so neither of these can actually fail,
        // but an upload is exactly the wrong place to find out a later change broke that.
        if sets.reduce(0, { $0 + $1.reps }) != a.totalReps { return nil }
        if !sets.contains(where: { $0.reps > 0 }) { return nil }

        return sets
    }
}
