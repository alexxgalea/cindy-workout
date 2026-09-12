package com.cindy.tracker

/** How much of the athlete the camera is managing to read. */
enum class TrackingHealth {
    /** The movement's joints are as legible as they have been all session. */
    GOOD,

    /** Legibility is falling. Measured on darkened footage, the count is still right here. */
    WEAK,

    /** Legibility has collapsed far enough that reps are being missed. */
    LOST
}

/**
 * Watches whether the camera can still read the athlete, and says so before the score goes wrong.
 *
 * ### What this exists to fix
 *
 * A tester reported that a workout stopped counting his pull-ups around the tenth round, outdoors,
 * at sunset. Reproducing that by darkening a clip whose ground truth is five reps showed something
 * worse than "stopped": the score *bleeds*. As the light fell the same five pull-ups scored 5, 3,
 * 2, 1, 0 — with no warning, and nothing in the saved record to say the number was a lower bound.
 * The athlete notices at zero, long after the count stopped being true.
 *
 * The counting gates cannot fix that. They already refuse a frame whose joints are not legible, so
 * darkness produces an *absent* rep rather than a wrong one — across every light level tested the
 * count only ever moved down, never up. There is no rep to reject, and no gate can recover one the
 * camera never saw. The only honest response is to notice, say so, and stop presenting the total
 * as if it were certain.
 *
 * ### Why legibility, and why relative to the session
 *
 * The signal is the share of recent frames in which every joint the current movement scores from
 * was confidently seen. Deliberately *stricter* than the counting gates, which fall back to
 * whichever side of the body is visible: the health reading is supposed to degrade **before**
 * counting does, which is the whole point of a warning.
 *
 * It is measured against the session's own baseline rather than a fixed percentage, because no
 * fixed percentage survives contact with real footage. Of the two clips measured, one sat at 89%
 * legible while counting perfectly and the other at 31% while also counting perfectly — the second
 * simply contains stretches with nobody in shot. An absolute threshold anywhere between those
 * numbers would cry wolf on a clip that is working. As a *fraction of what that clip itself
 * achieves*, though, both lose reps at around half — which is where the losing threshold is set. This is the
 * same argument that made RepCounter learn its band instead of trusting fixed thresholds.
 *
 * The baseline is kept per movement because Cindy alternates three of them and they are not
 * comparable: pull-ups need both wrists overhead, which are small, fast and often silhouetted,
 * and they fail roughly sixteen times sooner than push-ups as light falls. Holding pull-ups to a
 * baseline learned during squats would either warn constantly or never warn at all.
 *
 * Free of Android types, like [Coach], so the rules can be tested.
 */
class TrackingHealthMonitor {

    private companion object {
        /**
         * How much recent history a reading is taken over.
         *
         * Long enough that a single occluded rep does not move it — a pull-up hides its own
         * wrists at the top — and short enough to notice a light that is going within a set.
         */
        const val WINDOW_MS = 4_000L

        /** Samples the window needs before it describes anything. */
        const val MIN_SAMPLES = 20

        /**
         * Share of the session's own best legibility below which the camera is falling behind.
         *
         * Measured: the clip still scored all five reps down to 65% of its baseline, and had lost
         * two of them by 46%. Warning at 70% therefore lands while the count is still right,
         * which is the only moment a warning is worth anything.
         */
        const val FADING = 0.70f

        /** And below which reps are being missed — 55% and 46% of baseline lost reps in both clips. */
        const val LOSING = 0.50f

        /** Recovery has to beat the warning threshold, so a reading sitting on it cannot flap. */
        const val RECOVERED = 0.80f

        /**
         * How long a reading must hold before the athlete is told anything.
         *
         * Matches the coach's existing patience with a fault. Shorter than this and stepping out
         * of shot to chalk up would announce a tracking failure.
         */
        const val DWELL_MS = 3_000L

        /**
         * Brightness gain past which the picture really was dark, rather than merely unreadable.
         *
         * The detector reports what it had to multiply the crop by to bring it up to a normal
         * exposure, so a large value is direct evidence about the light — the one thing that
         * separates "too dark to see you" from "you are not in shot", which look identical in
         * the keypoints alone. Two means the crop metered under half a normal exposure.
         */
        const val DARK_GAIN = 2f
    }

    /** Timestamps of every frame in the window, and of the legible ones, evicted together. */
    private val seen = ArrayDeque<Long>()
    private val read = ArrayDeque<Long>()

    /** Best sustained legibility this session, per movement. NaN until one is established. */
    private val baseline = FloatArray(Exercise.entries.size) { Float.NaN }

    private var candidate = TrackingHealth.GOOD
    private var candidateSince = 0L
    private var lastNow = 0L
    /** When the current window started filling, so "long enough to judge" is measurable. */
    private var windowSince = 0L
    /** The movement the window is describing; a change empties it. */
    private var lastExercise: Exercise? = null

    var health = TrackingHealth.GOOD
        private set

    /**
     * What to tell the athlete, or null while nothing is wrong.
     *
     * This replaces the engine's own hint rather than joining it. When the light goes, the engine
     * refuses frames for "Show both hands" and then "Step into frame" — which is the app telling
     * someone hanging on the bar in front of it that they are not there. It is not merely
     * unhelpful, it is wrong, and it sends the athlete off to fix their position instead of the
     * light.
     */
    var advice: String? = null
        private set

