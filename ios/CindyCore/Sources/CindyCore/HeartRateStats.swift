import Foundation

/// The five bands of effort, by share of the athlete's maximum heart rate.
public enum HeartZone: Int, CaseIterable, Sendable {
    case warmUp, easy, aerobic, threshold, maximum

    public var label: String {
        switch self {
        case .warmUp: return "Warm-up"
        case .easy: return "Easy"
        case .aerobic: return "Aerobic"
        case .threshold: return "Threshold"
        case .maximum: return "Maximum"
        }
    }

    /// The share of the maximum this zone starts at, in tenths.
    var fromTenths: Int {
        switch self {
        case .warmUp: return 0
        case .easy: return 6
        case .aerobic: return 7
        case .threshold: return 8
        case .maximum: return 9
        }
    }

    /// "Z3", for where a figure is too tight for the name.
    public var short: String { "Z\(rawValue + 1)" }
}

/// Time spent in one `zone`, and the beats per minute it spans. `toBpm` is nil for the top zone.
public struct ZoneTime: Equatable, Sendable {
    public let zone: HeartZone
    public let ms: Int64
    public let fromBpm: Int?
    public let toBpm: Int?

    public init(zone: HeartZone, ms: Int64, fromBpm: Int?, toBpm: Int?) {
        self.zone = zone
        self.ms = ms
        self.fromBpm = fromBpm
        self.toBpm = toBpm
    }
}

/// The round with the highest time-weighted average heart rate, and how much of it the watch saw.
public struct HardestRound: Equatable, Sendable {
    public let number: Int
    public let avgBpm: Int
    public let coveredMs: Int64

    public init(number: Int, avgBpm: Int, coveredMs: Int64) {
        self.number = number
        self.avgBpm = avgBpm
        self.coveredMs = coveredMs
    }
}

/// What a session's heart rate says, drawn from `HeartRateStats.of`.
///
/// `zones`, `estimatedMaxBpm` and `verdict` are nil together: all three need an age, which exists
/// only once the athlete has set their heart-rate details.
public struct HeartRateSummary: Equatable, Sendable {
    public let avgBpm: Int
    public let maxBpm: Int
    /// Workout-clock ms a reading covered.
    public let coveredMs: Int64
    public let durationMs: Int64
    public let estimatedMaxBpm: Int?
    public let zones: [ZoneTime]?
    public let hardestRound: HardestRound?
    public let verdict: String?

    public init(avgBpm: Int, maxBpm: Int, coveredMs: Int64, durationMs: Int64, estimatedMaxBpm: Int?,
                zones: [ZoneTime]?, hardestRound: HardestRound?, verdict: String?) {
        self.avgBpm = avgBpm
        self.maxBpm = maxBpm
        self.coveredMs = coveredMs
        self.durationMs = durationMs
        self.estimatedMaxBpm = estimatedMaxBpm
        self.zones = zones
        self.hardestRound = hardestRound
        self.verdict = verdict
    }
}

/// Average, maximum, zones and the hardest round of one session's heart rate.
///
/// Coverage is `Calories`' own rule, shared so the card and the calorie estimate cannot disagree
/// about how much of the workout the watch saw: a usable reading holds until the next one, for at
/// most `Calories.maxHoldMs`, and never past the end of the clock. Time no reading holds is not
/// averaged in as zero or as the last reading carried on; it is simply not counted, which is why
/// the card says how much of the session it covers.
///
/// Zones are a share of an *estimated* maximum, not a measured one, so everything that needs it
/// hangs off the age: no age, no zones, and nothing here guesses one. Port of `HeartRateStats`.
public enum HeartRateStats {

    /// A round the watch saw for less than this says too little to be called the hardest.
    public static let minRoundCoveredMs: Int64 = 30_000

    /// Tanaka et al. (2001): `208 - 0.7 x age`, rounded.
    public static func estimatedMax(_ age: Int) -> Int {
        Int(JavaText.roundToLong(208.0 - 0.7 * Double(age)))
    }

    /// The zone `bpm` falls in against `maxBpm`; integer arithmetic, so 90% is exactly 90%.
    public static func zoneOf(_ bpm: Int, _ maxBpm: Int) -> HeartZone {
        var zone = HeartZone.warmUp
        for z in HeartZone.allCases where bpm * 10 >= z.fromTenths * maxBpm { zone = z }
        return zone
    }

