package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.ZoneId

class BadgesTest {

    private val zone = ZoneId.of("Europe/Bucharest")
    private val monday = DayOfWeek.MONDAY

    /** A Monday, so that days and weeks can be counted on the page. */
    private val start = LocalDate.of(2026, 3, 2)

    private val adaptive = CindyProfile(squat = SquatVariant.BOX_SQUAT)
    private val tolerance = Records.UNTRACKED_TOLERANCE_MS

    private fun millis(day: LocalDate, hour: Int = 12, minute: Int = 0, at: ZoneId = zone): Long =
        day.atTime(hour, minute).atZone(at).toInstant().toEpochMilli()

    /** A session that earns as little as it can: short, standard, nothing remarkable about it. */
    private fun attempt(
        day: LocalDate = start,
        rounds: Int = 10,
        reps: Int = 0,
        profile: CindyProfile? = CindyProfile.STANDARD,
        untrackedMs: Long = 0L,
        manualReps: Int = 0,
        durationMs: Long = 10 * 60_000L,
        splitsMs: List<Long> = emptyList(),
        countedReps: Int? = null
    ) = Attempt(
        rounds = rounds,
        reps = reps,
        atMillis = millis(day),
        durationMs = durationMs,
        roundSplitsMs = splitsMs,
        profile = profile,
        manualReps = manualReps,
        countedReps = countedReps,
        untrackedMs = untrackedMs
    )

    private fun earned(
        attempts: List<Attempt>,
        weekStart: DayOfWeek = monday,
        at: ZoneId = zone
    ): Set<Badge> = Badges.earned(attempts, at, weekStart).map { it.badge }.toSet()

    private fun stamps(attempts: List<Attempt>): Map<Badge, Long> =
        Badges.earned(attempts, zone, monday).associate { it.badge to it.atMillis }

    private fun progress(
        badge: Badge,
        attempts: List<Attempt>,
        today: LocalDate = start,
        weekStart: DayOfWeek = monday
    ) = Badges.progress(badge, attempts, today, zone, weekStart)

    /** One session on each of [n] days in a row, starting at [from]. */
    private fun everyDay(n: Int, from: LocalDate = start): List<Attempt> =
        (0 until n).map { attempt(from.plusDays(it.toLong())) }

    /** One session in each of [n] weeks in a row, starting at [from]. */
    private fun everyWeek(n: Int, from: LocalDate = start): List<Attempt> =
        (0 until n).map { attempt(from.plusWeeks(it.toLong())) }

    /** [n] sessions two days apart, so that no streak gets in the way of counting them. */
    private fun spaced(n: Int, make: (LocalDate) -> Attempt = { attempt(it) }): List<Attempt> =
        (0 until n).map { make(start.plusDays(2L * it)) }

    private fun family(badges: Set<Badge>, vararg families: BadgeFamily): Set<Badge> =
        badges.filterTo(linkedSetOf()) { it.family in families }

    // ── the catalogue ─────────────────────────────────────────────────────────

    @Test
    fun `the catalogue has 26 badges`() {
        assertEquals(26, Badge.entries.size)
    }

    @Test
    fun `titles are unique and faces are unique within a family`() {
        assertEquals(Badge.entries.size, Badge.entries.map { it.title }.toSet().size)
        for ((family, badges) in Badge.entries.groupBy { it.family }) {
            assertEquals("faces in $family", badges.size, badges.map { it.face }.toSet().size)
        }
    }

    @Test
    fun `the families sit together, in the order the profile lists them`() {
        val families = Badge.entries.map { it.family }
        assertEquals(BadgeFamily.entries.toList(), families.distinct())
        // One block per family: the family only changes as many times as there are borders.
        assertEquals(BadgeFamily.entries.size - 1, families.zipWithNext().count { (a, b) -> a != b })
    }

    @Test
    fun `every badge says what earns it, in a sentence`() {
        for (badge in Badge.entries) {
            assertTrue("${badge.name} has no requirement", badge.requirement.isNotBlank())
            assertTrue("${badge.name}: ${badge.requirement}", badge.requirement.endsWith("."))
            assertTrue("${badge.name} has no face", badge.face.isNotBlank())
            assertTrue("${badge.name}'s face is too wide for its disc", badge.face.length <= 4)
        }
    }

