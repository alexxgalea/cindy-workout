import Foundation

/// What the round-splits chart draws and says: each complete round's time, where it can be split
/// by movement, the round still running when the clock stopped, and the words for whichever bar
/// is selected.
///
/// Pure, like `Comparisons`: no UI types, so the arithmetic and the decisions about what the
/// record can honestly support are testable without a phone. Colour is left to the caller for the
/// same reason; `Versus` says which way a gap went and nothing about how to paint it.
public enum RoundSplits {

    /// A round is these three movements, in this order, and `SplitBook` files them that way.
    private static let cycle = Exercise.allCases

    /// The reps one round asks for in all, which is the denominator under an unfinished round.
    public static let roundTarget: Int = cycle.reduce(0) { $0 + $1.target }

    /// How far a round's movement times may sit from the round's own split before they stop being
    /// believed. `SplitBook` and the round timer both start from the same moment and are read from
    /// the same clock, so a healthy record agrees to within a few milliseconds; a gap of seconds
    /// means one of the two was cut short, and stacking it would draw a bar whose parts disagree
    /// with its height.
    private static let sumToleranceMs: Int64 = 2_000

    /// An unfinished round shorter than this is the athlete still putting the bar away.
    private static let minUnfinishedMs: Int64 = 1_000

    /// One bar.
    ///
    /// - `ms`: the round's time; for an `unfinished` round, the clock time since the last one.
    /// - `sets`: the time of each movement in cycle order, or `nil` when the record cannot say. A
    ///   finished round has all three; an unfinished one has the movements it had already left
    ///   behind, which may be none.
    /// - `byHand`: a rep in one of its sets was tapped in rather than seen.
    /// - `reps`: what had been counted in an `unfinished` round, or `nil` when the record does not
    ///   allow that to be said.
    /// - `atLeast`: `reps` is a floor, because the camera lost the athlete for long enough that
    ///   the score it derives from is a lower bound.
    public struct Bar: Equatable, Sendable {
        public let round: Int
        public let ms: Int64
        public let sets: [Int64]?
        public let byHand: Bool
        public let unfinished: Bool
        public let reps: Int?
        public let atLeast: Bool

        public init(round: Int, ms: Int64, sets: [Int64]?, byHand: Bool = false,
                    unfinished: Bool = false, reps: Int? = nil, atLeast: Bool = false) {
            self.round = round
            self.ms = ms
            self.sets = sets
            self.byHand = byHand
            self.unfinished = unfinished
            self.reps = reps
            self.atLeast = atLeast
        }

        /// `reps` where saying it means something: a floor of zero says nothing, so it is left out.
        public var repsToQuote: Int? {
            guard let reps, !(atLeast && reps == 0) else { return nil }
            return reps
        }
    }

    /// The bars, in round order, with the unfinished round (if any) last.
    public struct Split: Equatable, Sendable {
        public let bars: [Bar]
        public let fastest: Int
        public let averageMs: Int64

        public var finished: [Bar] { bars.filter { !$0.unfinished } }
        public var hasBreakdown: Bool { bars.contains { !$0.unfinished && $0.sets != nil } }
        public var hasUnfinished: Bool { bars.last?.unfinished == true }
    }

    /// Which way a gap to the comparison went. `faster` is `nil` when the two are level.
    public struct Versus: Equatable, Sendable {
        public let text: String
        public let faster: Bool?
    }

    public struct Readout: Equatable, Sendable {
        public let title: String
        public let detail: String
        public let versus: Versus?

        /// One sentence for a screen reader, which reads the row as a unit.
        public func spoken() -> String {
            [title, detail, versus?.text].compactMap { $0 }.joined(separator: ". ")
        }
    }

    /// `nil` when the attempt has no complete round to chart.
    public static func of(_ a: Attempt) -> Split? {
        let splits = a.roundSplitsMs
        if splits.isEmpty { return nil }

        var bars: [Bar] = splits.enumerated().map { i, ms in
            let sets = breakdown(a, i, ms)
            return Bar(round: i + 1, ms: ms, sets: sets,
                       byHand: sets != nil && a.setSplits[(i * 3)..<(i * 3 + 3)].contains { $0.manualReps > 0 })
        }
        if let open = unfinished(a) { bars.append(open) }

        return Split(bars: bars, fastest: splits.firstIndex(of: splits.min()!)!,
                     averageMs: splits.reduce(0, +) / Int64(splits.count))
    }

    /// Round `i`'s three movement times, or `nil` when they cannot be trusted.
    ///
    /// Positional: round `i` is sets `3i` to `3i + 2`, which holds only while the list is the
    /// unbroken cycle `SplitBook` writes. A list cut short or reordered shifts every later round
    /// onto the wrong movement, and each of those then fails the order check on its own, so no
    /// round needs to know about the others. A round that skipped a movement still has its set:
    /// skip files it at the reps it reached, so the order is intact and only its reps are short.
    private static func breakdown(_ a: Attempt, _ i: Int, _ roundMs: Int64) -> [Int64]? {
        if i * 3 + 3 > a.setSplits.count { return nil }
        let sets = a.setSplits[(i * 3)..<(i * 3 + 3)]
        if sets.map({ $0.movement }) != cycle { return nil }
        let times = sets.map { $0.ms }
        let off = times.reduce(0, +) - roundMs
        return (off < 0 ? -off : off) <= sumToleranceMs ? times : nil
    }

