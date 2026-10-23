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
}