    @Test
    fun `the round badges are the rungs of the ladder and are read from it`() {
        val rungs = mapOf(
            Badge.NOVICE to Level.NOVICE,
            Badge.INTERMEDIATE to Level.INTERMEDIATE,
            Badge.ADVANCED to Level.ADVANCED,
            Badge.ELITE to Level.ELITE,
            Badge.LEGEND to Level.LEGEND
        )
        for ((badge, level) in rungs) {
            assertEquals(level.title, badge.title)
            assertEquals("${level.minRounds}R", badge.face)
            assertTrue(badge.requirement, badge.requirement.startsWith("${level.minRounds} rounds"))
            assertTrue(
                "${badge.name} at ${level.minRounds} rounds",
                badge in earned(listOf(attempt(rounds = level.minRounds)))
            )
            assertFalse(
                "${badge.name} one round short",
                badge in earned(listOf(attempt(rounds = level.minRounds - 1)))
            )
        }
    }

    @Test
    fun `no rung of the ladder can be mistaken for First round`() {
        // First round asks for one round, and the menu finds the highest rung held by its round
        // count. A ladder retuned to put a rung at one round or fewer would collide with it, and
        // lose its progress line, which is not shown for a target of one.
        for (level in Level.entries.filter { it != Level.FIRST_STEPS }) {
            assertTrue("${level.title} at ${level.minRounds} rounds", level.minRounds > 1)
        }
    }

    // ── nothing yet ───────────────────────────────────────────────────────────

    @Test
    fun `there is nothing to earn before the first session`() {
        assertTrue(Badges.earned(emptyList(), zone, monday).isEmpty())
    }

    @Test
    fun `an empty history is at zero on every badge that counts something`() {
        assertEquals(BadgeProgress(0, 10, "sessions"), progress(Badge.SESSIONS_10, emptyList()))
        assertEquals(BadgeProgress(0, 10, "rounds"), progress(Badge.INTERMEDIATE, emptyList()))
        assertEquals(BadgeProgress(0, 7, "days"), progress(Badge.STREAK_7, emptyList()))
        assertEquals(BadgeProgress(0, 4, "weeks"), progress(Badge.WEEKS_4, emptyList()))
        assertEquals(BadgeProgress(0, 1_000, "reps"), progress(Badge.REPS_1000, emptyList()))
    }

    // ── sessions ──────────────────────────────────────────────────────────────

    @Test
    fun `any first session earns First Cindy, however it went`() {
        val sessions = listOf(
            attempt(),
            attempt(untrackedMs = tolerance),
            attempt(profile = adaptive),
            attempt(profile = null),
            attempt(rounds = 0, reps = 3)
        )
        for (a in sessions) assertTrue(Badge.FIRST_CINDY in earned(listOf(a)))
    }

    @Test
    fun `each session count is earned at its number and not the one before`() {
        val counts = mapOf(
            Badge.SESSIONS_10 to 10,
            Badge.SESSIONS_25 to 25,
            Badge.SESSIONS_50 to 50,
            Badge.SESSIONS_100 to 100
        )
        for ((badge, n) in counts) {
            assertFalse("${badge.name} at ${n - 1}", badge in earned(spaced(n - 1)))
            assertTrue("${badge.name} at $n", badge in earned(spaced(n)))
        }
    }

    @Test
    fun `every kind of session counts towards the number of sessions`() {
        val kinds: List<(LocalDate) -> Attempt> = listOf(
            { attempt(it) },
            { attempt(it, untrackedMs = tolerance) },
            { attempt(it, profile = adaptive) },
            { attempt(it, profile = null) },
            { attempt(it, rounds = 0, reps = 2) }
        )
        val ten = spaced(10) { day -> kinds[(day.toEpochDay() % kinds.size).toInt()](day) }
        assertTrue(Badge.SESSIONS_10 in earned(ten))
    }

    // ── rounds ────────────────────────────────────────────────────────────────

    @Test
    fun `First round needs a whole round, not most of one`() {
        assertFalse(Badge.FIRST_ROUND in earned(listOf(attempt(rounds = 0, reps = 29))))
        assertTrue(Badge.FIRST_ROUND in earned(listOf(attempt(rounds = 1))))
    }

    @Test
    fun `the rungs are about one session, so rounds in two sessions do not add up`() {
        val two = listOf(attempt(start, rounds = 6), attempt(start.plusDays(2), rounds = 6))
        assertFalse(Badge.INTERMEDIATE in earned(two))
        assertTrue(Badge.NOVICE in earned(two))
    }

