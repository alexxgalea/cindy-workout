package com.cindy.tracker

import kotlin.math.roundToInt

/**
 * An estimate of the energy a Cindy cost.
 *
 * The arithmetic is the standard MET equation — `kcal/min = MET × 3.5 × kg / 200` — which is
 * what every fitness tracker without a heart-rate strap is doing underneath. It needs the
 * athlete's actual body weight, so nothing is shown until they have given one: a guessed weight
 * would produce a confident number that is wrong by however much the guess was.
 *
 * The wrinkle is that Cindy is an AMRAP, so twenty minutes buys wildly different amounts of
 * work. Eight rounds and twenty-five rounds are not the same effort, and a flat MET would call
 * them equal. So the MET is scaled by the rate the athlete actually worked at, and clamped at
 * both ends, because neither an idle twenty minutes nor a superhuman one is what the reference
 * value describes.
 *
 * Treat the output as an estimate with real uncertainty in it. Without heart rate or gas
 * exchange there is no honest way to do better, and the UI says so.
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
}
