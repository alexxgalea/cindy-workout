package com.cindy.tracker

import com.cindy.tracker.LockFixtures.hanging
import com.cindy.tracker.LockFixtures.jointMoved
import com.cindy.tracker.LockFixtures.moved
import com.cindy.tracker.LockFixtures.scaled
import com.cindy.tracker.LockFixtures.standing
import com.cindy.tracker.LockFixtures.withScore
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The identity lock's rules, on synthetic bodies. Fixture bodies have a 100 px torso, so a move of
 * 70 px is 0.7 torso lengths.
 */
class AthleteLockTest {

    private var clock = 1_000L
    private val pull = LockContext(Exercise.PULLUP, 480, 640)
    private val squat = LockContext(Exercise.SQUAT, 480, 640)

    private fun AthleteLock.feed(
        pose: Array<Keypoint>,
        ctx: LockContext = pull,
        probes: List<Array<Keypoint>> = emptyList(),
        frames: Int = 1,
        stepMs: Long = 66
    ): Verdict {
        var v = Verdict.UNCERTAIN
        repeat(frames) {
            v = onFrame(pose, probes, clock, ctx)
            clock += stepMs
        }
        return v
    }

    /** A lock that has already acquired and confirmed [pose]. */
    private fun lockedOn(pose: Array<Keypoint>, ctx: LockContext = pull, predict: Boolean = false): AthleteLock {
        val lock = AthleteLock(predict)
        lock.beginAcquiring(clock)
        lock.feed(pose, ctx, frames = 3)
        lock.confirm(clock)
        assertEquals(LockState.LOCKED, lock.state)
        return lock
    }

    // ── continuity ───────────────────────────────────────────────────────────

    @Test
    fun `motion up to 0_7 torso per frame is confirmed, with or without prediction`() {
        for (predict in listOf(true, false)) {
            val lock = lockedOn(hanging(), predict = predict)
            var x = 0f
            repeat(20) {
                x += 70f
                assertEquals("predict=$predict step $it", Verdict.CONFIRMED, lock.feed(hanging().moved(x, 0f)))
            }
        }
    }

    @Test
    fun `a one-torso jump and a 1_6x scale jump are refused`() {
        val lock = lockedOn(hanging())
        lock.feed(hanging(), frames = 5)
        assertEquals(Verdict.REFUSED, lock.feed(hanging().moved(100f, 0f)))
        assertEquals("jump", lock.reason)

        val scaled = lockedOn(hanging())
        scaled.feed(hanging(), frames = 5)
        assertEquals(Verdict.REFUSED, scaled.feed(hanging().scaled(1.6f)))
        assertEquals("scale", scaled.reason)
    }

    @Test
    fun `a consistent partial torso is confirmed, one far torso joint is refused, no torso is uncertain`() {
        val lock = lockedOn(hanging())
        lock.feed(hanging(), frames = 5)
        val oneHipHidden = hanging().withScore(0f, KP.LEFT_HIP)
        assertEquals(Verdict.CONFIRMED, lock.feed(oneHipHidden))
        assertEquals("partial-ok", lock.reason)

        val farHip = hanging().withScore(0f, KP.LEFT_HIP).jointMoved(KP.RIGHT_HIP, 300f, 0f)
        assertEquals(Verdict.REFUSED, lock.feed(farHip))
        assertEquals("partial-far", lock.reason)

        val noHips = hanging().withScore(0f, KP.LEFT_HIP, KP.RIGHT_HIP)
        assertEquals(Verdict.UNCERTAIN, lock.feed(noHips))
    }

    @Test
    fun `refusals become LOST after a second and a half`() {
        val lock = lockedOn(hanging())
        val someoneElse = hanging().moved(300f, 0f)
        lock.feed(someoneElse, frames = 20, stepMs = 70) // 1.4 s
        assertEquals(LockState.LOCKED, lock.state)
        lock.feed(someoneElse, frames = 3, stepMs = 70)
        assertEquals(LockState.LOST, lock.state)
    }

    // ── acquisition ──────────────────────────────────────────────────────────

