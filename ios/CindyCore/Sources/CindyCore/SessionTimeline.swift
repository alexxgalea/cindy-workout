import Foundation

/// The reps banked by `clockMs` on the workout clock, and how many of those the athlete tapped in
/// rather than the camera seeing.
public struct RepPoint: Equatable, Sendable {
    public let clockMs: Int64
    public let reps: Int
    public let manualReps: Int

    public init(_ clockMs: Int64, _ reps: Int, _ manualReps: Int) {
        self.clockMs = clockMs
        self.reps = reps
        self.manualReps = manualReps
    }
}

/// A session's cumulative reps over its clock, from the origin to the last rep.
///
/// `exact` says where the points came from. True: one per rep, from the marks the workout itself
/// filed. False: one per finished set, from `Attempt.setSplits`, for a session recorded before rep
/// times existed; the chart then joins sets, and says so, rather than inventing reps between them.
public struct RepSeries: Equatable, Sendable {
    public let points: [RepPoint]
    public let exact: Bool

    public init(_ points: [RepPoint], exact: Bool) {
        self.points = points
        self.exact = exact
    }

    /// What had been banked at `clockMs`: the last point at or before it, so always a value that
    /// really was banked. In per-set mode that is the last finished set, never a position between
    /// two of them.
    public func at(_ clockMs: Int64) -> RepPoint {
        var lo = 0
        var hi = points.count
        while lo < hi {
            let mid = (lo + hi) >> 1
            if points[mid].clockMs <= clockMs { lo = mid + 1 } else { hi = mid }
        }
        return points[max(lo - 1, 0)]
    }
}

/// One movement block on the clock; `inProgress` when the clock stopped before it was finished.
public struct SetSpan: Equatable, Sendable {
    public let startMs: Int64
    public let endMs: Int64
    public let movement: Exercise
    public let round: Int
    public let inProgress: Bool

    public init(startMs: Int64, endMs: Int64, movement: Exercise, round: Int, inProgress: Bool) {
        self.startMs = startMs
        self.endMs = endMs
        self.movement = movement
        self.round = round
        self.inProgress = inProgress
    }
}

/// One round on the clock; `complete` is false only for the one still running when it stopped.
public struct RoundSpan: Equatable, Sendable {
    public let number: Int
    public let startMs: Int64
    public let endMs: Int64
    public let complete: Bool

    public init(number: Int, startMs: Int64, endMs: Int64, complete: Bool) {
        self.number = number
        self.startMs = startMs
        self.endMs = endMs
        self.complete = complete
    }
}

/// What the session is measured against, built from the reference attempt's own record.
public struct ReferenceTimeline: Equatable, Sendable {
    public let kind: Comparisons.Kind
    public let reps: RepSeries?
    public let roundEnds: [Int64]

    public init(kind: Comparisons.Kind, reps: RepSeries?, roundEnds: [Int64]) {
        self.kind = kind
        self.reps = reps
        self.roundEnds = roundEnds
    }

    /// How the reference is named in a sentence: "your best", "last time".
    public var phrase: String { kind == .best ? "your best" : "last time" }
}

/// Everything the timeline knows about one instant of the clock.
public struct Moment: Equatable, Sendable {
    public let clockMs: Int64
    /// The round in progress, which is the one just finished at the instant it finishes.
    public let round: Int?
    public let movement: Exercise?
    public let reps: Int?
    public let manualReps: Int
    public let bpm: Int?
    /// The latest round both sessions had finished by `clockMs`.
    public let aheadRound: Int?
    /// That round's end in the reference minus its end here: positive is ahead, or faster.
    public let aheadMs: Int64?
    /// Estimated kilocalories burned by `clockMs`, or nil with no calorie line.
    public let kcal: Int?
    /// True when `kcal` includes stretches estimated from the reps, so it is a floor on a
    /// lower-bound score.
    public let kcalFromReps: Bool

    public init(clockMs: Int64, round: Int?, movement: Exercise?, reps: Int?, manualReps: Int, bpm: Int?,
                aheadRound: Int?, aheadMs: Int64?, kcal: Int? = nil, kcalFromReps: Bool = false) {
        self.clockMs = clockMs
        self.round = round
        self.movement = movement
        self.reps = reps
        self.manualReps = manualReps
        self.bpm = bpm
        self.aheadRound = aheadRound
        self.aheadMs = aheadMs
        self.kcal = kcal
        self.kcalFromReps = kcalFromReps
    }
}

