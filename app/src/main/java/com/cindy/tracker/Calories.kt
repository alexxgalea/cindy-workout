package com.cindy.tracker

import kotlin.math.roundToInt

/**
 * An estimate of the energy a Cindy cost.
 *
 * The base arithmetic is the standard MET equation — `kcal/min = MET × 3.5 × kg / 200` — which
 * is what every fitness tracker without a heart-rate strap is doing underneath. It needs the
 * athlete's actual body weight, so nothing is shown until they have given one: a guessed weight
 * would produce a confident number that is wrong by however much the guess was.
 *
 * The wrinkle is that Cindy is an AMRAP, so twenty minutes buys wildly different amounts of
 * work. Eight rounds and twenty-five rounds are not the same effort, and a flat MET would call
 * them equal. So the MET is scaled by the rate the athlete actually worked at, and clamped at
 * both ends, because neither an idle twenty minutes nor a superhuman one is what the reference
 * value describes.
 *
 * Treat the output as an estimate with real uncertainty in it. With heart rate, this is what it
 * does; without, the above.
 */
object Calories {

    /**
     * Vigorous calisthenics — push-ups, sit-ups, pull-ups — and general circuit training both
     * sit at 8 METs in the Compendium of Physical Activities. Cindy is exactly that.
     */
    const val REFERENCE_MET = 8.0

    /**
     * The work rate the reference MET is taken to describe: ten rounds inside the twenty
     * minutes, which is where CrossFit puts a competent unscaled effort.
     */
    const val REFERENCE_REPS_PER_MINUTE = 10.0 * 30.0 / 20.0

    /** Twenty minutes of standing near the bar is still not sedentary, but it is not eight METs. */
    const val MIN_MET = 5.0

    /**
     * Sustaining more than this for twenty minutes is beyond what the compendium describes, so
     * the estimate stops following the work rate up rather than inventing numbers off the end
     * of the scale.
     */
    const val MAX_MET = 14.0

    /**
     * Longest a heart-rate reading is assumed to hold before the time after it counts as
     * uncovered.
     *
     * Declared here rather than beside the heart-rate calorie work that uses it later, because
     * [HeartRateRecorder] needs the same figure for the same reason: a reading a few seconds old
     * is still a fair stand-in for "now", and one from a while ago is not. One constant, so the
     * recorder's seeding and the calorie estimate's coverage cannot quietly disagree about where
     * that line is.
     */
    const val MAX_HOLD_MS = 5_000L

    /** The effective MET for work done at this rate. */
    fun met(totalReps: Int, activeMs: Long): Double {
        if (totalReps <= 0 || activeMs <= 0L) return MIN_MET
        val minutes = activeMs / 60_000.0
        if (minutes <= 0.0) return MIN_MET
        val repsPerMinute = totalReps / minutes
        val scaled = REFERENCE_MET * (repsPerMinute / REFERENCE_REPS_PER_MINUTE)
        return scaled.coerceIn(MIN_MET, MAX_MET)
    }

    /**
     * Kilocalories for [totalReps] done in [activeMs] of clock by an athlete of [bodyWeightKg],
     * or null when there is nothing to base it on.
     *
     * [activeMs] is the workout clock and so already excludes paused time — resting with the
     * clock stopped is not work.
     */
    fun burned(totalReps: Int, activeMs: Long, bodyWeightKg: Double): Int? {
        if (bodyWeightKg <= 0.0 || activeMs <= 0L) return null
        val minutes = activeMs / 60_000.0
        val kcal = met(totalReps, activeMs) * 3.5 * bodyWeightKg / 200.0 * minutes
        return kcal.roundToInt().coerceAtLeast(0)
    }

    /** kJ per kcal, the unit the Keytel equation is published in. */
    const val KJ_PER_KCAL = 4.184

    /**
     * Kilocalories per minute from heart rate alone, by the Keytel et al. (2005) equation
     * (*Prediction of energy expenditure from heart rate monitoring during submaximal exercise*,
     * J Sports Sci 23(3):289–297) — fitted separately for women and men, which is why [body] must
     * already carry a [Sex]; [Sex.UNSTATED] averages the two rather than guessing between them.
     *
     * Below the fit's range the equation undershoots badly: at 60 bpm it falls under resting
     * metabolism, which a workout obviously is not. The published model has no resting-HR term to
     * blend towards instead, so this floors at 1 MET (`3.5 × kg / 200`) rather than inventing a
     * new input to ask for. During Cindy the heart rate sits far above the floor anyway.
     *
     * Requires `body.canUseHeartRate`; the caller — [estimate] — is what actually checks it.
     */
    fun keytelKcalPerMinute(bpm: Int, body: Body): Double {
        val w = body.weightKg
        val a = body.age!!
        val male = -55.0969 + 0.6309 * bpm + 0.1988 * w + 0.2017 * a
        val female = -20.4022 + 0.4472 * bpm - 0.1263 * w + 0.074 * a
        val kJPerMinute = when (body.sex!!) {
            Sex.MALE -> male
            Sex.FEMALE -> female
            Sex.UNSTATED -> (male + female) / 2.0
        }
        val floor = 3.5 * w / 200.0
        return maxOf(kJPerMinute / KJ_PER_KCAL, floor)
    }

