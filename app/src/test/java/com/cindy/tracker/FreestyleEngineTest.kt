package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Freestyle counted by recognition (ADR 0010), through the engine's own inputs and outputs: a
 * frame at a time with its time, START, pause, resume, STOP, minus and plus in, the scoreboard's
 * readout, the voice, the banked reps and the filed session out. Poses are the shared fixtures.
 */
class FreestyleEngineTest {

    private val engine = FreestyleEngine().also { it.start(0L) }
    private var clock = 0L
    private var last: FreestyleFrame = engine.onFrame(PoseFixtures.empty(), clock)
    private val events = mutableListOf<FreestyleEvent>()
    private val said = mutableListOf<FreestyleVoice>()

    private fun hold(pose: Array<Keypoint>, forMs: Long = 1_000, stable: Boolean = true) {
        repeat((forMs / 100).toInt()) {
            clock += 100
            last = engine.onFrame(pose, clock, stable)
            events += last.events
            said += last.voice
        }
    }

    private fun squatRep() {
        hold(PoseFixtures.squat(80f))
        hold(PoseFixtures.squat(175f))
    }

    private fun pushupRep() {
        hold(PoseFixtures.pushup(80f))
        hold(PoseFixtures.pushup(175f))
    }

    private fun banked() = events.filterIsInstance<FreestyleEvent.Banked>().sumOf { it.reps }

    @Test
    fun `a lone first rep shows and banks nothing`() {
        hold(PoseFixtures.pushup(175f))
        pushupRep()
        assertEquals(0, last.readout.figure)
        assertNull(last.readout.movement)
        assertEquals("Freestyle · Count up", last.readout.line)
        assertEquals(0, banked())
        assertTrue(said.isEmpty())
    }

    @Test
    fun `the 2nd rep confirms the movement with 2 banked`() {
        hold(PoseFixtures.pushup(175f))
        repeat(2) { pushupRep() }
        assertEquals(Movement.PUSH_UPS, last.readout.movement)
        assertEquals(2, last.readout.figure)
        assertEquals("PUSH-UPS · 2 total", last.readout.line)
        assertEquals(2, banked())
        assertEquals(listOf(FreestyleEvent.Banked(Movement.PUSH_UPS, reps = 2, figure = 2, total = 2)),
            events.filterIsInstance<FreestyleEvent.Banked>())
        assertEquals(listOf<FreestyleVoice>(FreestyleVoice.Confirmed(Movement.PUSH_UPS, 2)), said)
        pushupRep()
        assertEquals(3, last.readout.figure)
        assertEquals(FreestyleVoice.Count(3), said.last())
    }

    @Test
    fun `the figure is kept through a rest inside one movement`() {
        hold(PoseFixtures.pushup(175f))
        repeat(3) { pushupRep() }
        hold(PoseFixtures.kneelingUp(ankleBehind = 100f), forMs = 4_000)
        assertEquals(3, last.readout.figure)
        hold(PoseFixtures.pushup(175f))
        pushupRep()
        assertEquals(4, last.readout.figure)
        assertEquals("PUSH-UPS · 4 total", last.readout.line)
    }

    @Test
    fun `the figure resets only on a new movement, and the total stays`() {
        hold(PoseFixtures.pushup(175f))
        repeat(3) { pushupRep() }
        hold(PoseFixtures.squat(175f), forMs = 2_000)
        assertEquals("a stray position changes nothing", 3, last.readout.figure)
        squatRep()
        assertEquals(3, last.readout.figure)
        squatRep()
        assertEquals(Movement.SQUATS, last.readout.movement)
        assertEquals(2, last.readout.figure)
        assertEquals("SQUATS · 2 total", last.readout.line)
        assertEquals(5, banked())
    }

    @Test
    fun `a return to a recognised movement counts at once`() {
        hold(PoseFixtures.pushup(175f))
        repeat(2) { pushupRep() }
        hold(PoseFixtures.squat(175f), forMs = 3_000)
        hold(PoseFixtures.pushup(175f), forMs = 2_000)
        pushupRep()
        assertEquals(3, last.readout.figure)
        assertEquals(3, banked())
    }

    @Test
    fun `minus and plus are dimmed before the first confirmation`() {
        assertFalse(last.readout.adjustable)
        hold(PoseFixtures.pushup(175f))
        pushupRep()
        assertFalse(last.readout.adjustable)
        assertNull(engine.plus(clock))
        assertNull(engine.minus(clock))
        assertEquals(0, engine.current().figure)
    }

