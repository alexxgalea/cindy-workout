package com.cindy.tracker

/** One movement block of a round: how long it took on the clock, and what it scored. */
data class SetSplit(val movement: Exercise, val ms: Long, val reps: Int, val manualReps: Int) {
    /** Reached its target rather than being skipped. */
    val complete: Boolean get() = reps >= movement.target

    /** Complete, and every rep in it seen by the camera: a time the app can stand behind. */
    val measured: Boolean get() = complete && manualReps == 0
}

/**
 * Times each set on the workout clock, pauses excluded, and unwinds across an undo.
 *
 * A set runs from the end of the one before to the end of its own, so it includes getting into
 * position — as a round split does.
 */
class SplitBook {
    private val done = mutableListOf<SetSplit>()
    private val starts = mutableListOf<Long>()
    private val manualStarts = mutableListOf<Int>()
    private var setStartMs = 0L
    private var manualAtStart = 0

    val sets: List<SetSplit> get() = done.toList()

    fun start(atMs: Long = 0L) {
        done.clear(); starts.clear(); manualStarts.clear()
        setStartMs = atMs
        manualAtStart = 0
    }

    fun movementDone(movement: Exercise, atMs: Long, reps: Int, manualTotal: Int) {
        starts += setStartMs
        manualStarts += manualAtStart
        done += SetSplit(
            movement, (atMs - setStartMs).coerceAtLeast(0L), reps,
            (manualTotal - manualAtStart).coerceAtLeast(0)
        )
        setStartMs = atMs
        manualAtStart = manualTotal
    }

    /** An undo stepped back into the previous movement: reopen its set from where it began. */
    fun stepBack() {
        if (done.isEmpty()) return
        done.removeAt(done.lastIndex)
        setStartMs = starts.removeAt(starts.lastIndex)
        manualAtStart = manualStarts.removeAt(manualStarts.lastIndex)
    }
}