/// One stretch of the calorie line that is all one kind: measured by a heart rate, or estimated
/// from the work rate. Runs share their boundary point, so drawn one after another they read as a
/// single line that changes style where its source changes.
public struct CalorieRun: Equatable, Sendable {
    public let points: [CaloriePoint]
    public let estimated: Bool

    public init(_ points: [CaloriePoint], estimated: Bool) {
        self.points = points
        self.estimated = estimated
    }
}

/// The two lines above the chart; `detail` is nil when there is nothing to add to `title`.
/// (Kotlin's `Readout`; renamed here because P8's progress `Readout` already holds that name.)
public struct TimelineReadout: Equatable, Sendable {
    public let title: String
    public let detail: String?

    public init(_ title: String, _ detail: String?) {
        self.title = title
        self.detail = detail
    }
}

/// A session laid out on its own clock: reps banked, heart rate, round ends, and the same for the
/// session it is being measured against. Pure, like `Comparisons`, so every number the chart and
/// its readout claim can be tested without a phone.
///
/// Each series says how far it can be trusted. Rep marks are used only when `RepTimes.validFor`
/// accepts them *for the attempt they were filed with*: the reviewed session and the reference are
/// checked separately, because one can have a file and the other, recorded earlier, none. Otherwise
/// the line falls back to the set splits, and failing that there is no line at all rather than one
/// drawn from `rounds * 30`. Nothing is ever interpolated between two banked values: a rep count at
/// an instant is the last one that was actually banked. Port of `SessionTimeline.kt`.
public final class SessionTimeline {
    private let attempt: Attempt
    public let reps: RepSeries?
    public let roundEnds: [Int64]
    public let sets: [SetSpan]
    public let rounds: [RoundSpan]
    /// Heart-rate samples, broken wherever the watch went quiet for longer than it could be held.
    public let heartRuns: [[HeartRateSample]]
    public let reference: ReferenceTimeline?
    /// Cumulative estimated kilocalories, from `Calories.timeline`; empty without a body weight.
    /// An estimate throughout, which is why every place it is worded says so.
    public let calories: [CaloriePoint]

    /// `calories` cut into stretches of one kind each, in clock order; empty for no line.
    public let calorieRuns: [CalorieRun]

    private let heart: [HeartRateSample]

    private init(attempt: Attempt, reps: RepSeries?, roundEnds: [Int64], sets: [SetSpan], rounds: [RoundSpan],
                 heartRuns: [[HeartRateSample]], reference: ReferenceTimeline?, calories: [CaloriePoint]) {
        self.attempt = attempt
        self.reps = reps
        self.roundEnds = roundEnds
        self.sets = sets
        self.rounds = rounds
        self.heartRuns = heartRuns
        self.reference = reference
        self.calories = calories
        self.heart = heartRuns.flatMap { $0 }
        self.calorieRuns = Self.calorieRuns(calories)
    }

    public var durationMs: Int64 { attempt.durationMs }

    /// There is something to draw: reps, or a heart rate.
    public var hasData: Bool { durationMs > 0 && (reps != nil || !heartRuns.isEmpty) }

    /// Kilocalories at `clockMs`, by the straight line between the two points either side: each
    /// stretch was built from one rate held across it, so a line between its ends is the estimate
    /// itself rather than a smoothing of it. Nil with no calorie line.
    private func kcalAt(_ clockMs: Int64) -> Double? {
        if calories.isEmpty { return nil }
        guard let i = calories.firstIndex(where: { $0.clockMs >= clockMs }) else { return calories[calories.count - 1].kcal }
        if i == 0 { return calories[0].kcal }
        let a = calories[i - 1]
        let b = calories[i]
        return a.kcal + (b.kcal - a.kcal) * Double(clockMs - a.clockMs) / Double(b.clockMs - a.clockMs)
    }

    /// Whether any stretch before `clockMs` was estimated from the reps rather than a heart rate.
    private func repsEstimatedBy(_ clockMs: Int64) -> Bool {
        var i = 1
        while i < calories.count {
            if calories[i - 1].clockMs >= clockMs { break }
            if !calories[i].fromHeartRate { return true }
            i += 1
        }
        return false
    }