    @Test
    fun `the rung badges match the level that a score earns, rounds 0 to 30`() {
        val rungBadges = Badge.entries.filter {
            it.family == BadgeFamily.ROUNDS && it != Badge.FIRST_ROUND && it != Badge.PAST_BENCHMARK
        }
        for (rounds in 0..30) {
            val a = attempt(rounds = rounds)
            val expected = Level.entries
                .filter { it != Level.FIRST_STEPS && it.ordinal <= a.level!!.ordinal }
                .map { it.title }
            val got = earned(listOf(a)).filter { it in rungBadges }.map { it.title }
            assertEquals("at $rounds rounds", expected, got)
        }
    }

    @Test
    fun `Legend is level with the benchmark and only going past it beats it`() {
        val level = earned(listOf(attempt(rounds = 27)))
        assertTrue(Badge.LEGEND in level)
        assertFalse(Badge.PAST_BENCHMARK in level)

        assertTrue(Badge.PAST_BENCHMARK in earned(listOf(attempt(rounds = 27, reps = 1))))
    }

    @Test
    fun `Past the benchmark says what the record board says`() {
        val scores = listOf(26 to 29, 27 to 0, 27 to 1, 28 to 0)
        for (profile in listOf(CindyProfile.STANDARD, adaptive, null)) {
            for (untracked in listOf(0L, tolerance - 1, tolerance)) {
                for ((rounds, reps) in scores) {
                    val a = attempt(rounds = rounds, reps = reps, profile = profile, untrackedMs = untracked)
                    assertEquals(
                        "$rounds+$reps, $profile, $untracked ms untracked",
                        Records.beatsBenchmark(a),
                        Badge.PAST_BENCHMARK in earned(listOf(a))
                    )
                }
            }
        }
    }

    @Test
    fun `a session the camera lost the athlete in earns no round badge`() {
        val a = attempt(rounds = 27, reps = 1, untrackedMs = tolerance)
        val got = earned(listOf(a))
        assertEquals(emptySet<Badge>(), family(got, BadgeFamily.ROUNDS))
        assertTrue("it still counts as a session", Badge.FIRST_CINDY in got)
    }

    @Test
    fun `a moment short of the tolerance is still an exact score`() {
        val a = attempt(rounds = 10, untrackedMs = tolerance - 1)
        assertTrue(Badge.INTERMEDIATE in earned(listOf(a)))
    }

    @Test
    fun `an adaptive session earns no round or pace badge, but it counts for the rest`() {
        val a = attempt(rounds = 27, reps = 1, profile = adaptive, splitsMs = listOf(30_000L))
        val got = earned(listOf(a))
        assertEquals(emptySet<Badge>(), family(got, BadgeFamily.ROUNDS, BadgeFamily.PACE))
        assertTrue(Badge.FIRST_CINDY in got)
        assertTrue(Badge.MADE_IT_YOURS in got)
    }

    @Test
    fun `a profile this build cannot read earns no round or pace badge and is not called adaptive`() {
        val a = attempt(rounds = 27, reps = 1, profile = null, splitsMs = listOf(30_000L))
        val got = earned(listOf(a))
        assertEquals(emptySet<Badge>(), family(got, BadgeFamily.ROUNDS, BadgeFamily.PACE))
        assertFalse("what it was is unknown, so it is not claimed", Badge.MADE_IT_YOURS in got)
        assertTrue(Badge.FIRST_CINDY in got)
    }

    // ── streaks ───────────────────────────────────────────────────────────────

    @Test
    fun `three days in a row earn the badge on the third day`() {
        val got = stamps(everyDay(3))
        assertEquals(millis(start.plusDays(2)), got[Badge.STREAK_3])
        assertFalse(Badge.STREAK_3 in earned(everyDay(2)))
    }

    @Test
    fun `each daily run is earned at its length and not the day before`() {
        val runs = mapOf(
            Badge.STREAK_3 to 3,
            Badge.STREAK_7 to 7,
            Badge.STREAK_14 to 14,
            Badge.STREAK_30 to 30
        )
        for ((badge, n) in runs) {
            assertFalse("${badge.name} at ${n - 1}", badge in earned(everyDay(n - 1)))
            assertTrue("${badge.name} at $n", badge in earned(everyDay(n)))
        }
    }

    @Test
    fun `a missed day starts the run again`() {
        // Two days, a day off, two more: never three together.
        val days = listOf(0L, 1L, 3L, 4L).map { attempt(start.plusDays(it)) }
        assertFalse(Badge.STREAK_3 in earned(days))

        // A fifth day makes three: 3, 4 and 5.
        val fifth = days + attempt(start.plusDays(5))
        assertEquals(millis(start.plusDays(5)), stamps(fifth)[Badge.STREAK_3])
    }

