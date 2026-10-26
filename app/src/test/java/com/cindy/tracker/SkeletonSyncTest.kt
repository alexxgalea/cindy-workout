package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * What the picture shows, when, and with which skeleton.
 *
 * Every test drives [SkeletonSync] through its public calls with a clock the test owns, and
 * asserts only what comes out: which frames are released, in what order, carrying which skeleton.
 * Camera timestamps are arbitrary numbers here on purpose. They are only ever compared with each
 * other, never with the clock, so they sit on a completely different scale.
 */
class SkeletonSyncTest {

    private val ms = 1_000_000L

    /** The test's monotonic clock, in nanoseconds. */
    private var now = 5_000L * ms

    private fun advance(millis: Long) {
        now += millis * ms
    }

    private fun sync(
        mode: SkeletonSync.Mode = SkeletonSync.Mode.ANALYSED_ONLY,
        capacity: Int = 8
    ) = SkeletonSync(mode, capacity) { now }

    /** A frame's capture stamp. Thirty-three milliseconds apart, as a 30 fps camera would. */
    private fun stamp(frame: Int) = 90_000_000_000L + frame * 33L * ms

    private fun skeleton(pose: Array<Keypoint> = PoseFixtures.pullup(90f)) =
        SyncSkeleton(pose, 480, 640, mirrored = false, guide = null)

    private fun List<SkeletonSync.Released>.stamps() = map { it.captureNanos }

    @Test
    fun `a frame is released with exactly the skeleton computed from it`() {
        val s = sync()
        val own = skeleton(PoseFixtures.pullup(90f))
        assertTrue(s.frameKnown(stamp(1)).isEmpty())

        val shown = s.skeletonReady(stamp(1), own)

        assertEquals(listOf(stamp(1)), shown.stamps())
        assertSame(own, shown.single().skeleton)
    }

    @Test
    fun `a frame is never shown with the skeleton of another frame`() {
        val s = sync()
        val first = skeleton(PoseFixtures.pullup(150f))
        val second = skeleton(PoseFixtures.pullup(60f))
        s.frameKnown(stamp(1))
        s.frameKnown(stamp(2))

        val shownSecond = s.skeletonReady(stamp(2), second)

        assertSame(second, shownSecond.single().skeleton)
        assertTrue(s.skeletonReady(stamp(1), first).isEmpty())
    }

    @Test
    fun `frames are released strictly in capture order`() {
        val s = sync()
        for (f in 1..4) s.frameKnown(stamp(f))

        val shown = listOf(1, 2, 4, 3).flatMap { s.skeletonReady(stamp(it), skeleton()) }

        assertEquals(listOf(stamp(1), stamp(2), stamp(4)), shown.stamps())
    }

    @Test
    fun `a skeleton for a frame the sync never heard of shows nothing`() {
        val s = sync()

        assertTrue(s.skeletonReady(stamp(7), skeleton()).isEmpty())
    }

    @Test
    fun `in live mode every frame is released at once`() {
        val s = sync(SkeletonSync.Mode.LIVE)

        val first = s.frameKnown(stamp(1))
        val second = s.frameKnown(stamp(2))

        assertEquals(listOf(stamp(1)), first.stamps())
        assertEquals(listOf(stamp(2)), second.stamps())
    }

    @Test
    fun `in live mode a frame carries the newest skeleton there is`() {
        val s = sync(SkeletonSync.Mode.LIVE)
        val newest = skeleton()
        s.frameKnown(stamp(1))
        s.skeletonReady(stamp(1), newest)

        assertSame(newest, s.frameKnown(stamp(2)).single().skeleton)
    }

    @Test
    fun `a frame still without a skeleton 250 ms after it became known is released without one`() {
        val s = sync()
        s.frameKnown(stamp(1))

        advance(249)
        assertTrue(s.due().isEmpty())
        advance(1)
        val shown = s.due()

        assertEquals(listOf(stamp(1)), shown.stamps())
        assertNull(shown.single().skeleton)
    }

