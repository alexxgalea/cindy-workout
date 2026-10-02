package com.cindy.tracker

/** One rep's moment on the workout clock: when it banked, which movement it belongs to, and how. */
data class RepMark(val clockMs: Long, val movement: Exercise, val manual: Boolean)

/**
 * Where every rep of a session landed on the workout clock, for the chart a later screen draws.
 *
 * [follow] is handed the engine's own banked [totalReps], not the [RepEvent] that came with them,
 * and compares that number to what it saw last: risen by n -> n reps just banked, so append n
 * marks; fallen by n -> an undo just took them back, so drop the last n; unchanged -> nothing
 * happened that counts, whatever event fired. A SKIP is free by construction this way: it moves
 * [Exercise] on without moving the total.
 *
 * That is deliberate rather than switching on the event. [FrameHandoff] drops a stale *state*
 * frame but never a stale *event* one, so in principle the two are equivalent — but a total can
 * also jump by more than one between two calls, exactly when a state frame carrying an
 * intermediate count was the one dropped, and an event-keyed version would have to special-case
 * that instead of simply reading the number that is already correct. Comparing totals also keeps
 * this log unable to disagree with the score the session is actually saved under: a rep here is
 * "banked, never inferred", the same rule [Attempt.countedReps] exists to hold, because it comes
 * from the one number the engine itself commits to rather than from re-deriving a count per event.
 */
class RepLog {

    private val log = mutableListOf<RepMark>()
    private var lastTotal = 0
    private var lastManual = 0

    val marks: List<RepMark> get() = log.toList()

    /** Starts a new session: forgets every mark left over from whatever came before. */
    fun start() {
        log.clear()
        lastTotal = 0
        lastManual = 0
    }

    /**
     * Reconciles [marks] with the engine's latest banked totals.
     *
     * [movement] is whichever one the rep that moved the total belongs to — the caller's job, not
     * this class's, since only the caller knows whether the engine has already advanced past it
     * (see [Exercise.previous]: the finishing rep of a movement is read after the snapshot has
     * moved on). When the total has fallen, [movement] is not consulted: an undo only ever removes
     * the latest mark, whatever it was tagged with.
     */
    fun follow(totalReps: Int, manualReps: Int, movement: Exercise, clockMs: Long) {
        val delta = totalReps - lastTotal
        if (delta > 0) {
            val manualDelta = (manualReps - lastManual).coerceIn(0, delta)
            repeat(delta) { i -> log += RepMark(clockMs, movement, manual = i >= delta - manualDelta) }
        } else if (delta < 0) {
            repeat(minOf(-delta, log.size)) { log.removeAt(log.lastIndex) }
        }
        lastTotal = totalReps
        lastManual = manualReps
    }
}
