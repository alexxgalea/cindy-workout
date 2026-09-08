import Foundation

/// Training levels, ranked by rounds completed in the 20-minute AMRAP.
///
/// PROVISIONAL. Finishing a full Cindy is pitched as `.intermediate` per the brief, with the
/// scaled tiers below it and the benchmark at the top. The whole ladder is this one table, so
/// retuning it is a matter of editing numbers rather than logic.
///
/// Rounds are the right axis even though the brief talks about time: in a fixed 20-minute AMRAP,
/// average round time and rounds completed are the same measurement read two ways.
public enum Level: Int, CaseIterable, Sendable {
    case firstSteps, novice, intermediate, advanced, elite, legend

    public var title: String {
        switch self {
        case .firstSteps: return "First Steps"
        case .novice: return "Novice"
        case .intermediate: return "Intermediate"
        case .advanced: return "Advanced"
        case .elite: return "Elite"
        case .legend: return "Legend"
        }
    }

    public var minRounds: Int {
        switch self {
        case .firstSteps: return 0
        case .novice: return 5
        case .intermediate: return 10
        case .advanced: return 16
        case .elite: return 21
        case .legend: return 27
        }
    }

    public var blurb: String {
        switch self {
        case .firstSteps: return "Moving. Everything starts here."
        case .novice: return "Through the workout, finding a pace."
        case .intermediate: return "A complete Cindy. The benchmark most people train toward."
        case .advanced: return "Sustained pace under real fatigue."
        case .elite: return "Unbroken sets deep into the clock."
        case .legend: return "Level with \(Records.benchmarkName)."
        }
    }

    /// The level a score of `rounds` earns.
    public static func of(_ rounds: Int) -> Level {
        allCases.last { rounds >= $0.minRounds } ?? .firstSteps
    }

    /// The next level up, or nil at the top of the ladder.
    public static func next(after level: Level) -> Level? {
        Level(rawValue: level.rawValue + 1)
    }

    /// Rounds still needed to rank up, or nil if there is nothing above.
    public static func roundsToNext(_ rounds: Int) -> Int? {
        guard let next = next(after: of(rounds)) else { return nil }
        return max(0, next.minRounds - rounds)
    }

    /// Progress through the current level, 0...1, for a progress bar.
    public static func progress(_ rounds: Int) -> Float {
        let level = of(rounds)
        guard let next = next(after: level) else { return 1 }
        let span = Float(next.minRounds - level.minRounds)
        guard span > 0 else { return 1 }
        return max(0, min(1, Float(rounds - level.minRounds) / span))
    }
}