    @Test
    fun `the cap counts from when the app learned of the frame, not from its capture stamp`() {
        val s = sync()
        // A stamp on a wildly different scale from the clock must change nothing.
        val farAway = Long.MAX_VALUE / 2
        s.frameKnown(farAway)

        advance(250)

        assertEquals(listOf(farAway), s.due().stamps())
    }

    @Test
    fun `in analysed only mode a frame is not released without its skeleton before the cap`() {
        val s = sync()
        s.frameKnown(stamp(1))
        s.frameKnown(stamp(2))

        advance(100)

        assertTrue(s.due().isEmpty())
    }

    @Test
    fun `frames that time out are released in capture order`() {
        val s = sync()
        s.frameKnown(stamp(1))
        advance(100)
        s.frameKnown(stamp(2))
        advance(150)
        assertEquals(listOf(stamp(1)), s.due().stamps())
        advance(100)
        assertEquals(listOf(stamp(2)), s.due().stamps())
    }

    @Test
    fun `a skeleton that arrives after its frame timed out shows nothing more`() {
        val s = sync()
        s.frameKnown(stamp(1))
        advance(250)
        s.due()

        assertTrue(s.skeletonReady(stamp(1), skeleton()).isEmpty())
    }

    @Test
    fun `the wait reports how many frames the cap released`() {
        val s = sync()
        s.frameKnown(stamp(1))
        s.frameKnown(stamp(2))
        s.skeletonReady(stamp(2), skeleton())
        s.frameKnown(stamp(3))
        advance(250)
        s.due()

        // Frame 1 was superseded, not capped; only frame 3 timed out.
        assertEquals(1, s.cappedCount)
    }

    @Test
    fun `it says when the next frame will time out`() {
        val s = sync()
        assertNull(s.nextDeadlineNanos())
        s.frameKnown(stamp(1))
        val known = now
        advance(40)
        s.frameKnown(stamp(2))

        assertEquals(known + 250 * ms, s.nextDeadlineNanos())
    }

    @Test
    fun `the wait never exceeds its capacity and the oldest frame goes first`() {
        val s = sync(capacity = 3)
        for (f in 1..5) s.frameKnown(stamp(f))

        // Frames 1 and 2 were pushed out. Their skeletons find nothing to show.
        assertTrue(s.skeletonReady(stamp(1), skeleton()).isEmpty())
        assertTrue(s.skeletonReady(stamp(2), skeleton()).isEmpty())
        assertEquals(listOf(stamp(3)), s.skeletonReady(stamp(3), skeleton()).stamps())
        // Frame 3 shown, so the wait is down to frames 4 and 5, and the cap releases both.
        advance(250)
        assertEquals(listOf(stamp(4), stamp(5)), s.due().stamps())
    }

    @Test
    fun `a frame pushed out by capacity is dropped, not shown without a skeleton`() {
        val s = sync(capacity = 2)

        val shown = (1..4).flatMap { s.frameKnown(stamp(it)) }

        assertTrue(shown.isEmpty())
        assertEquals(2, s.droppedCount)
    }

    @Test
    fun `releasing everything shows every waiting frame without a skeleton and empties the wait`() {
        val s = sync()
        for (f in 1..3) s.frameKnown(stamp(f))

        val shown = s.releaseAll()

        assertEquals(listOf(stamp(1), stamp(2), stamp(3)), shown.stamps())
        assertTrue(shown.all { it.skeleton == null })
        assertNull(s.nextDeadlineNanos())
        advance(500)
        assertTrue(s.due().isEmpty())
        assertTrue(s.skeletonReady(stamp(2), skeleton()).isEmpty())
    }

    @Test
    fun `a frame the effect no longer holds is counted as dropped and never waits for the cap`() {
        val s = sync()
        s.frameKnown(stamp(1))
        s.frameKnown(stamp(2))

        s.frameLost(stamp(1))
        advance(250)

        assertEquals(1, s.droppedCount)
        assertEquals(listOf(stamp(2)), s.due().stamps())
        assertTrue(s.skeletonReady(stamp(1), skeleton()).isEmpty())
    }