    /**
     * Kilocalories for [totalReps] done in [activeMs], blending heart rate with the work-rate
     * model wherever [trace] does not cover the clock.
     *
     * Null exactly when [burned] would be: no weight, or no clock. Otherwise:
     * - No trace, no usable body details, or no sample inside `[0, activeMs)` — the same MET-only
     *   number [burned] already gives, so that function stays the one place the plain formula is
     *   written down. `estimatedMs` is the whole of [activeMs] and `heartRateMs` is zero: nothing
     *   here claims a heart rate was used when none was.
     * - Otherwise, each usable sample (bpm inside [HeartRateMeasurement.MIN_BPM]..
     *   [HeartRateMeasurement.MAX_BPM]) covers the clock from itself up to the next sample, up to
     *   [MAX_HOLD_MS] after itself, or up to [activeMs] — whichever comes first. Time no sample
     *   covers — a gap wider than the hold, or before the first / after the last usable sample —
     *   falls back to the MET model for exactly that stretch. The two are summed in kcal-minutes
     *   and rounded once, at the end, so a twenty-minute trace does not accumulate a rounding
     *   error from a thousand tiny additions.
     *
     * No reading outside `MIN_BPM..MAX_BPM` is ever used, and there is deliberately no upper
     * clamp beyond that: a hard Cindy legitimately exceeds what the Keytel study's participants
     * were asked to sustain, and the number that must be caught is sensor junk, not real effort.
     */
    fun estimate(totalReps: Int, activeMs: Long, body: Body, trace: HeartRateTrace?): CalorieEstimate? {
        if (body.weightKg <= 0.0 || activeMs <= 0L) return null
        val effortMet = met(totalReps, activeMs)

        val usable = trace?.samples
            ?.filter {
                it.bpm in HeartRateMeasurement.MIN_BPM..HeartRateMeasurement.MAX_BPM &&
                    it.clockMs in 0 until activeMs
            }
            ?.sortedBy { it.clockMs }
            .orEmpty()

        if (!body.canUseHeartRate || usable.isEmpty()) {
            return CalorieEstimate(
                kcal = burned(totalReps, activeMs, body.weightKg)!!,
                heartRateMs = 0L,
                estimatedMs = activeMs,
                met = effortMet
            )
        }

        var heartRateMs = 0L
        var kcal = 0.0
        var cursor = 0L
        val metKcalPerMs = effortMet * 3.5 * body.weightKg / 200.0 / 60_000.0

        for (i in usable.indices) {
            val at = usable[i].clockMs
            val next = if (i + 1 < usable.size) usable[i + 1].clockMs else Long.MAX_VALUE
            val end = minOf(next, at + MAX_HOLD_MS, activeMs)
            if (end <= at) continue
            if (at > cursor) kcal += metKcalPerMs * (at - cursor)
            val coveredMs = end - at
            kcal += keytelKcalPerMinute(usable[i].bpm, body) * (coveredMs / 60_000.0)
            heartRateMs += coveredMs
            cursor = maxOf(cursor, end)
        }
        if (cursor < activeMs) kcal += metKcalPerMs * (activeMs - cursor)

        return CalorieEstimate(
            kcal = kcal.roundToInt().coerceAtLeast(0),
            heartRateMs = heartRateMs,
            estimatedMs = activeMs - heartRateMs,
            met = effortMet
        )
    }
}

/** Female and male are the Keytel equation's own two fits; the third is what averages them. */
enum class Sex(val label: String) { FEMALE("Female"), MALE("Male"), UNSTATED("Prefer not to say") }

/**
 * What [Calories] needs to know about the athlete.
 *
 * [age] and [sex] are formula inputs the MET model has no use for, which is why they can be
 * absent even once [weightKg] is known — see [Profile] for why they are asked separately.
 */
data class Body(val weightKg: Double, val age: Int? = null, val sex: Sex? = null) {
    /** Whether there is enough here for [Calories.estimate] to even attempt heart rate. */
    val canUseHeartRate: Boolean get() = weightKg > 0.0 && age != null && sex != null
}

/**
 * What [Calories.estimate] found, and how it got there.
 *
 * [heartRateMs] and [estimatedMs] always sum to the workout's active clock, so the results screen
 * can say exactly how much of the number came from the watch and how much from reps.
 */
data class CalorieEstimate(
    val kcal: Int,
    /** Workout-clock ms the heart rate covered. */
    val heartRateMs: Long,
    /** Workout-clock ms estimated from the work rate instead. */
    val estimatedMs: Long,
    /** The MET the work-rate part used: `Calories.met(totalReps, activeMs)`. */
    val met: Double
) {
    val usedHeartRate: Boolean get() = heartRateMs > 0L
}
