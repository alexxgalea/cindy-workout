package com.cindy.tracker

import android.content.Context
import android.content.SharedPreferences
import java.util.Locale

/** One finished attempt at Cindy. */
data class Attempt(
    val rounds: Int,
    val reps: Int,
    val atMillis: Long,
    /** Clock time: how long the workout timer actually ran, pauses excluded. */
    val durationMs: Long = 0L,
    /** Time spent paused. Hidden from the workout clock but not from the day. */
    val pausedMs: Long = 0L,
    /** Clock time for each *completed* round, in order, pauses excluded. */
    val roundSplitsMs: List<Long> = emptyList(),
    /**
     * The movements this score was actually produced with.
     *
     * Null means the attempt was written by a build that knew a movement this one does not.
     * Deliberately not defaulted to standard in that case: quietly relabelling someone's
     * band-assisted session as strict is exactly the dishonesty [CindyProfile] exists to stop.
     * Attempts written before variations existed decode as standard, because they were.
     */
    val profile: CindyProfile? = CindyProfile.STANDARD,
    /**
     * How many of [totalReps] were tapped in rather than seen.
     *
     * Kept because "87 reps" and "87 reps, 12 of them by hand" are different claims, and the
     * app is not entitled to make the first one when the second is true.
     */
    val manualReps: Int = 0
) {
    val totalReps: Int get() = rounds * 30 + reps

    /**
     * The ladder rung this score earns, or null when the ladder does not describe it.
     *
     * The levels are calibrated against strict Cindy and top out level with [Records.BENCHMARK],
     * so awarding "Legend" for twenty-seven rounds of knee push-ups would be telling the athlete
     * something untrue about a benchmark they did not attempt. An adaptive session is a
     * different prescription, not a lower score, and it is ranked against its own kind instead.
     */
    val level: Level? get() = if (profile?.isStandard == true) Level.of(rounds) else null

    /** Wall time from first rep to last, including everything spent paused. */
    val realTimeMs: Long get() = durationMs + pausedMs

    /**
     * What to print beside the score.
     *
     * A standard Cindy earns a rung on the ladder. Anything else says what it actually was,
     * because the rung would be a claim about a workout the athlete did not attempt.
     */
    val caption: String
        get() = level?.title ?: profile?.label() ?: "Movements not recognised"

    /** "27 + 12" — the way an AMRAP score is normally written. */
    fun scoreLabel(): String = if (reps == 0) "$rounds" else "$rounds + $reps"

    /**
     * Mean time per completed round. Prefers the splits, which cover only whole rounds; falls
     * back to dividing the duration, which charges the unfinished round to the average.
     */
    val avgRoundMs: Long?
        get() = when {
            roundSplitsMs.isNotEmpty() -> roundSplitsMs.sum() / roundSplitsMs.size
            rounds > 0 && durationMs > 0L -> durationMs / rounds
            else -> null
        }

    val fastestRoundMs: Long? get() = roundSplitsMs.minOrNull()
    val slowestRoundMs: Long? get() = roundSplitsMs.maxOrNull()
}

/** m:ss, for round splits and totals alike. */
fun formatDuration(ms: Long): String {
    val total = ms / 1000L
    return String.format(Locale.US, "%d:%02d", total / 60, total % 60)
}

/**
 * Serialisation and ranking for the record board.
 *
 * Kept free of Android types on purpose: this is the part with logic worth testing, and
 * SharedPreferences and org.json are both unavailable in plain JVM unit tests.
 */
object Records {

    /** The score that started this whole thing. */
    const val BENCHMARK_NAME = "Tom Holland"
    val BENCHMARK = Attempt(rounds = 27, reps = 0, atMillis = 0L, durationMs = 20 * 60 * 1000L)

    private const val V3 = "v3"
    private const val V4 = "v4"

    fun encode(attempts: List<Attempt>): String = attempts.joinToString("\n") { a ->
        listOf(
            V4,
            a.rounds.toString(),
            a.reps.toString(),
            a.atMillis.toString(),
            a.durationMs.toString(),
            a.pausedMs.toString(),
            a.roundSplitsMs.joinToString(","),
            a.profile?.pull?.name.orEmpty(),
            a.profile?.push?.name.orEmpty(),
            a.profile?.squat?.name.orEmpty(),
            a.manualReps.toString()
        ).joinToString("|")
    }

    fun decode(raw: String?): List<Attempt> {
        if (raw.isNullOrBlank()) return emptyList()
        return raw.lineSequence().mapNotNull { line ->
            when {
                line.startsWith("$V4|") -> decodeV4(line)
                // Attempts written before the movement profile was recorded. They predate the
                // choice existing, so standard is what they were, not an assumption about them.
                line.startsWith("$V3|") -> decodeV3(line)
                // Attempts written before splits and pauses were recorded.
                else -> decodeV1(line)
            }
        }.toList()
    }

