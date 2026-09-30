package com.cindy.tracker

/** What one attempt turns into for Strava: the JSON payload, alongside the name and description it ships with. */
data class StravaComposition(val payload: String, val name: String, val description: String)

/**
 * Gathers everything one Strava upload needs from an attempt and its already-loaded heart-rate
 * trace and body details.
 *
 * The calorie estimate is computed exactly once here and used for both the payload's total and
 * the description's basis line, so the two can never disagree with each other about which basis
 * actually produced the number.
 *
 * Pure: [startMillis] and [utcOffsetSeconds] are already decided by the caller, so nothing here
 * reaches for a clock, a file, or the network, and the same inputs always compose the same
 * upload.
 */
object StravaComposer {

    fun compose(
        a: Attempt,
        sets: List<WorkoutSet>,
        startMillis: Long,
        utcOffsetSeconds: Int,
        trace: HeartRateTrace?,
        body: Body
    ): StravaComposition {
        val heartRate = trace?.let { StravaHeartRate.points(it, startMillis) }?.takeIf { it.isNotEmpty() }
        val est = Calories.estimate(a.totalReps, a.durationMs, body, trace)
        val basis = when {
            est?.usedHeartRate == true -> CalorieBasis.HEART_RATE
            est != null -> CalorieBasis.BODY_WEIGHT
            else -> CalorieBasis.NONE
        }
        return StravaComposition(
            payload = StravaPayload.build(a, sets, startMillis, utcOffsetSeconds, est?.kcal, heartRate),
            name = StravaActivityText.name(a),
            description = StravaActivityText.description(a, basis)
        )
    }
}