    @Test
    fun `switching to live mode releases what was waiting`() {
        val s = sync()
        s.frameKnown(stamp(1))

        val shown = s.setMode(SkeletonSync.Mode.LIVE)

        assertEquals(listOf(stamp(1)), shown.stamps())
        assertEquals(listOf(stamp(2)), s.frameKnown(stamp(2)).stamps())
    }

    @Test
    fun `switching back to analysed only starts a fresh wait`() {
        val s = sync(SkeletonSync.Mode.LIVE)
        s.frameKnown(stamp(1))
        s.setMode(SkeletonSync.Mode.ANALYSED_ONLY)

        assertTrue(s.frameKnown(stamp(2)).isEmpty())
        assertEquals(listOf(stamp(2)), s.skeletonReady(stamp(2), skeleton()).stamps())
    }

    @Test
    fun `a long run keeps the delay between a frame becoming known and shown constant`() {
        val s = sync()
        val delays = ArrayList<Long>()
        val knownAt = HashMap<Long, Long>()
        // The model takes 70 ms a frame, sees every other camera frame, and its skeleton for
        // frame n arrives while frame n+2 is already known.
        for (f in 0 until 2_000 step 2) {
            knownAt[stamp(f)] = now
            s.frameKnown(stamp(f))
            advance(66)
            s.skeletonReady(stamp(f), skeleton()).forEach { delays += (now - knownAt.getValue(it.captureNanos)) / ms }
            s.due()
        }

        assertEquals(1, delays.toSet().size)
        assertEquals(1_000, delays.size)
    }

    @Test
    fun `a frame passed over by a newer one is counted as dropped`() {
        val s = sync()
        s.frameKnown(stamp(1))
        s.frameKnown(stamp(2))

        s.skeletonReady(stamp(2), skeleton())

        assertEquals(1, s.droppedCount)
    }

    // ---- every frame: in-between frames wait, then show an interpolated skeleton ----

    private fun everyFrame() = sync(SkeletonSync.Mode.EVERY_FRAME)

    /** A skeleton whose every joint sits at ([x], [x]) and is fully seen. */
    private fun at(x: Float, score: Float = 0.9f) =
        SyncSkeleton(Array(17) { Keypoint(x, x, score) }, 480, 640, mirrored = false, guide = null)

    @Test
    fun `a frame between two analysed frames waits for the next skeleton and is shown halfway between`() {
        val s = everyFrame()
        s.frameKnown(stamp(0))
        s.skeletonReady(stamp(0), at(100f))
        s.frameKnown(stamp(1))
        s.frameKnown(stamp(2))
        assertTrue(s.frameKnown(stamp(3)).isEmpty())

        val shown = s.skeletonReady(stamp(3), at(130f))

        assertEquals(listOf(stamp(1), stamp(2), stamp(3)), shown.stamps())
        assertEquals(110f, shown[0].skeleton!!.keypoints[0].x, 0.001f)
        assertEquals(120f, shown[1].skeleton!!.keypoints[0].x, 0.001f)
        assertEquals(130f, shown[2].skeleton!!.keypoints[0].x, 0.001f)
    }

    private fun withJoint0(score: Float, x: Float) = SyncSkeleton(
        Array(17) { Keypoint(x, x, if (it == 0) score else 0.9f) }, 480, 640, mirrored = false, guide = null
    )

    @Test
    fun `a joint unseen in either neighbour is not drawn on the frames between them`() {
        for ((first, second) in listOf(0.1f to 0.9f, 0.9f to 0.1f)) {
            val s = everyFrame()
            s.frameKnown(stamp(0))
            s.skeletonReady(stamp(0), withJoint0(first, 100f))
            s.frameKnown(stamp(1))
            s.frameKnown(stamp(2))

            val shown = s.skeletonReady(stamp(2), withJoint0(second, 120f))

            assertTrue(shown[0].skeleton!!.keypoints[0].score < PoseGeometry.MIN_SCORE)
            assertTrue(shown[0].skeleton!!.keypoints[1].score >= PoseGeometry.MIN_SCORE)
            assertEquals(second, shown[1].skeleton!!.keypoints[0].score, 0f)
        }
    }

