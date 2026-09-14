package com.cindy.tracker

import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.atomic.AtomicReference

/**
 * The handoff from the analysis thread to the main thread, which drops what is stale and keeps
 * what is irreplaceable.
 *
 * ### The queue that had to go
 *
 * Every analysed frame used to become its own posted runnable. The analysis thread never waits
 * for the main thread, so that is an unbounded queue: when the main thread falls behind — a text
 * layout, a TTS call, a dialog arriving with its own window — runnables pile up, and every single
 * one is eventually rendered, each staler than the one before. The lag grows and never recovers,
 * which is a far better fit for "not in real time" than any fixed cost would be.
 *
 * ### Why it cannot simply be a latest-value slot
 *
 * Keeping only the newest frame fixes that, and would be correct if every frame were *state*.
 * Most are: a rep count, a hint, a status dot, a progress bar — render the newest and the ones
 * skipped never mattered.
 *
 * Some are not. A frame carrying a [RepEvent] is the *only* notice that a rep was counted, undone,
 * or that a movement or round finished. Dropping one loses a vibration and a spoken number, and
 * for a finished round it loses that round's split from the session record permanently. Those are
 * events, and an event that is coalesced away has not been deferred, it has been lost.
 *
 * So: events queue and are all delivered in order; state is a single slot holding only the
 * newest. Falling behind then costs *frames* rather than *freshness* — the same bargain CameraX
 * already makes upstream with `STRATEGY_KEEP_ONLY_LATEST` — without ever costing a rep.
 */
class FrameHandoff<T> {

    private val events = ConcurrentLinkedQueue<T>()
    private val latest = AtomicReference<T?>(null)

    /** What became of a submitted frame, and whether the main thread needs waking for it. */
    enum class Outcome {
        /** Nothing was already scheduled to collect this: the caller must post a [drain]. */
        SCHEDULE,

        /**
         * This frame replaced a state frame that had not been rendered yet, and a drain is
         * already scheduled. The displaced frame is gone — which is the point, and which is also
         * the measurement: a high share of these says the main thread cannot keep up with the
         * analysis thread, and so says that the old post-per-frame design was queueing.
         */
        REPLACED_PENDING
    }

    /** Offers one frame from the analysis thread. */
    fun submit(frame: T, isEvent: Boolean): Outcome {
        if (isEvent) {
            events.add(frame)
            return Outcome.SCHEDULE
        }
        return if (latest.getAndSet(frame) == null) Outcome.SCHEDULE else Outcome.REPLACED_PENDING
    }

    /**
     * Renders everything owed, oldest first: every event in order, then the newest state.
     *
     * Safe to call spuriously — a second scheduled drain simply finds nothing and returns, which
     * is what makes the "should I schedule?" answer above allowed to be conservative.
     */
    fun drain(render: (T) -> Unit) {
        while (true) {
            val event = events.poll() ?: break
            render(event)
        }
        latest.getAndSet(null)?.let(render)
    }

    /** Forgets everything owed. For teardown, and for a camera rebind that invalidates it all. */
    fun clear() {
        events.clear()
        latest.set(null)
    }
}
