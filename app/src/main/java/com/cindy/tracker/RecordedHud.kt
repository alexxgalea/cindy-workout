package com.cindy.tracker

/**
 * What the burned-in recording HUD shows for one rendered frame.
 *
 * Kept apart from the four on-screen views because the film and the screen read differently in
 * two situations: the setup check, which the screen narrates with "SET UP" and a bare rep count,
 * and the few seconds after it ends, when the film alone carries a banner saying what just
 * happened. [RecordingOverlay] draws this and nothing else.
 */
data class RecordedHudText(
    val clock: String,
    val round: String,
    val label: String,
    val count: String,
    /** A line shown for a few seconds after the setup check ends, or null the rest of the time. */
    val banner: String?
)

/**
 * Produces [RecordedHudText] from what [MainActivity] already knows about the workout and the
 * setup check.
 *
 * Framework-free, like [OverlayTransform]: the one part of this with any real logic — whether
 * the banner is still inside its three seconds — depends on a clock, and a clock the caller hands
 * in rather than one this class reads for itself is a clock a test can move.
 */
class RecordedHud {

    // Mirrors the screen's own round and rep views, which is where ROUND and the target it
    // drops a weight and a shade behind actually live; the film wants them as one string each.
    private var workoutRound = "ROUND 1"
    private var workoutCount = "0 / 5"

    private var bannerText: String? = null
    private var bannerShownAt = 0L

    /** Called wherever the screen's own round and rep views are, so the film agrees with them. */
    fun workout(rounds: Int, reps: Int, target: Int) {
        workoutRound = "ROUND ${rounds + 1}"
        workoutCount = "$reps / $target"
    }

    /** Starts the three-second "calibrated" banner. Called once, where the setup check succeeds. */
    fun calibrated(now: Long) {
        bannerText = "CALIBRATED · $CALIBRATION_REPS REPS"
        bannerShownAt = now
    }

    /** Starts the three-second "skipped" banner. Called once, where SKIP leaves the check early. */
    fun skipped(now: Long) {
        bannerText = "CALIBRATION SKIPPED"
        bannerShownAt = now
    }

    /** The film's HUD for a running workout: byte-for-byte what it has always shown. */
    fun forWorkout(now: Long, clock: String, label: String): RecordedHudText = RecordedHudText(
        clock = clock,
        round = workoutRound,
        label = label,
        count = workoutCount,
        banner = bannerAt(now)
    )

    /**
     * The film's HUD while the setup check runs: its own clock and round panel, the movement
     * marked not scored, and a count against [CALIBRATION_REPS] rather than the movement's real
     * target — so the two calibration pull-ups read as calibration instead of the first two of a
     * round that has not started.
     *
     * [setup] is null for the one frame that can be rendered before the analysis thread has
     * produced its first setup reading; that reads the same as a fresh [SetupStage.FRAMING]
     * would, which is what it would say a frame later anyway.
     */
    fun forSetup(now: Long, setup: Setup?, label: String): RecordedHudText {
        val count = if (setup == null || setup.stage == SetupStage.FRAMING) {
            "– / $CALIBRATION_REPS"
        } else {
            "${setup.reps} / $CALIBRATION_REPS"
        }
        return RecordedHudText(
            clock = "SETUP",
            round = "CALIBRATION",
            label = "$label · NOT SCORED",
            count = count,
            banner = bannerAt(now)
        )
    }

    private fun bannerAt(now: Long): String? {
        val text = bannerText ?: return null
        return text.takeIf { now - bannerShownAt < BANNER_MS }
    }

    companion object {
        /**
         * The calibration target the setup check counts against, read by [MainActivity] too so
         * the on-screen "/2" and the burned-in one never say different numbers.
         *
         * Mirrors [WorkoutEngine]'s own constant of the same value. Duplicated rather than read
         * from there because that one is private to the engine; if it is ever retuned, this one
         * has to be told by hand.
         */
        const val CALIBRATION_REPS = 2

        /** How long the post-check banner stays burned into the film. */
        const val BANNER_MS = 3_000L
    }
}
