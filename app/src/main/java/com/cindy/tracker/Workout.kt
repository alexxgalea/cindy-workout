package com.cindy.tracker

/**
 * How a workout arranges its movements over time.
 *
 * All four are known from the start, though only Cindy's is in the catalog yet: a session
 * recorded under any of them has to be readable by every build that follows, so the names are
 * settled before the workouts that need them are.
 */
enum class Structure(val label: String) {
    /** As many rounds as possible before the clock runs out. Cindy is one. */
    AMRAP("AMRAP"),

    /** A set at the top of every minute, resting for whatever is left of it. */
    EMOM("EMOM"),

    /** The work is fixed, and the score is how long it took, under a cap. */
    FOR_TIME("For time"),

    /** Any movement, in any order, for as long as the athlete likes. Freestyle is the one. */
    FREE("Free")
}

/** What a workout's score is made of. */
enum class Scoring {
    /** Whole rounds, then the reps of the round in progress: "27 + 12". */
    ROUNDS_AND_REPS,

    /** How long the work took. */
    TIME,

    /** Reps banked in all. */
    REPS,

    /** The reps of each movement, and the time. */
    TOTALS
}

/**
 * One movement of a workout, and how many reps of it each round asks for.
 *
 * [reps] is null where the structure sets no number, as Free does: the athlete decides.
 */
data class Prescription(val movement: Exercise, val reps: Int?)

/**
 * A named plan: which movements, in what structure, under what time cap, and how it is scored.
 *
 * Pure, like [Records], so the catalog can be tested without a phone. A workout describes what
 * a session is; it does not count anything. Counting stays with the engine, which still runs
 * Cindy whatever is chosen, and the catalog only holds workouts the engine can count.
 *
 * [id] is what a recorded session keeps, so it is never renamed once a session may carry it:
 * [name] is free to change, and the id is the promise. It is lower case letters, digits and
 * hyphens only, because it sits in the record board's line format between `|` separators.
 */
data class Workout(
    val id: String,
    val name: String,
    val structure: Structure,
    /** In the order a round takes them. */
    val movements: List<Prescription>,
    /** How long the clock runs, or null for a workout with no cap. */
    val timeCapMs: Long?,
    val scoring: Scoring,
    /** One line, for the Workouts page. */
    val description: String
) {
    /** "20-minute AMRAP", "For time, 15-minute cap", "Free": the structure with its clock. */
    val format: String
        get() {
            val minutes = timeCapMs?.let { it / 60_000L }
            return when {
                minutes == null -> structure.label
                structure == Structure.FOR_TIME -> "${structure.label}, $minutes-minute cap"
                else -> "$minutes-minute ${structure.label}"
            }
        }
}

/** Every workout this build can run. */
object Workouts {

    /** What every session recorded before workouts existed was, and still is. */
    const val CINDY_ID = "cindy"

    /** The length of a Cindy. The same twenty minutes the camera screen's clock runs. */
    const val CINDY_TIME_CAP_MS = 20 * 60_000L

    /**
     * Cindy, defined from the constants the app already counts it by: the engine's target for
     * each movement and the camera screen's twenty minutes. Defined from them rather than beside
     * them, so this cannot describe a different Cindy from the one being counted.
     */
    val CINDY: Workout = Exercise.entries.map { Prescription(it, it.target) }.let { round ->
        Workout(
            id = CINDY_ID,
            name = "Cindy",
            structure = Structure.AMRAP,
            movements = round,
            timeCapMs = CINDY_TIME_CAP_MS,
            scoring = Scoring.ROUNDS_AND_REPS,
            description = "Rounds of ${roundOf(round)}, as many as you can."
        )
    }

    /** In the order the Workouts page lists them. */
    val catalog: List<Workout> = listOf(CINDY)

    /** The workout filed under [id], or null for one this build does not know. */
    fun byId(id: String?): Workout? = catalog.firstOrNull { it.id == id }

    /** "5 pull-ups, 10 push-ups and 15 squats", in the round's order. */
    private fun roundOf(round: List<Prescription>): String {
        val parts = round.map { p ->
            val name = p.movement.label.lowercase()
            if (p.reps == null) name else "${p.reps} $name"
        }
        if (parts.size < 2) return parts.joinToString()
        return parts.dropLast(1).joinToString(", ") + " and " + parts.last()
    }
}
