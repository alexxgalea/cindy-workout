package com.cindy.tracker

/**
 * What the voice has always said, and still says byte for byte.
 *
 * The wording lived in [MainActivity] and [Coach] as string literals and moved here unchanged;
 * [PhrasebookEnTest] pins each one, so making the voice multilingual could not quietly change it.
 * It is also the language the speaker falls back to when the chosen voice cannot be used, and the
 * one the screen-reader descriptions borrow [duration] from.
 */
object PhrasebookEn : Phrasebook {

    override val tag = "en"

    override fun say(line: VoiceLine): String = when (line) {
        is VoiceLine.Count -> "${line.reps}"
        is VoiceLine.Movement -> line.exercise.spoken
        is VoiceLine.RoundDone -> "Round ${line.round} in ${duration(line.splitMs)}"
        VoiceLine.PhoneMoved -> "Phone moved. Check the framing."
        VoiceLine.SetUp -> "Get in frame, then do two slow pull ups"
        is VoiceLine.Go -> if (line.calibrated) "Calibrated. Go." else "Go. Pull ups"
        VoiceLine.Resume -> "Resume"
        is VoiceLine.Finished -> if (line.early) "Stopped." else "Time."
        is VoiceLine.Score -> score(line.rounds, line.totalReps)
        is VoiceLine.Averaging -> "Averaging ${duration(line.roundMs)} a round"
        is VoiceLine.BeatBenchmark -> "You beat ${line.name}"
        VoiceLine.Ready -> "Ready"
        is VoiceLine.Fault -> line.hint
        is VoiceLine.Clock -> clock(line)
        VoiceLine.Sample -> "Three. Four. Five. Push ups."
        VoiceLine.VolumeCheck -> "Three"
        is VoiceLine.RecordingSoon -> "Recording in ${line.seconds}"
        VoiceLine.RecordingStarted -> "Recording"
        VoiceLine.RecordingFailed -> "Recording failed"
    }

    /** "one minute twenty" — TTS makes a mess of "1:20". */
    fun duration(ms: Long): String {
        val (m, sec) = minutesAndSeconds(ms)
        return when {
            m == 0 -> "$sec seconds"
            sec == 0 -> "$m minute${if (m == 1) "" else "s"}"
            else -> "$m minute${if (m == 1) "" else "s"} $sec"
        }
    }

    private fun clock(line: VoiceLine.Clock): String = when (line.mark) {
        ClockMark.TEN_SECONDS_LEFT -> "Ten seconds. Everything you have."
        ClockMark.ONE_MINUTE_LEFT ->
            "One minute left. ${rounds(line.rounds)} down — finish the one you're in."
        ClockMark.TWO_MINUTES_LEFT -> "Two minutes. " + push(line.rounds, line.totalReps)
        ClockMark.FIVE_MINUTES_LEFT -> "Five minutes left. " + pace(line)
        ClockMark.HALFWAY -> "Halfway. " + pace(line)
        ClockMark.FIVE_MINUTES_IN -> "Five minutes in. " + pace(line)
    }

    /**
     * Rounds so far, and where that rate lands at twenty minutes. Falls back to the plain
     * encouragement before there is a projection, where a figure off a fraction of a round would
     * be a wild number stated confidently.
     */
    private fun pace(line: VoiceLine.Clock): String =
        line.projectedRounds?.let { "${rounds(line.rounds)} — on for $it." }
            ?: "Keep the pace you're on."

    private fun push(rounds: Int, totalReps: Int): String =
        score(rounds, totalReps) + if (rounds < 1) ". Keep going." else ". Hold the pace."

    private fun score(rounds: Int, totalReps: Int): String {
        val reps = "$totalReps rep${if (totalReps == 1) "" else "s"}"
        return if (rounds < 1) reps else "${rounds(rounds)} — $reps in total"
    }

    /** "1 round", "6 rounds" — said often enough to be worth getting right. */
    private fun rounds(rounds: Int): String = "$rounds round${if (rounds == 1) "" else "s"}"
}
