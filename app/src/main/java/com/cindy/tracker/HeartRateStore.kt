package com.cindy.tracker

import android.content.Context
import java.io.File

/**
 * The line format a [HeartRateTrace] is saved as.
 *
 * A trace is a header line, then zero or more pause lines, then zero or more sample lines:
 * ```
 * hr1|<startedAtMillis>
 * p|<atClockMs>|<lengthMs>        (zero or more)
 * <clockMs>,<bpm>                 (zero or more)
 * ```
 * Kept free of Android types on purpose, exactly like [Records]' own codec: this is the part
 * worth testing on the JVM, and [HeartRateStore] is only the thin file-handling layer around it.
 */
object HeartRateTraces {

    private const val HEADER = "hr1"
    private const val PAUSE = "p"

    fun encode(t: HeartRateTrace): String {
        val lines = mutableListOf("$HEADER|${t.startedAtMillis}")
        t.pauses.forEach { lines += "$PAUSE|${it.atClockMs}|${it.lengthMs}" }
        t.samples.forEach { lines += "${it.clockMs},${it.bpm}" }
        return lines.joinToString("\n")
    }

    /**
     * Null for null, blank, or a header line that is missing or not this format's own. Any other
     * malformed line is skipped rather than failing the whole trace — a corrupt sample in the
     * middle of a thousand-line file is not a reason to throw the other nine hundred away.
     */
    fun decode(raw: String?): HeartRateTrace? {
        if (raw.isNullOrBlank()) return null
        val lines = raw.lineSequence().iterator()
        if (!lines.hasNext()) return null
        val header = lines.next().split("|")
        if (header.size != 2 || header[0] != HEADER) return null
        val startedAtMillis = header[1].toLongOrNull() ?: return null

        val pauses = mutableListOf<HeartRatePause>()
        val samples = mutableListOf<HeartRateSample>()
        while (lines.hasNext()) {
            val line = lines.next()
            if (line.startsWith("$PAUSE|")) {
                val p = line.split("|")
                val at = p.getOrNull(1)?.toLongOrNull()
                val length = p.getOrNull(2)?.toLongOrNull()
                if (p.size == 3 && at != null && length != null) {
                    pauses += HeartRatePause(at, length)
                }
            } else {
                val s = line.split(",")
                val clock = s.getOrNull(0)?.toLongOrNull()
                val bpm = s.getOrNull(1)?.toIntOrNull()
                if (s.size == 2 && clock != null && bpm != null) {
                    samples += HeartRateSample(clock, bpm)
                }
            }
        }
        return HeartRateTrace(startedAtMillis, samples, pauses)
    }
}

/**
 * Where one attempt's heart-rate trace lives: a file of its own, not a field on [Attempt].
 *
 * About a sample a second for twenty minutes is well over a thousand readings, and [RecordStore]
 * rewrites its whole SharedPreferences string on every save — a trace that size in every attempt
 * would make each new score cost writing out every score before it again. [Attempt] itself stays
 * untouched; [atMillis] is the only join between a record and its trace, exactly as it already is
 * the join [ResultsActivity] uses to find the attempt it is showing.
 *
 * The app's existing backup rules already carry the whole of `filesDir`, so a trace travels with
 * its record without anything here having to say so twice.
 */
class HeartRateStore(context: Context) {

    private val dir = File(context.filesDir, DIR_NAME)

    /**
     * Writes [trace] for the attempt saved at [atMillis].
     *
     * Written to a `.tmp` file first and then renamed into place, so a process killed mid-write —
     * the phone was about to do exactly that, moving from the camera screen to the results one —
     * cannot leave a half-written trace where [load] would find it.
     */
    fun save(atMillis: Long, trace: HeartRateTrace) {
        if (!dir.exists()) dir.mkdirs()
        val tmp = File(dir, "$atMillis.hr.tmp")
        tmp.writeText(HeartRateTraces.encode(trace))
        tmp.renameTo(File(dir, "$atMillis.hr"))
    }

    /** Null when there is no file for [atMillis], or when what is there does not decode. */
    fun load(atMillis: Long): HeartRateTrace? {
        val file = File(dir, "$atMillis.hr")
        if (!file.exists()) return null
        return HeartRateTraces.decode(file.readText())
    }

    /** Every saved trace, gone — the companion to [RecordStore.clear]. */
    fun clear() {
        dir.listFiles { f -> f.name.endsWith(".hr") }?.forEach { it.delete() }
    }

    private companion object {
        const val DIR_NAME = "heart_rate"
    }
}
