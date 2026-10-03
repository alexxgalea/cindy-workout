import Foundation

/// The session's own movement words in cycle order, one per movement.
///
/// Kotlin returns an insertion-ordered map; a Swift dictionary has no order, and the order is part
/// of what callers read ("pull-ups, push-ups, squats"), so this keeps it.
public struct MovementPlurals: Equatable, Sendable {
    public let pullup: String
    public let pushup: String
    public let squat: String

    public subscript(_ movement: Exercise) -> String {
        switch movement {
        case .pullup: return pullup
        case .pushup: return pushup
        case .squat: return squat
        }
    }

    /// The words in cycle order.
    public var values: [String] { [pullup, pushup, squat] }
}

/// What one movement of one round banked: its reps, and how many of them were tapped in.
///
/// `tappedReps` is `nil` when the record cannot say. Only the set still running at finish can be in
/// that position (see `SessionStats.from`); a set the athlete left behind carries its own figure.
public struct RoundPart: Equatable, Sendable {
    public let movement: Exercise
    public let reps: Int
    public let tappedReps: Int?

    public init(_ movement: Exercise, _ reps: Int, _ tappedReps: Int?) {
        self.movement = movement
        self.reps = reps
        self.tappedReps = tappedReps
    }

    /// Reached its target, rather than being skipped or still running when the clock stopped.
    public var reachedTarget: Bool { reps >= movement.target }
}

/// One round as it was actually performed.
///
/// `parts` always holds the three movements in cycle order, a movement the athlete never got to
/// showing as zero, so a caller can lay every round out the same way. `finished` is whether the
/// athlete left all three behind: a round with a skipped pull-up set is finished and worth less
/// than thirty, which is the whole reason this is read off the sets and never off a target.
public struct RoundStat: Equatable, Sendable {
    public let number: Int
    public let parts: [RoundPart]
    public let finished: Bool
    /// Clock time of the round, when it was finished and the record timed it.
    public let timeMs: Int64?

    public init(number: Int, parts: [RoundPart], finished: Bool, timeMs: Int64?) {
        self.number = number
        self.parts = parts
        self.finished = finished
        self.timeMs = timeMs
    }

    public var reps: Int { parts.reduce(0) { $0 + $1.reps } }

    /// Every movement reached its target: a full round, thirty reps for the standard scheme.
    public var complete: Bool { parts.allSatisfy { $0.reachedTarget } }

    /// Reps tapped in across the round, or `nil` if any part of it cannot say.
    public var tappedReps: Int? {
        if parts.contains(where: { $0.tappedReps == nil }) { return nil }
        return parts.reduce(0) { $0 + $1.tappedReps! }
    }

    /// "Round 8 · 12 of 30 · 5 pull-ups, 7 push-ups · unfinished", or
    /// "Round 3 · 30 of 30 · 2:44".
    ///
    /// A full round says what it cost; anything less says what went into it, because "25 of 30"
    /// alone cannot tell a skipped set from a round the clock ran out on. Tapped reps are named
    /// rather than folded in. `plurals` is the session's own movement words, so a knee push-up
    /// session never reads "push-ups". `atLeast` is for a session the camera lost the athlete in:
    /// what was banked is a floor, so the round says "at least" before its reps.
    public func caption(_ plurals: MovementPlurals, atLeast: Bool = false) -> String {
        let target = parts.reduce(0) { $0 + $1.movement.target }
        var text = "Round \(number) · \(atLeast ? "at least " : "")\(reps) of \(target)"
        if !complete {
            let done = parts.filter { $0.reps > 0 }
                .map { "\($0.reps) \(plurals[$0.movement])" }
                .joined(separator: ", ")
            if !done.isEmpty { text += " · \(done)" }
        }
        if !finished {
            text += " · unfinished"
        } else if let timeMs {
            text += " · \(formatDuration(timeMs))"
        }
        if let tapped = tappedReps, tapped > 0 { text += " · \(tapped) tapped" }
        return text
    }
}

/// One movement across the whole session.
public struct MovementStat: Equatable, Sendable {
    public let movement: Exercise
    /// The session's own plural: "knee push-ups", never the standard movement's name.
    public let label: String
    public let reps: Int
    /// Clock time spent in its finished sets; `nil` when none was ever finished.
    public let timeMs: Int64?
    /// Its part of the finished sets' time; `nil` unless every movement has a complete set.
    public let shareOfClock: Double?
    public let completeSets: Int
    public let averageCompleteSetMs: Int64?
    /// Reps tapped in; `nil` when the record cannot say (the set still running at finish).
    public let tappedReps: Int?
}

/// The session as rounds and movements, read off the sets the record banked.
///
/// Every figure here comes from `StravaSets.from`, which is the one place that knows how to read
/// `Attempt.setSplits` together with `Attempt.countedReps` and to refuse when they disagree. A
/// session worth `rounds * 30` is exactly the inference this exists to avoid: a skipped pull-up
/// set still advances the cycle, so its round is finished at 25 reps and the rounds say nothing
/// about it.
public struct SessionStats: Equatable, Sendable {
    public let rounds: [RoundStat]
    public let movements: [MovementStat]

    /// The round still running when the clock stopped, if there was one.
    public var unfinished: RoundStat? { rounds.last { !$0.finished } }

