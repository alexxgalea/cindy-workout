import Foundation

/// One finished attempt at Cindy.
public struct Attempt: Equatable, Sendable {
    public let rounds: Int
    public let reps: Int
    public let atMillis: Int64
    /// Clock time: how long the workout timer actually ran, pauses excluded.
    public let durationMs: Int64
    /// Time spent paused. Hidden from the workout clock but not from the day.
    public let pausedMs: Int64
    /// Clock time for each *completed* round, in order, pauses excluded.
    public let roundSplitsMs: [Int64]
    /// The movements this score was actually produced with.
    ///
    /// `nil` means the attempt was written by a build that knew a movement this one does not.
    /// Deliberately not defaulted to standard in that case: quietly relabelling someone's
    /// band-assisted session as strict is exactly the dishonesty `CindyProfile` exists to stop.
    /// Attempts written before variations existed decode as standard, because they were.
    public let profile: CindyProfile?
    /// How many of `totalReps` were tapped in rather than seen.
    ///
    /// Kept because "87 reps" and "87 reps, 12 of them by hand" are different claims, and the
    /// app is not entitled to make the first one when the second is true.
    public let manualReps: Int

    public init(
        rounds: Int, reps: Int, atMillis: Int64,
        durationMs: Int64 = 0, pausedMs: Int64 = 0, roundSplitsMs: [Int64] = [],
        profile: CindyProfile? = CindyProfile.standard, manualReps: Int = 0
    ) {
        self.rounds = rounds
        self.reps = reps
        self.atMillis = atMillis
        self.durationMs = durationMs
        self.pausedMs = pausedMs
        self.roundSplitsMs = roundSplitsMs
        self.profile = profile
        self.manualReps = manualReps
    }

    public var totalReps: Int { rounds * 30 + reps }

    /// The ladder rung this score earns, or `nil` when the ladder does not describe it.
    ///
    /// The levels are calibrated against strict Cindy and top out level with `Records.benchmark`,
    /// so awarding "Legend" for twenty-seven rounds of knee push-ups would be telling the athlete
    /// something untrue about a benchmark they did not attempt. An adaptive session is a
    /// different prescription, not a lower score, and it is ranked against its own kind instead.
    public var level: Level? { profile?.isStandard == true ? Level.of(rounds) : nil }

    /// What to print beside the score.
    ///
    /// A standard Cindy earns a rung on the ladder. Anything else says what it actually was,
    /// because the rung would be a claim about a workout the athlete did not attempt.
    public var caption: String { level?.title ?? profile?.label() ?? "Movements not recognised" }

    /// Wall time from first rep to last, including everything spent paused.
    public var realTimeMs: Int64 { durationMs + pausedMs }

    /// "27 + 12" — the way an AMRAP score is normally written.
    public var scoreLabel: String { reps == 0 ? "\(rounds)" : "\(rounds) + \(reps)" }

    /// Mean time per completed round. Prefers the splits, which cover only whole rounds; falls
    /// back to dividing the duration, which charges the unfinished round to the average.
    public var avgRoundMs: Int64? {
        if !roundSplitsMs.isEmpty {
            return roundSplitsMs.reduce(0, +) / Int64(roundSplitsMs.count)
        }
        if rounds > 0 && durationMs > 0 { return durationMs / Int64(rounds) }
        return nil
    }

    public var fastestRoundMs: Int64? { roundSplitsMs.min() }
    public var slowestRoundMs: Int64? { roundSplitsMs.max() }
}

/// m:ss, for round splits and totals alike.
public func formatDuration(_ ms: Int64) -> String {
    let total = ms / 1000
    return String(format: "%d:%02d", total / 60, total % 60)
}

/// Serialisation and ranking for the record board.
public enum Records {

    /// The score that started this whole thing.
    public static let benchmarkName = "Tom Holland"
    public static let benchmark = Attempt(rounds: 27, reps: 0, atMillis: 0,
                                          durationMs: 20 * 60 * 1000)

    private static let v3 = "v3"
    private static let v4 = "v4"

    public static func encode(_ attempts: [Attempt]) -> String {
        attempts.map { a in
            [v4, "\(a.rounds)", "\(a.reps)", "\(a.atMillis)",
             "\(a.durationMs)", "\(a.pausedMs)",
             a.roundSplitsMs.map(String.init).joined(separator: ","),
             a.profile?.pull.rawValue ?? "",
             a.profile?.push.rawValue ?? "",
             a.profile?.squat.rawValue ?? "",
             "\(a.manualReps)"]
                .joined(separator: "|")
        }.joined(separator: "\n")
    }

