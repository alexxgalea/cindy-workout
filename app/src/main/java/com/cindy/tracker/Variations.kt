package com.cindy.tracker

/**
 * The movements the athlete actually performed, and what the app is entitled to call them.
 *
 * Cindy prescribes a strict pull-up, a standard push-up and a full-depth air squat. Plenty of
 * people cannot do all three, and an app that only counts those three is an app that tells them
 * to come back when they are fitter. So the movement is a choice made before the clock starts,
 * and the choice travels with the result: into the summary, the history line and the record
 * board.
 *
 * The rule the whole file exists to enforce is that a modified movement is *reported as* the
 * modified movement. Not silently counted as the strict one, and not sneered at either — a
 * band-assisted pull-up is a different prescription, not a worse athlete.
 */

/** Whether the camera can be trusted to score a variation, or whether the athlete taps it in. */
enum class Tracking {
    /** Validated against fixtures: the engine counts it. */
    AUTO,

    /**
     * Counted with the "+1" button.
     *
     * Not a lesser option and not a placeholder — for several of these the pose alone genuinely
     * does not carry the information, and a confident wrong count is worse than an honest tap.
     */
    MANUAL
}

/** What happened on the bar. */
enum class PullVariant(
    val label: String,
    val plural: String,
    val tracking: Tracking,
    val setupGuide: String
) {
    STRICT_PULL_UP(
        "Strict pull-up", "strict pull-ups", Tracking.AUTO,
        "Hang with straight arms, then pull until your head clears the bar."
    ),

    /**
     * Counted, but on a relaxed bottom.
     *
     * The band holds you up, so the arms may never straighten into a dead hang. The head still
     * has to clear the bar and drop back below the reset line, which is the part that says a
     * whole rep happened; see [WorkoutEngine] for why the elbow is the conjunct that goes.
     */
    BAND_ASSISTED_PULL_UP(
        "Band-assisted", "band-assisted pull-ups", Tracking.AUTO,
        "Set the band, then pull until your head clears the bar and lower all the way back down."
    ),

    /**
     * Manual, for a concrete reason rather than caution.
     *
     * "Hands above hips" is what separates a pull-up from a push-up in the pose. On a low bar
     * with the feet down, the hips ride up level with the hands and that test stops meaning
     * anything in either direction, so it cannot simply be loosened.
     */
    FOOT_ASSISTED_PULL_UP(
        "Foot-assisted", "foot-assisted pull-ups", Tracking.MANUAL,
        "Set your feet on the floor or a box. Tap +1 for each rep."
    ),

    /**
     * Manual: a negative has no return, so there is no oscillation to count.
     *
     * The counter books a rep at the *top* of a climb away from a trough. A rep that is only
     * ever a descent never presents one.
     */
    NEGATIVE_PULL_UP(
        "Negatives", "negative pull-ups", Tracking.MANUAL,
        "Start at the top and lower yourself slowly. Tap +1 for each rep."
    )
}

/** What happened on the floor. */
enum class PushVariant(
    val label: String,
    val plural: String,
    val tracking: Tracking,
    val setupGuide: String
) {
    STANDARD_PUSH_UP(
        "Standard", "standard push-ups", Tracking.AUTO,
        "Hands under your shoulders, body in a line, chest to the floor."
    ),

    /**
     * Counted, and counted by exactly the same code as a standard push-up.
     *
     * The push-up signal is the elbow angle and the gate in front of it asks only which way the
     * torso points, so this has always scored — see `KneePushupTest`. Naming it changes nothing
     * about the counting and everything about what the history says happened.
     */
    KNEE_PUSH_UP(
        "From knees", "knee push-ups", Tracking.AUTO,
        "Hands under your shoulders, knees on the floor, chest toward the floor."
    ),

    /**
     * Manual, because the start gate is a torso-direction test.
     *
     * A shallow incline reads as a push-up, but a steep one — hands on a wall — reads as
     * standing upright, and the gate refuses to open. Where the boundary falls depends on the
     * bench, so the honest answer is to tap it rather than to count it sometimes.
     */
    INCLINE_PUSH_UP(
        "Incline", "incline push-ups", Tracking.MANUAL,
        "Hands on a bench, box or wall. Tap +1 for each rep."
    )
}