    /// The round the clock stopped in, if it had run for long enough to be one.
    ///
    /// Its time is whatever the round splits did not account for, both read from the workout
    /// clock. Its reps come from `StravaSets`, which already knows how to put the movement still
    /// running back in and refuses a record that does not add up; that nil is honoured here as
    /// "reps unknown" rather than replaced with a figure worked out from the round count.
    private static func unfinished(_ a: Attempt) -> Bar? {
        let done = a.roundSplitsMs.count
        let trailing = a.durationMs - a.roundSplitsMs.reduce(0, +)
        if trailing < minUnfinishedMs { return nil }

        let left = Array(a.setSplits.dropFirst(done * 3))
        let inOrder = left.count < cycle.count && left.indices.allSatisfy { left[$0].movement == cycle[$0] }
        let sets: [Int64]? = inOrder && a.setSplits.count >= done * 3 ? left.map { $0.ms } : nil

        // The set list is positional, so it speaks for this round only when the finished rounds
        // account for exactly the sets before it.
        var reps: Int?
        if let all = StravaSets.from(a), a.setSplits.count / 3 == done {
            reps = all.filter { $0.round == done + 1 }.reduce(0) { $0 + $1.reps }
        }
        return Bar(round: done + 1, ms: trailing, sets: sets, byHand: inOrder && left.contains { $0.manualReps > 0 },
                   unfinished: true, reps: reps, atLeast: reps != nil && a.scoreIsLowerBound)
    }

    /// The comparison's split at each bar's round, `nil` where it has none (or the bar is open).
    public static func reference(_ split: Split, _ reference: Attempt?) -> [Int64?] {
        split.bars.map { bar in
            if bar.unfinished { return nil }
            guard let splits = reference?.roundSplitsMs, splits.indices.contains(bar.round - 1)
            else { return nil }
            return splits[bar.round - 1]
        }
    }

    /// The three movements' names for this athlete: their own variant's plural where they changed
    /// it, the plain name where they did not, so a knee push-up session never reads "push-ups".
    public static func movementNames(_ profile: CindyProfile?) -> [String] {
        cycle.map { movement in
            let plain = movement.label.lowercased()
            guard let profile else { return plain }
            let standard = CindyProfile.standard
            switch movement {
            case .pullup: return profile.pull != standard.pull ? profile.pull.plural : plain
            case .pushup: return profile.push != standard.push ? profile.push.plural : plain
            case .squat: return profile.squat != standard.squat ? profile.squat.plural : plain
            }
        }
    }

    /// The words for `selected` (`nil` for none), against `reference` where it has a split at the
    /// same round.
    ///
    /// `kind` says which comparison `reference` is, since "your best's round 5" and "round 5 last
    /// time" are not the same sentence with a different noun.
    public static func readout(
        _ a: Attempt, _ split: Split, selected: Int?, reference: Attempt?, kind: Comparisons.Kind?
    ) -> Readout {
        guard let selected, split.bars.indices.contains(selected) else { return idle(split) }
        let bar = split.bars[selected]
        let names = movementNames(a.profile)

        if bar.unfinished {
            let title = "Round \(bar.round) · \(formatDuration(bar.ms)) so far"
            var parts: [String] = []
            if let reps = bar.repsToQuote {
                parts.append("\(bar.atLeast ? "at least " : "")\(reps) of \(roundTarget) reps")
            }
            parts.append("not a finished round")
            let detail = [parts.joined(separator: " · "), timedSets(names, bar.sets), handNote(bar)]
                .compactMap { $0 }.joined(separator: ". ")
            return Readout(title: title, detail: detail, versus: nil)
        }

        let title = "Round \(bar.round) · \(formatDuration(bar.ms))"
        let timed = timedSets(names, bar.sets) ?? "No per-movement times for this round"
        let detail = bar.byHand ? "\(timed). \(handNote(bar)!)" : timed
        let splits = reference?.roundSplitsMs ?? []
        let ref: Int64? = splits.indices.contains(bar.round - 1) ? splits[bar.round - 1] : nil
        let against: Versus? = (ref == nil || kind == nil) ? nil : versus(bar, ref!, kind!)
        return Readout(title: title, detail: detail, versus: against)
    }

    /// What the row says before anything is chosen.
    private static func idle(_ split: Split) -> Readout {
        let fastest = split.bars[split.fastest]
        var title = "Fastest: round \(fastest.round) at \(formatDuration(fastest.ms))"
        if split.finished.count > 1 { title += " · average \(formatDuration(split.averageMs))" }
        return Readout(title: title,
                       detail: "Tap or drag across the bars to see where each round's time went.",
                       versus: nil)
    }

    /// "Pull-ups 0:41 · push-ups 0:52 · squats 1:15", or just what a round had reached.
    private static func timedSets(_ names: [String], _ sets: [Int64]?) -> String? {
        guard let sets, !sets.isEmpty else { return nil }
        let text = sets.enumerated().map { "\(names[$0.offset]) \(formatDuration($0.element))" }
            .joined(separator: " · ")
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    private static func handNote(_ bar: Bar) -> String? {
        bar.byHand ? "Some reps in this round were added by hand" : nil
    }

    private static func versus(_ bar: Bar, _ referenceMs: Int64, _ kind: Comparisons.Kind) -> Versus {
        let gapMs = referenceMs - bar.ms
        let seconds = Int64((Double(gapMs < 0 ? -gapMs : gapMs) / 1000.0).rounded(.toNearestOrAwayFromZero))
        let against: String
        switch kind {
        case .best: against = "your best's round \(bar.round)"
        case .last: against = "round \(bar.round) last time"
        }
        if seconds == 0 { return Versus(text: "Level with \(against)", faster: nil) }
        let gap = seconds < 60 ? "\(seconds) s" : formatDuration(seconds * 1000)
        let faster = gapMs > 0
        return Versus(text: "\(gap) \(faster ? "faster" : "slower") than \(against)", faster: faster)
    }
}