    @Test
    fun `several sessions in one day are one day`() {
        val sessions = listOf(
            attempt(start), attempt(start), attempt(start), attempt(start.plusDays(1))
        )
        assertFalse(Badge.STREAK_3 in earned(sessions))
    }

    @Test
    fun `a streak is for keeping, so stopping does not take it back`() {
        val sevenThenNothing = everyDay(7) + attempt(start.plusDays(400))
        assertTrue(Badge.STREAK_7 in earned(sevenThenNothing))
    }

    @Test
    fun `a day is the athlete's local day, not a UTC one`() {
        // 23:50 and 00:10 in Bucharest fall on one UTC date and on two dates of the athlete's.
        val sessions = listOf(
            Attempt(rounds = 10, reps = 0, atMillis = millis(start, 23, 50)),
            Attempt(rounds = 10, reps = 0, atMillis = millis(start.plusDays(1), 0, 10)),
            Attempt(rounds = 10, reps = 0, atMillis = millis(start.plusDays(2), 12, 0))
        )
        assertTrue(Badge.STREAK_3 in earned(sessions, at = zone))
        assertFalse(Badge.STREAK_3 in earned(sessions, at = ZoneId.of("UTC")))
    }

    @Test
    fun `four weeks in a row earn the badge in the fourth week`() {
        val got = stamps(everyWeek(4))
        assertEquals(millis(start.plusWeeks(3)), got[Badge.WEEKS_4])
        assertFalse(Badge.WEEKS_4 in earned(everyWeek(3)))
    }

    @Test
    fun `each weekly run is earned at its length and not the week before`() {
        val runs = mapOf(Badge.WEEKS_4 to 4, Badge.WEEKS_12 to 12, Badge.WEEKS_26 to 26)
        for ((badge, n) in runs) {
            assertFalse("${badge.name} at ${n - 1}", badge in earned(everyWeek(n - 1)))
            assertTrue("${badge.name} at $n", badge in earned(everyWeek(n)))
        }
    }

    @Test
    fun `a week with no session breaks the run`() {
        val weeks = listOf(0L, 1L, 3L, 4L).map { attempt(start.plusWeeks(it)) }
        assertFalse(Badge.WEEKS_4 in earned(weeks))
    }

    @Test
    fun `where the week starts is the locale's call`() {
        assertEquals(DayOfWeek.MONDAY, start.dayOfWeek)
        // Mon 2, Sun 15, Mon 16, Mon 23 March. Weeks begin on Monday: four weeks in a row.
        // Begin them on Sunday and the 15th and 16th share one, leaving a gap after the 2nd.
        val sessions = listOf(
            attempt(start),
            attempt(start.plusDays(13)),
            attempt(start.plusDays(14)),
            attempt(start.plusDays(21))
        )
        assertEquals(DayOfWeek.SUNDAY, start.plusDays(13).dayOfWeek)
        assertTrue(Badge.WEEKS_4 in earned(sessions, weekStart = DayOfWeek.MONDAY))
        assertFalse(Badge.WEEKS_4 in earned(sessions, weekStart = DayOfWeek.SUNDAY))
    }

    // ── volume ────────────────────────────────────────────────────────────────

    @Test
    fun `each rep total is earned at its number and not the rep before`() {
        val totals = mapOf(Badge.REPS_1000 to 1_000, Badge.REPS_5000 to 5_000, Badge.REPS_10000 to 10_000)
        for ((badge, n) in totals) {
            assertFalse("${badge.name} at ${n - 1}", badge in earned(listOf(attempt(countedReps = n - 1))))
            assertTrue("${badge.name} at $n", badge in earned(listOf(attempt(countedReps = n))))
        }
    }

    @Test
    fun `reps add up across sessions and the badge belongs to the session that got there`() {
        val first = attempt(start, countedReps = 600)
        val second = attempt(start.plusDays(2), countedReps = 400)
        val third = attempt(start.plusDays(4), countedReps = 400)
        val got = stamps(listOf(first, second, third))
        assertEquals(second.atMillis, got[Badge.REPS_1000])
    }

    @Test
    fun `every session's reps count, the lower-bound and adaptive ones too`() {
        val sessions = listOf(
            attempt(start, countedReps = 400, untrackedMs = tolerance),
            attempt(start.plusDays(2), countedReps = 300, profile = adaptive),
            attempt(start.plusDays(4), countedReps = 300, profile = null)
        )
        assertTrue(Badge.REPS_1000 in earned(sessions))
    }

