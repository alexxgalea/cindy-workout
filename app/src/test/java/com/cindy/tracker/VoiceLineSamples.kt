package com.cindy.tracker

/**
 * A representative instance of every [VoiceLine], for the tests that must hold across all of them.
 *
 * Each phrasebook is an exhaustive `when`, so the compiler already refuses a language that lacks a
 * line. What it cannot refuse is a line nobody wrote a *test* for, which is what [KINDS] is for:
 * it is the number of kinds of line there are, and [all] has to cover exactly that many.
 */
object VoiceLineSamples {

    /** The number of kinds of [VoiceLine]. Adding one means adding it to [all] and bumping this. */
    const val KINDS = 19

    val all: List<VoiceLine> = buildList {
        add(VoiceLine.Count(3))
        Exercise.entries.forEach { add(VoiceLine.Movement(it)) }
        add(VoiceLine.RoundDone(3, 80_000L))
        add(VoiceLine.PhoneMoved)
        add(VoiceLine.SetUp)
        add(VoiceLine.Go(calibrated = true))
        add(VoiceLine.Go(calibrated = false))
        add(VoiceLine.Resume)
        add(VoiceLine.Finished(early = true))
        add(VoiceLine.Finished(early = false))
        add(VoiceLine.Score(6, 185))
        add(VoiceLine.Score(0, 12))
        add(VoiceLine.Averaging(80_000L))
        add(VoiceLine.BeatBenchmark("Tom Holland"))
        add(VoiceLine.Ready)
        add(VoiceLine.Fault("Get on the bar"))
        ClockMark.entries.forEach { mark ->
            add(VoiceLine.Clock(mark, rounds = 6, totalReps = 185, projectedRounds = 12))
            add(VoiceLine.Clock(mark, rounds = 0, totalReps = 12, projectedRounds = null))
        }
        add(VoiceLine.Sample)
        add(VoiceLine.VolumeCheck)
        add(VoiceLine.RecordingSoon(3))
        add(VoiceLine.RecordingStarted)
        add(VoiceLine.RecordingFailed)
    }
}
