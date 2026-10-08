import Foundation

/// One finished attempt at Cindy.
public struct Attempt: Equatable, Sendable {
    public var rounds: Int
    public var reps: Int
    public var atMillis: Int64
    /// Clock time: how long the workout timer actually ran, pauses excluded.
    public var durationMs: Int64
    /// Time spent paused. Hidden from the workout clock but not from the day.
    public var pausedMs: Int64
    /// Clock time for each *completed* round, in order, pauses excluded.
    public var roundSplitsMs: [Int64]
    /// The movements this score was actually produced with.
    ///
    /// `nil` means the attempt was written by a build that knew a movement this one does not.
    /// Deliberately not defaulted to standard in that case: quietly relabelling someone's
    /// band-assisted session as strict is exactly the dishonesty `CindyProfile` exists to stop.
    /// Attempts written before variations existed decode as standard, because they were.
    public var profile: CindyProfile?
    /// How many of `totalReps` were tapped in rather than seen.
    ///
    /// Kept because "87 reps" and "87 reps, 12 of them by hand" are different claims, and the
    /// app is not entitled to make the first one when the second is true.
    public var manualReps: Int
    /// The reps the engine actually banked, or `nil` for an attempt written before it was kept.
    ///
    /// A skipped movement still advances the cycle, so the round count alone cannot say what was
    /// done: a round with a skipped pull-up set is finished and worth twenty-five, not thirty.
    public var countedReps: Int?
    /// Clock time the camera spent unable to read the athlete.
    public var untrackedMs: Int64
    /// The time each movement block took, in the order they were left behind.
    public var setSplits: [SetSplit]

    public init(
        rounds: Int, reps: Int, atMillis: Int64,
        durationMs: Int64 = 0, pausedMs: Int64 = 0, roundSplitsMs: [Int64] = [],
        profile: CindyProfile? = CindyProfile.standard, manualReps: Int = 0,
        countedReps: Int? = nil, untrackedMs: Int64 = 0, setSplits: [SetSplit] = []
    ) {
        self.rounds = rounds
        self.reps = reps
        self.atMillis = atMillis
        self.durationMs = durationMs
        self.pausedMs = pausedMs
        self.roundSplitsMs = roundSplitsMs
        self.profile = profile
        self.manualReps = manualReps
        self.countedReps = countedReps
        self.untrackedMs = untrackedMs
        self.setSplits = setSplits
    }

    /// What the attempt scored: the reps counted where the record kept them, otherwise the round
    /// tally, which is only an inference.
    public var totalReps: Int { countedReps ?? (rounds * 30 + reps) }

    /// True when the camera lost the athlete for long enough that the score may be short.
    ///
    /// The app cannot tell resting out of frame from being unreadable in frame, so this says only
    /// what it knows: the number may be a lower bound.
    public var scoreIsLowerBound: Bool { untrackedMs >= Records.untrackedToleranceMs }

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
    private static let v5 = "v5"
    private static let v6 = "v6"
    private static let v7 = "v7"

    /// Untracked time a score can carry and still be treated as exact.
    ///
    /// Half a minute of a twenty-minute workout, which is about 2.5% of it. Long enough that
    /// stepping out of shot for a drink does not tarnish a session, short enough that a fading
    /// light cannot take a dozen reps before anything is said. The app cannot tell resting out of
    /// frame from being unreadable in frame, so the flag it raises says only what it knows: the
    /// score may be a lower bound.
    public static let untrackedToleranceMs: Int64 = 30_000

    public static func encode(_ attempts: [Attempt]) -> String {
        attempts.map(encodeLine).joined(separator: "\n")
    }

    private static func encodeLine(_ a: Attempt) -> String {
        let splits: String = a.roundSplitsMs.map { String($0) }.joined(separator: ",")
        // Empty for an attempt recorded before the count existed, so that reading it back
        // leaves it unknown rather than restating it as the round tally times thirty.
        let counted: String = a.countedReps.map { String($0) } ?? ""
        let sets: String = a.setSplits
            .map { "\($0.movement.name):\($0.ms):\($0.reps):\($0.manualReps)" }
            .joined(separator: ",")
        var f: [String] = [v7, String(a.rounds), String(a.reps), String(a.atMillis)]
        f += [String(a.durationMs), String(a.pausedMs), splits]
        f += [a.profile?.pull.rawValue ?? "", a.profile?.push.rawValue ?? "",
              a.profile?.squat.rawValue ?? ""]
        f += [String(a.manualReps), counted, String(a.untrackedMs), sets]
        return f.joined(separator: "|")
    }