    // ── pace ──────────────────────────────────────────────────────────────────

    @Test
    fun `a round under two minutes`() {
        assertTrue(Badge.ROUND_UNDER_2 in earned(listOf(attempt(splitsMs = listOf(119_999L)))))
        assertFalse(Badge.ROUND_UNDER_2 in earned(listOf(attempt(splitsMs = listOf(120_000L)))))
    }

    @Test
    fun `it is the fastest round that counts, not the average`() {
        val a = attempt(splitsMs = listOf(200_000L, 119_000L, 300_000L))
        assertTrue(Badge.ROUND_UNDER_2 in earned(listOf(a)))
    }

    @Test
    fun `a round under 45 seconds is under two minutes too`() {
        val under = earned(listOf(attempt(splitsMs = listOf(44_999L))))
        assertTrue(Badge.ROUND_UNDER_45 in under)
        assertTrue(Badge.ROUND_UNDER_2 in under)

        val over = earned(listOf(attempt(splitsMs = listOf(45_000L))))
        assertFalse(Badge.ROUND_UNDER_45 in over)
        assertTrue(Badge.ROUND_UNDER_2 in over)
    }

    @Test
    fun `no round splits, no pace badge`() {
        assertEquals(emptySet<Badge>(), family(earned(listOf(attempt(rounds = 27))), BadgeFamily.PACE))
    }

    @Test
    fun `a fast round only counts in an exact standard Cindy`() {
        val fast = listOf(30_000L)
        val notClaimed = listOf(
            attempt(splitsMs = fast, profile = adaptive),
            attempt(splitsMs = fast, profile = null),
            attempt(splitsMs = fast, untrackedMs = tolerance)
        )
        for (a in notClaimed) {
            assertEquals(emptySet<Badge>(), family(earned(listOf(a)), BadgeFamily.PACE))
        }
        assertEquals(
            setOf(Badge.ROUND_UNDER_2, Badge.ROUND_UNDER_45),
            family(earned(listOf(attempt(splitsMs = fast))), BadgeFamily.PACE)
        )
    }

    // ── craft ─────────────────────────────────────────────────────────────────

    /** A whole clock from a build that counted reps: the only kind of session that can be Every rep seen. */
    private fun whole(
        durationMs: Long = Progress.FULL_SESSION_MS,
        manualReps: Int = 0,
        untrackedMs: Long = 0L,
        profile: CindyProfile? = CindyProfile.STANDARD,
        countedReps: Int? = 300
    ) = attempt(
        durationMs = durationMs,
        manualReps = manualReps,
        untrackedMs = untrackedMs,
        profile = profile,
        countedReps = countedReps
    )

    @Test
    fun `a whole clock with nothing tapped in earns Every rep seen`() {
        assertTrue(Badge.EVERY_REP_SEEN in earned(listOf(whole())))
    }

    @Test
    fun `a second short of the clock is not a whole session`() {
        assertFalse(Badge.EVERY_REP_SEEN in earned(listOf(whole(durationMs = Progress.FULL_SESSION_MS - 1))))
    }

    @Test
    fun `one rep tapped in spoils it`() {
        assertFalse(Badge.EVERY_REP_SEEN in earned(listOf(whole(manualReps = 1))))
    }

    @Test
    fun `a score the camera could not stand behind does not earn it`() {
        assertFalse(Badge.EVERY_REP_SEEN in earned(listOf(whole(untrackedMs = tolerance))))
        assertTrue(Badge.EVERY_REP_SEEN in earned(listOf(whole(untrackedMs = tolerance - 1))))
    }

    @Test
    fun `a whole clock with nothing counted earns nothing`() {
        assertFalse(Badge.EVERY_REP_SEEN in earned(listOf(whole(countedReps = 0))))
    }

    @Test
    fun `a session from before reps were counted cannot show that none were tapped in`() {
        // Such a session decodes with no taps and no blind time because they were not recorded,
        // not because there were none.
        assertFalse(Badge.EVERY_REP_SEEN in earned(listOf(whole(countedReps = null))))
        assertTrue(Badge.EVERY_REP_SEEN in earned(listOf(whole())))
    }

    @Test
    fun `it does not have to be a standard Cindy`() {
        assertTrue(Badge.EVERY_REP_SEEN in earned(listOf(whole(profile = adaptive))))
    }