    /// The session's rounds and movements, or `nil` when the record cannot be trusted to give
    /// them: it predates counted reps or set times (so the detail is simply unknown), or its sets
    /// do not add up to its own round count. A caller shows nothing then; the tiles that need only
    /// the attempt's own totals still work without this.
    public static func from(_ a: Attempt) -> SessionStats? {
        guard let sets = StravaSets.from(a) else { return nil }
        let closed = a.setSplits
        let finishedRounds = closed.count / 3
        // The engine's own round count and the sets it filed are two banks of the same fact.
        // A record where they differ was cut or edited somewhere, and a track drawn from it
        // would show rounds the score does not have.
        if finishedRounds != a.rounds { return nil }

        // What the set still running at finish tapped in: the same bank-minus-bank sum
        // StravaSets uses for its reps. Out of range means the record does not add up, and
        // saying nothing is better than guessing a figure.
        let openSet: WorkoutSet? = sets.count > closed.count ? sets.last : nil
        let leftOver = a.manualReps - closed.reduce(0) { $0 + $1.manualReps }
        let openTapped: Int? = (leftOver >= 0 && leftOver <= (openSet?.reps ?? 0)) ? leftOver : nil

        // Sets arrive in round order, so a round is a run of equal round numbers.
        var numbers: [Int] = []
        var inRound: [Int: [(index: Int, set: WorkoutSet)]] = [:]
        for (index, set) in sets.enumerated() {
            if inRound[set.round] == nil { numbers.append(set.round) }
            inRound[set.round, default: []].append((index, set))
        }
        let rounds: [RoundStat] = numbers.map { number in
            let parts: [RoundPart] = Exercise.allCases.map { movement in
                guard let entry = inRound[number]!.first(where: { $0.set.exercise == movement })
                else { return RoundPart(movement, 0, 0) }
                if entry.index >= closed.count {
                    return RoundPart(movement, entry.set.reps, openTapped)
                }
                return RoundPart(movement, entry.set.reps, closed[entry.index].manualReps)
            }
            let finished = number <= finishedRounds
            let timed: Int64? = a.roundSplitsMs.indices.contains(number - 1) ? a.roundSplitsMs[number - 1] : nil
            return RoundStat(number: number, parts: parts, finished: finished,
                             timeMs: finished ? timed : nil)
        }

        return SessionStats(rounds: rounds,
                            movements: movementStats(a, sets, closed, openSet, openTapped))
    }

    private static func movementStats(
        _ a: Attempt, _ sets: [WorkoutSet], _ closed: [SetSplit],
        _ openSet: WorkoutSet?, _ openTapped: Int?
    ) -> [MovementStat] {
        let words = plurals(a.profile)
        let timedMs = closed.reduce(Int64(0)) { $0 + $1.ms }
        // A share of the finished sets' time is only a share of anything once all three
        // movements have a complete set to stand on; without that, one movement's 100%
        // would be an artefact of the others not having happened yet.
        let everyMovementComplete = Exercise.allCases.allSatisfy { m in
            closed.contains { $0.movement == m && $0.complete }
        }
        return Exercise.allCases.map { movement in
            let mine = closed.filter { $0.movement == movement }
            let complete = mine.filter { $0.complete }
            let ms: Int64? = mine.isEmpty ? nil : mine.reduce(Int64(0)) { $0 + $1.ms }
            let inOpenSet = openSet?.exercise == movement
            let share: Double? = (everyMovementComplete && ms != nil && timedMs > 0)
                ? Double(ms!) / Double(timedMs) : nil
            let average: Int64? = complete.isEmpty ? nil : Int64(
                (Double(complete.reduce(Int64(0)) { $0 + $1.ms }) / Double(complete.count))
                    .rounded(.toNearestOrAwayFromZero))
            let tapped: Int? = (inOpenSet && openTapped == nil)
                ? nil : mine.reduce(0) { $0 + $1.manualReps } + (inOpenSet ? openTapped! : 0)
            return MovementStat(
                movement: movement,
                label: words[movement],
                reps: sets.filter { $0.exercise == movement }.reduce(0) { $0 + $1.reps },
                timeMs: ms,
                shareOfClock: share,
                completeSets: complete.count,
                averageCompleteSetMs: average,
                tappedReps: tapped)
        }
    }

    /// The session's movement words in cycle order: the plain name for a movement the athlete did
    /// not change, the profile's own plural for one they did ("knee push-ups"). The other
    /// session-page sections speak the same way, so a standard session never reads "strict
    /// pull-ups" in one place and "pull-ups" in the next. A nil profile is a record written before
    /// profiles existed, which was the standard movements.
    public static func plurals(_ profile: CindyProfile?) -> MovementPlurals {
        let standard = CindyProfile.standard
        return MovementPlurals(
            pullup: profile.flatMap { $0.pull != standard.pull ? $0.pull.plural : nil } ?? "pull-ups",
            pushup: profile.flatMap { $0.push != standard.push ? $0.push.plural : nil } ?? "push-ups",
            squat: profile.flatMap { $0.squat != standard.squat ? $0.squat.plural : nil } ?? "squats")
    }

    /// Reps a minute of workout clock, or `nil` before the clock ran. Pauses are not in the clock,
    /// so a paused session is not slowed by them. Derived from the score, so it is a floor exactly
    /// when `Attempt.scoreIsLowerBound` is.
    public static func repsPerMinute(_ a: Attempt) -> Double? {
        a.durationMs > 0 ? Double(a.totalReps) * 60_000.0 / Double(a.durationMs) : nil
    }
}
