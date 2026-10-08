import Foundation

/// An estimate of the energy a Cindy cost.
///
/// The base arithmetic is the standard MET equation, `kcal/min = MET × 3.5 × kg / 200`, which is
/// what every fitness tracker without a heart-rate strap is doing underneath. It needs the
/// athlete's actual body weight, so nothing is shown until they have given one: a guessed weight
/// would produce a confident number that is wrong by however much the guess was.
///
/// The wrinkle is that Cindy is an AMRAP, so twenty minutes buys wildly different amounts of work.
/// Eight rounds and twenty-five rounds are not the same effort, and a flat MET would call them
/// equal. So the MET is scaled by the rate the athlete actually worked at, and clamped at both ends,
/// because neither an idle twenty minutes nor a superhuman one is what the reference value describes.
///
/// Where a watch sent a heart rate, `estimate` replaces the MET for the minutes it covered with the
/// Keytel heart-rate equation, which follows the effort the athlete actually made rather than a
/// table's idea of it. Minutes the watch did not cover stay on the MET model, so a dropped
/// connection costs precision, not the number.
///
/// Treat the output as an estimate with real uncertainty in it either way. Heart rate makes it a
/// better estimate, not a measurement, and the screen says so. Port of `Calories.kt`.
public enum Calories {

    /// Vigorous calisthenics (push-ups, sit-ups, pull-ups) and general circuit training both sit at
    /// 8 METs in the Compendium of Physical Activities. Cindy is exactly that.
    public static let referenceMet = 8.0

    /// The work rate the reference MET is taken to describe: ten rounds inside the twenty minutes,
    /// which is where CrossFit puts a competent unscaled effort.
    public static let referenceRepsPerMinute = 10.0 * 30.0 / 20.0

    /// Twenty minutes of standing near the bar is still not sedentary, but it is not eight METs.
    public static let minMet = 5.0

    /// Sustaining more than this for twenty minutes is beyond what the compendium describes, so the
    /// estimate stops following the work rate up rather than inventing numbers off the end of the scale.
    public static let maxMet = 14.0

    /// Longest a heart-rate reading is assumed to hold before the time after it counts as uncovered.
    ///
    /// Shared with `HeartRateRecorder`, which needs the same figure for the same reason: a reading a
    /// few seconds old is still a fair stand-in for "now", and one from a while ago is not. One
    /// constant, so the recorder's seeding and the calorie estimate's coverage cannot quietly
    /// disagree about where that line is.
    public static let maxHoldMs: Int64 = 5_000

    /// The effective MET for work done at this rate.
    public static func met(totalReps: Int, activeMs: Int64) -> Double {
        if totalReps <= 0 || activeMs <= 0 { return minMet }
        let minutes = Double(activeMs) / 60_000.0
        if minutes <= 0.0 { return minMet }
        let repsPerMinute = Double(totalReps) / minutes
        let scaled = referenceMet * (repsPerMinute / referenceRepsPerMinute)
        return min(max(scaled, minMet), maxMet)
    }

    /// Kilocalories for `totalReps` done in `activeMs` of clock by an athlete of `bodyWeightKg`, or
    /// nil when there is nothing to base it on.
    ///
    /// `activeMs` is the workout clock and so already excludes paused time: resting with the clock
    /// stopped is not work.
    public static func burned(totalReps: Int, activeMs: Int64, bodyWeightKg: Double) -> Int? {
        if bodyWeightKg <= 0.0 || activeMs <= 0 { return nil }
        let minutes = Double(activeMs) / 60_000.0
        let kcal = met(totalReps: totalReps, activeMs: activeMs) * 3.5 * bodyWeightKg / 200.0 * minutes
        return max(JavaText.roundToInt(kcal), 0)
    }

    /// kJ per kcal, the unit the Keytel equation is published in.
    public static let kjPerKcal = 4.184

    /// Kilocalories per minute from heart rate alone, by the Keytel et al. (2005) equation
    /// (*Prediction of energy expenditure from heart rate monitoring during submaximal exercise*,
    /// J Sports Sci 23(3):289–297), fitted separately for women and men, which is why `body` must
    /// already carry a `Sex`; `.unstated` averages the two rather than guessing between them.
    ///
    /// Below the fit's range the equation undershoots badly: at 60 bpm it falls under resting
    /// metabolism, which a workout obviously is not. The published model has no resting-HR term to
    /// blend towards instead, so this floors at 1 MET (`3.5 × kg / 200`) rather than inventing a new
    /// input to ask for. During Cindy the heart rate sits far above the floor anyway.
    ///
    /// Requires `body.canUseHeartRate`; the caller, `estimate`, is what actually checks it.
    public static func keytelKcalPerMinute(bpm: Int, body: Body) -> Double {
        let w = body.weightKg
        let a = Double(body.age!)
        let b = Double(bpm)
        let male = -55.0969 + 0.6309 * b + 0.1988 * w + 0.2017 * a
        let female = -20.4022 + 0.4472 * b - 0.1263 * w + 0.074 * a
        let kJPerMinute: Double
        switch body.sex! {
        case .male: kJPerMinute = male
        case .female: kJPerMinute = female
        case .unstated: kJPerMinute = (male + female) / 2.0
        }
        let floor = 3.5 * w / 200.0
        return max(kJPerMinute / kjPerKcal, floor)
    }