    @Test
    fun `Made it yours is an adaptive session and nothing else`() {
        assertTrue(Badge.MADE_IT_YOURS in earned(listOf(attempt(profile = adaptive))))
        assertFalse(Badge.MADE_IT_YOURS in earned(listOf(attempt(profile = CindyProfile.STANDARD))))
        assertFalse(Badge.MADE_IT_YOURS in earned(listOf(attempt(profile = null))))
    }

    // ── stamps and order ──────────────────────────────────────────────────────

    @Test
    fun `a badge belongs to the session that first earned it, not to a later, better one`() {
        val first = attempt(start, rounds = 5)
        val second = attempt(start.plusDays(2), rounds = 12)
        val got = stamps(listOf(first, second))
        assertEquals(first.atMillis, got[Badge.NOVICE])
        assertEquals(second.atMillis, got[Badge.INTERMEDIATE])
        assertEquals(first.atMillis, got[Badge.FIRST_CINDY])
    }

    @Test
    fun `the order the sessions are given in changes nothing`() {
        val sessions = listOf(
            attempt(start, rounds = 5),
            attempt(start.plusDays(1), rounds = 12, profile = adaptive),
            attempt(start.plusDays(2), rounds = 13, countedReps = 700),
            attempt(start.plusDays(3), rounds = 28, splitsMs = listOf(40_000L)),
            attempt(start.plusDays(9), rounds = 2)
        )
        assertEquals(stamps(sessions), stamps(sessions.reversed()))
        assertEquals(stamps(sessions), stamps(sessions.shuffled(java.util.Random(7))))
    }

    @Test
    fun `badges come back in catalogue order, each once`() {
        val sessions = listOf(
            attempt(start, profile = adaptive),
            attempt(start.plusDays(1), rounds = 12),
            attempt(start.plusDays(2), rounds = 12)
        )
        val list = Badges.earned(sessions, zone, monday).map { it.badge }
        assertEquals(list.sortedBy { it.ordinal }, list)
        assertEquals(list.size, list.toSet().size)
    }

    // ── earnedBy ──────────────────────────────────────────────────────────────

    @Test
    fun `a first session is credited with its first badges`() {
        val first = attempt(start, rounds = 10)
        assertEquals(
            listOf(Badge.FIRST_CINDY, Badge.FIRST_ROUND, Badge.NOVICE, Badge.INTERMEDIATE),
            Badges.earnedBy(listOf(first), first, zone, monday)
        )
    }

    @Test
    fun `a session is credited with what it added and nothing it found already earned`() {
        val first = attempt(start, rounds = 10)
        val second = attempt(start.plusDays(1), rounds = 10)
        val all = listOf(first, second)
        assertTrue(Badges.earnedBy(all, second, zone, monday).isEmpty())
        assertEquals(
            listOf(Badge.FIRST_CINDY, Badge.FIRST_ROUND, Badge.NOVICE, Badge.INTERMEDIATE),
            Badges.earnedBy(all, first, zone, monday)
        )
    }

    @Test
    fun `the session that completes a run is credited with the streak`() {
        val all = everyDay(3)
        assertEquals(listOf(Badge.STREAK_3), Badges.earnedBy(all, all.last(), zone, monday))
    }

    @Test
    fun `the session that makes a better score is credited with the next rung only`() {
        val first = attempt(start, rounds = 10)
        val better = attempt(start.plusDays(2), rounds = 17)
        assertEquals(
            listOf(Badge.ADVANCED),
            Badges.earnedBy(listOf(first, better), better, zone, monday)
        )
    }

    @Test
    fun `a session that was never stored is credited with nothing`() {
        val stored = attempt(start, rounds = 5)
        val unsaved = attempt(start.plusDays(1), rounds = 30)
        assertTrue(Badges.earnedBy(listOf(stored), unsaved, zone, monday).isEmpty())
        assertTrue(Badges.earnedBy(emptyList(), unsaved, zone, monday).isEmpty())
    }

    // ── progress ──────────────────────────────────────────────────────────────

    @Test
    fun `sessions progress counts every session and stops at the target`() {
        assertEquals(BadgeProgress(3, 10, "sessions"), progress(Badge.SESSIONS_10, spaced(3)))
        assertEquals(BadgeProgress(10, 10, "sessions"), progress(Badge.SESSIONS_10, spaced(12)))
    }

