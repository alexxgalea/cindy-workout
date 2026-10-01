package com.cindy.tracker

/** The five bands of effort, by share of the athlete's maximum heart rate. */
enum class HeartZone(val label: String, internal val fromTenths: Int) {
    WARM_UP("Warm-up", 0),
    EASY("Easy", 6),
    AEROBIC("Aerobic", 7),
    THRESHOLD("Threshold", 8),
    MAXIMUM("Maximum", 9);

    /** "Z3", for where a figure is too tight for the name. */
    val short: String get() = "Z${ordinal + 1}"
}

/** Time spent in one [zone], and the beats per minute it spans. [toBpm] is null for the top zone. */
data class ZoneTime(val zone: HeartZone, val ms: Long, val fromBpm: Int?, val toBpm: Int?)

/** The round with the highest time-weighted average heart rate, and how much of it the watch saw. */
data class HardestRound(val number: Int, val avgBpm: Int, val coveredMs: Long)

/**
 * What a session's heart rate says, drawn from [HeartRateStats.of].
 *
 * [zones], [estimatedMaxBpm] and [verdict] are null together: all three need an age, which exists
 * only once the athlete has set their heart-rate details.
 */
data class HeartRateSummary(
    val avgBpm: Int,
    val maxBpm: Int,
    /** Workout-clock ms a reading covered. */
    val coveredMs: Long,
    val durationMs: Long,
    val estimatedMaxBpm: Int?,
    val zones: List<ZoneTime>?,
    val hardestRound: HardestRound?,
    val verdict: String?
)

/**
 * Average, maximum, zones and the hardest round of one session's heart rate.
 *
 * Coverage is [Calories]' own rule, shared so the card and the calorie estimate cannot disagree
 * about how much of the workout the watch saw: a usable reading holds until the next one, for at
 * most [Calories.MAX_HOLD_MS], and never past the end of the clock. Time no reading holds is not
 * averaged in as zero or as the last reading carried on — it is simply not counted, which is why
 * the card says how much of the session it covers. A watch that dropped out for two minutes would
 * otherwise drag the average down by exactly the part of the workout it did not see.
 *
 * Zones are a share of an *estimated* maximum, not a measured one, so everything that needs it
 * hangs off the age: no age, no zones, and nothing here guesses one.
 */
object HeartRateStats {

    /** A round the watch saw for less than this says too little to be called the hardest. */
    const val MIN_ROUND_COVERED_MS = 30_000L

    /**
     * Tanaka et al. (2001): `208 - 0.7 x age`, rounded. Fitted across ages and fitness levels,
     * where the older `220 - age` overstates the maximum for the young and understates it for the
     * old.
     */
    fun estimatedMax(age: Int): Int = Math.round(208.0 - 0.7 * age).toInt()

    /** The zone [bpm] falls in against [maxBpm]; integer arithmetic, so 90% is exactly 90%. */
    fun zoneOf(bpm: Int, maxBpm: Int): HeartZone {
        var zone = HeartZone.WARM_UP
        for (z in HeartZone.entries) if (bpm * 10 >= z.fromTenths * maxBpm) zone = z
        return zone
    }

    /** The lowest whole bpm in [zone]: the first one at or past its share of [maxBpm]. */
    private fun lowerBound(zone: HeartZone, maxBpm: Int): Int = (zone.fromTenths * maxBpm + 9) / 10

    /** One reading and the stretch of the clock it holds for. */
    private class Held(val startMs: Long, val endMs: Long, val bpm: Int)

    private fun held(trace: HeartRateTrace?, durationMs: Long): List<Held> {
        if (durationMs <= 0L) return emptyList()
        val usable = trace?.samples.orEmpty()
            .filter {
                it.bpm in HeartRateMeasurement.MIN_BPM..HeartRateMeasurement.MAX_BPM &&
                    it.clockMs in 0L until durationMs
            }
            .sortedBy { it.clockMs }
        val out = ArrayList<Held>(usable.size)
        for (i in usable.indices) {
            val at = usable[i].clockMs
            val next = if (i + 1 < usable.size) usable[i + 1].clockMs else Long.MAX_VALUE
            val end = minOf(next, at + Calories.MAX_HOLD_MS, durationMs)
            if (end > at) out += Held(at, end, usable[i].bpm)
        }
        return out
    }

    /**
     * Null when no reading covers any of the clock. [rounds] are the finished rounds' spans; an
     * unfinished last round is left out by the caller, since a part-round is not one to name the
     * hardest. [age] null means no zones.
     */
    fun of(
        trace: HeartRateTrace?,
        durationMs: Long,
        rounds: List<RoundSpan>,
        age: Int?
    ): HeartRateSummary? {
        val held = held(trace, durationMs)
        if (held.isEmpty()) return null

        var covered = 0L
        var weighted = 0.0
        var max = 0
        for (h in held) {
            val ms = h.endMs - h.startMs
            covered += ms
            weighted += h.bpm.toDouble() * ms
            if (h.bpm > max) max = h.bpm
        }

        val estimatedMax = age?.let { estimatedMax(it) }?.takeIf { it > 0 }
        val zones = estimatedMax?.let { zonesOf(held, it) }

        return HeartRateSummary(
            avgBpm = Math.round(weighted / covered).toInt(),
            maxBpm = max,
            coveredMs = covered,
            durationMs = durationMs,
            estimatedMaxBpm = estimatedMax,
            zones = zones,
            hardestRound = hardestRound(held, rounds),
            verdict = zones?.let { verdict(it, covered) }
        )
    }

    private fun zonesOf(held: List<Held>, maxBpm: Int): List<ZoneTime> {
        val ms = LongArray(HeartZone.entries.size)
        for (h in held) ms[zoneOf(h.bpm, maxBpm).ordinal] += h.endMs - h.startMs
        return HeartZone.entries.map { z ->
            ZoneTime(
                zone = z,
                ms = ms[z.ordinal],
                fromBpm = if (z == HeartZone.WARM_UP) null else lowerBound(z, maxBpm),
                toBpm = HeartZone.entries.getOrNull(z.ordinal + 1)?.let { lowerBound(it, maxBpm) - 1 }
            )
        }
    }

    /** Ties go to the earlier round; the first to be that hard is the one that was. */
    private fun hardestRound(held: List<Held>, rounds: List<RoundSpan>): HardestRound? {
        var best: HardestRound? = null
        var bestAvg = 0.0
        for (r in rounds) {
            var covered = 0L
            var weighted = 0.0
            for (h in held) {
                val ms = minOf(h.endMs, r.endMs) - maxOf(h.startMs, r.startMs)
                if (ms <= 0L) continue
                covered += ms
                weighted += h.bpm.toDouble() * ms
            }
            if (covered < MIN_ROUND_COVERED_MS) continue
            val avg = weighted / covered
            if (best == null || avg > bestAvg) {
                bestAvg = avg
                best = HardestRound(r.number, Math.round(avg).toInt(), covered)
            }
        }
        return best
    }

    /** A tie goes to the harder zone: the athlete worked at least that hard for as long. */
    private fun verdict(zones: List<ZoneTime>, coveredMs: Long): String {
        val top = zones.reversed().maxByOrNull { it.ms }!!
        return "Longest in ${top.zone.short} ${top.zone.label}: " +
            "${formatDuration(top.ms)} of the ${formatDuration(coveredMs)} your watch covered."
    }
}
