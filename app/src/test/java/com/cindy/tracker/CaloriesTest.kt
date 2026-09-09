package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CaloriesTest {

    private val twentyMinutes = 20 * 60 * 1000L

    @Test
    fun `no body weight means no number`() {
        assertNull(Calories.burned(300, twentyMinutes, bodyWeightKg = 0.0))
        assertNull(Calories.burned(300, twentyMinutes, bodyWeightKg = -5.0))
    }

    @Test
    fun `no clock means no number`() {
        assertNull(Calories.burned(300, activeMs = 0L, bodyWeightKg = 80.0))
    }

    @Test
    fun `the reference effort lands on the reference MET`() {
        // Ten rounds in twenty minutes is what the 8-MET figure is taken to describe.
        assertEquals(Calories.REFERENCE_MET, Calories.met(10 * 30, twentyMinutes), 0.001)
    }

    @Test
    fun `the reference effort matches the MET equation by hand`() {
        // 8 MET x 3.5 x 80kg / 200 x 20min = 224 kcal.
        assertEquals(224, Calories.burned(10 * 30, twentyMinutes, bodyWeightKg = 80.0))
    }

    @Test
    fun `working harder for the same time burns more`() {
        val easy = Calories.burned(5 * 30, twentyMinutes, 80.0)!!
        val hard = Calories.burned(15 * 30, twentyMinutes, 80.0)!!
        assertTrue("$hard should exceed $easy", hard > easy)
    }

    @Test
    fun `a heavier athlete burns more for the same work`() {
        val light = Calories.burned(10 * 30, twentyMinutes, 60.0)!!
        val heavy = Calories.burned(10 * 30, twentyMinutes, 100.0)!!
        assertTrue("$heavy should exceed $light", heavy > light)
    }

    @Test
    fun `an idle twenty minutes does not read as vigorous exercise`() {
        assertEquals(Calories.MIN_MET, Calories.met(0, twentyMinutes), 0.001)
        assertEquals(Calories.MIN_MET, Calories.met(30, twentyMinutes), 0.001)
    }

    @Test
    fun `a superhuman score does not run off the top of the scale`() {
        // The compendium does not describe sustaining this, so the estimate stops following it.
        assertEquals(Calories.MAX_MET, Calories.met(40 * 30, twentyMinutes), 0.001)
        assertEquals(Calories.MAX_MET, Calories.met(100 * 30, twentyMinutes), 0.001)
    }

    @Test
    fun `a workout stopped early is charged for the time it ran`() {
        val full = Calories.burned(10 * 30, twentyMinutes, 80.0)!!
        val half = Calories.burned(5 * 30, twentyMinutes / 2, 80.0)!!
        // Same work rate, half the time: about half the energy.
        assertTrue("$half should be about half of $full", kotlin.math.abs(half - full / 2) <= 2)
    }
}