    @Test
    fun `the bar zone on a frame between is the earlier neighbours`() {
        val s = everyFrame()
        val earlier = WorkoutEngine.BarGuide(BarZone.Bounds(10f, 0f, 50f, 5f, 15f), 20f, true)
        val later = WorkoutEngine.BarGuide(BarZone.Bounds(30f, 0f, 50f, 25f, 35f), 40f, false)
        s.frameKnown(stamp(0))
        s.skeletonReady(stamp(0), SyncSkeleton(at(100f).keypoints, 480, 640, false, earlier))
        s.frameKnown(stamp(1))
        s.frameKnown(stamp(2))

        val shown = s.skeletonReady(stamp(2), SyncSkeleton(at(130f).keypoints, 480, 640, false, later))

        assertSame(earlier, shown[0].skeleton!!.guide)
        assertSame(later, shown[1].skeleton!!.guide)
    }

    @Test
    fun `an interpolated joint never passes the newer position`() {
        val s = everyFrame()
        s.frameKnown(stamp(0))
        s.skeletonReady(stamp(0), at(100f))
        for (f in 1..5) s.frameKnown(stamp(f))

        val shown = s.skeletonReady(stamp(5), at(70f))

        for (r in shown) assertTrue(r.skeleton!!.keypoints[0].x in 70f..100f)
        assertEquals(70f, shown.last().skeleton!!.keypoints[0].x, 0f)
    }

    @Test
    fun `frames before any skeleton exists are shown bare, and the same after a release`() {
        val s = everyFrame()
        s.frameKnown(stamp(0))
        s.frameKnown(stamp(1))
        val first = s.skeletonReady(stamp(1), at(100f))
        assertNull(first[0].skeleton)
        assertEquals(100f, first[1].skeleton!!.keypoints[0].x, 0f)

        s.releaseAll()
        s.frameKnown(stamp(2))
        s.frameKnown(stamp(3))
        val after = s.skeletonReady(stamp(3), at(130f))
        assertNull(after[0].skeleton)
    }

    @Test
    fun `a frame whose next skeleton never arrives is shown bare when the cap fires`() {
        val s = everyFrame()
        s.frameKnown(stamp(0))
        s.skeletonReady(stamp(0), at(100f))
        s.frameKnown(stamp(1))
        advance(SkeletonSync.CAP_MS - 1)
        assertTrue(s.due().isEmpty())
        advance(1)

        val shown = s.due()

        assertEquals(listOf(stamp(1)), shown.stamps())
        assertNull(shown.single().skeleton)
    }

    @Test
    fun `at 30 fps with a skeleton every sixth frame the picture delay stays constant for minutes`() {
        val s = everyFrame()
        val frameMs = 33L
        val analysisEvery = 6
        val analysisMs = 150L
        // The wall time each frame was captured at, and when it was shown.
        val delays = ArrayList<Long>()
        val shownAt = HashMap<Long, Long>()
        val capturedAt = HashMap<Long, Long>()
        val start = now
        val frames = 30 * 180
        for (f in 0 until frames) {
            now = start + f * frameMs * ms
            capturedAt[stamp(f)] = now
            s.frameKnown(stamp(f))
            if (f % analysisEvery == 0) {
                // The skeleton of this frame is ready after the analysis time.
                val readyAt = now + analysisMs * ms
                now = readyAt
                for (r in s.skeletonReady(stamp(f), at(f.toFloat()))) shownAt[r.captureNanos] = now
                now = start + f * frameMs * ms
            }
        }
        for (f in 0 until frames) {
            val shown = shownAt[stamp(f)] ?: continue
            delays.add((shown - capturedAt.getValue(stamp(f))) / ms)
        }
        val firstMinute = delays.take(30 * 60 / analysisEvery * analysisEvery).max()
        val lastMinute = delays.takeLast(30 * 60).max()
        assertEquals(firstMinute, lastMinute)
        assertTrue(lastMinute <= analysisMs + analysisEvery * frameMs)
    }
}