    /// "at least 84 kcal (est.)" or "84 kcal (est.)"; `spoken` writes it for VoiceOver, which would
    /// otherwise read "kcal" as a word. "At least" when the score is a lower bound and any of the
    /// figure comes from the reps: missing reps can only have lowered that part.
    private func kcalPhrase(_ kcal: Int, _ fromReps: Bool, spoken: Bool = false) -> String {
        let floor = attempt.scoreIsLowerBound && fromReps ? "at least " : ""
        return spoken ? "\(floor)\(kcal) kilocalories, estimated" : "\(floor)\(kcal) kcal (est.)"
    }

    /// The latest sample no more than `Calories.maxHoldMs` before `clockMs`; none otherwise.
    private func bpmAt(_ clockMs: Int64) -> Int? {
        guard let i = heart.lastIndex(where: { $0.clockMs <= clockMs }) else { return nil }
        let s = heart[i]
        return clockMs - s.clockMs <= Calories.maxHoldMs ? s.bpm : nil
    }

    /// Round `round`'s end in the reference minus its end here, when both sessions finished it.
    /// Two exact clock times, never a position between them.
    public func aheadOfReference(_ round: Int) -> Int64? {
        guard let ends = reference?.roundEnds, round - 1 >= 0, round - 1 < ends.count,
              round - 1 < roundEnds.count else { return nil }
        return ends[round - 1] - roundEnds[round - 1]
    }

    public func at(_ clockMs: Int64) -> Moment {
        let t = min(max(clockMs, 0), durationMs)
        // A round is still "in progress" at the instant it ends, so that the stop for a round and
        // the cursor sitting on its end agree about which round it is.
        let round: Int? = rounds.isEmpty ? nil : min(roundEnds.filter { $0 < t }.count + 1, rounds.count)
        let movement = sets.first(where: { t <= $0.endMs })?.movement ?? sets.last?.movement
        let point = reps?.at(t)
        let finishedHere = roundEnds.filter { $0 <= t }.count
        let finishedThere = reference?.roundEnds.filter { $0 <= t }.count ?? 0
        let common = min(finishedHere, finishedThere)
        let ahead = common >= 1 ? aheadOfReference(common) : nil
        let kcal = kcalAt(t)
        return Moment(
            clockMs: t,
            round: round,
            movement: movement,
            reps: point?.reps,
            manualReps: point?.manualReps ?? 0,
            bpm: bpmAt(t),
            aheadRound: ahead != nil ? common : nil,
            aheadMs: ahead,
            kcal: kcal.map { JavaText.roundToInt($0) },
            kcalFromReps: kcal != nil && repsEstimatedBy(t))
    }

    /// The mean of the samples inside `startMs...endMs`, or nil when the watch said nothing.
    public func averageBpm(_ startMs: Int64, _ endMs: Int64) -> Int? {
        let inside = heart.filter { $0.clockMs >= startMs && $0.clockMs <= endMs }
        if inside.isEmpty { return nil }
        let sum = inside.reduce(0) { $0 + $1.bpm }
        return Int(JavaText.roundToLong(Double(sum) / Double(inside.count)))
    }

    private var manualInSession: Bool { (reps?.points.last?.manualReps ?? 0) > 0 }

    private func repsPhrase(_ count: Int, _ manual: Int) -> String {
        let base = "\(attempt.scoreIsLowerBound ? "at least " : "")\(count) rep\(count == 1 ? "" : "s")"
        return manual > 0 ? "\(base), \(manual) by hand" : base
    }

    private func movementName(_ m: Exercise) -> String {
        let standard = CindyProfile.standard
        // The profile's own plural names what was actually done; the plain movement name is only
        // right when that is what the athlete did, and for a record whose movements this build
        // does not know (a nil profile) it is the only name there is.
        let plural: String
        if let profile = attempt.profile {
            switch m {
            case .pullup: plural = profile.pull == standard.pull ? m.label : profile.pull.plural
            case .pushup: plural = profile.push == standard.push ? m.label : profile.push.plural
            case .squat: plural = profile.squat == standard.squat ? m.label : profile.squat.plural
            }
        } else {
            plural = m.label
        }
        return Self.capitalised(plural)
    }