    /// The lowest whole bpm in `zone`: the first one at or past its share of `maxBpm`.
    private static func lowerBound(_ zone: HeartZone, _ maxBpm: Int) -> Int {
        (zone.fromTenths * maxBpm + 9) / 10
    }

    /// One reading and the stretch of the clock it holds for.
    private struct Held {
        let startMs: Int64
        let endMs: Int64
        let bpm: Int
    }

    private static func held(_ trace: HeartRateTrace?, _ durationMs: Int64) -> [Held] {
        if durationMs <= 0 { return [] }
        let usable = JavaText.sortedStably((trace?.samples ?? []).filter {
            (HeartRateMeasurement.minBpm...HeartRateMeasurement.maxBpm).contains($0.bpm)
                && $0.clockMs >= 0 && $0.clockMs < durationMs
        }, by: { $0.clockMs })
        var out: [Held] = []
        for i in usable.indices {
            let at = usable[i].clockMs
            let next = i + 1 < usable.count ? usable[i + 1].clockMs : Int64.max
            let end = min(next, at + Calories.maxHoldMs, durationMs)
            if end > at { out.append(Held(startMs: at, endMs: end, bpm: usable[i].bpm)) }
        }
        return out
    }

    /// Nil when no reading covers any of the clock. `rounds` are the finished rounds' spans; an
    /// unfinished last round is left out by the caller, since a part-round is not one to name the
    /// hardest. `age` nil means no zones.
    public static func of(_ trace: HeartRateTrace?, durationMs: Int64, rounds: [RoundSpan], age: Int?) -> HeartRateSummary? {
        let held = held(trace, durationMs)
        if held.isEmpty { return nil }

        var covered: Int64 = 0
        var weighted = 0.0
        var max = 0
        for h in held {
            let ms = h.endMs - h.startMs
            covered += ms
            weighted += Double(h.bpm) * Double(ms)
            if h.bpm > max { max = h.bpm }
        }

        let maxBpm = age.map { Self.estimatedMax($0) }.flatMap { $0 > 0 ? $0 : nil }
        let zones = maxBpm.map { zonesOf(held, $0) }

        return HeartRateSummary(
            avgBpm: Int(JavaText.roundToLong(weighted / Double(covered))),
            maxBpm: max,
            coveredMs: covered,
            durationMs: durationMs,
            estimatedMaxBpm: maxBpm,
            zones: zones,
            hardestRound: hardestRound(held, rounds),
            verdict: zones.map { verdict($0, covered) })
    }

    private static func zonesOf(_ held: [Held], _ maxBpm: Int) -> [ZoneTime] {
        var ms = [Int64](repeating: 0, count: HeartZone.allCases.count)
        for h in held { ms[zoneOf(h.bpm, maxBpm).rawValue] += h.endMs - h.startMs }
        return HeartZone.allCases.map { z in
            let next = z.rawValue + 1 < HeartZone.allCases.count ? HeartZone.allCases[z.rawValue + 1] : nil
            return ZoneTime(zone: z, ms: ms[z.rawValue],
                            fromBpm: z == .warmUp ? nil : lowerBound(z, maxBpm),
                            toBpm: next.map { lowerBound($0, maxBpm) - 1 })
        }
    }

    /// Ties go to the earlier round; the first to be that hard is the one that was.
    private static func hardestRound(_ held: [Held], _ rounds: [RoundSpan]) -> HardestRound? {
        var best: HardestRound?
        var bestAvg = 0.0
        for r in rounds {
            var covered: Int64 = 0
            var weighted = 0.0
            for h in held {
                let ms = min(h.endMs, r.endMs) - max(h.startMs, r.startMs)
                if ms <= 0 { continue }
                covered += ms
                weighted += Double(h.bpm) * Double(ms)
            }
            if covered < minRoundCoveredMs { continue }
            let avg = weighted / Double(covered)
            if best == nil || avg > bestAvg {
                bestAvg = avg
                best = HardestRound(number: r.number, avgBpm: Int(JavaText.roundToLong(avg)), coveredMs: covered)
            }
        }
        return best
    }

    /// A tie goes to the harder zone: the athlete worked at least that hard for as long.
    private static func verdict(_ zones: [ZoneTime], _ coveredMs: Int64) -> String {
        var top = zones[zones.count - 1]
        for z in zones.reversed() where z.ms > top.ms { top = z }
        return "Longest in \(top.zone.short) \(top.zone.label): "
            + "\(formatDuration(top.ms)) of the \(formatDuration(coveredMs)) your watch covered."
    }
}