    /** Time spent unable to read the athlete, which is what makes a score a lower bound. */
    var lostMs = 0L
        private set

    /** Time spent falling behind but still believed to be counting correctly. */
    var weakMs = 0L
        private set

    /**
     * Feeds one frame of a running workout.
     *
     * [legible] is whether every joint this movement scores from was confidently seen.
     * [softGain] is what the detector had to brighten the crop by, which is the only evidence
     * available about whether the picture was dark.
     */
    fun update(
        exercise: Exercise,
        legible: Boolean,
        softGain: Float,
        now: Long
    ): TrackingHealth {
        accrue(now)
        lastNow = now

        // A window spanning a movement change describes neither of them. Cindy switches every few
        // reps, and the three are not comparable — carrying pull-up frames into the first seconds
        // of a squat reads as a collapse that never happened, once per movement, all workout.
        // The learned baselines survive; only the window in progress is thrown away.
        if (exercise != lastExercise) {
            lastExercise = exercise
            seen.clear()
            read.clear()
            windowSince = 0L
            candidateSince = now
        }

        if (windowSince == 0L) windowSince = now
        seen.addLast(now)
        if (legible) read.addLast(now)
        val cutoff = now - WINDOW_MS
        while (seen.isNotEmpty() && seen.first() < cutoff) seen.removeFirst()
        while (read.isNotEmpty() && read.first() < cutoff) read.removeFirst()

        // A window that is merely short describes nothing: it takes a few frames to tell a dark
        // room from a blink, and reading one before it has filled is how a monitor announces a
        // failure at the moment the workout starts. Measured from the first sample rather than
        // the oldest surviving one, which after eviction is by definition inside the window.
        if (seen.size < MIN_SAMPLES || now - windowSince < WINDOW_MS) return health

        val fraction = read.size.toFloat() / seen.size
        val best = baseline[exercise.ordinal]
        // The baseline is a high-water mark: what this athlete, this framing and this light have
        // actually managed. It only rises, because the question being asked is how far the camera
        // has fallen from its own best — letting it fall too would quietly accept the degradation
        // as the new normal, which is exactly the silence this class exists to break.
        if (best.isNaN() || fraction > best) baseline[exercise.ordinal] = fraction

        val reference = baseline[exercise.ordinal]
        // A baseline of zero is not a lenient baseline, it is the absence of one: the camera has
        // never once read this movement. Treating that as "nothing to fall from, so all is well"
        // made the monitor call a clip it could read *nothing* in perfectly healthy — which is
        // the session that starts already degraded, the one case a relative reading cannot see.
        // Reading nothing is unambiguous, so it is scored as the failure it is.
        val ratio = if (reference <= 0f) 0f else fraction / reference
        settle(
            when {
                ratio < LOSING -> TrackingHealth.LOST
                ratio < FADING -> TrackingHealth.WEAK
                ratio >= RECOVERED -> TrackingHealth.GOOD
                // Between FADING and RECOVERED nothing changes, so a reading hovering on the
                // threshold does not alternate between warning and silence.
                else -> health
            },
            softGain,
            now
        )
        return health
    }

    /** Holds a new reading for [DWELL_MS] before acting on it. */
    private fun settle(reading: TrackingHealth, softGain: Float, now: Long) {
        if (reading != candidate) {
            candidate = reading
            candidateSince = now
            return
        }
        if (reading == health) return
        // Recovering is allowed to be instant. Making someone wait three seconds to be told the
        // app can see them again, when they have just turned a light on, reads as the fix not
        // having worked.
        if (reading != TrackingHealth.GOOD && now - candidateSince < DWELL_MS) return
        health = reading
        advice = when (reading) {
            TrackingHealth.GOOD -> null
            TrackingHealth.WEAK -> "Losing you — more light helps"
            // Only claimed when the detector measured a dark crop. Without that evidence the app
            // genuinely cannot tell darkness from an empty frame, and saying "too dark" to
            // someone who has walked out of shot is the same mistake in the other direction.
            TrackingHealth.LOST ->
                if (softGain >= DARK_GAIN) "Too dark to count — tap +1"
                else "Can't see you — tap +1"
        }
    }

    private fun accrue(now: Long) {
        if (lastNow == 0L || now <= lastNow) return
        val elapsed = now - lastNow
        when (health) {
            TrackingHealth.LOST -> lostMs += elapsed
            TrackingHealth.WEAK -> weakMs += elapsed
            TrackingHealth.GOOD -> Unit
        }
    }

    /**
     * Forgets the learned baselines without clearing what the session has already suffered.
     *
     * Called when the camera moves. The baseline describes a framing, so one learned before the
     * phone was knocked over says nothing about the view it has now — but the reps that were
     * missed before it moved were still missed.
     */
    fun reframe() {
        baseline.fill(Float.NaN)
        seen.clear()
        read.clear()
        windowSince = 0L
        lastExercise = null
        candidate = health
        candidateSince = 0L
    }

    fun reset() {
        seen.clear()
        read.clear()
        baseline.fill(Float.NaN)
        health = TrackingHealth.GOOD
        advice = null
        candidate = TrackingHealth.GOOD
        candidateSince = 0L
        lastNow = 0L
        windowSince = 0L
        lastExercise = null
        lostMs = 0L
        weakMs = 0L
    }
}
