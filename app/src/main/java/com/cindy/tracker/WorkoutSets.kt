package com.cindy.tracker

import android.content.Context
import java.io.File

/**
 * What one movement of one round actually banked.
 *
 * This is the unit Strava's JSON `sets` array wants, and the only one honest to give it:
 * [reps] is what [WorkoutEngine.sets] says was banked, never a movement's target. [round] counts
 * from 1, matching how the app already talks about rounds everywhere else.
 */
data class WorkoutSet(val round: Int, val exercise: Exercise, val reps: Int)

/**
 * Serialises the sets a finished attempt banked, one line per set — the same shape [Records]
 * uses for attempts, kept separate because a set list means nothing without the attempt it
 * belongs to (see [SetStore]).
 */
object WorkoutSets {

    private const val V1 = "v1"

    fun encode(sets: List<WorkoutSet>): String = sets.joinToString("\n") { s ->
        listOf(V1, s.round.toString(), s.exercise.name, s.reps.toString()).joinToString("|")
    }

    /**
     * Decodes a saved set list, or null for the whole thing on the first line that does not
     * parse.
     *
     * An exercise name this build does not know, or a line that is otherwise malformed, is not
     * guessed at and not quietly dropped — either would risk uploading a `sets` array that no
     * longer sums to the attempt's real total. Returning null instead leaves the caller with
     * nothing to upload, which is the honest failure.
     */
    fun decode(raw: String?): List<WorkoutSet>? {
        if (raw.isNullOrBlank()) return emptyList()
        val sets = mutableListOf<WorkoutSet>()
        for (line in raw.lineSequence()) {
            if (line.isBlank()) continue
            val p = line.split("|")
            if (p.size != 4 || p[0] != V1) return null
            val round = p[1].toIntOrNull() ?: return null
            val exercise = Exercise.entries.firstOrNull { it.name == p[2] } ?: return null
            val reps = p[3].toIntOrNull() ?: return null
            sets += WorkoutSet(round, exercise, reps)
        }
        return sets
    }
}

/**
 * Where a finished attempt's banked sets live, keyed by [Attempt.atMillis].
 *
 * Mirrors the heart-rate work's `HeartRateStore` (`hr-p1-core`): a plain file per attempt under
 * `filesDir`, so the Strava payload can be composed lazily, long after the workout ended and
 * even across a process death.
 */
class SetStore(private val context: Context) {

    /**
     * Written beside the real file and renamed over it, so a reader only ever sees a whole list.
     *
     * A file cut off by a process death mid-write could otherwise end on a line boundary and
     * decode as a *shorter* list that looks perfectly valid — sets that no longer add up to the
     * attempt's total, which is the one thing this store exists to prevent.
     */
    fun save(atMillis: Long, sets: List<WorkoutSet>) {
        val f = file(atMillis)
        f.parentFile?.mkdirs()
        val tmp = File(f.parentFile, "${f.name}.tmp")
        tmp.writeText(WorkoutSets.encode(sets))
        if (!tmp.renameTo(f)) {
            tmp.delete()
            throw java.io.IOException("Could not save the sets for $atMillis")
        }
    }

    /** Null when nothing was saved for this attempt, or the file no longer decodes. */
    fun load(atMillis: Long): List<WorkoutSet>? {
        val f = file(atMillis)
        if (!f.isFile) return null
        return WorkoutSets.decode(f.readText())
    }

    /** Wipes every attempt's sets, alongside [RecordStore.clear] wiping the record board. */
    fun clear() {
        dir().deleteRecursively()
    }

    private fun dir(): File = File(context.filesDir, "sets")

    private fun file(atMillis: Long): File = File(dir(), "$atMillis.sets")
}
