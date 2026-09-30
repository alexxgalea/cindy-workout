package com.cindy.tracker

import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.min

/** What a badge is about, in the order the profile lists them. */
enum class BadgeFamily(val label: String) {
    SESSIONS("Sessions"),
    ROUNDS("Rounds"),
    STREAKS("Streaks"),
    VOLUME("Volume"),
    PACE("Pace"),
    CRAFT("Craft")
}

/** What earns a badge, so that one evaluator reads the whole catalogue. */
internal enum class BadgeRule {
    /** Sessions finished, of any kind. */
    SESSIONS,

    /** Rounds in one standard Cindy the camera could stand behind. */
    ROUND_COUNT,

    /** A standard Cindy that passed the benchmark. */
    BENCHMARK,

    /** Consecutive days trained. */
    DAYS,

    /** Consecutive weeks trained. */
    WEEKS,

    /** Reps across every session. */
    REPS,

    /** A round in a standard Cindy faster than a number of seconds. */
    ROUND_SECONDS,

    /**
     * A whole twenty minutes the camera read, with nothing tapped in, in a session recorded by a
     * build that counted reps, since an older one cannot say whether anything was.
     */
    EVERY_REP_SEEN,

    /** A session at movements other than the standard three. */
    ADAPTIVE
}

private fun rungRequirement(level: Level, rest: String = ""): String =
    "${level.minRounds} rounds in a standard Cindy$rest."

/**
 * Everything an athlete can earn, in the order the profile shows it.
 *
 * Each badge is a fact about the sessions already recorded, worked out by [Badges] rather than
 * stored: it cannot disagree with the record board, it comes back with it from a backup, and it
 * goes when the records are cleared. Nothing here is a reward for opening the app.
 *
 * The rules follow the ones the rest of the app already keeps. A badge about a score is earned
 * only by a standard Cindy the camera could stand behind, the same line a personal record draws,
 * because the rungs are calibrated against the strict workout. A badge about showing up counts
 * every session, lower-bound and adaptive included, because those were still sessions. The round
 * rungs are read from [Level], so retuning the ladder retunes them.
 */
