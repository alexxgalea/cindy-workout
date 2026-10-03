import Foundation

/// What a session is measured against on the results screen: the best earlier attempt at the
/// same movements, or the last one.
///
/// Pure, like `Records`: no UI types and no clock of its own, so the selection can be tested
/// without a phone. "Earlier" is strict — `Attempt.atMillis` before the session's own — so a
/// session is never measured against itself or against something that had not happened yet. After
/// a workout that pool is exactly `Records.personalRecord`'s; in review, it stays frozen at the
/// moment the session being looked at actually happened.
public enum Comparisons {

    /// Attempts `of` could honestly be measured against: the same movements, strictly before it.
    public static func earlier(_ attempts: [Attempt], of: Attempt) -> [Attempt] {
        attempts.filter { $0.profile == of.profile && $0.atMillis < of.atMillis }
    }

    /// The best of `earlier` — the record `of` was actually chasing.
    public static func best(_ attempts: [Attempt], of: Attempt) -> Attempt? {
        Records.best(earlier(attempts, of: of))
    }

    /// The most recent of `earlier`.
    public static func last(_ attempts: [Attempt], of: Attempt) -> Attempt? {
        earlier(attempts, of: of).max { $0.atMillis < $1.atMillis }
    }

    /// Which comparison a chip or card is showing.
    public enum Kind: Sendable { case best, last }

    /// One choice on the compare card: which kind it is, the session behind it, and its label.
    public struct Option: Equatable, Sendable {
        public let kind: Kind
        public let attempt: Attempt
        public let label: String
    }

    /// `best` then `last`, dropping `last` when it is the same session as `best` — the ordinary
    /// case for an athlete with only one earlier attempt, or one who just beat their previous best
    /// with their very next one. Empty when there is nothing earlier at all, which is what hides
    /// the card: a session cannot be measured against a history it does not have.
    public static func options(_ attempts: [Attempt], of: Attempt) -> [Option] {
        guard let b = best(attempts, of: of) else { return [] }
        let l = last(attempts, of: of)
        let sameSession = l != nil && l!.atMillis == b.atMillis
        var out = [Option(kind: .best, attempt: b,
                          label: sameSession ? "Your best · also last time" : "Your best")]
        if let l, !sameSession { out.append(Option(kind: .last, attempt: l, label: "Last time")) }
        return out
    }

    /// Reps, rounds and average round, `of` minus `reference`; positive is ahead, or faster.
    public struct Delta: Equatable, Sendable {
        public let reps: Int
        public let rounds: Int
        public let avgRoundMs: Int64?
    }

    public static func delta(_ of: Attempt, _ reference: Attempt) -> Delta {
        Delta(reps: of.totalReps - reference.totalReps,
              rounds: of.rounds - reference.rounds,
              avgRoundMs: avgRoundDelta(of, reference))
    }

    /// Positive when `of`'s average round was faster — shorter — than `reference`'s.
    private static func avgRoundDelta(_ of: Attempt, _ reference: Attempt) -> Int64? {
        guard let mine = of.avgRoundMs, let theirs = reference.avgRoundMs else { return nil }
        return theirs - mine
    }
}
