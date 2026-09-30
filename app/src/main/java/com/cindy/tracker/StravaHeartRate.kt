package com.cindy.tracker

/**
 * Places a [HeartRateTrace]'s samples onto the wall clock, and from there onto a payload's own
 * seconds-from-start axis.
 *
 * A trace's samples are stamped on the workout clock, which stands still while the workout is
 * paused. Strava's stream wants real elapsed seconds instead, so every sample has to be walked
 * back onto the wall clock first — exactly the pauses that had already happened by that sample's
 * moment, added back in.
 */
object StravaHeartRate {

    /**
     * The wall-clock epoch ms [clockMs] on [trace]'s own workout clock actually happened at:
     * the trace's start, plus the clock reading itself, plus every pause whose [HeartRatePause.atClockMs]
     * had already passed by then.
     */
    fun wallMillis(trace: HeartRateTrace, clockMs: Long): Long =
        trace.startedAtMillis + clockMs + trace.pauses.filter { it.atClockMs <= clockMs }.sumOf { it.lengthMs }

    /** Every sample in [trace], as seconds from [startMillis] via [wallMillis], floored. */
    fun points(trace: HeartRateTrace, startMillis: Long): List<HrPoint> =
        trace.samples.map { sample ->
            val seconds = Math.floorDiv(wallMillis(trace, sample.clockMs) - startMillis, 1_000L)
            HrPoint(seconds.toInt(), sample.bpm)
        }
}