enum class Badge(
    val title: String,
    /** What the badge shows inside its disc: a few characters at most. */
    val face: String,
    val requirement: String,
    val family: BadgeFamily,
    internal val rule: BadgeRule,
    /** The figure the rule compares against: sessions, rounds, days, weeks, reps or seconds. */
    internal val target: Int = 0
) {
    FIRST_CINDY(
        "First Cindy", "1st", "Finish your first session.",
        BadgeFamily.SESSIONS, BadgeRule.SESSIONS, 1
    ),
    SESSIONS_10(
        "10 sessions", "×10", "Finish 10 sessions.",
        BadgeFamily.SESSIONS, BadgeRule.SESSIONS, 10
    ),
    SESSIONS_25(
        "25 sessions", "×25", "Finish 25 sessions.",
        BadgeFamily.SESSIONS, BadgeRule.SESSIONS, 25
    ),
    SESSIONS_50(
        "50 sessions", "×50", "Finish 50 sessions.",
        BadgeFamily.SESSIONS, BadgeRule.SESSIONS, 50
    ),
    SESSIONS_100(
        "100 sessions", "×100", "Finish 100 sessions.",
        BadgeFamily.SESSIONS, BadgeRule.SESSIONS, 100
    ),

    FIRST_ROUND(
        "First round", "R1", "Complete a round of standard Cindy.",
        BadgeFamily.ROUNDS, BadgeRule.ROUND_COUNT, 1
    ),
    NOVICE(
        Level.NOVICE.title, "${Level.NOVICE.minRounds}R", rungRequirement(Level.NOVICE),
        BadgeFamily.ROUNDS, BadgeRule.ROUND_COUNT, Level.NOVICE.minRounds
    ),
    INTERMEDIATE(
        Level.INTERMEDIATE.title, "${Level.INTERMEDIATE.minRounds}R",
        rungRequirement(Level.INTERMEDIATE, " — a complete Cindy"),
        BadgeFamily.ROUNDS, BadgeRule.ROUND_COUNT, Level.INTERMEDIATE.minRounds
    ),
    ADVANCED(
        Level.ADVANCED.title, "${Level.ADVANCED.minRounds}R", rungRequirement(Level.ADVANCED),
        BadgeFamily.ROUNDS, BadgeRule.ROUND_COUNT, Level.ADVANCED.minRounds
    ),
    ELITE(
        Level.ELITE.title, "${Level.ELITE.minRounds}R", rungRequirement(Level.ELITE),
        BadgeFamily.ROUNDS, BadgeRule.ROUND_COUNT, Level.ELITE.minRounds
    ),
    LEGEND(
        Level.LEGEND.title, "${Level.LEGEND.minRounds}R",
        rungRequirement(Level.LEGEND, " — level with ${Records.BENCHMARK_NAME}"),
        BadgeFamily.ROUNDS, BadgeRule.ROUND_COUNT, Level.LEGEND.minRounds
    ),
    PAST_BENCHMARK(
        "Past ${Records.BENCHMARK_NAME}", "${Records.BENCHMARK.totalReps}+",
        "Beat ${Records.BENCHMARK.rounds} rounds in a standard Cindy.",
        BadgeFamily.ROUNDS, BadgeRule.BENCHMARK
    ),

    STREAK_3(
        "3 days in a row", "3d", "Train 3 days in a row.",
        BadgeFamily.STREAKS, BadgeRule.DAYS, 3
    ),
    STREAK_7(
        "7 days in a row", "7d", "Train 7 days in a row.",
        BadgeFamily.STREAKS, BadgeRule.DAYS, 7
    ),
    STREAK_14(
        "14 days in a row", "14d", "Train 14 days in a row.",
        BadgeFamily.STREAKS, BadgeRule.DAYS, 14
    ),
    STREAK_30(
        "30 days in a row", "30d", "Train 30 days in a row.",
        BadgeFamily.STREAKS, BadgeRule.DAYS, 30
    ),
    WEEKS_4(
        "4 weeks in a row", "4w", "Train in 4 weeks in a row.",
        BadgeFamily.STREAKS, BadgeRule.WEEKS, 4
    ),
    WEEKS_12(
        "12 weeks in a row", "12w", "Train in 12 weeks in a row.",
        BadgeFamily.STREAKS, BadgeRule.WEEKS, 12
    ),
    WEEKS_26(
        "26 weeks in a row", "26w", "Train in 26 weeks in a row.",
        BadgeFamily.STREAKS, BadgeRule.WEEKS, 26
    ),

    REPS_1000(
        "1,000 reps", "1k", "1,000 reps across all sessions.",
        BadgeFamily.VOLUME, BadgeRule.REPS, 1_000
    ),
    REPS_5000(
        "5,000 reps", "5k", "5,000 reps across all sessions.",
        BadgeFamily.VOLUME, BadgeRule.REPS, 5_000
    ),
    REPS_10000(
        "10,000 reps", "10k", "10,000 reps across all sessions.",
        BadgeFamily.VOLUME, BadgeRule.REPS, 10_000
    ),

    // The two marks for a round that the Help screen quotes.
    ROUND_UNDER_2(
        "Round under 2 minutes", "2:00", "A round under 2:00 in a standard Cindy.",
        BadgeFamily.PACE, BadgeRule.ROUND_SECONDS, 120
    ),
    ROUND_UNDER_45(
        "Round under 45 seconds", "0:45", "A round under 0:45 in a standard Cindy.",
        BadgeFamily.PACE, BadgeRule.ROUND_SECONDS, 45
    ),

    EVERY_REP_SEEN(
        "Every rep seen", "100%",
        "A full 20 minutes with no reps tapped in and the camera keeping track of you.",
        BadgeFamily.CRAFT, BadgeRule.EVERY_REP_SEEN
    ),
    MADE_IT_YOURS(
        "Made it yours", "A", "Finish an Adaptive Cindy.",
        BadgeFamily.CRAFT, BadgeRule.ADAPTIVE
    )
}

/** A badge, and the session that first earned it. */
data class EarnedBadge(val badge: Badge, val atMillis: Long)

/** How far along a badge that is not yet earned is. */
data class BadgeProgress(val current: Int, val target: Int, val unit: String) {
    /** "1,240 of 5,000 reps", said the same way on the tile and in its sheet. */
    val label: String
        get() = "${Progress.formatReps(current)} of ${Progress.formatReps(target)} $unit"
}

