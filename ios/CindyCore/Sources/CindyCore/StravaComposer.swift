import Foundation

/// What one attempt turns into for Strava: the JSON payload, alongside the name and description it
/// ships with.
public struct StravaComposition: Equatable, Sendable {
    public let payload: String
    public let name: String
    public let description: String

    public init(payload: String, name: String, description: String) {
        self.payload = payload
        self.name = name
        self.description = description
    }
}

/// Gathers everything one Strava upload needs from an attempt and its already-loaded heart-rate
/// trace and body details.
///
/// The calorie estimate is computed exactly once here and used for both the payload's total and
/// the description's basis line, so the two can never disagree with each other about which basis
/// actually produced the number.
///
/// Pure: `startMillis` and `utcOffsetSeconds` are already decided by the caller, so nothing here
/// reaches for a clock, a file, or the network, and the same inputs always compose the same upload.
public enum StravaComposer {

    public static func compose(
        _ a: Attempt,
        _ sets: [WorkoutSet],
        startMillis: Int64,
        utcOffsetSeconds: Int,
        trace: HeartRateTrace?,
        body: Body
    ) throws -> StravaComposition {
        let points = trace.map { StravaHeartRate.points($0, startMillis: startMillis) }
        let heartRate = points?.isEmpty == false ? points : nil
        let est = Calories.estimate(totalReps: a.totalReps, activeMs: a.durationMs, body: body, trace: trace)
        let basis: CalorieBasis
        if est?.usedHeartRate == true {
            basis = .heartRate
        } else if est != nil {
            basis = .bodyWeight
        } else {
            basis = .none
        }
        return StravaComposition(
            payload: try StravaPayload.build(a, sets, startMillis: startMillis, utcOffsetSeconds: utcOffsetSeconds,
                                             kcal: est?.kcal, heartRate: heartRate),
            name: StravaActivityText.name(a),
            description: StravaActivityText.description(a, basis, heartRateMs: est?.heartRateMs))
    }
}
