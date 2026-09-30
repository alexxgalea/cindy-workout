package com.cindy.tracker

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
