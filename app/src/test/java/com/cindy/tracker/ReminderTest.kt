package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZonedDateTime

class ReminderTest {

    private val zone = ZoneId.of("Europe/Bucharest")
    private val today = LocalDate.of(2026, 9, 9)
    private val monday = DayOfWeek.MONDAY

    private fun attempt(iso: String, rounds: Int = 13, reps: Int = 10): Attempt {
        val at = LocalDate.parse(iso).atTime(12, 0).atZone(zone).toInstant().toEpochMilli()
        return Attempt(rounds = rounds, reps = reps, atMillis = at, durationMs = 20 * 60_000L)
    }

    private fun message(vararg a: Attempt, on: LocalDate = today) =
        Reminder.message(a.toList(), on, zone, monday)

    private fun at(iso: String) = ZonedDateTime.parse(iso)

    private fun millis(iso: String) = at(iso).toInstant().toEpochMilli()

    // nextFire

    @Test
    fun `next fire later today when the time has not come`() {
        val next = Reminder.nextFire(at("2026-09-09T10:00:00+03:00[Europe/Bucharest]"), 18 * 60)
        assertEquals(at("2026-09-09T18:00:00+03:00[Europe/Bucharest]"), next)
    }

    @Test
    fun `next fire is tomorrow when the time has passed`() {
        val next = Reminder.nextFire(at("2026-09-09T19:00:00+03:00[Europe/Bucharest]"), 18 * 60)
        assertEquals(at("2026-09-10T18:00:00+03:00[Europe/Bucharest]"), next)
    }

    @Test
    fun `next fire is tomorrow when it is exactly the time`() {
        val next = Reminder.nextFire(at("2026-09-09T18:00:00+03:00[Europe/Bucharest]"), 18 * 60)
        assertEquals(at("2026-09-10T18:00:00+03:00[Europe/Bucharest]"), next)
    }

    @Test
    fun `next fire moves out of the spring forward gap`() {
        val now = at("2026-03-29T01:00:00+02:00[Europe/Bucharest]")
        val next = Reminder.nextFire(now, 3 * 60 + 30)
        assertEquals(at("2026-03-29T04:30:00+03:00[Europe/Bucharest]"), next)
        assertEquals(4, next.hour)
        assertEquals(30, next.minute)
    }

    @Test
    fun `next fire picks the earlier offset when fall back repeats the hour`() {
        val now = at("2026-10-25T01:00:00+03:00[Europe/Bucharest]")
        val next = Reminder.nextFire(now, 3 * 60 + 30)
        assertEquals(3, next.hour)
        assertEquals(30, next.minute)
        assertEquals(java.time.ZoneOffset.ofHours(3), next.offset)
    }

    // shouldPost

    @Test
    fun `posts on time`() {
        val t = millis("2026-09-09T18:00:00+03:00[Europe/Bucharest]")
        assertTrue(Reminder.shouldPost(t, t))
    }

    @Test
    fun `does not post three hours late`() {
        val t = millis("2026-09-09T18:00:00+03:00[Europe/Bucharest]")
        assertFalse(Reminder.shouldPost(t, t + 3 * 60 * 60 * 1000L))
    }

    @Test
    fun `posts just after midnight when still inside the late limit`() {
        val t = millis("2026-09-09T23:50:00+03:00[Europe/Bucharest]")
        assertTrue(Reminder.shouldPost(t, t + 15 * 60 * 1000L))
    }

    @Test
    fun `does not post a day late`() {
        val t = millis("2026-09-09T18:00:00+03:00[Europe/Bucharest]")
        assertFalse(Reminder.shouldPost(t, t + 25 * 60 * 60 * 1000L))
    }

    @Test
    fun `posts when thirty seconds early`() {
        val t = millis("2026-09-09T18:00:00+03:00[Europe/Bucharest]")
        assertTrue(Reminder.shouldPost(t, t - 30_000L))
    }

    @Test
    fun `does not post without a target`() {
        assertFalse(Reminder.shouldPost(0L, 1_000L))
    }

    // message

    @Test
    fun `nothing to say when today is already trained`() {
        assertNull(message(attempt("2026-09-09")))
    }

    @Test
    fun `first ever reminder invites the first Cindy`() {
        val m = message()
        assertEquals("Time for your first Cindy", m?.title)
        assertEquals(
            "Twenty minutes: 5 pull-ups, 10 push-ups, 15 squats, as many rounds as you can.",
            m?.body
        )
    }

    @Test
    fun `a running streak is named and the next number promised`() {
        val m = message(attempt("2026-09-07"), attempt("2026-09-08"))
        assertEquals("Keep your 2-day streak going", m?.title)
        assertEquals("Train today and it's 3.", m?.body)
    }

    @Test
    fun `one day of streak asks for a second`() {
        val m = message(attempt("2026-09-08"))
        assertEquals("Make it two days in a row", m?.title)
        assertEquals("You trained yesterday. Twenty minutes today starts a streak.", m?.body)
    }

    @Test
    fun `last day of the week warns about the weekly streak`() {
        // Sunday; weeks start on Monday; last week and the week before were trained, this not.
        val sunday = LocalDate.of(2026, 9, 13)
        val m = message(attempt("2026-08-26"), attempt("2026-09-02"), on = sunday)
        assertEquals("Last day to keep your 2-week streak", m?.title)
        assertEquals("One session today and it's 3 weeks.", m?.body)
    }

    @Test
    fun `the weekly warning waits for the last day of the week`() {
        // Saturday, not Sunday: falls through to the general line.
        val saturday = LocalDate.of(2026, 9, 12)
        val m = message(attempt("2026-08-26"), attempt("2026-09-02"), on = saturday)
        assertEquals("Cindy's ready when you are", m?.title)
    }

    @Test
    fun `otherwise the reminder quotes the best score in the latest category`() {
        val m = message(attempt("2026-09-01", rounds = 12, reps = 0), attempt("2026-09-03"))
        assertEquals("Cindy's ready when you are", m?.title)
        assertEquals("Your best is 13 + 10. Twenty minutes to chase it.", m?.body)
    }

    // preview

    @Test
    fun `preview is never null even when today is trained`() {
        val m = Reminder.preview(listOf(attempt("2026-09-09")), today, zone, monday)
        assertNotNull(m)
        assertEquals("Time for your first Cindy", m.title)
    }

    @Test
    fun `preview ignores today and keeps earlier days`() {
        val m = Reminder.preview(
            listOf(attempt("2026-09-08"), attempt("2026-09-09")), today, zone, monday
        )
        assertEquals("Make it two days in a row", m.title)
    }

    // formatTime

    @Test
    fun `formats a time on a 24 hour phone`() {
        assertEquals("18:00", Reminder.formatTime(1080, true))
        assertEquals("12:05", Reminder.formatTime(725, true))
    }

    @Test
    fun `formats a time on a 12 hour phone`() {
        assertEquals("6:00 PM", Reminder.formatTime(1080, false))
        assertEquals("12:00 AM", Reminder.formatTime(0, false))
        assertEquals("12:05 PM", Reminder.formatTime(725, false))
    }
}
