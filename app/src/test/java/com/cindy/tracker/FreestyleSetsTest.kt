package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Test

/** Set derivation from known sequences of rep times. Pure: marks in, sets and gaps out. */
class FreestyleSetsTest {

    private fun marks(movement: Exercise, vararg seconds: Int) =
        seconds.map { RepMark(it * 1000L, movement, manual = false) }

    @Test
    fun `no marks give no sets and no gaps`() {
        val d = FreestyleSets.derive(emptyList())
        assertEquals(emptyList<FreestyleSet>(), d.sets)
        assertEquals(emptyList<FreestyleGap>(), d.gaps)
    }

    @Test
    fun `reps of one movement close together are one set`() {
        val d = FreestyleSets.derive(marks(Exercise.SQUAT, 10, 12, 14, 16))
        assertEquals(listOf(FreestyleSet(Exercise.SQUAT, 4, 10_000L, 16_000L)), d.sets)
        assertEquals(6_000L, d.sets.single().lengthMs)
        assertEquals(emptyList<FreestyleGap>(), d.gaps)
    }

    @Test
    fun `a short gap inside one movement does not end the set`() {
        // 8 s, under the threshold.
        val d = FreestyleSets.derive(marks(Exercise.PUSHUP, 10, 12, 20, 22))
        assertEquals(1, d.sets.size)
        assertEquals(4, d.sets.single().reps)
    }

    @Test
    fun `a gap of exactly the threshold does not end the set, one past it does`() {
        val t = FreestyleSets.REST_THRESHOLD_MS
        fun sets(gap: Long) = FreestyleSets.derive(
            listOf(RepMark(0, Exercise.SQUAT, false), RepMark(gap, Exercise.SQUAT, false))
        ).sets.size
        assertEquals(1, sets(t))
        assertEquals(2, sets(t + 1))
    }

    @Test
    fun `a movement repeated after a long gap is a second set with a Rest between`() {
        val d = FreestyleSets.derive(marks(Exercise.SQUAT, 10, 12, 14, 40, 42))
        assertEquals(
            listOf(
                FreestyleSet(Exercise.SQUAT, 3, 10_000L, 14_000L),
                FreestyleSet(Exercise.SQUAT, 2, 40_000L, 42_000L)
            ),
            d.sets
        )
        assertEquals(listOf(FreestyleGap(GapKind.REST, 14_000L, 40_000L)), d.gaps)
        assertEquals(26_000L, d.gaps.single().lengthMs)
    }

    @Test
    fun `a change of movement is a Transition however short the gap`() {
        val d = FreestyleSets.derive(
            marks(Exercise.PUSHUP, 10, 12) + marks(Exercise.SQUAT, 14, 16)
        )
        assertEquals(listOf(Exercise.PUSHUP, Exercise.SQUAT), d.sets.map { it.movement })
        assertEquals(listOf(FreestyleGap(GapKind.TRANSITION, 12_000L, 14_000L)), d.gaps)
    }

    @Test
    fun `a mixed session gives its sets and gaps in order`() {
        val d = FreestyleSets.derive(
            marks(Exercise.SQUAT, 5, 7) + marks(Exercise.PULLUP, 30, 33) +
                marks(Exercise.PULLUP, 60) + marks(Exercise.PUSHUP, 65)
        )
        assertEquals(
            listOf(GapKind.TRANSITION, GapKind.REST, GapKind.TRANSITION), d.gaps.map { it.kind }
        )
        assertEquals(listOf(2, 2, 1, 1), d.sets.map { it.reps })
    }

    @Test
    fun `marks out of time order are read in time order`() {
        val d = FreestyleSets.derive(marks(Exercise.SQUAT, 14, 10, 12))
        assertEquals(FreestyleSet(Exercise.SQUAT, 3, 10_000L, 14_000L), d.sets.single())
    }

    @Test
    fun `totals derive from the sets, and a relabelled mark moves its reps`() {
        val original = marks(Exercise.SQUAT, 10, 12) + marks(Exercise.PUSHUP, 14, 16)
        assertEquals(
            mapOf(Exercise.SQUAT to 2, Exercise.PUSHUP to 2),
            FreestyleSets.derive(original).totals
        )
        val relabelled = original.map { if (it.movement == Exercise.PUSHUP) it.copy(movement = Exercise.SQUAT) else it }
        val d = FreestyleSets.derive(relabelled)
        assertEquals(mapOf(Exercise.SQUAT to 4), d.totals)
        assertEquals(1, d.sets.size)
    }

    @Test
    fun `time in sets sums each movement's set lengths`() {
        val d = FreestyleSets.derive(
            marks(Exercise.SQUAT, 10, 14) + marks(Exercise.SQUAT, 40, 45) + marks(Exercise.PUSHUP, 50, 51)
        )
        assertEquals(9_000L, d.timeInSets(Exercise.SQUAT))
        assertEquals(1_000L, d.timeInSets(Exercise.PUSHUP))
        assertEquals(2, d.setCount(Exercise.SQUAT))
    }
}
