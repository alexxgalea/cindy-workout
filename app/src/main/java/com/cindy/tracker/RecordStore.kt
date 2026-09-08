package com.cindy.tracker

import android.content.Context
import android.content.SharedPreferences

/** One finished attempt at Cindy. */
data class Attempt(
    val rounds: Int,
    val reps: Int,
    val atMillis: Long
) {
    val totalReps: Int get() = rounds * 30 + reps

    /** "27 + 12" — the way an AMRAP score is normally written. */
    fun scoreLabel(): String = if (reps == 0) "$rounds" else "$rounds + $reps"
}

/**
 * Serialisation and ranking for the record board.
 *
 * Kept free of Android types on purpose: this is the part with logic worth testing, and
 * SharedPreferences and org.json are both unavailable in plain JVM unit tests.
 */
object Records {

    /** The score that started this whole thing. */
    val BENCHMARK_NAME = "Tom Holland"
    val BENCHMARK = Attempt(rounds = 27, reps = 0, atMillis = 0L)

    fun encode(attempts: List<Attempt>): String =
        attempts.joinToString("\n") { "${it.rounds},${it.reps},${it.atMillis}" }

    fun decode(raw: String?): List<Attempt> {
        if (raw.isNullOrBlank()) return emptyList()
        return raw.lineSequence().mapNotNull { line ->
            val p = line.split(",")
            if (p.size != 3) return@mapNotNull null
            val rounds = p[0].toIntOrNull() ?: return@mapNotNull null
            val reps = p[1].toIntOrNull() ?: return@mapNotNull null
            val at = p[2].toLongOrNull() ?: return@mapNotNull null
            Attempt(rounds, reps, at)
        }.toList()
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
