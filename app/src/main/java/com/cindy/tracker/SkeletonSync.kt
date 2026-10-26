package com.cindy.tracker

/** One analysed frame's skeleton, with what is needed to draw it into that frame's picture. */
class SyncSkeleton(
    val keypoints: Array<Keypoint>,
    val width: Int,
    val height: Int,
    /** Whether the analysis frame was mirrored, as it is for the selfie camera. */
    val mirrored: Boolean,
    val guide: WorkoutEngine.BarGuide?
)

/**
 * Decides which picture frame is shown when, and with which skeleton.
 *
 * Frames are told to it by their camera capture timestamp, skeletons arrive stamped with the
 * timestamp of the frame they were computed from, and what comes back is the frames to show now.
 * Timestamps are only ever compared with each other. The clock it is given is the app's own
 * monotonic one, and nothing here subtracts a camera timestamp from it.
 *
 * Not thread safe: each instance belongs to one effect's handler thread.
 */
class SkeletonSync(
    mode: Mode,
    private val capacity: Int = DEFAULT_CAPACITY,
    private val nowNanos: () -> Long
) {

    enum class Mode {
        /** Nothing waits: every frame is shown at once, as the picture always was. */
        LIVE,

        /** A frame the model analysed waits for its own skeleton; frames it never saw are not shown. */
        ANALYSED_ONLY,

        /**
         * Every camera frame is shown. One the model never saw waits for the next skeleton and is
         * then drawn with one interpolated, joint by joint and linearly in capture time, between
         * the two real skeletons around it.
         */
        EVERY_FRAME
    }

    /** A frame to show now. [skeleton] is null when none was ready for it. */
    class Released(val captureNanos: Long, val skeleton: SyncSkeleton?)

    private class Waiting(val captureNanos: Long, val knownAtNanos: Long)

    private class Paced(val frame: Released, val showAtNanos: Long)

    var mode: Mode = mode
        private set

    /** Waiting frames, oldest first. */
    private val waiting = ArrayList<Waiting>()

    private var newest: SyncSkeleton? = null

    /** The last real skeleton released, with its capture stamp: the earlier end of an interpolation. */
    private var anchorNanos = 0L
    private var anchor: SyncSkeleton? = null

    /**
     * Released frames not yet shown, oldest first. A release in every-frame mode carries several
     * frames at once, and drawn together only the last would reach the screen. So each waits a
     * capture gap after the one before it.
     */
    private val paced = ArrayDeque<Paced>()
    private var lastPacedAtNanos = 0L
    private var lastPacedCaptureNanos = 0L
    private var pacing = false

    /** Frames the cap released without their skeleton, for the latency readout. */
    var cappedCount = 0
        private set

    /** Frames that will never be shown: pushed out by capacity, passed over, or gone from the effect. */
    var droppedCount = 0
        private set

    /** A picture frame the model is about to analyse, or in live mode, any frame at all. */
    fun frameKnown(captureNanos: Long): List<Released> {
        if (mode == Mode.LIVE) return listOf(Released(captureNanos, newest))
        // The camera's stamps and the analysis reach here on different threads, so a frame can be
        // announced after a skeleton newer than it was used. It could only be shown out of order.
        if (mode == Mode.EVERY_FRAME && anchor != null && captureNanos <= anchorNanos) {
            // The frame the newest skeleton was computed from: it has its real skeleton already.
            if (captureNanos == anchorNanos) return pace(listOf(Released(captureNanos, anchor)))
            droppedCount++
            return emptyList()
        }
        waiting.add(Waiting(captureNanos, nowNanos()))
        // Past capacity the oldest goes, and is simply never shown: showing it without its
        // skeleton would put a bare frame on screen that the cap had not yet allowed.
        while (waiting.size > capacity) {
            waiting.removeAt(0)
            droppedCount++
        }
        return emptyList()
    }

    /** The skeleton computed from the frame stamped [captureNanos]. */
    fun skeletonReady(captureNanos: Long, skeleton: SyncSkeleton): List<Released> {
        newest = skeleton
        if (mode == Mode.EVERY_FRAME) return releaseThrough(captureNanos, skeleton)
        val index = waiting.indexOfFirst { it.captureNanos == captureNanos }
        if (index < 0) return emptyList()
        // Showing a frame discards every older one the picture still holds, so an older frame
        // still waiting is gone either way. Dropping it here keeps the order strict.
        droppedCount += index
        waiting.subList(0, index + 1).clear()
        return listOf(Released(captureNanos, skeleton))
    }

    /**
     * Every frame up to [captureNanos], in capture order: those before it interpolated, and it
     * with the real skeleton if it was announced. A skeleton older than the last one is ignored.
     */
    private fun releaseThrough(captureNanos: Long, skeleton: SyncSkeleton): List<Released> {
        if (anchor != null && captureNanos <= anchorNanos) return emptyList()
        val earlier = anchor
        val released = ArrayList<Released>()
        var upTo = 0
        while (upTo < waiting.size && waiting[upTo].captureNanos <= captureNanos) {
            val at = waiting[upTo].captureNanos
            released.add(
                Released(
                    at,
                    if (at == captureNanos) skeleton
                    else earlier?.let { between(it, anchorNanos, skeleton, captureNanos, at) }
                )
            )
            upTo++
        }
        waiting.subList(0, upTo).clear()
        anchor = skeleton
        anchorNanos = captureNanos
        return pace(released)
    }

    /**
     * Schedules [released] one capture gap apart, a little less so a late picture catches up,
     * never sooner than now, and returns the ones due already.
     */
    private fun pace(released: List<Released>): List<Released> {
        val now = nowNanos()
        for (r in released) {
            val at = if (!pacing) {
                now
            } else {
                val gap = r.captureNanos - lastPacedCaptureNanos
                maxOf(now, lastPacedAtNanos + gap - gap / CATCH_UP_DIVISOR)
            }
            paced.addLast(Paced(r, at))
            pacing = true
            lastPacedAtNanos = at
            lastPacedCaptureNanos = r.captureNanos
        }
        return pacedDue(now)
    }

    private fun pacedDue(now: Long): List<Released> {
        if (paced.isEmpty() || paced.first().showAtNanos > now) return emptyList()
        val due = ArrayList<Released>()
        while (paced.isNotEmpty() && paced.first().showAtNanos <= now) due.add(paced.removeFirst().frame)
        return due
    }

    private fun flushPaced(): List<Released> {
        val all = paced.map { it.frame }
        paced.clear()
        pacing = false
        return all
    }

    /**
     * The paced frames whose turn has come, and, without a skeleton, every frame that has waited
     * as long as the cap allows.
     */
    fun due(): List<Released> {
        val limit = nowNanos() - CAP_NANOS
        var expired = 0
        // Oldest first, and knownAt only grows, so the expired frames are a prefix.
        while (expired < waiting.size && waiting[expired].knownAtNanos <= limit) expired++
        if (expired == 0) return pacedDue(nowNanos())
        // The paced frames are older than any still waiting, so they go first, at once.
        val released = flushPaced() + waiting.subList(0, expired).map { Released(it.captureNanos, null) }
        cappedCount += expired
        waiting.subList(0, expired).clear()
        // The skeletons stopped coming, so the last one is no end of an interpolation.
        anchor = null
        return released
    }

    /**
     * The effect no longer holds the frame stamped [captureNanos], so it can never be shown.
     * It stops waiting at once rather than sitting out the cap.
     */
    fun frameLost(captureNanos: Long) {
        waiting.removeAll { it.captureNanos == captureNanos }
        droppedCount++
    }

    /** Every waiting frame, without a skeleton: a lens flip, a pause, leaving the screen. */
    fun releaseAll(): List<Released> {
        val released = flushPaced() + waiting.map { Released(it.captureNanos, null) }
        waiting.clear()
        // After a lens flip the old skeleton is of another picture, so nothing is drawn from it.
        anchor = null
        return released
    }

    /** Switches mode without a restart. Whatever was waiting is released, never carried over. */
    fun setMode(next: Mode): List<Released> {
        if (next == mode) return emptyList()
        mode = next
        return releaseAll()
    }

    private fun between(
        from: SyncSkeleton, fromNanos: Long, to: SyncSkeleton, toNanos: Long, at: Long
    ): SyncSkeleton {
        val t = if (toNanos == fromNanos) 1f else
            ((at - fromNanos).toDouble() / (toNanos - fromNanos)).toFloat().coerceIn(0f, 1f)
        val joints = Array(from.keypoints.size) { i ->
            val a = from.keypoints[i]
            val b = to.keypoints[i]
            Keypoint(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, minOf(a.score, b.score))
        }
        return SyncSkeleton(joints, from.width, from.height, from.mirrored, from.guide)
    }

    /** When the oldest waiting frame hits the cap, on the clock this was built with. */
    fun nextDeadlineNanos(): Long? {
        val cap = waiting.firstOrNull()?.let { it.knownAtNanos + CAP_NANOS }
        val turn = paced.firstOrNull()?.showAtNanos
        return if (cap == null) turn else if (turn == null) cap else minOf(cap, turn)
    }

    companion object {
        const val DEFAULT_CAPACITY = 8

        /** The longest a frame waits for its skeleton before it is shown without one. */
        const val CAP_MS = 250L

        /** A paced frame follows the one before it this fraction of its capture gap sooner. */
        private const val CATCH_UP_DIVISOR = 8L
        private const val CAP_NANOS = CAP_MS * 1_000_000L
    }
}
