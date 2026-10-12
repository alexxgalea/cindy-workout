import Foundation

/// Maps a banked movement to the `exercise_type` Strava's strength-training JSON expects.
///
/// The repo's rule is that a modified movement is *reported as* the modified movement
/// (see `CindyProfile`), never silently folded into the strict one. Strava's own list has no slot
/// for several of our variants (a band-assisted pull-up, a box squat), so this picks the family's
/// generic type as the least-wrong label and leaves the real movement to be named in the
/// description (`StravaActivityText`), rather than claiming equipment nobody used (a
/// `BARBELL_BOX_SQUAT`, say) just because Strava's generic name is dull.
///
/// Every `switch` here is exhaustive over the variant's enum and has no `default`, on purpose: a
/// new variant must fail this file's compilation until someone has decided what Strava calls it.
public enum StravaExercises {

    public static func typeFor(_ exercise: Exercise, _ profile: CindyProfile?) -> String {
        switch exercise {
        case .pullup: return pullType(profile?.pull)
        case .pushup: return pushType(profile?.push)
        case .squat: return squatType(profile?.squat)
        }
    }

    /// Nil means the attempt predates `CindyProfile` and its movements are unknown.
    private static func pullType(_ variant: PullVariant?) -> String {
        guard let variant = variant else { return "PULL_UP_GENERIC" }
        switch variant {
        case .strictPullUp: return "PULL_UP_GENERIC"
        // No band-assisted type exists. The description names it.
        case .bandAssistedPullUp: return "PULL_UP_GENERIC"
        case .invertedRow: return "INVERTED_ROW"
        // No foot-assisted type exists. The description names it.
        case .footAssistedPullUp: return "PULL_UP_GENERIC"
        case .negativePullUp: return "NEGATIVE_PULL_UP"
        }
    }

    private static func pushType(_ variant: PushVariant?) -> String {
        guard let variant = variant else { return "PUSH_UP_GENERIC" }
        switch variant {
        case .standardPushUp: return "PUSH_UP_GENERIC"
        case .kneePushUp: return "MODIFIED_PUSH_UP"
        case .inclinePushUp: return "INCLINE_PUSH_UP"
        }
    }

    private static func squatType(_ variant: SquatVariant?) -> String {
        guard let variant = variant else { return "SQUAT_GENERIC" }
        switch variant {
        case .airSquat: return "AIR_SQUAT"
        // No heels-flat type exists. The description names it.
        case .heelsFlat: return "SQUAT_GENERIC"
        // BARBELL_BOX_SQUAT would claim a barbell nobody used. The description names it.
        case .boxSquat: return "SQUAT_GENERIC"
        case .supportedSquat: return "SQUAT_GENERIC"
        }
    }
}

/// One heart-rate sample, already placed on the payload's own clock.
public struct HrPoint: Equatable, Sendable {
    public let secondsFromStart: Int
    public let bpm: Int

    public init(_ secondsFromStart: Int, _ bpm: Int) {
        self.secondsFromStart = secondsFromStart
        self.bpm = bpm
    }
}

/// The payload cannot be built because there is nothing in it. Android's `require` failure.
public struct StravaPayloadError: Error, Equatable, Sendable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }
}

/// Turns a finished attempt, its banked sets and whatever else is known into the JSON body
/// Strava's `POST /uploads` wants for `data_type=json`.
///
/// Pure, and composed lazily by the upload from the attempt record itself (`sets` is what
/// `StravaSets.from` built from `Attempt.setSplits`, not a live store this file owns), so nothing
/// here reaches for a clock, a file, or the network, and a process death between finishing and
/// uploading loses nothing: the same `Attempt` and `sets` rebuild the identical payload.
public enum StravaPayload {