    private fun decodeV4(line: String): Attempt? {
        val p = line.split("|")
        if (p.size != 11) return null
        val rounds = p[1].toIntOrNull() ?: return null
        val reps = p[2].toIntOrNull() ?: return null
        val at = p[3].toLongOrNull() ?: return null
        val duration = p[4].toLongOrNull() ?: return null
        val paused = p[5].toLongOrNull() ?: return null
        val splits = p[6].split(",").mapNotNull { it.toLongOrNull() }
        // A movement name this build does not know leaves the profile unknown rather than
        // guessing at it; the attempt itself is still the athlete's and is kept.
        val pull = enumOrNull<PullVariant>(p[7])
        val push = enumOrNull<PushVariant>(p[8])
        val squat = enumOrNull<SquatVariant>(p[9])
        val profile =
            if (pull != null && push != null && squat != null) CindyProfile(pull, push, squat)
            else null
        return Attempt(rounds, reps, at, duration, paused, splits, profile, p[10].toIntOrNull() ?: 0)
    }

    private inline fun <reified T : Enum<T>> enumOrNull(name: String): T? =
        enumValues<T>().firstOrNull { it.name == name }

    private fun decodeV3(line: String): Attempt? {
        val p = line.split("|")
        if (p.size != 7) return null
        val rounds = p[1].toIntOrNull() ?: return null
        val reps = p[2].toIntOrNull() ?: return null
        val at = p[3].toLongOrNull() ?: return null
        val duration = p[4].toLongOrNull() ?: return null
        val paused = p[5].toLongOrNull() ?: return null
        val splits = p[6].split(",").mapNotNull { it.toLongOrNull() }
        return Attempt(rounds, reps, at, duration, paused, splits)
    }

    private fun decodeV1(line: String): Attempt? {
        val p = line.split(",")
        if (p.size != 3) return null
        val rounds = p[0].toIntOrNull() ?: return null
        val reps = p[1].toIntOrNull() ?: return null
        val at = p[2].toLongOrNull() ?: return null
        return Attempt(rounds, reps, at)
    }

    /** Best score first; ties broken by the more recent attempt. */
    fun ranked(attempts: List<Attempt>): List<Attempt> =
        attempts.sortedWith(compareByDescending<Attempt> { it.totalReps }.thenByDescending { it.atMillis })

    fun best(attempts: List<Attempt>): Attempt? = ranked(attempts).firstOrNull()

    /**
     * Whether this score passes [BENCHMARK].
     *
     * Only a standard Cindy can: the benchmark is a strict score, so comparing an adaptive one
     * against it would be scoring two different workouts on one scale in whichever direction
     * happened to flatter.
     */
    fun beatsBenchmark(a: Attempt): Boolean =
        a.profile?.isStandard == true && a.totalReps > BENCHMARK.totalReps

    /**
     * The attempts a given score may honestly be ranked against: the same movements, exactly.
     *
     * Not "standard versus everything else" — a band-assisted Cindy and a knee-push-up Cindy are
     * no more comparable to each other than either is to the strict one.
     */
    fun inCategory(attempts: List<Attempt>, profile: CindyProfile?): List<Attempt> =
        attempts.filter { it.profile == profile }

    /** The best score recorded under [profile], or null if there is none. */
    fun bestIn(attempts: List<Attempt>, profile: CindyProfile?): Attempt? =
        best(inCategory(attempts, profile))

    /** The record [of] was actually chasing: the best previous attempt at the same movements. */
    fun personalRecord(attempts: List<Attempt>, of: Attempt): Attempt? =
        bestIn(attempts.filter { it.atMillis != of.atMillis }, of.profile)

    /** True when [of] is the best score yet recorded for its own movements. */
    fun isPersonalRecord(attempts: List<Attempt>, of: Attempt): Boolean {
        val previous = personalRecord(attempts, of) ?: return of.totalReps > 0
        return of.totalReps > previous.totalReps
    }
}

/** SharedPreferences-backed record board. */
class RecordStore(context: Context) {

    private val prefs: SharedPreferences =
        context.getSharedPreferences("cindy", Context.MODE_PRIVATE)

    fun all(): List<Attempt> = Records.decode(prefs.getString(KEY, null))

    /** Attempts oldest first, for charting progress over time. */
    fun chronological(): List<Attempt> = all().sortedBy { it.atMillis }

    fun add(attempt: Attempt) {
        // A zero-rep attempt is someone opening the app and letting the clock run out.
        if (attempt.totalReps == 0) return
        prefs.edit().putString(KEY, Records.encode(all() + attempt)).apply()
    }

    fun clear() = prefs.edit().remove(KEY).apply()

    private companion object {
        const val KEY = "attempts"
    }
}