/** What happened on the legs. */
enum class SquatVariant(
    val label: String,
    val plural: String,
    val tracking: Tracking,
    val setupGuide: String
) {
    AIR_SQUAT(
        "Air squat", "air squats", Tracking.AUTO,
        "Stand tall, sit down to depth, stand all the way back up."
    ),

    /**
     * Counted without a calibration step of its own.
     *
     * [RepCounter] already learns the range the athlete actually produces and judges reps
     * against that, so a box caps the descent and the band settles around it. The setup reps are
     * the calibration.
     */
    BOX_SQUAT(
        "To a box", "box squats", Tracking.AUTO,
        "Set a box or chair behind you. Sit to it and stand all the way back up."
    ),

    /**
     * Manual: holding a rail puts the hands somewhere the squat gates do not expect, and the
     * support often occludes a leg.
     */
    SUPPORTED_SQUAT(
        "Supported", "supported squats", Tracking.MANUAL,
        "Hold a rail or door frame for balance. Tap +1 for each rep."
    )
}

/** Standard Cindy, or a Cindy with at least one movement changed. */
enum class CindyMode(val label: String) {
    STANDARD("Cindy"),
    ADAPTIVE("Adaptive Cindy")
}

/**
 * The three choices, together.
 *
 * [mode] is derived rather than stored, so a profile can never disagree with its own label.
 */
data class CindyProfile(
    val pull: PullVariant = PullVariant.STRICT_PULL_UP,
    val push: PushVariant = PushVariant.STANDARD_PUSH_UP,
    val squat: SquatVariant = SquatVariant.AIR_SQUAT
) {
    val mode: CindyMode
        get() = if (this == STANDARD) CindyMode.STANDARD else CindyMode.ADAPTIVE

    val isStandard: Boolean get() = mode == CindyMode.STANDARD

    /** True when every chosen movement is one the camera is trusted to score. */
    val fullyAutomatic: Boolean
        get() = pull.tracking == Tracking.AUTO &&
            push.tracking == Tracking.AUTO &&
            squat.tracking == Tracking.AUTO

    /** The movements this profile expects the athlete to tap in rather than be counted. */
    val manualMovements: List<Exercise>
        get() = buildList {
            if (pull.tracking == Tracking.MANUAL) add(Exercise.PULLUP)
            if (push.tracking == Tracking.MANUAL) add(Exercise.PUSHUP)
            if (squat.tracking == Tracking.MANUAL) add(Exercise.SQUAT)
        }

    fun tracking(exercise: Exercise): Tracking = when (exercise) {
        Exercise.PULLUP -> pull.tracking
        Exercise.PUSHUP -> push.tracking
        Exercise.SQUAT -> squat.tracking
    }

    /** "Band-assisted pull-ups · knee push-ups · air squats", naming only what was changed. */
    fun changedMovements(): String = buildList {
        if (pull != STANDARD.pull) add(pull.plural)
        if (push != STANDARD.push) add(push.plural)
        if (squat != STANDARD.squat) add(squat.plural)
    }.joinToString(" · ")

    /** The full line for a history row: "Adaptive Cindy · knee push-ups". */
    fun label(): String =
        if (isStandard) mode.label else "${mode.label} · ${changedMovements()}"

    companion object {
        val STANDARD = CindyProfile()
    }
}

/**
 * Persisting the athlete's choice between sessions.
 *
 * Free of Android types so the round trip is testable; the caller owns the preferences file.
 */
object Variations {

    fun encode(profile: CindyProfile): String =
        listOf(profile.pull.name, profile.push.name, profile.squat.name).joinToString("|")

    /**
     * Decodes a saved choice, falling back to the standard movement for anything unrecognised.
     *
     * Deliberately *unlike* a recorded attempt, where an unknown movement has to stay unknown
     * rather than be relabelled. This is a preference for a workout that has not happened yet:
     * nothing is being claimed about the past, and the worst a wrong default does is make the
     * athlete open the picker they were already heading for.
     */
    fun decode(raw: String?): CindyProfile {
        val parts = raw?.split("|").orEmpty()
        if (parts.size != 3) return CindyProfile.STANDARD
        return CindyProfile(
            pull = PullVariant.entries.firstOrNull { it.name == parts[0] }
                ?: CindyProfile.STANDARD.pull,
            push = PushVariant.entries.firstOrNull { it.name == parts[1] }
                ?: CindyProfile.STANDARD.push,
            squat = SquatVariant.entries.firstOrNull { it.name == parts[2] }
                ?: CindyProfile.STANDARD.squat
        )
    }
}