    /// Kotlin's `lowercase(Locale.US).replaceFirstChar { it.uppercase(Locale.US) }`, on the first
    /// UTF-16 unit, which for every name this app has is one letter.
    private static func capitalised(_ text: String) -> String {
        let lower = text.lowercased()
        guard let first = lower.unicodeScalars.first else { return lower }
        return String(first).uppercased() + String(String.UnicodeScalarView(lower.unicodeScalars.dropFirst()))
    }

    private func aheadPhrase(_ ms: Int64, spoken: Bool) -> String {
        guard let name = reference?.phrase else { return "" }
        let seconds = JavaText.roundToLong(Double(ms) / 1000.0)
        let amount = spoken ? Self.spokenSeconds(abs(seconds)) : Self.shortSeconds(abs(seconds))
        if seconds > 0 { return "\(amount) ahead of \(name)" }
        if seconds < 0 { return "\(amount) behind \(name)" }
        return "level with \(name)"
    }

    /// Nothing selected: the whole session in a line, "20:00 · 7 rounds + 12".
    public func idleReadout() -> TimelineReadout {
        let r = attempt.rounds
        let rounds = "\(r) round\(r == 1 ? "" : "s")"
        let loose = attempt.reps > 0 ? " + \(attempt.reps)" : ""
        return TimelineReadout("\(formatDuration(durationMs)) · \(rounds)\(loose)", nil)
    }

    /// "12:34 · Round 6 · Push-ups" over "171 reps · 158 bpm · round 5: 38 s ahead of your best".
    public func readout(_ m: Moment) -> TimelineReadout {
        var title = [formatDuration(m.clockMs)]
        if let round = m.round { title.append("Round \(round)") }
        if let movement = m.movement { title.append(movementName(movement)) }
        var parts: [String] = []
        if let reps = m.reps { parts.append(repsPhrase(reps, m.manualReps)) }
        if let bpm = m.bpm { parts.append("\(bpm) bpm") }
        if let kcal = m.kcal { parts.append(kcalPhrase(kcal, m.kcalFromReps)) }
        if let ahead = m.aheadMs {
            parts.append("round \(m.aheadRound!): \(aheadPhrase(ahead, spoken: false))")
        }
        let detail = parts.joined(separator: " · ")
        return TimelineReadout(title.joined(separator: " · "), detail.isEmpty ? nil : detail)
    }

    /// What VoiceOver reads for one round: when it ran, how long it took, what had been banked by
    /// its end, its heart rate and how it went against the reference.
    public func describeRound(_ round: RoundSpan) -> String {
        var parts: [String] = []
        parts.append("Round \(round.number)")
        if round.complete {
            parts.append("\(formatDuration(round.startMs)) to \(formatDuration(round.endMs))")
        } else {
            parts.append("in progress, \(formatDuration(round.startMs)) to the end at \(formatDuration(round.endMs))")
        }
        if round.complete { parts.append(Self.spokenDuration(round.endMs - round.startMs)) }
        if let p = reps?.at(round.endMs) {
            parts.append("\(repsPhrase(p.reps, p.manualReps)) by \(round.complete ? "its" : "the") end")
        }
        if let avg = averageBpm(round.startMs, round.endMs) {
            parts.append("\(avg) beats per minute on average")
        }
        if let k = kcalAt(round.endMs) {
            parts.append("\(kcalPhrase(JavaText.roundToInt(k), repsEstimatedBy(round.endMs), spoken: true)), "
                + "by \(round.complete ? "its" : "the") end")
        }
        if round.complete, let ahead = aheadOfReference(round.number) {
            parts.append(aheadPhrase(ahead, spoken: true))
        }
        return parts.joined(separator: ", ")
    }

    /// One line saying what the dashed line is, and anything about how the reps are plotted that a
    /// reader would otherwise take for more precision than there is. Nil when there is nothing to say.
    public func legend() -> String? {
        var parts: [String] = []
        let ref = reference
        if ref?.reps != nil { parts.append("Dashed: \(ref!.phrase).") }
        let mine = reps != nil && !reps!.exact
        let theirs = ref?.reps != nil && !ref!.reps!.exact
        if mine && theirs { parts.append("Reps are plotted per set for both sessions.") }
        else if mine { parts.append("Reps are plotted per set for this session.") }
        else if theirs { parts.append("Reps are plotted per set for \(ref!.phrase).") }
        if manualInSession { parts.append("Reps added by hand count, but the camera did not see them.") }
        if let c = calorieLegend() { parts.append(c) }
        let text = parts.joined(separator: " ")
        return text.isEmpty ? nil : text
    }