    @Test
    fun `minus and plus act on the recognised movement after it`() {
        hold(PoseFixtures.pushup(175f))
        repeat(2) { pushupRep() }
        assertTrue(last.readout.adjustable)
        val plus = engine.plus(clock)!!
        assertEquals(3, plus.readout.figure)
        assertEquals("PUSH-UPS · 3 total", plus.readout.line)
        assertEquals(FreestyleVoice.Count(3), plus.voice.single())
        val minus = engine.minus(clock)!!
        assertEquals(2, minus.readout.figure)
        assertEquals("PUSH-UPS · 2 total", minus.readout.line)
        val filed = engine.stop(clock)!!
        assertEquals(mapOf(Exercise.PUSHUP to 2), filed.totals)
        assertEquals(0, filed.manualReps)
    }

    @Test
    fun `STOP files the sets derived from when the reps banked`() {
        hold(PoseFixtures.pushup(175f))
        repeat(2) { pushupRep() }
        hold(PoseFixtures.squat(175f), forMs = 2_000)
        repeat(2) { squatRep() }
        val filed = engine.stop(clock)!!
        assertEquals(listOf(Exercise.PUSHUP, Exercise.SQUAT), filed.sets.map { it.movement })
        assertEquals(filed.totals, filed.sets.groupBy { it.movement }.mapValues { (_, s) -> s.sumOf { it.reps } })
        assertEquals(FreestyleSets.derive(filed.marks).sets, filed.sets)
    }

    @Test
    fun `zero reps files nothing`() {
        hold(PoseFixtures.pushup(175f))
        pushupRep()
        assertNull(engine.stop(clock))
    }

    @Test
    fun `STOP files the clock time and the totals per movement, pauses left out`() {
        hold(PoseFixtures.pushup(175f))
        repeat(2) { pushupRep() }
        engine.pause(clock)
        clock += 5_000
        engine.resume(clock)
        hold(PoseFixtures.squat(175f), forMs = 2_000)
        repeat(2) { squatRep() }
        val filed = engine.stop(clock)
        assertNotNull(filed)
        assertEquals(mapOf(Exercise.PUSHUP to 2, Exercise.SQUAT to 2), filed!!.totals)
        assertEquals(5_000L, filed.pausedMs)
        assertEquals(clock - 5_000L, filed.durationMs)
        assertEquals(4, filed.marks.size)
        assertEquals(listOf(Exercise.PUSHUP, Exercise.PUSHUP, Exercise.SQUAT, Exercise.SQUAT), filed.marks.map { it.movement })
    }

    @Test
    fun `frames while paused count nothing`() {
        hold(PoseFixtures.pushup(175f))
        repeat(2) { pushupRep() }
        engine.pause(clock)
        pushupRep()
        engine.resume(clock)
        assertEquals(2, engine.current().figure)
    }

    private fun Array<Keypoint>.moved(dx: Float, dy: Float): Array<Keypoint> =
        Array(size) { k -> if (this[k].score <= 0f) this[k] else Keypoint(this[k].x + dx, this[k].y + dy, this[k].score) }

    private fun pullupRep(dy: Float) {
        hold(PoseFixtures.pullup(170f).moved(0f, dy))
        hold(PoseFixtures.pullup(60f).moved(0f, dy))
    }

    @Test
    fun `a moved camera is recalibrated, so the bar learned in the old framing stops refusing reps`() {
        hold(PoseFixtures.pullup(170f))
        repeat(3) { pullupRep(0f) }
        val before = banked()
        assertEquals(3, before)
        // The whole scene shifts, as when the phone is knocked: the old bar is where nobody hangs.
        engine.recalibrate()
        hold(PoseFixtures.pullup(170f).moved(0f, 400f))
        pullupRep(400f)
        assertTrue("the new framing must count: banked ${banked()}", banked() > before)
    }

    @Test
    fun `without recalibrating the old bar refuses the moved framing, which is what recalibrating cures`() {
        hold(PoseFixtures.pullup(170f))
        repeat(3) { pullupRep(0f) }
        val before = banked()
        hold(PoseFixtures.pullup(170f).moved(0f, 400f))
        pullupRep(400f)
        assertEquals(before, banked())
    }

    @Test
    fun `recalibrating keeps what is banked and the movement shown`() {
        hold(PoseFixtures.pushup(175f))
        repeat(3) { pushupRep() }
        engine.recalibrate()
        assertEquals(3, engine.current().figure)
        assertEquals(Movement.PUSH_UPS, engine.current().movement)
        assertEquals(3, engine.totalReps())
    }
}
