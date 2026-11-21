package com.cindy.tracker

/** How long a Freestyle may run without a banked rep before the app asks whether to stop. */
const val FREESTYLE_IDLE_ASK_MS = 10 * 60_000L

/**
 * The idle rule of a Freestyle (ticket #192): after [askAfterMs] of running time with no banked
 * rep the app asks whether to stop. It decides nothing itself and never stops a session: the
 * caller shows the question when [shouldAsk] says so, and answers with [keepGoing] or files.
 *
 * Time is the one millisecond clock the engine uses. Time spent paused is not counted. It asks
 * once per wait, so a question left on screen is not asked again. Cindy never consults this.
 *
 * Threads: the main thread only.
 */
class FreestyleIdleWatch(private val askAfterMs: Long = FREESTYLE_IDLE_ASK_MS) {

    private var started = false
    private var sinceAt = 0L
    private var pausedAt: Long? = null
    private var asked = false

    fun start(now: Long) {
        started = true
        sinceAt = now
        pausedAt = null
        asked = false
    }

    /** A rep was banked: the wait begins again. Taking one back does not call this. */
    fun repBanked(now: Long) = restart(now)

    /** The answer "keep going": another full wait from now. */
    fun keepGoing(now: Long) = restart(now)

    fun pause(now: Long) {
        if (started && pausedAt == null) pausedAt = now
    }

    fun resume(now: Long) {
        val at = pausedAt ?: return
        sinceAt += now - at
        pausedAt = null
    }

    /** True once, when [askAfterMs] of running time has passed since the last rep. */
    fun shouldAsk(now: Long): Boolean {
        if (!started || pausedAt != null || asked) return false
        if (now - sinceAt < askAfterMs) return false
        asked = true
        return true
    }

    private fun restart(now: Long) {
        if (!started) return
        sinceAt = now - (pausedAt?.let { now - it } ?: 0L)
        asked = false
    }
}
