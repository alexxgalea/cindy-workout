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

    var mode: Mode = mode
        private set

    /** Waiting frames, oldest first. */
    private val waiting = ArrayList<Waiting>()

    private var newest: SyncSkeleton? = null

    /** The last real skeleton released, with its capture stamp: the earlier end of an interpolation. */
    private var anchorNanos = 0L
    private var anchor: SyncSkeleton? = null

    /** Frames the cap released without their skeleton, for the latency readout. */
    var cappedCount = 0
        private set

    /** Frames that will never be shown: pushed out by capacity, passed over, or gone from the effect. */
    var droppedCount = 0
        private set

    /** A picture frame the model is about to analyse, or in live mode, any frame at all. */
    fun frameKnown(captureNanos: Long): List<Released> {
        if (mode == Mode.LIVE) return listOf(Released(captureNanos, newest))
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
        val index = waiting.indexOfFirst { it.captureNanos == captureNanos }
        if (index < 0) return emptyList()
        if (mode == Mode.EVERY_FRAME) return releaseThrough(index, captureNanos, skeleton)
        // Showing a frame discards every older one the picture still holds, so an older frame
        // still waiting is gone either way. Dropping it here keeps the order strict.
        droppedCount += index
        waiting.subList(0, index + 1).clear()
        return listOf(Released(captureNanos, skeleton))
    }

    /** Frames up to and including [index], in capture order, the ones before it interpolated. */
    private fun releaseThrough(index: Int, captureNanos: Long, skeleton: SyncSkeleton): List<Released> {
        val earlier = anchor
        val released = ArrayList<Released>(index + 1)
        for (i in 0 until index) {
            val at = waiting[i].captureNanos
            released.add(Released(at, earlier?.let { between(it, anchorNanos, skeleton, captureNanos, at) }))
        }
        released.add(Released(captureNanos, skeleton))
        waiting.subList(0, index + 1).clear()
        anchor = skeleton
        anchorNanos = captureNanos
        return released
    }

    /** Releases, without a skeleton, every frame that has waited as long as the cap allows. */
    fun due(): List<Released> {
        val limit = nowNanos() - CAP_NANOS
        var expired = 0
        // Oldest first, and knownAt only grows, so the expired frames are a prefix.
        while (expired < waiting.size && waiting[expired].knownAtNanos <= limit) expired++
        if (expired == 0) return emptyList()
        val released = waiting.subList(0, expired).map { Released(it.captureNanos, null) }
        waiting.subList(0, expired).clear()
        cappedCount += released.size
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
        val released = waiting.map { Released(it.captureNanos, null) }
        waiting.clear()
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
    fun nextDeadlineNanos(): Long? = waiting.firstOrNull()?.let { it.knownAtNanos + CAP_NANOS }

    companion object {
        const val DEFAULT_CAPACITY = 8

        /** The longest a frame waits for its skeleton before it is shown without one. */
        const val CAP_MS = 250L
        private const val CAP_NANOS = CAP_MS * 1_000_000L
    }
}
