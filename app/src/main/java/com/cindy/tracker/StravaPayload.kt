package com.cindy.tracker

import java.time.Instant
import java.time.temporal.ChronoUnit
import org.json.JSONArray
import org.json.JSONObject

/**
 * What one movement of one round actually banked.
 *
 * This is the unit Strava's JSON `sets` array wants, and the only one honest to give it:
 * [reps] is a figure [StravaSets.from] reads straight off [Attempt.setSplits] — the record
 * [MainActivity] already keeps of what each movement scored — never a movement's target.
 * [round] counts from 1, matching how the app already talks about rounds everywhere else.
 */
data class WorkoutSet(val round: Int, val exercise: Exercise, val reps: Int)

/**
 * Maps a banked movement to the `exercise_type` Strava's strength-training JSON expects.
 *
 * The repo's rule is that a modified movement is *reported as* the modified movement
 * (see [Variations.kt][CindyProfile]), never silently folded into the strict one. Strava's own
 * list has no slot for several of our variants — a band-assisted pull-up, a box squat — so this
 * picks the family's generic type as the least-wrong label and leaves the real movement to be
 * named in the description ([StravaActivityText]), rather than claiming equipment nobody used
 * (a `BARBELL_BOX_SQUAT`, say) just because Strava's generic name is dull.
 *
 * Every `when` here is exhaustive over the variant's enum and has no `else`, on purpose: a new
 * variant must fail this file's compilation until someone has decided what Strava calls it.
 */
object StravaExercises {

    fun typeFor(exercise: Exercise, profile: CindyProfile?): String = when (exercise) {
        Exercise.PULLUP -> pullType(profile?.pull)
        Exercise.PUSHUP -> pushType(profile?.push)
        Exercise.SQUAT -> squatType(profile?.squat)
    }

    /** Null means the attempt predates [CindyProfile] and its movements are unknown. */
    private fun pullType(variant: PullVariant?): String = when (variant) {
        null -> "PULL_UP_GENERIC"
        PullVariant.STRICT_PULL_UP -> "PULL_UP_GENERIC"
        // No band-assisted type exists. The description names it.
        PullVariant.BAND_ASSISTED_PULL_UP -> "PULL_UP_GENERIC"
        PullVariant.INVERTED_ROW -> "INVERTED_ROW"
        // No foot-assisted type exists. The description names it.
        PullVariant.FOOT_ASSISTED_PULL_UP -> "PULL_UP_GENERIC"
        PullVariant.NEGATIVE_PULL_UP -> "NEGATIVE_PULL_UP"
    }

    private fun pushType(variant: PushVariant?): String = when (variant) {
        null -> "PUSH_UP_GENERIC"
        PushVariant.STANDARD_PUSH_UP -> "PUSH_UP_GENERIC"
        PushVariant.KNEE_PUSH_UP -> "MODIFIED_PUSH_UP"
        PushVariant.INCLINE_PUSH_UP -> "INCLINE_PUSH_UP"
    }

    private fun squatType(variant: SquatVariant?): String = when (variant) {
        null -> "SQUAT_GENERIC"
        SquatVariant.AIR_SQUAT -> "AIR_SQUAT"
        // BARBELL_BOX_SQUAT would claim a barbell nobody used. The description names it.
        SquatVariant.BOX_SQUAT -> "SQUAT_GENERIC"
        SquatVariant.SUPPORTED_SQUAT -> "SQUAT_GENERIC"
    }
}

/** One heart-rate sample, already placed on the payload's own clock. */
data class HrPoint(val secondsFromStart: Int, val bpm: Int)

/**
 * Turns a finished attempt, its banked sets and whatever else is known into the JSON body
 * Strava's `POST /uploads` wants for `data_type=json`.
 *
 * Pure, and composed lazily by the upload worker from the attempt record itself — [sets] is what
 * [StravaSets.from] built from [Attempt.setSplits], not a live store this file owns — so nothing
 * here reaches for a clock, a file, or the network, and a process death between finishing and
 * uploading loses nothing: the same [Attempt] and [sets] rebuild the identical payload.
 */
object StravaPayload {

    fun build(
        a: Attempt,
        sets: List<WorkoutSet>,
        startMillis: Long,
        utcOffsetSeconds: Int,
        kcal: Int?,
        heartRate: List<HrPoint>?
    ): String {
        // The caller's job to check before ever reaching here -- StravaSets.from already
        // refuses a broken or empty set list, and an attempt this old or this broken has
        // nothing worth Strava's upload quota. Asserted rather than quietly upload a
        // workout-shaped JSON with no workout in it.
        require(sets.any { it.reps > 0 }) { "Refusing to build a payload with no banked reps" }

        val elapsedTime = Math.round(a.realTimeMs / 1000.0).toInt()
        val activeTime = Math.round(a.durationMs / 1000.0).toInt()

        val json = JSONObject()
            .put("version", "1.0")
            .put(
                "start_time",
                Instant.ofEpochMilli(startMillis).truncatedTo(ChronoUnit.SECONDS).toString()
            )
            .put("utc_offset", utcOffsetSeconds)
            .put("elapsed_time", elapsedTime)
            .put("active_time", activeTime)
            .put("creator", JSONObject().put("name", "Cindy Tracker"))
            .put("sets", setsJson(sets, a.profile))

        // Bodyweight movements carry no external load, so weight is never set — a set here is
        // exercise_type and repetitions only.
        if (kcal != null) json.put("total_calories", kcal)
        if (!heartRate.isNullOrEmpty()) json.put("streams", streamsJson(heartRate, elapsedTime))

        return json.toString()
    }

    private fun setsJson(sets: List<WorkoutSet>, profile: CindyProfile?): JSONArray {
        val array = JSONArray()
        // A movement SKIPped at zero reps banked nothing, and Strava's set list is about work
        // that happened.
        sets.filter { it.reps > 0 }.forEach { s ->
            array.put(
                JSONObject()
                    .put("exercise_type", StravaExercises.typeFor(s.exercise, profile))
                    .put("repetitions", s.reps)
            )
        }
        return array
    }

    /**
     * Strava's stream contract wants `time` strictly increasing. Clamping a trace that starts a
     * little early or runs a little long can pile more than one sample onto the same boundary
     * second, so every point is clamped first, then the earliest-seen sample of any second two
     * land on is kept and the rest of that second dropped — never averaged or invented.
     */
    private fun streamsJson(heartRate: List<HrPoint>, elapsedTime: Int): JSONObject {
        val deduped = mutableListOf<HrPoint>()
        heartRate
            .map { it.copy(secondsFromStart = it.secondsFromStart.coerceIn(0, elapsedTime)) }
            .sortedBy { it.secondsFromStart }
            .forEach { point ->
                if (deduped.isEmpty() || deduped.last().secondsFromStart != point.secondsFromStart) {
                    deduped += point
                }
            }
        val time = JSONArray()
        val heartrate = JSONArray()
        deduped.forEach {
            time.put(it.secondsFromStart)
            heartrate.put(it.bpm)
        }
        return JSONObject().put("time", time).put("heartrate", heartrate)
    }
}

/**
 * Where the payload's clock starts: [Attempt.atMillis] is stamped at finish, so the start is
 * that far back, minus every millisecond — running and paused alike — the attempt actually took.
 *
 * A heart-rate trace carries its own exact start, and the upload prefers that when there is one.
 * The trace begins recording a touch before the first rep is seen.
 */
fun startMillisOf(a: Attempt): Long = a.atMillis - a.realTimeMs
