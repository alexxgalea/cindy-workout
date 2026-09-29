package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.ZoneId

class StreakTest {

    private val zone = ZoneId.of("Europe/Bucharest")
    private val today = LocalDate.of(2026, 9, 9)

    private fun days(vararg iso: String) = iso.map { LocalDate.parse(it) }.toSet()

    /** An attempt at a given local date and time in [zone]. */
    private fun attempt(iso: String, hour: Int = 12, minute: Int = 0): Attempt {
        val at = LocalDate.parse(iso).atTime(hour, minute).atZone(zone).toInstant().toEpochMilli()
        return Attempt(rounds = 10, reps = 0, atMillis = at)
    }

    @Test
    fun `no training is no streak`() {
        assertEquals(0, Streak.current(emptySet(), today))
        assertEquals(0, Streak.longest(emptySet()))
    }

    @Test
    fun `training today starts a streak of one`() {
        assertEquals(1, Streak.current(days("2026-09-09"), today))
    }

    @Test
    fun `consecutive days run back from today`() {
        assertEquals(3, Streak.current(days("2026-09-09", "2026-09-08", "2026-09-07"), today))
    }

    @Test
    fun `a gap ends the streak`() {
        // The 6th is stranded on the far side of a missed 7th.
        assertEquals(2, Streak.current(days("2026-09-09", "2026-09-08", "2026-09-06"), today))
    }

    @Test
    fun `yesterday keeps the streak alive through today`() {
        // At nine in the morning the streak is not broken; it is merely not extended yet.
        assertEquals(2, Streak.current(days("2026-09-08", "2026-09-07"), today))
        assertTrue(Streak.atRisk(days("2026-09-08"), today))
    }

    @Test
    fun `two days off does break it`() {
        assertEquals(0, Streak.current(days("2026-09-07", "2026-09-06"), today))
    }

    @Test
    fun `training today is not at risk`() {
        assertFalse(Streak.atRisk(days("2026-09-09", "2026-09-08"), today))
    }

    @Test
    fun `the longest run is found wherever it sits`() {
        val trained = days(
            "2026-08-01", "2026-08-02", "2026-08-03", "2026-08-04", // four
            "2026-08-20", "2026-08-21",                             // two
            "2026-09-09"                                            // one
        )
        assertEquals(4, Streak.longest(trained))
        assertEquals(1, Streak.current(trained, today))
    }

    @Test
    fun `a run is counted once, not once per day in it`() {
        assertEquals(3, Streak.longest(days("2026-09-01", "2026-09-02", "2026-09-03")))
    }

    @Test
    fun `two attempts on one day are one day`() {
        val trained = Streak.daysTrained(
            listOf(attempt("2026-09-09", hour = 7), attempt("2026-09-09", hour = 19)),
            zone
        )
        assertEquals(1, trained.size)
        assertEquals(1, Streak.current(trained, today))
    }

    @Test
    fun `either side of midnight is two days, not twenty minutes`() {
        val trained = Streak.daysTrained(
            listOf(attempt("2026-09-08", hour = 23, minute = 50), attempt("2026-09-09", hour = 0, minute = 10)),
            zone
        )
        assertEquals(2, trained.size)
        assertEquals("twenty minutes apart, but a two-day streak", 2, Streak.current(trained, today))
    }

    @Test
    fun `days are the athlete's local days, not UTC ones`() {
        // 00:30 local on the 9th in Bucharest is still the 8th in UTC.
        val trained = Streak.daysTrained(listOf(attempt("2026-09-09", hour = 0, minute = 30)), zone)
        assertEquals(setOf(LocalDate.of(2026, 9, 9)), trained)
    }

    private val monday = DayOfWeek.MONDAY

    private fun weeks(vararg iso: String) = days(*iso)

    @Test
    fun `weeks start where the locale says`() {
        assertEquals(LocalDate.of(2026, 9, 7), Streak.weekStart(today, DayOfWeek.MONDAY))
        assertEquals(LocalDate.of(2026, 9, 6), Streak.weekStart(today, DayOfWeek.SUNDAY))
    }