    @Test
    fun `rounds progress is the best exact standard session, not a total`() {
        val sessions = listOf(
            attempt(start, rounds = 8),
            attempt(start.plusDays(2), rounds = 6),
            attempt(start.plusDays(4), rounds = 12, profile = adaptive),
            attempt(start.plusDays(6), rounds = 15, untrackedMs = tolerance),
            attempt(start.plusDays(8), rounds = 15, profile = null)
        )
        assertEquals(BadgeProgress(8, 16, "rounds"), progress(Badge.ADVANCED, sessions))
    }

    @Test
    fun `days progress is the run that is still alive`() {
        val run = everyDay(3)
        val lastDay = start.plusDays(2)
        assertEquals(BadgeProgress(3, 7, "days"), progress(Badge.STREAK_7, run, today = lastDay))
        // Yesterday still counts: today is not over yet.
        assertEquals(BadgeProgress(3, 7, "days"), progress(Badge.STREAK_7, run, today = lastDay.plusDays(1)))
        // Two days of nothing ended it, whatever the run once was.
        assertEquals(BadgeProgress(0, 7, "days"), progress(Badge.STREAK_7, run, today = lastDay.plusDays(2)))
    }

    @Test
    fun `weeks progress is the run that is still alive`() {
        val run = everyWeek(2)
        val lastWeek = start.plusWeeks(1)
        assertEquals(BadgeProgress(2, 4, "weeks"), progress(Badge.WEEKS_4, run, today = lastWeek))
        assertEquals(
            BadgeProgress(2, 4, "weeks"), progress(Badge.WEEKS_4, run, today = lastWeek.plusWeeks(1))
        )
        assertEquals(
            BadgeProgress(0, 4, "weeks"), progress(Badge.WEEKS_4, run, today = lastWeek.plusWeeks(2))
        )
    }

    @Test
    fun `weeks progress counts weeks from where the locale starts them`() {
        // The four sessions of the week-start test above, on the Monday after the last of them.
        val sessions = listOf(
            attempt(start),
            attempt(start.plusDays(13)),
            attempt(start.plusDays(14)),
            attempt(start.plusDays(21))
        )
        val today = start.plusDays(21)
        assertEquals(
            BadgeProgress(4, 4, "weeks"),
            progress(Badge.WEEKS_4, sessions, today, DayOfWeek.MONDAY)
        )
        assertEquals(
            BadgeProgress(2, 4, "weeks"),
            progress(Badge.WEEKS_4, sessions, today, DayOfWeek.SUNDAY)
        )
    }

    @Test
    fun `days progress counts days on the athlete's calendar`() {
        // 23:50 and 00:10 in Bucharest: two days there, one on the UTC calendar.
        val sessions = listOf(
            Attempt(rounds = 10, reps = 0, atMillis = millis(start, 23, 50)),
            Attempt(rounds = 10, reps = 0, atMillis = millis(start.plusDays(1), 0, 10))
        )
        val today = start.plusDays(1)
        assertEquals(
            BadgeProgress(2, 3, "days"),
            Badges.progress(Badge.STREAK_3, sessions, today, zone, monday)
        )
        assertEquals(
            BadgeProgress(1, 3, "days"),
            Badges.progress(Badge.STREAK_3, sessions, today, ZoneId.of("UTC"), monday)
        )
    }

    @Test
    fun `reps progress is worded with thousands separators`() {
        val p = progress(Badge.REPS_5000, listOf(attempt(countedReps = 1_240)))
        assertEquals(BadgeProgress(1_240, 5_000, "reps"), p)
        assertEquals("1,240 of 5,000 reps", p!!.label)
        assertEquals("3 of 10 sessions", BadgeProgress(3, 10, "sessions").label)
    }

    @Test
    fun `a badge that is had or not has no progress to report`() {
        val yesOrNo = listOf(
            Badge.FIRST_CINDY, Badge.FIRST_ROUND, Badge.PAST_BENCHMARK, Badge.ROUND_UNDER_2,
            Badge.ROUND_UNDER_45, Badge.EVERY_REP_SEEN, Badge.MADE_IT_YOURS
        )
        val history = spaced(3)
        for (badge in yesOrNo) assertNull(badge.name, progress(badge, history))
        // And everything else does have a figure to show.
        for (badge in Badge.entries - yesOrNo.toSet()) {
            assertTrue("${badge.name} has no progress", progress(badge, history) != null)
        }
    }

    // ── the menu's line ───────────────────────────────────────────────────────

    private fun held(vararg sessions: Attempt): List<EarnedBadge> =
        Badges.earned(sessions.toList(), zone, monday)

    @Test
    fun `no badges, nothing to say`() {
        assertNull(Badges.headline(emptyList()))
        assertNull(Badges.highestLevel(emptyList()))
    }

