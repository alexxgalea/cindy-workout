package com.cindy.tracker

import android.content.Context
import java.io.File

/**
 * The line format a session's [RepMark]s are saved as.
 *
 * A header line, then one line per mark, oldest first:
 * ```
 * reps1
 * <clockMs>,<MOVEMENT_NAME>,<c|m>        (zero or more)
 * ```
 * Kept free of Android types on purpose, exactly like [HeartRateTraces]: this is the part worth
 * testing on the JVM, and [RepTimesStore] is only the thin file-handling layer around it.
 */
object RepTimes {

    private const val HEADER = "reps1"
    private const val MANUAL = "m"
    private const val CAMERA = "c"

    fun encode(marks: List<RepMark>): String {
        val lines = mutableListOf(HEADER)
        marks.forEach {
            lines += "${it.clockMs},${it.movement.name},${if (it.manual) MANUAL else CAMERA}"
        }
        return lines.joinToString("\n")
    }

    /**
     * Null for null, blank, or a header line that is missing or not this format's own. Any other
     * malformed line is skipped rather than failing the whole file — one bad line is not a reason
     * to throw an otherwise-good session's marks away.
     */
    fun decode(raw: String?): List<RepMark>? {
        if (raw.isNullOrBlank()) return null
        val lines = raw.lineSequence().iterator()
        if (!lines.hasNext()) return null
        if (lines.next() != HEADER) return null

        val marks = mutableListOf<RepMark>()
        while (lines.hasNext()) {
            val f = lines.next().split(",")
            if (f.size != 3) continue
            val clockMs = f[0].toLongOrNull() ?: continue
            val movement = Exercise.entries.firstOrNull { it.name == f[1] } ?: continue
            val manual = when (f[2]) {
                MANUAL -> true
                CAMERA -> false
                else -> continue
            }
            marks += RepMark(clockMs, movement, manual)
        }
        return marks
    }

    /**
     * Whether [marks] are honestly [attempt]'s: the same count as what it actually counted, in
     * order, and never later than the clock it ran to.
     *
     * [Attempt.countedReps] null means the record predates this file existing — nothing to
     * validate against, so nothing can be valid. A mark count that disagrees with it is treated no
     * more gently: a consumer must fall back to per-set data rather than draw a chart that implies
     * precision this file does not have. The bound is `durationMs + 1_000` rather than `durationMs`
     * exactly, because the last rep and the clock stopping are two separate reads a frame or two
     * apart.
     */
    fun validFor(marks: List<RepMark>, attempt: Attempt): Boolean {
        val counted = attempt.countedReps ?: return false
        if (marks.size != counted) return false
        marks.forEachIndexed { i, mark ->
            if (mark.clockMs > attempt.durationMs + 1_000L) return false
            if (i > 0 && mark.clockMs < marks[i - 1].clockMs) return false
        }
        return true
    }
}

/**
 * Where one attempt's rep marks live: a file of its own, beside [HeartRateStore]'s trace and for
 * the same reason — [RecordStore] rewrites its whole SharedPreferences string on every save, and a
 * line per rep in every attempt would make each new score cost rewriting every rep that came
 * before it.
 */
class RepTimesStore(context: Context) {

    private val dir = File(context.filesDir, DIR_NAME)

    /**
     * Writes [marks] for the attempt saved at [atMillis].
     *
     * Written to a `.tmp` file first and then renamed into place, so a process killed mid-write
     * cannot leave a half-written file where [load] would find it.
     */
    fun save(atMillis: Long, marks: List<RepMark>) {
        if (!dir.exists()) dir.mkdirs()
        val tmp = File(dir, "$atMillis.reps.tmp")
        tmp.writeText(RepTimes.encode(marks))
        tmp.renameTo(File(dir, "$atMillis.reps"))
    }

    /** Null when there is no file for [atMillis], or when what is there does not decode. */
    fun load(atMillis: Long): List<RepMark>? {
        val file = File(dir, "$atMillis.reps")
        if (!file.exists()) return null
        return RepTimes.decode(file.readText())
    }

    /** Every saved file, gone — the companion to [HeartRateStore.clear]. */
    fun clear() {
        dir.listFiles { f -> f.name.endsWith(".reps") }?.forEach { it.delete() }
    }

    private companion object {
        const val DIR_NAME = "rep_times"
    }
}
