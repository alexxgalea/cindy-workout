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

    public init(rounds: Int, reps: Int, atMillis: Int64,
                durationMs: Int64 = 0, pausedMs: Int64 = 0, roundSplitsMs: [Int64] = []) {
        self.rounds = rounds
        self.reps = reps
        self.atMillis = atMillis
        self.durationMs = durationMs
        self.pausedMs = pausedMs
        self.roundSplitsMs = roundSplitsMs
    }

    public var totalReps: Int { rounds * 30 + reps }
    public var level: Level { Level.of(rounds) }

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

    public static func encode(_ attempts: [Attempt]) -> String {
        attempts.map { a in
            [v3, "\(a.rounds)", "\(a.reps)", "\(a.atMillis)",
             "\(a.durationMs)", "\(a.pausedMs)",
             a.roundSplitsMs.map(String.init).joined(separator: ",")]
                .joined(separator: "|")
        }.joined(separator: "\n")
    }

    public static func decode(_ raw: String?) -> [Attempt] {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return raw.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            let text = String(line)
            // Attempts written before splits and pauses were recorded used bare CSV.
            return text.hasPrefix("\(v3)|") ? decodeV3(text) : decodeV1(text)
        }
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

    public static func beatsBenchmark(_ a: Attempt) -> Bool { a.totalReps > benchmark.totalReps }
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