    @Test
    fun `a hanging candidate displaces a standing one after a second of out-ranking it`() {
        val lock = AthleteLock()
        lock.beginAcquiring(clock)
        val stander = standing().moved(240f, 300f)
        lock.feed(stander, frames = 3)
        assertEquals(Verdict.CONFIRMED, lock.verdict) // the first body found is followed
        val hanger = hanging().moved(100f, 100f)
        var switched = 0
        repeat(40) {
            lock.feed(stander, probes = listOf(hanger))
            if (lock.candidateChanged) switched++
        }
        assertEquals("exactly one switch", 1, switched)
        // Now the hanging body is followed, so it is the one confirmed.
        assertEquals(Verdict.CONFIRMED, lock.feed(hanger, probes = listOf(stander)))
        assertEquals(Verdict.REFUSED, lock.feed(stander, probes = listOf(hanger)))
    }

    @Test
    fun `a bigger standing candidate never displaces a hanging one`() {
        val lock = AthleteLock()
        lock.beginAcquiring(clock)
        val hanger = hanging().moved(100f, 100f)
        val bigStander = standing().scaled(1.4f).moved(300f, 300f)
        lock.feed(hanger, frames = 3)
        var switched = false
        repeat(60) {
            lock.feed(hanger, probes = listOf(bigStander))
            switched = switched || lock.candidateChanged
        }
        assertFalse(switched)
        assertEquals(Verdict.CONFIRMED, lock.verdict)
    }

    @Test
    fun `a calibrating candidate is not displaced`() {
        val lock = AthleteLock()
        lock.beginAcquiring(clock)
        val stander = standing().moved(240f, 300f)
        val hanger = hanging().moved(100f, 100f)
        val calibrating = pull.copy(calibrationReps = 1)
        lock.feed(stander, calibrating, frames = 3)
        assertEquals(LockState.CALIBRATING, lock.state)
        var switched = false
        repeat(60) {
            lock.feed(stander, calibrating, probes = listOf(hanger))
            switched = switched || lock.candidateChanged
        }
        assertFalse(switched)
    }

    @Test
    fun `two hanging candidates raise the ambiguity flag`() {
        val lock = AthleteLock()
        lock.beginAcquiring(clock)
        lock.feed(hanging().moved(80f, 100f), probes = listOf(hanging().moved(330f, 100f)))
        assertTrue(lock.ambiguous)
    }

    @Test
    fun `a candidate whose wrists are unseen is never hanging`() {
        // After SKIP nothing counts until someone holds the start position; blind wrists must not
        // pass for it, however long they are held.
        val lock = AthleteLock()
        lock.beginAcquiring(clock)
        val blindWrists = hanging().withScore(0f, KP.LEFT_WRIST, KP.RIGHT_WRIST)
        lock.feed(blindWrists, pull.copy(workoutRunning = true), frames = 40)
        assertEquals(LockState.ACQUIRING, lock.state)
        assertEquals(Verdict.REFUSED, lock.verdict)

        val noseHidden = hanging().withScore(0f, KP.NOSE) // wrists still well above the shoulders
        lock.feed(noseHidden, pull.copy(workoutRunning = true), frames = 10)
        assertEquals(LockState.LOCKED, lock.state)
    }

    // ── getting back ─────────────────────────────────────────────────────────

    @Test
    fun `re-acquisition takes the right scale at the station after a held start, and refuses rivals and wrong scales`() {
        val station = squat
        val athlete = standing().moved(240f, 300f)

        val lock = lockedOn(athlete, station)
        lock.feed(athlete, station, frames = 5)
        lock.lose(clock, clearStations = false)
        assertEquals(LockState.LOST, lock.state)
        lock.feed(athlete, station, frames = 5) // 330 ms held: not yet
        assertEquals(LockState.LOST, lock.state)
        lock.feed(athlete, station, frames = 5)
        assertEquals(LockState.LOCKED, lock.state)

        val rivalled = lockedOn(athlete, station)
        rivalled.feed(athlete, station, frames = 5)
        rivalled.lose(clock, clearStations = false)
        rivalled.feed(athlete, station, probes = listOf(athlete.moved(60f, 0f).moved(0f, 0f)), frames = 20)
        // A second qualifying body at the same station keeps the lock LOST.
        assertEquals(LockState.LOST, rivalled.state)
        assertTrue(rivalled.ambiguous)

        val wrongScale = lockedOn(athlete, station)
        wrongScale.feed(athlete, station, frames = 5)
        wrongScale.lose(clock, clearStations = false)
        wrongScale.feed(standing().scaled(1.8f).moved(240f, 300f), station, frames = 20)
        assertEquals(LockState.LOST, wrongScale.state)
    }