    public static func decode(_ raw: String?) -> [Attempt] {
        guard let raw, !isBlank(raw) else { return [] }
        return lines(raw).compactMap { line in
            if line.hasPrefix("\(v7)|") { return decodeV7(line) }
            if line.hasPrefix("\(v6)|") { return decodeV6(line) }
            if line.hasPrefix("\(v5)|") { return decodeV5(line) }
            if line.hasPrefix("\(v4)|") { return decodeV4(line) }
            // Attempts written before the movement profile was recorded. They predate the choice
            // existing, so standard is what they were, not an assumption about them.
            if line.hasPrefix("\(v3)|") { return decodeV3(line) }
            // Attempts written before splits and pauses were recorded used bare CSV.
            return decodeV1(line)
        }
    }

    /// V6 plus the time each set took.
    private static func decodeV7(_ line: String) -> Attempt? {
        let p = fields(line, "|")
        guard p.count == 14, var a = decodeCommon(p) else { return nil }
        a.countedReps = toInt(p[11])
        a.untrackedMs = toLong(p[12]) ?? 0
        a.setSplits = decodeSets(p[13])
        return a
    }

    /// One bad entry costs only itself: the attempt and its other sets are still the athlete's.
    private static func decodeSets(_ raw: String) -> [SetSplit] {
        fields(raw, ",").filter { !isBlank($0) }.compactMap { entry in
            let f = fields(entry, ":")
            guard f.count == 4,
                  let movement = Exercise(name: f[0]),
                  let ms = toLong(f[1]), let reps = toInt(f[2]), let manual = toInt(f[3])
            else { return nil }
            return SetSplit(movement, ms, reps, manual)
        }
    }

    /// V5 plus the time the camera spent unable to read the athlete.
    private static func decodeV6(_ line: String) -> Attempt? {
        let p = fields(line, "|")
        guard p.count == 13, var a = decodeCommon(p) else { return nil }
        // An attempt written before this was measured decodes as zero, which is the right
        // reading: nothing was known to be missed, rather than nothing was missed.
        a.countedReps = toInt(p[11])
        a.untrackedMs = toLong(p[12]) ?? 0
        return a
    }

    /// V4 plus the reps actually counted, which a skipped movement makes unguessable.
    private static func decodeV5(_ line: String) -> Attempt? {
        let p = fields(line, "|")
        guard p.count == 12, var a = decodeCommon(p) else { return nil }
        a.countedReps = toInt(p[11])
        return a
    }

    private static func decodeV4(_ line: String) -> Attempt? {
        let p = fields(line, "|")
        guard p.count == 11 else { return nil }
        return decodeCommon(p)
    }

    /// The ten fields V4 and V5 share, in the same places.
    private static func decodeCommon(_ p: [String]) -> Attempt? {
        guard let rounds = toInt(p[1]), let reps = toInt(p[2]), let at = toLong(p[3]),
              let duration = toLong(p[4]), let paused = toLong(p[5]) else { return nil }
        let splits = fields(p[6], ",").compactMap { toLong($0) }
        // A movement name this build does not know leaves the profile unknown rather than
        // guessing at it; the attempt itself is still the athlete's and is kept.
        let pull = PullVariant(rawValue: p[7])
        let push = PushVariant(rawValue: p[8])
        let squat = SquatVariant(rawValue: p[9])
        let profile: CindyProfile? = (pull != nil && push != nil && squat != nil)
            ? CindyProfile(pull: pull!, push: push!, squat: squat!) : nil
        return Attempt(rounds: rounds, reps: reps, atMillis: at, durationMs: duration,
                       pausedMs: paused, roundSplitsMs: splits, profile: profile,
                       manualReps: toInt(p[10]) ?? 0)
    }

    private static func decodeV3(_ line: String) -> Attempt? {
        let p = fields(line, "|")
        guard p.count == 7,
              let rounds = toInt(p[1]), let reps = toInt(p[2]), let at = toLong(p[3]),
              let duration = toLong(p[4]), let paused = toLong(p[5]) else { return nil }
        let splits = fields(p[6], ",").compactMap { toLong($0) }
        return Attempt(rounds: rounds, reps: reps, atMillis: at,
                       durationMs: duration, pausedMs: paused, roundSplitsMs: splits)
    }

    private static func decodeV1(_ line: String) -> Attempt? {
        let p = fields(line, ",")
        guard p.count == 3, let rounds = toInt(p[0]), let reps = toInt(p[1]), let at = toLong(p[2])
        else { return nil }
        return Attempt(rounds: rounds, reps: reps, atMillis: at)
    }