    /// What the calorie line is, and what its dashes mean on that lane, where they are not the
    /// reference's. Without a body weight there is no line and nothing to say.
    private func calorieLegend() -> String? {
        if calorieRuns.isEmpty { return nil }
        let fromReps = calorieRuns.contains { $0.estimated }
        let lowerBound = attempt.scoreIsLowerBound ? ", and since some reps may be missing, those read as at least" : ""
        let what: String
        if !fromReps {
            what = "KCAL is an estimate from your heart rate"
        } else if calorieRuns.contains(where: { !$0.estimated }) {
            what = "KCAL is an estimate; its dashed stretches come from your reps, not your heart rate\(lowerBound)"
        } else {
            what = "KCAL is an estimate from your reps\(lowerBound)"
        }
        // The method is written once, on the row that totals it, and pointed at from here.
        return "\(what). The Calories (est.) row below says how."
    }

    // MARK: building

    /// Cuts `points` into runs by whether the stretch ending at each point was measured. Two
    /// neighbouring stretches of one kind are one run, and a run starts at the point the previous
    /// one ended on, so the line has no break where its style changes.
    static func calorieRuns(_ points: [CaloriePoint]) -> [CalorieRun] {
        if points.count < 2 { return [] }
        var runs: [CalorieRun] = []
        var current = [points[0]]
        var estimated = !points[1].fromHeartRate
        for i in 1..<points.count {
            let p = points[i]
            if !p.fromHeartRate != estimated {
                runs.append(CalorieRun(current, estimated: estimated))
                current = [points[i - 1]]
                estimated = !p.fromHeartRate
            }
            current.append(p)
        }
        runs.append(CalorieRun(current, estimated: estimated))
        return runs
    }

    /// `marks` and `referenceMarks` are whatever `RepTimesStore.load` answered for each attempt,
    /// validated here against the attempt each belongs to. `trace` is the reviewed session's own
    /// heart rate; the reference's is never drawn.
    public static func of(_ attempt: Attempt, marks: [RepMark]?, trace: HeartRateTrace?,
                          reference: Attempt? = nil, referenceKind: Comparisons.Kind? = nil,
                          referenceMarks: [RepMark]? = nil, calories: [CaloriePoint] = []) -> SessionTimeline {
        let ends = roundEnds(attempt)
        let sets = setSpans(attempt)
        var ref: ReferenceTimeline?
        if let reference, let referenceKind {
            ref = ReferenceTimeline(kind: referenceKind, reps: repSeries(reference, referenceMarks),
                                    roundEnds: roundEnds(reference))
        }
        return SessionTimeline(attempt: attempt, reps: repSeries(attempt, marks), roundEnds: ends, sets: sets,
                               rounds: roundSpans(attempt, ends), heartRuns: heartRuns(attempt, trace),
                               reference: ref, calories: calories)
    }

    /// Where each finished round ended on the clock, for plotting no later than the clock itself.
    static func roundEnds(_ a: Attempt) -> [Int64] {
        var sum: Int64 = 0
        return a.roundSplitsMs.map { sum += $0; return min(sum, a.durationMs) }
    }

    static func roundSpans(_ a: Attempt, _ ends: [Int64]) -> [RoundSpan] {
        var out: [RoundSpan] = []
        var start: Int64 = 0
        for (i, end) in ends.enumerated() {
            out.append(RoundSpan(number: i + 1, startMs: start, endMs: end, complete: true))
            start = end
        }
        if a.durationMs > start {
            out.append(RoundSpan(number: ends.count + 1, startMs: start, endMs: a.durationMs, complete: false))
        }
        return out
    }