/**
 * Works the badges out from the recorded sessions.
 *
 * Pure: no clock of its own and no zone of its own, like [Streak] and [Peaks], which it leans on
 * for what a day and a week are. Nothing is remembered between calls, so a badge is always the
 * answer to "what do these sessions add up to", never to "what was once awarded".
 */
object Badges {

    /** A score is only ever credited to a standard Cindy the camera could stand behind. */
    private fun standardAndExact(a: Attempt): Boolean =
        a.profile?.isStandard == true && !a.scoreIsLowerBound

    /**
     * Every badge earned, in catalogue order, each stamped with the session that first earned it.
     *
     * The sessions are replayed oldest first, keeping what a rule needs as it goes: how many,
     * how many reps, which days and weeks were trained. Replaying rather than asking once is
     * what makes the stamp honest: a later, better session does not take an earlier one's badge.
     */
    fun earned(
        attempts: List<Attempt>,
        zone: ZoneId,
        firstDayOfWeek: DayOfWeek
    ): List<EarnedBadge> {
        val stamps = LinkedHashMap<Badge, Long>()
        var sessions = 0
        var reps = 0
        val days = HashSet<LocalDate>()
        val weeks = HashSet<LocalDate>()

        for (a in attempts.sortedBy { it.atMillis }) {
            sessions++
            reps += a.totalReps
            val day = Progress.localDate(a, zone)
            val week = Streak.weekStart(day, firstDayOfWeek)
            days += day
            weeks += week
            // Sessions arrive oldest first, so a run can only have grown at its end.
            val dayRun = runEndingAt(day, days) { it.minusDays(1) }
            val weekRun = runEndingAt(week, weeks) { it.minusWeeks(1) }

            for (badge in Badge.entries) {
                if (badge !in stamps && met(badge, a, sessions, reps, dayRun, weekRun)) {
                    stamps[badge] = a.atMillis
                }
            }
        }
        return Badge.entries.mapNotNull { badge ->
            stamps[badge]?.let { EarnedBadge(badge, it) }
        }
    }

    /**
     * The badges [attempt] itself earned: the ones whose stamp is this session.
     *
     * Empty for a session that was never stored. Nothing is stamped with a moment that no stored
     * session has, which is the same rule [Cheer.forResult] states outright: a score that was
     * never filed has earned nothing.
     */
    fun earnedBy(
        attempts: List<Attempt>,
        attempt: Attempt,
        zone: ZoneId,
        firstDayOfWeek: DayOfWeek
    ): List<Badge> = earned(attempts, zone, firstDayOfWeek)
        .filter { it.atMillis == attempt.atMillis }
        .map { it.badge }

    /**
     * How far along [badge] is, or null for one that is simply had or not.
     *
     * Only the badges that count something have a figure: sessions, rounds, days, weeks and
     * reps. "Complete a round" at one of one is a yes or a no, and saying "0 of 1" beside it
     * would be noise.
     */
    fun progress(
        badge: Badge,
        attempts: List<Attempt>,
        today: LocalDate,
        zone: ZoneId,
        firstDayOfWeek: DayOfWeek
    ): BadgeProgress? {
        val target = badge.target
        if (target <= 1) return null
        return when (badge.rule) {
            BadgeRule.SESSIONS ->
                BadgeProgress(min(attempts.size, target), target, "sessions")
            BadgeRule.ROUND_COUNT -> {
                val best = attempts.filter(::standardAndExact).maxOfOrNull { it.rounds } ?: 0
                BadgeProgress(min(best, target), target, "rounds")
            }
            BadgeRule.DAYS -> {
                val current = Streak.current(Streak.daysTrained(attempts, zone), today)
                BadgeProgress(min(current, target), target, "days")
            }
            BadgeRule.WEEKS -> {
                val weeks = Streak.weeksTrained(Streak.daysTrained(attempts, zone), firstDayOfWeek)
                val current = Streak.currentWeeks(weeks, today, firstDayOfWeek)
                BadgeProgress(min(current, target), target, "weeks")
            }
            BadgeRule.REPS ->
                BadgeProgress(min(attempts.sumOf { it.totalReps }, target), target, "reps")
            BadgeRule.BENCHMARK,
            BadgeRule.ROUND_SECONDS,
            BadgeRule.EVERY_REP_SEEN,
            BadgeRule.ADAPTIVE -> null
        }
    }