    /// The JSON text, keys sorted. Android's `JSONObject` keeps no order; readers parse it.
    public static func build(
        _ a: Attempt,
        _ sets: [WorkoutSet],
        startMillis: Int64,
        utcOffsetSeconds: Int,
        kcal: Int?,
        heartRate: [HrPoint]?
    ) throws -> String {
        // The caller's job to check before ever reaching here -- StravaSets.from already
        // refuses a broken or empty set list, and an attempt this old or this broken has
        // nothing worth Strava's upload quota. Refused rather than quietly upload a
        // workout-shaped JSON with no workout in it.
        guard sets.contains(where: { $0.reps > 0 }) else {
            throw StravaPayloadError("Refusing to build a payload with no banked reps")
        }

        let elapsedTime = Int(JavaText.roundToLong(Double(a.realTimeMs) / 1000.0))
        let activeTime = Int(JavaText.roundToLong(Double(a.durationMs) / 1000.0))

        var json: [String: Any] = [
            "version": "1.0",
            "start_time": isoInstant(startMillis),
            "utc_offset": utcOffsetSeconds,
            "elapsed_time": elapsedTime,
            "active_time": activeTime,
            "creator": ["name": "Cindy Tracker"],
            "sets": setsJson(sets, a.profile)
        ]

        // Bodyweight movements carry no external load, so weight is never set -- a set here is
        // exercise_type and repetitions only.
        if let kcal = kcal { json["total_calories"] = kcal }
        if let heartRate = heartRate, !heartRate.isEmpty {
            json["streams"] = streamsJson(heartRate, elapsedTime)
        }

        let data = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }

    private static func setsJson(_ sets: [WorkoutSet], _ profile: CindyProfile?) -> [[String: Any]] {
        // A movement SKIPped at zero reps banked nothing, and Strava's set list is about work
        // that happened.
        sets.filter { $0.reps > 0 }.map { set in
            ["exercise_type": StravaExercises.typeFor(set.exercise, profile), "repetitions": set.reps]
        }
    }

    /// Strava's stream contract wants `time` strictly increasing. Clamping a trace that starts a
    /// little early or runs a little long can pile more than one sample onto the same boundary
    /// second, so every point is clamped first, then the earliest-seen sample of any second two
    /// land on is kept and the rest of that second dropped -- never averaged or invented.
    private static func streamsJson(_ heartRate: [HrPoint], _ elapsedTime: Int) -> [String: Any] {
        let clamped = heartRate.map {
            HrPoint(min(max($0.secondsFromStart, 0), elapsedTime), $0.bpm)
        }
        var deduped: [HrPoint] = []
        for point in JavaText.sortedStably(clamped, by: { $0.secondsFromStart }) {
            if deduped.last?.secondsFromStart != point.secondsFromStart {
                deduped.append(point)
            }
        }
        return ["time": deduped.map { $0.secondsFromStart }, "heartrate": deduped.map { $0.bpm }]
    }

    /// `Instant.toString()` after truncating to the second: `2026-01-01T00:00:00Z`.
    ///
    /// Worked out from the day count rather than `ISO8601DateFormatter`, whose output follows the
    /// platform. Java writes a sign and more digits outside the years 0000 to 9999; no attempt this
    /// app can save is near either end.
    static func isoInstant(_ epochMillis: Int64) -> String {
        let seconds = Zone.floorDiv(epochMillis, 1_000)
        let days = Zone.floorDiv(seconds, 86_400)
        let secondOfDay = Int(seconds - days * 86_400)
        let date = LocalDate(epochDay: Int(days))
        return "\(date)T" + String(format: "%02d:%02d:%02dZ", secondOfDay / 3_600, secondOfDay / 60 % 60, secondOfDay % 60)
    }
}

/// Where the payload's clock starts: `Attempt.atMillis` is stamped at finish, so the start is
/// that far back, minus every millisecond (running and paused alike) the attempt actually took.
///
/// A heart-rate trace carries its own exact start, and the upload prefers that when there is one.
/// The trace begins recording a touch before the first rep is seen.
public func startMillisOf(_ a: Attempt) -> Int64 { a.atMillis - a.realTimeMs }
