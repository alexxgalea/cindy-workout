package com.cindy.tracker

/**
 * Notices that the bar is what is wrong, not the athlete.
 *
 * A bar is learned from one hang and then refuses every grip that is not on it. If it was learned
 * in the wrong place, nothing else corrects it: refining the bar needs a grip it already accepts,
 * and the one recovery that exists needs the athlete to change size in the frame. Four recorded
 * sessions sat at "Get on the bar" for as long as the athlete kept pulling up.
 *
 * So the engine tells this watch, on every frame it reads a pull-up, whether the bar refused it.
 * When the bar has refused half of what it was shown across four seconds, it is asked to be
 * forgotten and learned again from the next hang. An athlete who has stepped off the bar is refused
 * for just as long, and the next hang they make is then taken for the bar: that is the price of
 * being able to recover from a bar learned in the wrong place, and the owner's choice to pay it.
 */
class BarRefusalWatch {

    private companion object {
        /** How far back the refusals are counted. */
        const val WINDOW_MS = 4_000L
        /** Fewer frames than this say nothing, however many were refused. */
        const val MIN_FRAMES = 20
        /** How much of the window the frames must really span, so a burst is not four seconds. */
        const val MIN_SPAN_MS = 3_500L
    }

    private val times = ArrayDeque<Long>()
    private val refusals = ArrayDeque<Boolean>()
    private var refused = 0

    /**
     * Notes one frame: whether the bar refused it, at [now] in the engine's clock.
     * Returns true when the bar has refused enough of the last four seconds to be doubted, and
     * starts counting again from nothing.
     */
    fun record(now: Long, refusedByBar: Boolean): Boolean {
        times.addLast(now)
        refusals.addLast(refusedByBar)
        if (refusedByBar) refused++
        while (now - times.first() > WINDOW_MS) {
            times.removeFirst()
            if (refusals.removeFirst()) refused--
        }
        if (times.size < MIN_FRAMES || now - times.first() < MIN_SPAN_MS) return false
        // Half or more of the frames. In whole numbers, so no engine can round it differently.
        if (refused * 2 < times.size) return false
        clear()
        return true
    }

    /** Forgets what was counted, as when the bar itself has been forgotten. */
    fun clear() {
        times.clear()
        refusals.clear()
        refused = 0
    }
}