    /** A day the way every screen here writes one: "12 Mar 2026", in English whatever the phone speaks. */
    fun day(atMillis: Long, zone: ZoneId): String =
        DateTimeFormatter.ofPattern("d MMM yyyy", Locale.US)
            .format(Instant.ofEpochMilli(atMillis).atZone(zone))

    /**
     * The line on a badge's sheet: when it was earned, how far along it is, or that it is still
     * to come.
     */
    fun status(earned: EarnedBadge?, progress: BadgeProgress?, zone: ZoneId): String = when {
        earned != null -> "Earned ${day(earned.atMillis, zone)}"
        progress != null -> progress.label
        else -> "Not earned yet"
    }

    /**
     * What a tile in the grid says to a screen reader. One sentence, because the tile is one
     * control, and it says the same thing the sheet behind it does.
     */
    fun description(
        badge: Badge,
        earned: EarnedBadge?,
        progress: BadgeProgress?,
        zone: ZoneId
    ): String = when {
        earned != null -> "${badge.title}, earned ${day(earned.atMillis, zone)}"
        progress != null -> "${badge.title}, locked, ${progress.label}"
        else -> "${badge.title}, locked"
    }

    /** The line under the athlete's name on the profile screen. */
    fun trainingLine(attempts: List<Attempt>, zone: ZoneId): String {
        if (attempts.isEmpty()) return "Finish a session and your badges start here."
        val first = attempts.minOf { it.atMillis }
        val sessions = if (attempts.size == 1) "1 session" else "${attempts.size} sessions"
        return "Training since ${day(first, zone)} \u00B7 $sessions"
    }

    /**
     * The highest rung of the ladder among the badges held, or null before the first.
     *
     * Read from the badges rather than from the sessions, so that whatever the menu says the
     * athlete has reached is something they can open their profile and see earned: a session the
     * camera could not stand behind never earns a rung, and so never gets one named here either.
     */
    fun highestLevel(earned: List<EarnedBadge>): Level? = Level.entries.lastOrNull { level ->
        earned.any { it.badge.rule == BadgeRule.ROUND_COUNT && it.badge.target == level.minRounds }
    }

    /**
     * What the menu says under the athlete's name: how many badges, and the highest level among
     * them. Null while there are none, because "0 badges" is a reproach rather than a fact.
     */
    fun headline(earned: List<EarnedBadge>): String? {
        if (earned.isEmpty()) return null
        val count = if (earned.size == 1) "1 badge" else "${earned.size} badges"
        return highestLevel(earned)?.let { "$count · ${it.title}" } ?: count
    }

    private fun met(
        badge: Badge,
        a: Attempt,
        sessions: Int,
        reps: Int,
        dayRun: Int,
        weekRun: Int
    ): Boolean = when (badge.rule) {
        BadgeRule.SESSIONS -> sessions >= badge.target
        BadgeRule.ROUND_COUNT -> standardAndExact(a) && a.rounds >= badge.target
        BadgeRule.BENCHMARK -> Records.beatsBenchmark(a)
        BadgeRule.DAYS -> dayRun >= badge.target
        BadgeRule.WEEKS -> weekRun >= badge.target
        BadgeRule.REPS -> reps >= badge.target
        BadgeRule.ROUND_SECONDS ->
            standardAndExact(a) && (a.fastestRoundMs ?: Long.MAX_VALUE) < badge.target * 1_000L
        // Only a session from a build that counted reps can say none were tapped in. An older one
        // decodes with no taps and no blind time because they were not recorded, not because
        // there were none, and "the camera saw every rep" is not a claim to make from that.
        BadgeRule.EVERY_REP_SEEN ->
            a.countedReps != null && Progress.isFullSession(a) && a.manualReps == 0 &&
                !a.scoreIsLowerBound && a.totalReps > 0
        // A profile this build cannot read is not claimed as an adaptation: what it was is unknown.
        BadgeRule.ADAPTIVE -> a.profile?.isStandard == false
    }

    /** How many steps back from [end], one [previous] at a time, are all in [present]. */
    private fun runEndingAt(
        end: LocalDate,
        present: Set<LocalDate>,
        previous: (LocalDate) -> LocalDate
    ): Int {
        var length = 0
        var cursor = end
        while (cursor in present) {
            length++
            cursor = previous(cursor)
        }
        return length
    }
}