    @Test
    fun `after the phone moves, an athlete at a new distance is found again by a held start`() {
        val athlete = standing().moved(240f, 300f)
        val lock = lockedOn(athlete, squat)
        lock.feed(athlete, squat, frames = 5)
        lock.lose(clock, clearStations = true)
        val nearer = standing().scaled(1.8f).moved(240f, 200f)
        lock.feed(nearer, squat, frames = 10)
        assertEquals(LockState.LOCKED, lock.state)

        // Pausing does not move the phone: the same nearer body is not taken back then.
        val paused = lockedOn(athlete, squat)
        paused.feed(athlete, squat, frames = 5)
        paused.lose(clock, clearStations = false)
        paused.feed(nearer, squat, frames = 10)
        assertEquals(LockState.LOST, paused.state)
    }

    @Test
    fun `a clear refusal is remembered for two seconds, and a partial-torso refusal is not`() {
        val lock = lockedOn(hanging())
        lock.feed(hanging(), frames = 5)
        lock.feed(hanging(), probes = emptyList())
        val other = hanging().moved(300f, 0f)
        lock.onFrame(other, emptyList(), clock, pull)
        assertEquals(Verdict.REFUSED, lock.verdict)
        assertEquals(1, lock.knownOthers().size)
        clock += 66
        lock.feed(hanging(), frames = 1)
        clock += 2_100
        lock.feed(hanging(), frames = 1)
        assertEquals("expired after 2 s", 0, lock.knownOthers().size)

        val partial = lockedOn(hanging())
        partial.feed(hanging(), frames = 5)
        partial.feed(hanging().withScore(0f, KP.LEFT_HIP).jointMoved(KP.RIGHT_HIP, 300f, 0f))
        assertEquals(Verdict.REFUSED, partial.verdict)
        assertEquals(0, partial.knownOthers().size)
    }

    @Test
    fun `a known-other box never covers the athlete's predicted torso`() {
        val lock = lockedOn(hanging())
        lock.feed(hanging(), frames = 5)
        // A body refused by scale, standing right over the athlete.
        lock.feed(hanging().scaled(2f))
        assertEquals(Verdict.REFUSED, lock.verdict)
        assertEquals(0, lock.knownOthers().size)
    }

    @Test
    fun `second looks respect the one-in-three cap`() {
        val lock = lockedOn(hanging())
        lock.feed(hanging(), frames = 15)
        var wanted = 0
        val other = hanging().moved(300f, 0f)
        repeat(15) {
            lock.onFrame(if (it % 2 == 0) other else hanging(), emptyList(), clock, pull)
            if (lock.secondLookWanted) wanted++
            clock += 66
        }
        // 15 frames in one second: at most five second looks.
        assertTrue("wanted $wanted", wanted in 1..5)
    }

    @Test
    fun `a second look that passes is confirmed, and one that fails changes nothing`() {
        val lock = lockedOn(hanging())
        lock.feed(hanging(), frames = 5)
        lock.onFrame(hanging().moved(300f, 0f), emptyList(), clock, pull)
        assertTrue(lock.secondLookWanted)
        assertNotNull(lock.refusedBox)
        assertEquals(Verdict.CONFIRMED, lock.reconsider(hanging(), clock))
        assertEquals("second-look", lock.reason)
        clock += 66

        lock.onFrame(hanging().moved(300f, 0f), emptyList(), clock, pull)
        clock += 66
        lock.onFrame(hanging().moved(300f, 0f), emptyList(), clock, pull)
        clock += 66
        lock.onFrame(hanging().moved(300f, 0f), emptyList(), clock, pull)
        assertEquals(Verdict.REFUSED, lock.reconsider(hanging().moved(-300f, 0f), clock))
        // Nothing was learned from the failed look: the athlete's own pose is still confirmed.
        clock += 66
        assertEquals(Verdict.CONFIRMED, lock.feed(hanging()))
    }
}