    /// The readings of `trace` that can be used: a plausible bpm, inside the clock, oldest first.
    private static func usableSamples(_ trace: HeartRateTrace?, _ activeMs: Int64) -> [HeartRateSample] {
        JavaText.sortedStably((trace?.samples ?? []).filter {
            (HeartRateMeasurement.minBpm...HeartRateMeasurement.maxBpm).contains($0.bpm)
                && $0.clockMs >= 0 && $0.clockMs < activeMs
        }, by: { $0.clockMs })
    }

    /// Kilocalories for `totalReps` done in `activeMs`, blending heart rate with the work-rate model
    /// wherever `trace` does not cover the clock.
    ///
    /// Nil exactly when `burned` would be: no weight, or no clock. Otherwise:
    /// - No trace, no usable body details, or no sample inside `[0, activeMs)`: the same MET-only
    ///   number `burned` already gives, so that function stays the one place the plain formula is
    ///   written down. `estimatedMs` is the whole of `activeMs` and `heartRateMs` is zero: nothing
    ///   here claims a heart rate was used when none was.
    /// - Otherwise, each usable sample (bpm inside `HeartRateMeasurement.minBpm...maxBpm`) covers the
    ///   clock from itself up to the next sample, up to `maxHoldMs` after itself, or up to `activeMs`,
    ///   whichever comes first. Time no sample covers (a gap wider than the hold, or before the first
    ///   or after the last usable sample) falls back to the MET model for exactly that stretch. The two
    ///   are summed in kcal-minutes and rounded once, at the end, so a twenty-minute trace does not
    ///   accumulate a rounding error from a thousand tiny additions.
    ///
    /// No reading outside `minBpm...maxBpm` is ever used, and there is deliberately no upper clamp
    /// beyond that: a hard Cindy legitimately exceeds what the Keytel study's participants were asked
    /// to sustain, and the number that must be caught is sensor junk, not real effort.
    public static func estimate(totalReps: Int, activeMs: Int64, body: Body, trace: HeartRateTrace?) -> CalorieEstimate? {
        if body.weightKg <= 0.0 || activeMs <= 0 { return nil }
        let effortMet = met(totalReps: totalReps, activeMs: activeMs)
        let usable = usableSamples(trace, activeMs)

        if !body.canUseHeartRate || usable.isEmpty {
            return CalorieEstimate(kcal: burned(totalReps: totalReps, activeMs: activeMs, bodyWeightKg: body.weightKg)!,
                                   heartRateMs: 0, estimatedMs: activeMs, met: effortMet)
        }

        var heartRateMs: Int64 = 0
        var kcal = 0.0
        var cursor: Int64 = 0
        let metKcalPerMs = effortMet * 3.5 * body.weightKg / 200.0 / 60_000.0

        for i in usable.indices {
            let at = usable[i].clockMs
            let next = i + 1 < usable.count ? usable[i + 1].clockMs : Int64.max
            let end = min(next, at + maxHoldMs, activeMs)
            if end <= at { continue }
            if at > cursor { kcal += metKcalPerMs * Double(at - cursor) }
            let coveredMs = end - at
            kcal += keytelKcalPerMinute(bpm: usable[i].bpm, body: body) * (Double(coveredMs) / 60_000.0)
            heartRateMs += coveredMs
            cursor = max(cursor, end)
        }
        if cursor < activeMs { kcal += metKcalPerMs * Double(activeMs - cursor) }

        return CalorieEstimate(kcal: max(JavaText.roundToInt(kcal), 0), heartRateMs: heartRateMs,
                               estimatedMs: activeMs - heartRateMs, met: effortMet)
    }

