package com.cindy.tracker

import java.util.Locale

/**
 * The reps banked by [clockMs] on the workout clock, and how many of those the athlete tapped in
 * rather than the camera seeing.
 */
data class RepPoint(val clockMs: Long, val reps: Int, val manualReps: Int)

/**
 * A session's cumulative reps over its clock, from the origin to the last rep.
 *
 * [exact] says where the points came from. True: one per rep, from the marks the workout itself
 * filed. False: one per finished set, from [Attempt.setSplits], for a session recorded before
 * rep times existed — the chart then joins sets, and says so, rather than inventing reps between
 * them.
 */
class RepSeries(val points: List<RepPoint>, val exact: Boolean) {

    /**
     * What had been banked at [clockMs]: the last point at or before it, so always a value that
     * really was banked. In per-set mode that is the last finished set, never a position between
     * two of them.
     */
    fun at(clockMs: Long): RepPoint {
        var lo = 0
        var hi = points.size
        while (lo < hi) {
            val mid = (lo + hi) ushr 1
            if (points[mid].clockMs <= clockMs) lo = mid + 1 else hi = mid
        }
        return points[(lo - 1).coerceAtLeast(0)]
    }
}

/** One movement block on the clock; [inProgress] when the clock stopped before it was finished. */
data class SetSpan(
    val startMs: Long,
    val endMs: Long,
    val movement: Exercise,
    val round: Int,
    val inProgress: Boolean
)

/** One round on the clock; [complete] is false only for the one still running when it stopped. */
data class RoundSpan(val number: Int, val startMs: Long, val endMs: Long, val complete: Boolean)

/** What the session is measured against, built from the reference attempt's own record. */
class ReferenceTimeline(
    val kind: Comparisons.Kind,
    val reps: RepSeries?,
    val roundEnds: List<Long>
) {
    /** How the reference is named in a sentence: "your best", "last time". */
    val phrase: String get() = if (kind == Comparisons.Kind.BEST) "your best" else "last time"
}

/** Everything the timeline knows about one instant of the clock. */
data class Moment(
    val clockMs: Long,
    /** The round in progress, which is the one just finished at the instant it finishes. */
    val round: Int?,
    val movement: Exercise?,
    val reps: Int?,
    val manualReps: Int,
    val bpm: Int?,
    /** The latest round both sessions had finished by [clockMs]. */
    val aheadRound: Int?,
    /** That round's end in the reference minus its end here: positive is ahead, or faster. */
    val aheadMs: Long?
)

/** The two lines above the chart; [detail] is null when there is nothing to add to [title]. */
data class Readout(val title: String, val detail: String?)

/**
 * A session laid out on its own clock: reps banked, heart rate, round ends, and the same for the
 * session it is being measured against. Pure, like [Comparisons], so every number the chart and
 * its readout claim can be tested without a phone.
 *
 * Each series says how far it can be trusted. Rep marks are used only when
 * [RepTimes.validFor] accepts them *for the attempt they were filed with* — the reviewed session
 * and the reference are checked separately, because one can have a file and the other, recorded
 * earlier, none. Otherwise the line falls back to the set splits, and failing that there is no
 * line at all rather than one drawn from `rounds * 30`. Nothing is ever interpolated between two
 * banked values: a rep count at an instant is the last one that was actually banked.
 */