    @Test
    fun `one badge is a badge, not badges`() {
        // A few reps and no whole round: First Cindy and nothing else.
        assertEquals("1 badge", Badges.headline(held(attempt(rounds = 0, reps = 3))))
    }

    @Test
    fun `the headline counts the badges and names the highest level among them`() {
        // Ten rounds: First Cindy, First round, Novice and Intermediate.
        val got = held(attempt(rounds = 10))
        assertEquals(Level.INTERMEDIATE, Badges.highestLevel(got))
        assertEquals("4 badges · Intermediate", Badges.headline(got))
    }

    @Test
    fun `a later, weaker session does not lower the level`() {
        val got = held(attempt(start, rounds = 17), attempt(start.plusDays(2), rounds = 6))
        assertEquals(Level.ADVANCED, Badges.highestLevel(got))
    }

    @Test
    fun `no level is named before the first rung is held`() {
        // First Cindy and First round, but short of the five rounds of Novice.
        val got = held(attempt(rounds = 4))
        assertNull(Badges.highestLevel(got))
        assertEquals("2 badges", Badges.headline(got))
    }

    @Test
    fun `a session the camera lost the athlete in names no level`() {
        val got = held(attempt(rounds = 27, untrackedMs = tolerance))
        assertNull(Badges.highestLevel(got))
        assertEquals("1 badge", Badges.headline(got))
    }

    @Test
    fun `the top of the ladder is Legend`() {
        assertEquals(Level.LEGEND, Badges.highestLevel(held(attempt(rounds = 30))))
    }

    // ── wording ───────────────────────────────────────────────────────────────

    @Test
    fun `a day is written the way every screen writes one`() {
        assertEquals("2 Mar 2026", Badges.day(millis(start), zone))
        assertEquals("12 Dec 2026", Badges.day(millis(LocalDate.of(2026, 12, 12)), zone))
    }

    @Test
    fun `the day is the athlete's own, so ten past midnight is already the new day`() {
        val justAfterMidnight = millis(start, 0, 10)
        assertEquals("2 Mar 2026", Badges.day(justAfterMidnight, zone))
        assertEquals("1 Mar 2026", Badges.day(justAfterMidnight, ZoneId.of("UTC")))
    }

    @Test
    fun `the month is in English whatever language the phone speaks`() {
        val saved = java.util.Locale.getDefault()
        try {
            java.util.Locale.setDefault(java.util.Locale.FRANCE)
            assertEquals("2 Mar 2026", Badges.day(millis(start), zone))
        } finally {
            java.util.Locale.setDefault(saved)
        }
    }

    @Test
    fun `the sheet says when a badge was earned, how far along it is, or that it is still to come`() {
        val won = EarnedBadge(Badge.SESSIONS_10, millis(start))
        assertEquals("Earned 2 Mar 2026", Badges.status(won, null, zone))
        // Once earned, the progress towards it is beside the point.
        assertEquals("Earned 2 Mar 2026", Badges.status(won, BadgeProgress(10, 10, "sessions"), zone))
        assertEquals("3 of 10 sessions", Badges.status(null, BadgeProgress(3, 10, "sessions"), zone))
        assertEquals("Not earned yet", Badges.status(null, null, zone))
    }

    @Test
    fun `a tile is described in one sentence`() {
        val won = EarnedBadge(Badge.SESSIONS_10, millis(start))
        assertEquals(
            "10 sessions, earned 2 Mar 2026",
            Badges.description(Badge.SESSIONS_10, won, null, zone)
        )
        assertEquals(
            "10 sessions, locked, 3 of 10 sessions",
            Badges.description(Badge.SESSIONS_10, null, BadgeProgress(3, 10, "sessions"), zone)
        )
        assertEquals("First Cindy, locked", Badges.description(Badge.FIRST_CINDY, null, null, zone))
    }

    @Test
    fun `the profile line says since when, and how many sessions`() {
        assertEquals(
            "Finish a session and your badges start here.",
            Badges.trainingLine(emptyList(), zone)
        )
        assertEquals(
            "Training since 2 Mar 2026 · 1 session",
            Badges.trainingLine(listOf(attempt(start)), zone)
        )
        // Given out of order, the first is still the earliest.
        val three = listOf(attempt(start.plusDays(9)), attempt(start), attempt(start.plusDays(4)))
        assertEquals("Training since 2 Mar 2026 · 3 sessions", Badges.trainingLine(three, zone))
    }
}