    @Test
    fun `a session a week is a weekly streak`() {
        val w = Streak.weeksTrained(days("2026-08-26", "2026-09-01", "2026-09-09"), monday)
        assertEquals(3, Streak.currentWeeks(w, today, monday))
    }

    @Test
    fun `last week keeps the weekly streak alive`() {
        val w = Streak.weeksTrained(days("2026-08-26", "2026-09-01"), monday)
        assertEquals(2, Streak.currentWeeks(w, today, monday))
        assertTrue(Streak.weekAtRisk(w, today, monday))
    }

    @Test
    fun `a week off breaks the weekly streak`() {
        val w = Streak.weeksTrained(days("2026-08-19", "2026-08-26"), monday)
        assertEquals(0, Streak.currentWeeks(w, today, monday))
    }

    @Test
    fun `training this week is not a week at risk`() {
        val w = Streak.weeksTrained(days("2026-09-01", "2026-09-08"), monday)
        assertFalse(Streak.weekAtRisk(w, today, monday))
    }

    @Test
    fun `the locale decides which week a Sunday is in`() {
        val trained = days("2026-09-06", "2026-09-07")
        val mon = Streak.weeksTrained(trained, DayOfWeek.MONDAY)
        assertEquals(2, mon.size)
        assertEquals(2, Streak.longestWeeks(mon))
        assertEquals(1, Streak.weeksTrained(trained, DayOfWeek.SUNDAY).size)
    }

    @Test
    fun `a weekly streak crosses the new year`() {
        val w = Streak.weeksTrained(days("2025-12-30", "2026-01-06"), monday)
        assertEquals(2, Streak.longestWeeks(w))
    }

    @Test
    fun `the longest weekly run is found wherever it sits`() {
        val w = weeks("2026-07-06", "2026-07-13", "2026-07-20", "2026-08-31")
        assertEquals(3, Streak.longestWeeks(w))
    }

    @Test
    fun `the current run lists its days`() {
        val trained = days("2026-09-05", "2026-09-07", "2026-09-08", "2026-09-09")
        val run = days("2026-09-07", "2026-09-08", "2026-09-09")
        assertEquals(run, Streak.currentRun(trained, today))
        assertEquals(run, Streak.currentRun(trained, LocalDate.of(2026, 9, 10)))
    }

    @Test
    fun `no current run is empty`() {
        assertTrue(Streak.currentRun(days("2026-09-01"), today).isEmpty())
    }

    @Test
    fun `the longest run knows where it was`() {
        val trained = days(
            "2026-08-01", "2026-08-02", "2026-08-03", "2026-08-04",
            "2026-08-20", "2026-08-21",
            "2026-09-09"
        )
        assertEquals(LocalDate.of(2026, 8, 1)..LocalDate.of(2026, 8, 4), Streak.longestRun(trained))
        assertNull(Streak.longestRun(emptySet()))
    }

    @Test
    fun `a tie goes to the most recent run`() {
        val trained = days("2026-08-01", "2026-08-02", "2026-08-10", "2026-08-11")
        assertEquals(LocalDate.of(2026, 8, 10)..LocalDate.of(2026, 8, 11), Streak.longestRun(trained))
    }

    @Test
    fun `the longest weekly run knows where it was`() {
        val w = weeks("2026-07-06", "2026-07-13", "2026-08-31")
        assertEquals(LocalDate.of(2026, 7, 6)..LocalDate.of(2026, 7, 13), Streak.longestWeeksRun(w))
    }

    @Test
    fun `milestones`() {
        assertEquals(3, Streak.nextMilestone(0, Streak.DAILY_MILESTONES))
        assertEquals(7, Streak.nextMilestone(3, Streak.DAILY_MILESTONES))
        assertNull(Streak.nextMilestone(365, Streak.DAILY_MILESTONES))
        assertTrue(Streak.isMilestone(7, Streak.DAILY_MILESTONES))
        assertFalse(Streak.isMilestone(8, Streak.DAILY_MILESTONES))
        assertEquals(2, Streak.nextMilestone(1, Streak.WEEKLY_MILESTONES))
    }
}
