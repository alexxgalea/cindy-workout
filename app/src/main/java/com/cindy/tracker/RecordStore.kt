package com.cindy.tracker

import android.content.Context
import android.content.SharedPreferences
import java.util.Locale

/**
 * What a score may honestly be ranked against: the same workout, done with the same movements.
 *
 * Both halves matter. A band-assisted Cindy and a strict one are different prescriptions, which
 * is why the movements were always part of it; and a shorter or freer workout made of the same
 * movements is a different workout, so a partial day can never move a Cindy record.
 */
data class Category(val workoutId: String, val profile: CindyProfile?) {
    companion object {
        /** Cindy as prescribed: what the ladder, the benchmark and the tiers describe. */
        val STANDARD_CINDY = Category(Workouts.CINDY_ID, CindyProfile.STANDARD)
    }
}

/** One finished session of a [Workout]. */
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
    val manualReps: Int = 0,
    /**
     * Reps actually performed, across the whole attempt, or null for an attempt recorded before
     * the app counted them.
     *
     * A round used to be worth thirty reps by definition, because finishing one was the only way
     * to leave it. SKIP is the other way: a round can now be completed with fewer reps in it
     * than its movements asked for, and inferring the tally from the round count would report
     * work nobody did. Null rather than a computed default so that an old record keeps saying
     * what it always said instead of being quietly restated.
     */
    val countedReps: Int? = null,
    /**
     * How long the camera could not read the athlete while the workout clock was running.
     *
     * Recorded because a score produced while the camera was blind is a *lower bound*, not a
     * result. Darkening a clip whose ground truth is five reps showed the count bleeding away
     * quietly — 5, 3, 2, 1, 0 — with the app looking like it was working throughout. Nothing in
     * the saved record said the number had stopped being true, so the attempt was filed as fact.
     * This is what stops that happening twice.
     */
    val untrackedMs: Long = 0L,
    /**
     * How long each movement block took, in the order they were finished, pauses excluded.
     *
     * Empty for an attempt recorded before sets were timed, which says nothing was known
     * rather than that nothing happened. Kept beside the round splits because a round is three
     * very different efforts, and only the sets can say which one the time went on.
     */
    val setSplits: List<SetSplit> = emptyList(),
    /**
     * The [Workout] this session was, by its id.
     *
     * Every attempt written before workouts existed was a Cindy, so that is what one reads as,
     * without its line being rewritten. An id this build does not know is kept exactly as it was
     * rather than relabelled: [workout] is null for it, and it is only ever ranked against
     * sessions filed under the same id.
     */
    val workoutId: String = Workouts.CINDY_ID,
    /**
     * The reps of each movement, for a session that has no rounds to say it (Freestyle). Empty
     * for Cindy, whose sets say it, and for every attempt written before this existed.
     */
    val movementTotals: Map<Exercise, Int> = emptyMap(),
    /**
     * A Freestyle's sets, Rests and Transitions as worked out at STOP ([FreestyleSets]), in order.
     * They live and die with the attempt, so DISCARD takes them. Empty for Cindy and for every
     * attempt written before this existed. The gaps are not stored: they follow from the sets.
     */
    val freestyleSets: List<FreestyleSet> = emptyList()
) {
    /** What [workoutId] names, or null for a workout from a build that knew one this does not. */
    val workout: Workout? get() = Workouts.byId(workoutId)

    /** Which scores this one may be ranked against. */
    val category: Category get() = Category(workoutId, profile)

    /** True for a session of Cindy, which the ladder, the benchmark and the badges describe. */
    val isCindy: Boolean get() = workoutId == Workouts.CINDY_ID

    val totalReps: Int get() = countedReps ?: (rounds * 30 + reps)

    /**
     * True when the camera lost the athlete for long enough that reps were probably missed.
     *
     * The error only ever runs one way: an unreadable frame produces an *absent* rep, never an
     * invented one, measured across every light level tested. So the honest reading of a flagged
     * attempt is "at least this much", which is why one is still kept, still shown and still
     * counted towards the streak — it is only barred from claiming a record, because a record is
     * a claim about a precise number.
     */
    val scoreIsLowerBound: Boolean get() = untrackedMs >= Records.UNTRACKED_TOLERANCE_MS

    /**
     * The ladder rung this score earns, or null when the ladder does not describe it.
     *
     * The levels are calibrated against strict Cindy and top out level with [Records.BENCHMARK],
     * so awarding "Legend" for twenty-seven rounds of knee push-ups would be telling the athlete
     * something untrue about a benchmark they did not attempt. An adaptive session is a
     * different prescription, not a lower score, and it is ranked against its own kind instead.
     * So is any other workout, however many rounds it has: the rungs are counted in Cindy's.
     */
    val level: Level? get() = if (category == Category.STANDARD_CINDY) Level.of(rounds) else null

    /** Wall time from first rep to last, including everything spent paused. */
    val realTimeMs: Long get() = durationMs + pausedMs

    /**
     * What to print beside the score.
     *
     * A standard Cindy earns a rung on the ladder. Anything else says what it actually was,
     * because the rung would be a claim about a workout the athlete did not attempt. Another
     * workout is named, with whatever movements were changed: the movement labels name Cindy,
     * and saying "Adaptive Cindy" of a session that was not a Cindy would be untrue twice over.
     */
    val caption: String
        get() {
            if (!isCindy) {
                val name = workout?.name ?: "Workout not recognised"
                val changed = profile?.takeIf { !it.isStandard }?.changedMovements()
                return if (changed == null) name else "$name · $changed"
            }
            return level?.title ?: profile?.label() ?: "Movements not recognised"
        }

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
    val BENCHMARK = Attempt(
        rounds = 27, reps = 0, atMillis = 0L, durationMs = Workouts.CINDY_TIME_CAP_MS,
        workoutId = Workouts.CINDY_ID
    )

    private const val V3 = "v3"
    private const val V4 = "v4"
    private const val V5 = "v5"
    private const val V6 = "v6"
    private const val V7 = "v7"
    private const val V8 = "v8"
    private const val V9 = "v9"
    private const val V10 = "v10"

    /**
     * Untracked time a score can carry and still be treated as exact.
     *
     * Half a minute of a twenty-minute workout, which is about 2.5% of it. Long enough that
     * stepping out of shot for a drink does not tarnish a session, short enough that a fading
     * light cannot take a dozen reps before anything is said. The app cannot tell resting out of
     * frame from being unreadable in frame, so the flag it raises says only what it knows: the
     * score may be a lower bound.
     */
    const val UNTRACKED_TOLERANCE_MS = 30_000L

    fun encode(attempts: List<Attempt>): String = attempts.joinToString("\n") { a ->
        // V9 only for an attempt that has totals to carry, V10 only one that has sets too, so
        // every other line is written as it always was, and an older build reads everything but
        // a Freestyle.
        listOf(
            when {
                a.freestyleSets.isNotEmpty() -> V10
                a.movementTotals.isEmpty() -> V8
                else -> V9
            },
            a.rounds.toString(),
            a.reps.toString(),
            a.atMillis.toString(),
            a.durationMs.toString(),
            a.pausedMs.toString(),
            a.roundSplitsMs.joinToString(","),
            a.profile?.pull?.name.orEmpty(),
            a.profile?.push?.name.orEmpty(),
            a.profile?.squat?.name.orEmpty(),
            a.manualReps.toString(),
            // Empty for an attempt recorded before the count existed, so that reading it back
            // leaves it unknown rather than restating it as the round tally times thirty.
            a.countedReps?.toString().orEmpty(),
            a.untrackedMs.toString(),
            a.setSplits.joinToString(",") {
                "${it.movement.name}:${it.ms}:${it.reps}:${it.manualReps}"
            },
            a.workoutId
        ).let { fields ->
            val totals = a.movementTotals.entries.joinToString(",") { "${it.key.name}:${it.value}" }
            when {
                a.freestyleSets.isNotEmpty() -> fields + totals + a.freestyleSets.joinToString(",") {
                    // A fifth field, ":1", only on a set the athlete gave another movement; an
                    // unchanged set is written exactly as before.
                    "${it.movement.name}:${it.reps}:${it.startMs}:${it.endMs}" +
                        if (it.changedByAthlete) ":1" else ""
                }
                a.movementTotals.isEmpty() -> fields
                else -> fields + totals
            }
        }.joinToString("|")
    }

    fun decode(raw: String?): List<Attempt> {
        if (raw.isNullOrBlank()) return emptyList()
        return raw.lineSequence().mapNotNull { line ->
            when {
                line.startsWith("$V10|") -> decodeV10(line)
                line.startsWith("$V9|") -> decodeV9(line)
                line.startsWith("$V8|") -> decodeV8(line)
                // Everything below was written before workouts existed, when every session was a
                // Cindy, so each decodes as one by the field's default rather than by a rewrite.
                line.startsWith("$V7|") -> decodeV7(line)
                line.startsWith("$V6|") -> decodeV6(line)
                line.startsWith("$V5|") -> decodeV5(line)
                line.startsWith("$V4|") -> decodeV4(line)
                // Attempts written before the movement profile was recorded. They predate the
                // choice existing, so standard is what they were, not an assumption about them.
                line.startsWith("$V3|") -> decodeV3(line)
                // Attempts written before splits and pauses were recorded.
                else -> decodeV1(line)
            }
        }.toList()
    }

    /** V9 plus the sets a Freestyle was worked out into. */
    private fun decodeV10(line: String): Attempt? {
        val p = line.split("|")
        if (p.size != 17) return null
        val sets = p[16].split(",").filter { it.isNotBlank() }.mapNotNull { entry ->
            val f = entry.split(":")
            if (f.size != 4 && f.size != 5) return@mapNotNull null
            val movement = enumOrNull<Exercise>(f[0]) ?: return@mapNotNull null
            val reps = f[1].toIntOrNull() ?: return@mapNotNull null
            val start = f[2].toLongOrNull() ?: return@mapNotNull null
            val end = f[3].toLongOrNull() ?: return@mapNotNull null
            FreestyleSet(movement, reps, start, end, changedByAthlete = f.getOrNull(4) == "1")
        }
        return decodeV9(p)?.copy(freestyleSets = sets)
    }

    /** V8 plus the reps of each movement. */
    private fun decodeV9(line: String): Attempt? {
        val p = line.split("|")
        if (p.size != 16) return null
        return decodeV9(p)
    }

    private fun decodeV9(p: List<String>): Attempt? {
        val totals = p[15].split(",").filter { it.isNotBlank() }.mapNotNull { entry ->
            val f = entry.split(":")
            if (f.size != 2) return@mapNotNull null
            val movement = enumOrNull<Exercise>(f[0]) ?: return@mapNotNull null
            movement to (f[1].toIntOrNull() ?: return@mapNotNull null)
        }.toMap()
        return decodeV7Fields(p)?.copy(workoutId = p[14], movementTotals = totals)
    }

    /**
     * V7 plus the workout the session was.
     *
     * The id is kept as written, known to this build or not: a session of a workout this build
     * has never heard of is still the athlete's, and calling it a Cindy would rank it against
     * scores it has nothing in common with.
     */
    private fun decodeV8(line: String): Attempt? {
        val p = line.split("|")
        if (p.size != 15) return null
        return decodeV7Fields(p)?.copy(workoutId = p[14])
    }

    /** V6 plus the time each set took. */
    private fun decodeV7(line: String): Attempt? {
        val p = line.split("|")
        if (p.size != 14) return null
        return decodeV7Fields(p)
    }

    /** The fourteen fields V7 and V8 share, in the same places. */
    private fun decodeV7Fields(p: List<String>): Attempt? =
        decodeCommon(p)?.copy(
            countedReps = p[11].toIntOrNull(),
            untrackedMs = p[12].toLongOrNull() ?: 0L,
            setSplits = decodeSets(p[13])
        )

    /** One bad entry costs only itself: the attempt and its other sets are still the athlete's. */
    private fun decodeSets(raw: String): List<SetSplit> =
        raw.split(",").filter { it.isNotBlank() }.mapNotNull { entry ->
            val f = entry.split(":")
            if (f.size != 4) return@mapNotNull null
            val movement = enumOrNull<Exercise>(f[0]) ?: return@mapNotNull null
            val ms = f[1].toLongOrNull() ?: return@mapNotNull null
            val reps = f[2].toIntOrNull() ?: return@mapNotNull null
            val manual = f[3].toIntOrNull() ?: return@mapNotNull null
            SetSplit(movement, ms, reps, manual)
        }

    /** V5 plus the time the camera spent unable to read the athlete. */
    private fun decodeV6(line: String): Attempt? {
        val p = line.split("|")
        if (p.size != 13) return null
        // An attempt written before this was measured decodes as zero, which is the right
        // reading: nothing was known to be missed, rather than nothing was missed.
        return decodeCommon(p)
            ?.copy(countedReps = p[11].toIntOrNull(), untrackedMs = p[12].toLongOrNull() ?: 0L)
    }

    /** V4 plus the reps actually counted, which a skipped movement makes unguessable. */
    private fun decodeV5(line: String): Attempt? {
        val p = line.split("|")
        if (p.size != 12) return null
        return decodeCommon(p)?.copy(countedReps = p[11].toIntOrNull())
    }

    private fun decodeV4(line: String): Attempt? {
        val p = line.split("|")
        if (p.size != 11) return null
        return decodeCommon(p)
    }

    /** The ten fields V4 and V5 share, in the same places. */
    private fun decodeCommon(p: List<String>): Attempt? {
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

    /** One place on the leaderboard: the athlete's [attempt], or null for the benchmark. */
    data class Standing(val rank: Int, val attempt: Attempt?)

    /**
     * The leaderboard in order, with the benchmark standing among the athlete's sessions.
     *
     * Every session that [beatsBenchmark] ranks above it, best first; it then ranks above every
     * other session, best first. A session of other movements never passes it however many reps
     * it holds, for the reason [beatsBenchmark] gives, so the order is a partition and not a
     * plain sort by score. Ranks count from 1 and have no gaps.
     *
     * The benchmark is a Cindy, so it stands only on a Cindy board: [withBenchmark] is false for
     * any other workout's, which is then a plain ranking.
     */
    fun standings(attempts: List<Attempt>, withBenchmark: Boolean = true): List<Standing> {
        if (!withBenchmark) return ranked(attempts).mapIndexed { i, a -> Standing(i + 1, a) }
        val (above, below) = ranked(attempts).partition { beatsBenchmark(it) }
        val order: List<Attempt?> = above + listOf(null) + below
        return order.mapIndexed { i, a -> Standing(i + 1, a) }
    }

    /**
     * Whether this score passes [BENCHMARK].
     *
     * Only a standard Cindy can: the benchmark is a strict score, so comparing an adaptive one
     * against it would be scoring two different workouts on one scale in whichever direction
     * happened to flatter. Comparing another workout against it would be exactly that, too.
     */
    fun beatsBenchmark(a: Attempt): Boolean =
        a.category == Category.STANDARD_CINDY && !a.scoreIsLowerBound &&
            a.totalReps > BENCHMARK.totalReps

    /** The sessions of one workout, whatever their movements. */
    fun ofWorkout(attempts: List<Attempt>, workoutId: String): List<Attempt> =
        attempts.filter { it.workoutId == workoutId }

    /**
     * The attempts a given score may honestly be ranked against: the same workout, at the same
     * movements, exactly.
     *
     * Not "standard versus everything else" — a band-assisted Cindy and a knee-push-up Cindy are
     * no more comparable to each other than either is to the strict one, and no other workout is
     * comparable to a Cindy at all.
     */
    fun inCategory(attempts: List<Attempt>, category: Category): List<Attempt> =
        attempts.filter { it.category == category }

    /** The best score recorded under [category], or null if there is none. */
    fun bestIn(attempts: List<Attempt>, category: Category): Attempt? =
        best(inCategory(attempts, category))

    /** The record [of] was actually chasing: the best previous attempt in its own category. */
    fun personalRecord(attempts: List<Attempt>, of: Attempt): Attempt? =
        bestIn(attempts.filter { it.atMillis != of.atMillis }, of.category)

    /**
     * True when [of] is the best score yet recorded for its own workout and movements.
     *
     * A score the camera could not stand behind is never one, however large. It is still kept,
     * still shown and still ranked — the athlete did at least that much — but "a new record" is
     * a claim about an exact number, and an attempt with minutes of blind camera in it has not
     * earned that claim. This is the same line [beatsBenchmark] already drew for adaptive
     * movements: rank it honestly rather than withhold it.
     */
    fun isPersonalRecord(attempts: List<Attempt>, of: Attempt): Boolean {
        if (of.scoreIsLowerBound) return false
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

    /**
     * Stores [attempt], and says whether it actually was.
     *
     * A zero-rep attempt is someone opening the app and letting the clock run out, so it is
     * dropped rather than filed. The caller needs to know which happened: a heart-rate trace
     * belongs beside a saved attempt, and there is nothing for it to belong beside when nothing
     * was stored.
     */
    fun add(attempt: Attempt): Boolean {
        if (attempt.totalReps == 0) return false
        prefs.edit().putString(KEY, Records.encode(all() + attempt)).apply()
        return true
    }

    /**
     * Rewrites the filed session that has [attempt]'s time with [attempt], and says whether there
     * was one. Its place on the board does not change; nothing else is touched.
     */
    fun replace(attempt: Attempt): Boolean {
        val before = all()
        if (before.none { it.atMillis == attempt.atMillis }) return false
        val after = before.map { if (it.atMillis == attempt.atMillis) attempt else it }
        prefs.edit().putString(KEY, Records.encode(after)).apply()
        return true
    }

    /**
     * Takes the session filed at [atMillis] off the board, and says whether there was one.
     *
     * Everything else stays exactly as it was. The files kept beside a session are not this
     * store's to remove; [SessionDiscard] is the one call that takes a session whole.
     */
    fun remove(atMillis: Long): Boolean {
        val before = all()
        val after = before.filterNot { it.atMillis == atMillis }
        if (after.size == before.size) return false
        prefs.edit().putString(KEY, Records.encode(after)).apply()
        return true
    }

    fun clear() = prefs.edit().remove(KEY).apply()

    private companion object {
        const val KEY = "attempts"
    }
}