    // MARK: - reading text the way Kotlin does

    /// Kotlin's `String.split(delimiter)`: every piece, empty ones included.
    static func fields(_ text: String, _ separator: Character) -> [String] {
        text.split(separator: separator, omittingEmptySubsequences: false).map(String.init)
    }

    /// Kotlin's `lineSequence()`: breaks at `\n`, `\r\n` and `\r`, and only those. Swift sees
    /// `\r\n` as one character, so the text is walked as scalars.
    static func lines(_ text: String) -> [String] {
        var out: [String] = [], current = String.UnicodeScalarView()
        var afterReturn = false
        for scalar in text.unicodeScalars {
            if scalar == "\r" {
                out.append(String(current)); current = .init()
                afterReturn = true
            } else if scalar == "\n" {
                if !afterReturn { out.append(String(current)); current = .init() }
                afterReturn = false
            } else {
                afterReturn = false
                current.append(scalar)
            }
        }
        out.append(String(current))
        return out
    }

    /// Kotlin's `isNullOrBlank` for a string that is not null.
    static func isBlank(_ text: String) -> Bool {
        text.unicodeScalars.allSatisfy { $0.properties.isWhitespace }
    }

    /// Kotlin's `toIntOrNull` and `toLongOrNull`.
    ///
    /// Two things Swift's own parsers do differently. Kotlin reads any Unicode decimal digit
    /// (`Character.digit`), so "١٢٣" is 123 there and nothing here; and an `Int` is 32 bits, so a
    /// number that does not fit is not an `Int` in Kotlin either. Only the digits of the Basic
    /// Multilingual Plane count, because Kotlin reads UTF-16 units one at a time.
    static func toInt(_ text: String) -> Int? { asciiNumber(text).flatMap { Int32($0) }.map(Int.init) }
    static func toLong(_ text: String) -> Int64? { asciiNumber(text).flatMap { Int64($0) } }

    /// `text` with every decimal digit written as ASCII, or nil when it is not a sign and digits.
    private static func asciiNumber(_ text: String) -> String? {
        var out = ""
        var first = true
        for scalar in text.unicodeScalars {
            defer { first = false }
            if first && (scalar == "-" || scalar == "+") {
                out.unicodeScalars.append(scalar)
            } else if scalar.value <= 0xFFFF, scalar.properties.generalCategory == .decimalNumber,
                      let digit = scalar.properties.numericValue {
                out += String(Int(digit))
            } else {
                return nil
            }
        }
        // A sign alone, or nothing at all, is not a number.
        return out.isEmpty || out == "-" || out == "+" ? nil : out
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
        a.profile?.isStandard == true && !a.scoreIsLowerBound && a.totalReps > benchmark.totalReps
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
    ///
    /// A score the camera could not stand behind is never one, however large. It is still kept,
    /// still shown and still ranked — the athlete did at least that much — but "a new record" is
    /// a claim about an exact number, and an attempt with minutes of blind camera in it has not
    /// earned that claim. This is the same line `beatsBenchmark` already drew for adaptive
    /// movements: rank it honestly rather than withhold it.
    public static func isPersonalRecord(_ attempts: [Attempt], of: Attempt) -> Bool {
        if of.scoreIsLowerBound { return false }
        guard let previous = personalRecord(attempts, of: of) else { return of.totalReps > 0 }
        return of.totalReps > previous.totalReps
    }
}

/// `UserDefaults`-backed record board — the iOS counterpart to Android's `SharedPreferences` one,
/// holding the same string under the same key.
public final class RecordStore {

    private static let key = "attempts"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func all() -> [Attempt] { Records.decode(defaults.string(forKey: Self.key)) }

    /// Attempts oldest first, for charting progress over time.
    public func chronological() -> [Attempt] { all().sorted { $0.atMillis < $1.atMillis } }

    /// Stores `attempt`, and says whether it actually was.
    ///
    /// A zero-rep attempt is someone opening the app and letting the clock run out, so it is
    /// dropped rather than filed. The caller needs to know which happened: a heart-rate trace
    /// belongs beside a saved attempt, and there is nothing for it to belong beside when nothing
    /// was stored.
    @discardableResult
    public func add(_ attempt: Attempt) -> Bool {
        guard attempt.totalReps > 0 else { return false }
        defaults.set(Records.encode(all() + [attempt]), forKey: Self.key)
        return true
    }

    public func clear() { defaults.removeObject(forKey: Self.key) }
}
