package com.cindy.tracker

/**
 * Everything the voice can say, as a fact rather than as a sentence.
 *
 * The voice used to be handed English strings — a literal at each call site in [MainActivity], and
 * the coach's own wording in [Coach]. A string is finished: by the time it reaches the speaker the
 * words are already chosen, so it can only ever be said in the language it was written in. A line
 * is the fact instead ("round 3, eighty seconds"), and the [Phrasebook] of whichever voice is
 * actually speaking turns it into words. That is what lets the athlete pick a language, and what
 * keeps the words and the voice in agreement when the voice they picked turns out to be missing
 * and the speaker falls back to English.
 *
 * Sealed on purpose. Every phrasebook answers with an exhaustive `when` over this type, so a line
 * added here does not compile in any language until it has been written in all of them.
 *
 * Free of Android types, like [Coach]: the wording and the timing are only worth having if they
 * can be tested.
 */
sealed interface VoiceLine {

    /** The rep the athlete is now on, after a rep counted or was taken back. Spoken bare, and fast. */
    data class Count(val reps: Int) : VoiceLine

    /** The movement that starts now. */
    data class Movement(val exercise: Exercise) : VoiceLine

    /** A finished round: [round] is how many are complete, [splitMs] the clock time it took. */
    data class RoundDone(val round: Int, val splitMs: Long) : VoiceLine

    /** The camera was knocked, so what was learned about the framing has been thrown away. */
    data object PhoneMoved : VoiceLine

    /** The pre-workout check has started. */
    data object SetUp : VoiceLine

    /** The clock has started. [calibrated] is false when the check was skipped rather than passed. */
    data class Go(val calibrated: Boolean) : VoiceLine

    /** Back from a pause. */
    data object Resume : VoiceLine

    /** The clock stopped: [early] when the athlete ended it, otherwise because time ran out. */
    data class Finished(val early: Boolean) : VoiceLine

    /**
     * A score in words: the rounds done, and the *whole* rep tally behind them.
     *
     * The rep figure has to be the total, not the part of the round in progress. Those two
     * differ by a whole round's work at exactly the wrong moment — the reps of the current
     * round are zero the instant one completes, so an athlete who stopped having just finished
     * a clean round was told "1 rounds and 0 reps" over a screen reading thirty. Zero is the
     * one number a result must never say about work that was done.
     *
     * "In total" is spelled out, in every language, because the other reading — a round *and
     * then* thirty more — is the one a listener reaches for, and a score is not worth saying
     * ambiguously.
     */
    data class Score(val rounds: Int, val totalReps: Int) : VoiceLine

    /** The average round of a finished workout. */
    data class Averaging(val roundMs: Long) : VoiceLine

    /** The score beat [name]'s. A proper noun, so it travels as data and is never translated. */
    data class BeatBenchmark(val name: String) : VoiceLine

    /** The athlete is in a position that will score, having not been for a while. */
    data object Ready : VoiceLine

    /**
     * Something the athlete can fix by moving. [hint] is the engine's own English text: the
     * engine keeps it (the Python port compares it frame for frame), and each phrasebook
     * translates it on the way out.
     */
    data class Fault(val hint: String) : VoiceLine

    /**
     * A mark on the clock, with the facts to say beside it.
     *
     * Every mark pairs the time with something the athlete has done, because the time alone is
     * the half they can already read off the screen. [projectedRounds] is where the pace so far
     * lands at twenty minutes, or null when there is not yet enough workout behind it for the
     * figure to mean anything.
     */
    data class Clock(
        val mark: ClockMark,
        val rounds: Int,
        val totalReps: Int,
        val projectedRounds: Int?
    ) : VoiceLine

    /** The sample the menu plays for HEAR IT: a few counts and a movement, the way they sound. */
    data object Sample : VoiceLine

    /** The single word played when the volume slider is let go. */
    data object VolumeCheck : VoiceLine
}

/**
 * The marks [Coach] speaks the clock at, named by what the athlete needs to hear.
 *
 * Declared in the order they arrive in a workout.
 */
enum class ClockMark {
    /** Fifteen minutes to go. */
    FIVE_MINUTES_IN,
    /** Ten minutes to go. */
    HALFWAY,
    /** Five minutes to go. */
    FIVE_MINUTES_LEFT,
    /** Two minutes to go, when the score so far is worth stating. */
    TWO_MINUTES_LEFT,
    /** One minute to go. */
    ONE_MINUTE_LEFT,
    /** Ten seconds to go. */
    TEN_SECONDS_LEFT
}