    public static func decode(_ raw: String?) -> [Attempt] {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return raw.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            let text = String(line)
            if text.hasPrefix("\(v4)|") { return decodeV4(text) }
            // Attempts written before the movement profile was recorded. They predate the choice
            // existing, so standard is what they were, not an assumption about them.
            if text.hasPrefix("\(v3)|") { return decodeV3(text) }
            // Attempts written before splits and pauses were recorded used bare CSV.
            return decodeV1(text)
        }
    }

    private static func decodeV4(_ line: String) -> Attempt? {
        let p = line.components(separatedBy: "|")
        guard p.count == 11,
              let rounds = Int(p[1]), let reps = Int(p[2]), let at = Int64(p[3]),
              let duration = Int64(p[4]), let paused = Int64(p[5]) else { return nil }
        let splits = p[6].components(separatedBy: ",").compactMap { Int64($0) }
        // A movement name this build does not know leaves the profile unknown rather than
        // guessing at it; the attempt itself is still the athlete's and is kept.
        let pull = PullVariant(rawValue: p[7])
        let push = PushVariant(rawValue: p[8])
        let squat = SquatVariant(rawValue: p[9])
        let profile: CindyProfile? = (pull != nil && push != nil && squat != nil)
            ? CindyProfile(pull: pull!, push: push!, squat: squat!) : nil
        return Attempt(rounds: rounds, reps: reps, atMillis: at, durationMs: duration,
                       pausedMs: paused, roundSplitsMs: splits, profile: profile,
                       manualReps: Int(p[10]) ?? 0)
    }

    private static func decodeV3(_ line: String) -> Attempt? {
        let p = line.components(separatedBy: "|")
        guard p.count == 7,
              let rounds = Int(p[1]), let reps = Int(p[2]), let at = Int64(p[3]),
              let duration = Int64(p[4]), let paused = Int64(p[5]) else { return nil }
        let splits = p[6].components(separatedBy: ",").compactMap { Int64($0) }
        return Attempt(rounds: rounds, reps: reps, atMillis: at,
                       durationMs: duration, pausedMs: paused, roundSplitsMs: splits)
    }

    private static func decodeV1(_ line: String) -> Attempt? {
        let p = line.components(separatedBy: ",")
        guard p.count == 3, let rounds = Int(p[0]), let reps = Int(p[1]), let at = Int64(p[2])
        else { return nil }
        return Attempt(rounds: rounds, reps: reps, atMillis: at)
    }

    /// Best score first; ties broken by the more recent attempt.
    public static func ranked(_ attempts: [Attempt]) -> [Attempt] {
        attempts.sorted {
            $0.totalReps != $1.totalReps ? $0.totalReps > $1.totalReps : $0.atMillis > $1.atMillis
        }
    }

    public static func best(_ attempts: [Attempt]) -> Attempt? { ranked(attempts).first }

    /// Whether this score passes `benchmark`.
    ///
    /// Only a standard Cindy can: the benchmark is a strict score, so comparing an adaptive one
    /// against it would be scoring two different workouts on one scale in whichever direction
    /// happened to flatter.
    public static func beatsBenchmark(_ a: Attempt) -> Bool {
        a.profile?.isStandard == true && a.totalReps > benchmark.totalReps
    }

    /// The attempts a given score may honestly be ranked against: the same movements, exactly.
    ///
    /// Not "standard versus everything else" — a band-assisted Cindy and a knee-push-up Cindy are
    /// no more comparable to each other than either is to the strict one.
    public static func inCategory(_ attempts: [Attempt], profile: CindyProfile?) -> [Attempt] {
        attempts.filter { $0.profile == profile }
    }

    /// The best score recorded under `profile`, or `nil` if there is none.
    public static func bestIn(_ attempts: [Attempt], profile: CindyProfile?) -> Attempt? {
        best(inCategory(attempts, profile: profile))
    }

    /// The record `of` was actually chasing: the best previous attempt at the same movements.
    public static func personalRecord(_ attempts: [Attempt], of: Attempt) -> Attempt? {
        bestIn(attempts.filter { $0.atMillis != of.atMillis }, profile: of.profile)
    }

    /// True when `of` is the best score yet recorded for its own movements.
    public static func isPersonalRecord(_ attempts: [Attempt], of: Attempt) -> Bool {
        guard let previous = personalRecord(attempts, of: of) else { return of.totalReps > 0 }
        return of.totalReps > previous.totalReps
    }
}

/// UserDefaults-backed record board — the iOS counterpart to Android's SharedPreferences store.
public final class RecordStore {

    private static let key = "cindy.attempts"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func all() -> [Attempt] { Records.decode(defaults.string(forKey: Self.key)) }

    /// Attempts oldest first, for charting progress over time.
    public func chronological() -> [Attempt] { all().sorted { $0.atMillis < $1.atMillis } }

    public func add(_ attempt: Attempt) {
        // A zero-rep attempt is someone opening the app and letting the clock run out.
        guard attempt.totalReps > 0 else { return }
        defaults.set(Records.encode(all() + [attempt]), forKey: Self.key)
    }

    public func clear() { defaults.removeObject(forKey: Self.key) }
}
