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
    val roundSplitsMs: List<Long> = emptyList()
) {
    val totalReps: Int get() = rounds * 30 + reps

    val level: Level get() = Level.of(rounds)

    /** Wall time from first rep to last, including everything spent paused. */
    val realTimeMs: Long get() = durationMs + pausedMs

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

    fun encode(attempts: List<Attempt>): String = attempts.joinToString("\n") { a ->
        listOf(
            V3,
            a.rounds.toString(),
            a.reps.toString(),
            a.atMillis.toString(),
            a.durationMs.toString(),
            a.pausedMs.toString(),
            a.roundSplitsMs.joinToString(",")
        ).joinToString("|")
    }

    fun decode(raw: String?): List<Attempt> {
        if (raw.isNullOrBlank()) return emptyList()
        return raw.lineSequence().mapNotNull { line ->
            when {
                line.startsWith("$V3|") -> decodeV3(line)
                // Attempts written before splits and pauses were recorded.
                else -> decodeV1(line)
            }
        }.toList()
    }

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

    fun beatsBenchmark(a: Attempt): Boolean = a.totalReps > BENCHMARK.totalReps
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
