package com.cindy.tracker

/**
 * Puts heart-rate readings from a [HeartRateSource] onto the workout clock.
 *
 * Pure and main-thread-only, with every time injected rather than read from the system, for the
 * same reason [WorkoutEngine] is: a clock that reads itself cannot be driven by a test. The clock
 * it keeps is the workout clock — the same one behind [Attempt.durationMs] and
 * [Attempt.roundSplitsMs] — not wall time, so a trace and its attempt agree about when things
 * happened without any translation between them.
 *
 * A watch does not stop broadcasting just because the workout has not started, is paused, or has
 * finished. [offer] is therefore always safe to call; what changes with the recorder's state is
 * only whether a reading gets *recorded*, or merely remembered as the most recent one seen — the
 * latter is what lets a reading from just before `start` or `resume` seed the trace instead of
 * leaving an honest gap at the very beginning of a segment where a real bpm was in fact known.
 */
class HeartRateRecorder {

    private enum class State { IDLE, RUNNING, PAUSED, FINISHED }

    private var state = State.IDLE

    private var startedAtMillis = 0L
    /** The clock value the current running segment started from. */
    private var clockBase = 0L
    /** The elapsedRealtime the current running segment started from. */
    private var runningSince = 0L
    /** The clock never runs backward, even if a delayed callback hands [offer] a stale time. */
    private var clockHighWaterMs = 0L

    private var pausedClockMs = 0L
    private var pausedAtElapsedMs = 0L

    private var lastRecordedClockMs: Long? = null

    /** The most recent reading `offer` has seen, in any state — the seed for the next segment. */
    private var lastReadingBpm: Int? = null
    private var lastReadingAtElapsedMs = 0L

    private val samples = mutableListOf<HeartRateSample>()
    private val pauses = mutableListOf<HeartRatePause>()

    /** Starts a fresh trace. [wallMillis] is stamped as [HeartRateTrace.startedAtMillis]. */
    fun start(atElapsedMs: Long, wallMillis: Long) {
        state = State.RUNNING
        startedAtMillis = wallMillis
        clockBase = 0L
        runningSince = atElapsedMs
        clockHighWaterMs = 0L
        lastRecordedClockMs = null
        samples.clear()
        pauses.clear()
        seedFromRememberedReading(atElapsedMs)
    }

    /** Freezes the clock. Readings still arrive, through [offer], but stop being recorded. */
    fun pause(atElapsedMs: Long) {
        if (state != State.RUNNING) return
        pausedClockMs = clockAt(atElapsedMs)
        pausedAtElapsedMs = atElapsedMs
        state = State.PAUSED
    }

    /**
     * Resumes the clock where [pause] left it, and closes the pause that [pause] opened.
     *
     * Seeds from the remembered reading exactly as [start] does: a strap kept broadcasting the
     * whole time the clock was frozen, so the reading it sent just before this call is as good a
     * seed for the new segment as one sent just before the workout began.
     */
    fun resume(atElapsedMs: Long) {
        if (state != State.PAUSED) return
        pauses += HeartRatePause(atClockMs = pausedClockMs, lengthMs = atElapsedMs - pausedAtElapsedMs)
        clockBase = pausedClockMs
        runningSince = atElapsedMs
        state = State.RUNNING
        seedFromRememberedReading(atElapsedMs)
    }

    /**
     * A reading arrived. Recorded only while the clock is running; otherwise just remembered, so
     * a later [start] or [resume] can seed from it. Does nothing at all once [finish] has run.
     */
    fun offer(bpm: Int, atElapsedMs: Long) {
        if (state == State.FINISHED) return
        lastReadingBpm = bpm
        lastReadingAtElapsedMs = atElapsedMs
        if (state == State.RUNNING) {
            record(clockAt(atElapsedMs), bpm)
        }
    }

    /**
     * Closes the trace. While paused, the open pause is closed first — the same thing
     * `MainActivity.finishWorkout` already does with `pausedMs` — so a workout that ends mid-pause
     * does not lose the time it spent there.
     *
     * Null when nothing was ever recorded: an empty trace is not useful to [HeartRateStore] or to
     * [Calories.estimate], both of which already treat "no trace" as "use the MET model".
     */
    fun finish(atElapsedMs: Long): HeartRateTrace? {
        if (state == State.PAUSED) {
            pauses += HeartRatePause(atClockMs = pausedClockMs, lengthMs = atElapsedMs - pausedAtElapsedMs)
        }
        state = State.FINISHED
        if (samples.isEmpty()) return null
        return HeartRateTrace(startedAtMillis, samples.toList(), pauses.toList())
    }

    /** Back to nothing, including the remembered reading — a fresh [start] seeds from nothing. */
    fun reset() {
        state = State.IDLE
        startedAtMillis = 0L
        clockBase = 0L
        runningSince = 0L
        clockHighWaterMs = 0L
        lastRecordedClockMs = null
        lastReadingBpm = null
        lastReadingAtElapsedMs = 0L
        samples.clear()
        pauses.clear()
    }

    private fun seedFromRememberedReading(atElapsedMs: Long) {
        val bpm = lastReadingBpm ?: return
        if (atElapsedMs - lastReadingAtElapsedMs <= Calories.MAX_HOLD_MS) {
            record(clockAt(atElapsedMs), bpm)
        }
    }

    private fun clockAt(atElapsedMs: Long): Long {
        val computed = clockBase + (atElapsedMs - runningSince)
        val clamped = maxOf(computed, clockHighWaterMs)
        clockHighWaterMs = clamped
        return clamped
    }

    /** Caps the rate for straps that notify at 2–4 Hz; a sensor closer to 1 Hz passes untouched. */
    private fun record(clockMs: Long, bpm: Int) {
        val last = lastRecordedClockMs
        if (last != null && clockMs - last < MIN_SPACING_MS) return
        samples += HeartRateSample(clockMs, bpm)
        lastRecordedClockMs = clockMs
    }

    companion object {
        const val MIN_SPACING_MS = 900L
    }
}