    static func setSpans(_ a: Attempt) -> [SetSpan] {
        var out: [SetSpan] = []
        var start: Int64 = 0
        for (i, s) in a.setSplits.enumerated() {
            let end = min(start + s.ms, a.durationMs)
            out.append(SetSpan(startMs: start, endMs: end, movement: s.movement, round: i / 3 + 1, inProgress: false))
            start = end
        }
        // The movement still running when the clock stopped never reached an event of its own, so
        // it is not in the splits; it is whichever one follows the last that was. With no splits at
        // all the record predates set times, and which movement it was in is unknown rather than
        // the first.
        if let last = a.setSplits.last, a.durationMs > start {
            out.append(SetSpan(startMs: start, endMs: a.durationMs, movement: last.movement.next,
                               round: a.setSplits.count / 3 + 1, inProgress: true))
        }
        return out
    }

    /// One point per rep when `marks` are this attempt's own, else one per finished set, else nil.
    /// A series with nothing banked in it is nil too: a flat line at zero says less than no chart.
    static func repSeries(_ a: Attempt, _ marks: [RepMark]?) -> RepSeries? {
        if let marks, !marks.isEmpty, RepTimes.validFor(marks, a) {
            var manual = 0
            var points = [RepPoint(0, 0, 0)]
            for (i, m) in marks.enumerated() {
                if m.manual { manual += 1 }
                points.append(RepPoint(min(max(m.clockMs, 0), a.durationMs), i + 1, manual))
            }
            return RepSeries(points, exact: true)
        }
        return setSeries(a)
    }

    private static func setSeries(_ a: Attempt) -> RepSeries? {
        if a.setSplits.isEmpty { return nil }
        let total = a.setSplits.reduce(0) { $0 + $1.reps }
        // More banked in the sets than in the whole session means the record disagrees with itself;
        // a chart built on it would be a guess wearing banked numbers.
        if let counted = a.countedReps, total > counted { return nil }
        let spans = setSpans(a).filter { !$0.inProgress }
        var reps = 0
        var manual = 0
        var points = [RepPoint(0, 0, 0)]
        for (i, span) in spans.enumerated() {
            reps += a.setSplits[i].reps
            manual += a.setSplits[i].manualReps
            points.append(RepPoint(span.endMs, reps, manual))
        }
        // The clock stopping is a banked instant too: the total counted by then.
        if let counted = a.countedReps, counted > reps, a.durationMs > points[points.count - 1].clockMs {
            points.append(RepPoint(a.durationMs, counted, min(a.manualReps, counted)))
        }
        return points[points.count - 1].reps > 0 ? RepSeries(points, exact: false) : nil
    }

    /// The samples inside the workout clock, cut wherever the gap to the next exceeds
    /// `Calories.maxHoldMs`: the same line `Calories` stops holding a reading at, so the chart and
    /// the calorie estimate cannot disagree about when the watch was silent.
    static func heartRuns(_ a: Attempt, _ trace: HeartRateTrace?) -> [[HeartRateSample]] {
        let usable = JavaText.sortedStably((trace?.samples ?? []).filter {
            $0.clockMs >= 0 && $0.clockMs < a.durationMs
                && (HeartRateMeasurement.minBpm...HeartRateMeasurement.maxBpm).contains($0.bpm)
        }, by: { $0.clockMs })
        guard let first = usable.first else { return [] }
        var runs = [[first]]
        for i in 1..<max(usable.count, 1) where i < usable.count {
            if usable[i].clockMs - usable[i - 1].clockMs > Calories.maxHoldMs { runs.append([]) }
            runs[runs.count - 1].append(usable[i])
        }
        return runs
    }

    /// "38 s", "1 min 5 s".
    static func shortSeconds(_ seconds: Int64) -> String {
        seconds < 60 ? "\(seconds) s" : "\(seconds / 60) min \(seconds % 60) s"
    }

    /// "38 seconds", "1 minute 5 seconds", "2 minutes".
    static func spokenSeconds(_ seconds: Int64) -> String {
        let m = seconds / 60
        let s = seconds % 60
        let minutes = "\(m) minute\(m == 1 ? "" : "s")"
        let secs = "\(s) second\(s == 1 ? "" : "s")"
        if m == 0 { return secs }
        if s == 0 { return minutes }
        return "\(minutes) \(secs)"
    }

    static func spokenDuration(_ ms: Int64) -> String { spokenSeconds(JavaText.roundToLong(Double(ms) / 1000.0)) }
}