    /// The same estimate as `estimate`, as a running total across the clock: where it stood at the
    /// start of every stretch it was built from, so the results timeline can draw it and say which
    /// stretches a watch measured and which came from the reps.
    ///
    /// Walks `estimate`'s own loop in the same order and adds the same terms, so the last point
    /// rounds to exactly `estimate(...)!.kcal`. Two sums that were merely close would put one number
    /// on the timeline and another on the energy row above it. `estimate` is deliberately left alone:
    /// it is the figure the app already shows, and re-expressing it through this would change that
    /// figure's arithmetic for the sake of a chart.
    ///
    /// Empty exactly when `estimate` is nil. Without a usable heart rate it is just the origin and
    /// the end, joined by one stretch flagged as estimated; nothing here claims a watch was heard
    /// when none was.
    public static func timeline(totalReps: Int, activeMs: Int64, body: Body, trace: HeartRateTrace?) -> [CaloriePoint] {
        if body.weightKg <= 0.0 || activeMs <= 0 { return [] }
        let effortMet = met(totalReps: totalReps, activeMs: activeMs)
        let usable = usableSamples(trace, activeMs)

        var points = [CaloriePoint(0, 0.0, fromHeartRate: false)]
        if !body.canUseHeartRate || usable.isEmpty {
            let minutes = Double(activeMs) / 60_000.0
            points.append(CaloriePoint(activeMs, effortMet * 3.5 * body.weightKg / 200.0 * minutes, fromHeartRate: false))
            return points
        }

        var kcal = 0.0
        var cursor: Int64 = 0
        let metKcalPerMs = effortMet * 3.5 * body.weightKg / 200.0 / 60_000.0

        for i in usable.indices {
            let at = usable[i].clockMs
            let next = i + 1 < usable.count ? usable[i + 1].clockMs : Int64.max
            let end = min(next, at + maxHoldMs, activeMs)
            if end <= at { continue }
            if at > cursor {
                kcal += metKcalPerMs * Double(at - cursor)
                points.append(CaloriePoint(at, kcal, fromHeartRate: false))
            }
            let coveredMs = end - at
            kcal += keytelKcalPerMinute(bpm: usable[i].bpm, body: body) * (Double(coveredMs) / 60_000.0)
            points.append(CaloriePoint(end, kcal, fromHeartRate: true))
            cursor = max(cursor, end)
        }
        if cursor < activeMs {
            kcal += metKcalPerMs * Double(activeMs - cursor)
            points.append(CaloriePoint(activeMs, kcal, fromHeartRate: false))
        }
        return points
    }
}

/// Kilocalories burned by `clockMs` on the workout clock, cumulative and unrounded.
///
/// `fromHeartRate` describes the stretch that *ends* here, from the previous point to this one: true
/// where a heart rate measured it, false where the work rate estimated it. The first point, the
/// origin, has no stretch before it and says false.
public struct CaloriePoint: Equatable, Sendable {
    public let clockMs: Int64
    public let kcal: Double
    public let fromHeartRate: Bool

    public init(_ clockMs: Int64, _ kcal: Double, fromHeartRate: Bool) {
        self.clockMs = clockMs
        self.kcal = kcal
        self.fromHeartRate = fromHeartRate
    }
}

/// Female and male are the Keytel equation's own two fits; the third is what averages them.
public enum Sex: CaseIterable, Sendable {
    case female, male, unstated

    public var label: String {
        switch self {
        case .female: return "Female"
        case .male: return "Male"
        case .unstated: return "Prefer not to say"
        }
    }
}

/// What `Calories` needs to know about the athlete.
///
/// `age` and `sex` are formula inputs the MET model has no use for, which is why they can be absent
/// even once `weightKg` is known.
public struct Body: Equatable, Sendable {
    public let weightKg: Double
    public let age: Int?
    public let sex: Sex?

    public init(_ weightKg: Double, age: Int? = nil, sex: Sex? = nil) {
        self.weightKg = weightKg
        self.age = age
        self.sex = sex
    }

    /// Whether there is enough here for `Calories.estimate` to even attempt heart rate.
    public var canUseHeartRate: Bool { weightKg > 0.0 && age != nil && sex != nil }
}

/// What `Calories.estimate` found, and how it got there.
///
/// `heartRateMs` and `estimatedMs` always sum to the workout's active clock, so the results screen
/// can say exactly how much of the number came from the watch and how much from reps.
public struct CalorieEstimate: Equatable, Sendable {
    public let kcal: Int
    /// Workout-clock ms the heart rate covered.
    public let heartRateMs: Int64
    /// Workout-clock ms estimated from the work rate instead.
    public let estimatedMs: Int64
    /// The MET the work-rate part used: `Calories.met(totalReps:activeMs:)`.
    public let met: Double

    public init(kcal: Int, heartRateMs: Int64, estimatedMs: Int64, met: Double) {
        self.kcal = kcal
        self.heartRateMs = heartRateMs
        self.estimatedMs = estimatedMs
        self.met = met
    }

    public var usedHeartRate: Bool { heartRateMs > 0 }
}
