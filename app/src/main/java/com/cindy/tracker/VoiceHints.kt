package com.cindy.tracker

/**
 * Every position hint the voice can be asked to say, keyed by the engine's own English text.
 *
 * The engine words its hints in English and keeps doing so. [WorkoutEngine] and [TrackingHealth]
 * are mirrored by the Python port, which compares hint text frame for frame, so translating at
 * the source would break that check for the sake of a voice. The translation happens at the last
 * moment instead, in each [Phrasebook], and this is what it is keyed by.
 *
 * Kept in step with the engine by `VoiceHintsTest`, which reads the engine's sources and fails on
 * any string in them that is neither listed here nor known not to be spoken. So a hint added to
 * the engine cannot reach the voice untranslated: this enum gains an entry, and every phrasebook's
 * exhaustive `when` over it stops compiling until it has words for it.
 */
enum class Hint(val english: String) {
    STEP_INTO_FRAME("Step into frame"),
    FINISH_SETUP_FIRST("Finish setup first"),
    TRACKING("Tracking…"),

    // Pull-ups.
    HANG_FROM_BAR("Hang from the bar"),
    HANG_VERTICALLY("Hang vertically from the bar"),
    GET_ON_BAR("Get on the bar"),
    SHOW_BOTH_HANDS("Show both hands"),
    SHOW_YOUR_HEAD("Show your head"),
    ARMS_OUT_OF_FRAME("Arms out of frame"),
    GET_HEAD_OVER_BAR("Get your head over the bar"),
    RETURN_TO_DEAD_HANG("Return to a dead hang"),
    LOWER_ALL_THE_WAY("Lower all the way down"),

    // Push-ups and squats, which start from a position the athlete has to assume first.
    GET_SET_ON_FLOOR("Get set on the floor"),
    GET_ON_FLOOR("Get on the floor"),
    STAND_UP_TO_START("Stand up to start"),
    SHOW_YOUR_LEGS("Show your legs to the camera"),

    // Mid-rep, for a movement that is being counted.
    DRIVE_UP("Drive up"),
    GO_DOWN("Go down"),

    // From [TrackingHealth], when the camera itself is the problem.
    LOSING_YOU("Losing you — more light helps"),
    TOO_DARK("Too dark to count — tap +1"),
    CANT_SEE_YOU("Can't see you — tap +1");

    companion object {
        private val byEnglish = entries.associateBy { it.english }

        /** The hint the engine's [english] text stands for, or null for text nobody catalogued. */
        fun of(english: String): Hint? = byEnglish[english]
    }
}
