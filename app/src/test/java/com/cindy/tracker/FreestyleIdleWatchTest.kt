package com.cindy.tracker

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** The Freestyle idle rule: ask after 10 minutes without a banked rep, never stop alone. */
class FreestyleIdleWatchTest {

    private val minute = 60_000L
    private val watch = FreestyleIdleWatch().also { it.start(0L) }

    @Test
    fun asksAtTenMinutesWithoutARepAndNotBefore() {
        assertFalse(watch.shouldAsk(10 * minute - 1))
        assertTrue(watch.shouldAsk(10 * minute))
    }

    @Test
    fun aBankedRepStartsTheTenMinutesAgain() {
        watch.repBanked(9 * minute)
        assertFalse(watch.shouldAsk(19 * minute - 1))
        assertTrue(watch.shouldAsk(19 * minute))
    }

    @Test
    fun asksOnceUntilTheAthleteAnswers() {
        assertTrue(watch.shouldAsk(10 * minute))
        assertFalse(watch.shouldAsk(11 * minute))
        assertFalse(watch.shouldAsk(30 * minute))
    }

    @Test
    fun keepGoingWaitsAnotherTenMinutes() {
        assertTrue(watch.shouldAsk(10 * minute))
        watch.keepGoing(12 * minute)
        assertFalse(watch.shouldAsk(22 * minute - 1))
        assertTrue(watch.shouldAsk(22 * minute))
    }

    @Test
    fun pausedTimeDoesNotCount() {
        watch.pause(4 * minute)
        assertFalse(watch.shouldAsk(60 * minute))
        watch.resume(34 * minute)
        assertFalse(watch.shouldAsk(40 * minute - 1))
        assertTrue(watch.shouldAsk(40 * minute))
    }

    @Test
    fun startingAgainForgetsTheLastSession() {
        assertTrue(watch.shouldAsk(10 * minute))
        watch.start(20 * minute)
        assertFalse(watch.shouldAsk(30 * minute - 1))
        assertTrue(watch.shouldAsk(30 * minute))
    }

    @Test
    fun neverAsksBeforeStart() {
        assertFalse(FreestyleIdleWatch().shouldAsk(99 * minute))
    }
}