class SessionTimeline private constructor(
    private val attempt: Attempt,
    val reps: RepSeries?,
    val roundEnds: List<Long>,
    val sets: List<SetSpan>,
    val rounds: List<RoundSpan>,
    /** Heart-rate samples, broken wherever the watch went quiet for longer than it could be held. */
    val heartRuns: List<List<HeartRateSample>>,
    val reference: ReferenceTimeline?
) {

    val durationMs: Long get() = attempt.durationMs

    /** There is something to draw: reps, or a heart rate. */
    val hasData: Boolean get() = durationMs > 0L && (reps != null || heartRuns.isNotEmpty())

    private val heart: List<HeartRateSample> = heartRuns.flatten()

    /** The latest sample no more than [Calories.MAX_HOLD_MS] before [clockMs]; none otherwise. */
    private fun bpmAt(clockMs: Long): Int? {
        val i = heart.indexOfLast { it.clockMs <= clockMs }
        if (i < 0) return null
        val s = heart[i]
        return if (clockMs - s.clockMs <= Calories.MAX_HOLD_MS) s.bpm else null
    }

    /**
     * Round [round]'s end in the reference minus its end here, when both sessions finished it.
     * Two exact clock times, never a position between them.
     */
    fun aheadOfReference(round: Int): Long? {
        val theirs = reference?.roundEnds?.getOrNull(round - 1) ?: return null
        val mine = roundEnds.getOrNull(round - 1) ?: return null
        return theirs - mine
    }

    fun at(clockMs: Long): Moment {
        val t = clockMs.coerceIn(0L, durationMs)
        // A round is still "in progress" at the instant it ends, so that the stop for a round and
        // the cursor sitting on its end agree about which round it is.
        val round = if (rounds.isEmpty()) null
        else minOf(roundEnds.count { it < t } + 1, rounds.size)
        val movement = sets.firstOrNull { t <= it.endMs }?.movement
            ?: sets.lastOrNull()?.movement
        val point = reps?.at(t)
        val finishedHere = roundEnds.count { it <= t }
        val finishedThere = reference?.roundEnds?.count { it <= t } ?: 0
        val common = minOf(finishedHere, finishedThere)
        val ahead = if (common >= 1) aheadOfReference(common) else null
        return Moment(
            clockMs = t,
            round = round,
            movement = movement,
            reps = point?.reps,
            manualReps = point?.manualReps ?: 0,
            bpm = bpmAt(t),
            aheadRound = if (ahead != null) common else null,
            aheadMs = ahead
        )
    }

    /** The mean of the samples inside [startMs]..[endMs], or null when the watch said nothing. */
    fun averageBpm(startMs: Long, endMs: Long): Int? {
        val inside = heart.filter { it.clockMs in startMs..endMs }
        if (inside.isEmpty()) return null
        return Math.round(inside.sumOf { it.bpm }.toDouble() / inside.size).toInt()
    }

    private val manualInSession: Boolean get() = (reps?.points?.lastOrNull()?.manualReps ?: 0) > 0

    private fun repsPhrase(count: Int, manual: Int): String {
        val base = "${if (attempt.scoreIsLowerBound) "at least " else ""}$count rep${if (count == 1) "" else "s"}"
        return if (manual > 0) "$base, $manual by hand" else base
    }

    private fun movementName(m: Exercise): String {
        val profile = attempt.profile
        val standard = CindyProfile.STANDARD
        // The profile's own plural names what was actually done; the plain movement name is only
        // right when that is what the athlete did, and for a record whose movements this build
        // does not know (a null profile) it is the only name there is.
        val plural = when {
            profile == null -> m.label
            m == Exercise.PULLUP -> if (profile.pull == standard.pull) m.label else profile.pull.plural
            m == Exercise.PUSHUP -> if (profile.push == standard.push) m.label else profile.push.plural
            else -> if (profile.squat == standard.squat) m.label else profile.squat.plural
        }
        return plural.lowercase(Locale.US).replaceFirstChar { it.uppercase(Locale.US) }
    }

    private fun aheadPhrase(ms: Long, spoken: Boolean): String {
        val name = reference?.phrase ?: return ""
        val seconds = Math.round(ms / 1000.0)
        val amount = if (spoken) spokenSeconds(Math.abs(seconds)) else shortSeconds(Math.abs(seconds))
        return when {
            seconds > 0 -> "$amount ahead of $name"
            seconds < 0 -> "$amount behind $name"
            else -> "level with $name"
        }
    }

    /** Nothing selected: the whole session in a line, "20:00 · 7 rounds + 12". */
    fun idleReadout(): Readout {
        val r = attempt.rounds
        val rounds = "$r round${if (r == 1) "" else "s"}"
        val loose = if (attempt.reps > 0) " + ${attempt.reps}" else ""
        return Readout("${formatDuration(durationMs)} · $rounds$loose", null)
    }

    /** "12:34 · Round 6 · Push-ups" over "171 reps · 158 bpm · round 5: 38 s ahead of your best". */
    fun readout(m: Moment): Readout {
        val title = listOfNotNull(
            formatDuration(m.clockMs),
            m.round?.let { "Round $it" },
            m.movement?.let { movementName(it) }
        ).joinToString(" · ")
        val parts = listOfNotNull(
            m.reps?.let { repsPhrase(it, m.manualReps) },
            m.bpm?.let { "$it bpm" },
            m.aheadMs?.let { "round ${m.aheadRound}: ${aheadPhrase(it, spoken = false)}" }
        )
        return Readout(title, parts.joinToString(" · ").ifEmpty { null })
    }

    /**
     * What TalkBack reads for one round: when it ran, how long it took, what had been banked by
     * its end, its heart rate and how it went against the reference.
     */
    fun describeRound(round: RoundSpan): String {
        val parts = mutableListOf<String>()
        parts += "Round ${round.number}"
        parts += if (round.complete) {
            "${formatDuration(round.startMs)} to ${formatDuration(round.endMs)}"
        } else {
            "in progress, ${formatDuration(round.startMs)} to the end at ${formatDuration(round.endMs)}"
        }
        if (round.complete) parts += spokenDuration(round.endMs - round.startMs)
        reps?.at(round.endMs)?.let {
            parts += "${repsPhrase(it.reps, it.manualReps)} by ${if (round.complete) "its" else "the"} end"
        }
        averageBpm(round.startMs, round.endMs)?.let { parts += "$it beats per minute on average" }
        if (round.complete) aheadOfReference(round.number)?.let { parts += aheadPhrase(it, spoken = true) }
        return parts.joinToString(", ")
    }

    /**
     * One line saying what the dashed line is, and anything about how the reps are plotted that a
     * reader would otherwise take for more precision than there is. Null when there is nothing to
     * say.
     */
    fun legend(): String? {
        val parts = mutableListOf<String>()
        val ref = reference
        if (ref?.reps != null) {
            parts += "Dashed: ${ref.phrase}."
        }
        val mine = reps != null && !reps.exact
        val theirs = ref?.reps != null && !ref.reps.exact
        when {
            mine && theirs -> parts += "Reps are plotted per set for both sessions."
            mine -> parts += "Reps are plotted per set for this session."
            theirs -> parts += "Reps are plotted per set for ${ref!!.phrase}."
        }
        if (manualInSession) parts += "Reps added by hand count, but the camera did not see them."
        return parts.joinToString(" ").ifEmpty { null }
    }

    companion object {

        /**
         * [marks] and [referenceMarks] are whatever [RepTimesStore.load] answered for each
         * attempt, validated here against the attempt each belongs to. [trace] is the reviewed
         * session's own heart rate; the reference's is never drawn.
         */
        fun of(
            attempt: Attempt,
            marks: List<RepMark>?,
            trace: HeartRateTrace?,
            reference: Attempt? = null,
            referenceKind: Comparisons.Kind? = null,
            referenceMarks: List<RepMark>? = null
        ): SessionTimeline {
            val ends = roundEnds(attempt)
            val sets = setSpans(attempt)
            return SessionTimeline(
                attempt = attempt,
                reps = repSeries(attempt, marks),
                roundEnds = ends,
                sets = sets,
                rounds = roundSpans(attempt, ends),
                heartRuns = heartRuns(attempt, trace),
                reference = if (reference == null || referenceKind == null) null
                else ReferenceTimeline(
                    referenceKind, repSeries(reference, referenceMarks), roundEnds(reference)
                )
            )
        }

        /** Where each finished round ended on the clock, for plotting no later than the clock itself. */
        internal fun roundEnds(a: Attempt): List<Long> {
            var sum = 0L
            return a.roundSplitsMs.map { sum += it; minOf(sum, a.durationMs) }
        }

        internal fun roundSpans(a: Attempt, ends: List<Long>): List<RoundSpan> {
            val out = mutableListOf<RoundSpan>()
            var start = 0L
            ends.forEachIndexed { i, end ->
                out += RoundSpan(i + 1, start, end, complete = true)
                start = end
            }
            if (a.durationMs > start) out += RoundSpan(ends.size + 1, start, a.durationMs, complete = false)
            return out
        }

        internal fun setSpans(a: Attempt): List<SetSpan> {
            val out = mutableListOf<SetSpan>()
            var start = 0L
            a.setSplits.forEachIndexed { i, s ->
                val end = minOf(start + s.ms, a.durationMs)
                out += SetSpan(start, end, s.movement, i / 3 + 1, inProgress = false)
                start = end
            }
            // The movement still running when the clock stopped never reached an event of its own,
            // so it is not in the splits; it is whichever one follows the last that was. With no
            // splits at all the record predates set times, and which movement it was in is unknown
            // rather than the first.
            val last = a.setSplits.lastOrNull()
            if (last != null && a.durationMs > start) {
                out += SetSpan(
                    start, a.durationMs, last.movement.next(), a.setSplits.size / 3 + 1,
                    inProgress = true
                )
            }
            return out
        }

        /**
         * One point per rep when [marks] are this attempt's own, else one per finished set, else
         * null. A series with nothing banked in it is null too: a flat line at zero says less
         * than no chart.
         */
        internal fun repSeries(a: Attempt, marks: List<RepMark>?): RepSeries? {
            if (marks != null && marks.isNotEmpty() && RepTimes.validFor(marks, a)) {
                var manual = 0
                val points = mutableListOf(RepPoint(0L, 0, 0))
                marks.forEachIndexed { i, m ->
                    if (m.manual) manual++
                    points += RepPoint(m.clockMs.coerceIn(0L, a.durationMs), i + 1, manual)
                }
                return RepSeries(points, exact = true)
            }
            return setSeries(a)
        }

        private fun setSeries(a: Attempt): RepSeries? {
            if (a.setSplits.isEmpty()) return null
            val total = a.setSplits.sumOf { it.reps }
            // More banked in the sets than in the whole session means the record disagrees with
            // itself; a chart built on it would be a guess wearing banked numbers.
            if (a.countedReps != null && total > a.countedReps) return null
            val spans = setSpans(a).filter { !it.inProgress }
            var reps = 0
            var manual = 0
            val points = mutableListOf(RepPoint(0L, 0, 0))
            spans.forEachIndexed { i, span ->
                reps += a.setSplits[i].reps
                manual += a.setSplits[i].manualReps
                points += RepPoint(span.endMs, reps, manual)
            }
            // The clock stopping is a banked instant too: the total counted by then.
            val counted = a.countedReps
            if (counted != null && counted > reps && a.durationMs > points.last().clockMs) {
                points += RepPoint(a.durationMs, counted, minOf(a.manualReps, counted))
            }
            return if (points.last().reps > 0) RepSeries(points, exact = false) else null
        }

        /**
         * The samples inside the workout clock, cut wherever the gap to the next exceeds
         * [Calories.MAX_HOLD_MS] — the same line [Calories] stops holding a reading at, so the
         * chart and the calorie estimate cannot disagree about when the watch was silent.
         */
        internal fun heartRuns(a: Attempt, trace: HeartRateTrace?): List<List<HeartRateSample>> {
            val usable = trace?.samples.orEmpty()
                .filter {
                    it.clockMs in 0L until a.durationMs &&
                        it.bpm in HeartRateMeasurement.MIN_BPM..HeartRateMeasurement.MAX_BPM
                }
                .sortedBy { it.clockMs }
            if (usable.isEmpty()) return emptyList()
            val runs = mutableListOf(mutableListOf(usable.first()))
            for (i in 1 until usable.size) {
                if (usable[i].clockMs - usable[i - 1].clockMs > Calories.MAX_HOLD_MS) {
                    runs += mutableListOf<HeartRateSample>()
                }
                runs.last() += usable[i]
            }
            return runs
        }

        /** "38 s", "1 min 5 s". */
        internal fun shortSeconds(seconds: Long): String =
            if (seconds < 60) "$seconds s" else "${seconds / 60} min ${seconds % 60} s"

        /** "38 seconds", "1 minute 5 seconds", "2 minutes". */
        internal fun spokenSeconds(seconds: Long): String {
            val m = seconds / 60
            val s = seconds % 60
            val minutes = "$m minute${if (m == 1L) "" else "s"}"
            val secs = "$s second${if (s == 1L) "" else "s"}"
            return when {
                m == 0L -> secs
                s == 0L -> minutes
                else -> "$minutes $secs"
            }
        }

        internal fun spokenDuration(ms: Long): String = spokenSeconds(Math.round(ms / 1000.0))
    }
}
