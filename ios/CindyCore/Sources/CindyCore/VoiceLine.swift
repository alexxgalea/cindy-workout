import Foundation

/// Everything the voice can say, as a fact rather than as a sentence.
///
/// The voice used to be handed English strings — a literal at each call site, and the coach's own
/// wording in `Coach`. A string is finished: by the time it reaches the speaker the words are
/// already chosen, so it can only ever be said in the language it was written in. A line is the
/// fact instead ("round 3, eighty seconds"), and the `Phrasebook` of whichever voice is actually
/// speaking turns it into words. That is what lets the athlete pick a language, and what keeps the
/// words and the voice in agreement when the voice they picked turns out to be missing and the
/// speaker falls back to English.
///
/// Every phrasebook answers with an exhaustive `switch` over this type, so a line added here does
/// not compile in any language until it has been written in all of them.
///
/// Free of platform types, like `Coach`: the wording and the timing are only worth having if they
/// can be tested.
public enum VoiceLine: Equatable, Sendable {

    /// The rep the athlete is now on, after a rep counted or was taken back. Spoken bare, and fast.
    case count(reps: Int)

    /// The movement that starts now.
    case movement(Exercise)

    /// A finished round: `round` is how many are complete, `splitMs` the clock time it took.
    case roundDone(round: Int, splitMs: Int64)

    /// The camera was knocked, so what was learned about the framing has been thrown away.
    case phoneMoved

    /// The pre-workout check has started.
    case setUp

    /// The clock has started. `calibrated` is false when the check was skipped rather than passed.
    case go(calibrated: Bool)

    /// Back from a pause.
    case resume

    /// The clock stopped: `early` when the athlete ended it, otherwise because time ran out.
    case finished(early: Bool)

    /// A score in words: the rounds done, and the *whole* rep tally behind them.
    ///
    /// The rep figure has to be the total, not the part of the round in progress. Those two
    /// differ by a whole round's work at exactly the wrong moment — the reps of the current round
    /// are zero the instant one completes, so an athlete who stopped having just finished a clean
    /// round was told "1 rounds and 0 reps" over a screen reading thirty. Zero is the one number a
    /// result must never say about work that was done.
    ///
    /// "In total" is spelled out, in every language, because the other reading — a round *and
    /// then* thirty more — is the one a listener reaches for, and a score is not worth saying
    /// ambiguously.
    case score(rounds: Int, totalReps: Int)

    /// The average round of a finished workout.
    case averaging(roundMs: Int64)

    /// The score beat `name`'s. A proper noun, so it travels as data and is never translated.
    case beatBenchmark(name: String)

    /// The athlete is in a position that will score, having not been for a while.
    case ready

    /// Something the athlete can fix by moving. `hint` is the engine's own English text: the
    /// engine keeps it (the Python port compares it frame for frame), and each phrasebook
    /// translates it on the way out, through `Hint`.
    case fault(hint: String)

    /// A mark on the clock, with the facts to say beside it.
    ///
    /// Every mark pairs the time with something the athlete has done, because the time alone is
    /// the half they can already read off the screen. `projectedRounds` is where the pace so far
    /// lands at twenty minutes, or `nil` when there is not yet enough workout behind it for the
    /// figure to mean anything.
    case clock(mark: ClockMark, rounds: Int, totalReps: Int, projectedRounds: Int?)

    /// The sample the menu plays for HEAR IT: a few counts and a movement, the way they sound.
    case sample

    /// The single word played when the volume slider is let go.
    case volumeCheck

    /// REC was tapped and filming begins in `seconds`.
    ///
    /// Said as well as shown. The countdown exists so the athlete can put the phone down and get
    /// into the shot, which means they are walking away from the one screen that says filming is
    /// about to start. A phrase rather than a bare number, so beside the rep counts it cannot be
    /// mistaken for one.
    case recordingSoon(seconds: Int)

    /// Filming has begun.
    case recordingStarted

    /// Filming could not begin, or stopped without saving a clip.
    ///
    /// One line for both, worded so it is true of both: a failure reported minutes in is not one
    /// that "didn't start".
    case recordingFailed

    /// Smart squat counting has switched this session over to Adaptive Cindy, because the squats
    /// are heels flat.
    ///
    /// Said once, at the moment it happens, and never done quietly: the athlete did not choose it,
    /// and it changes how the rest of the session is counted and what it is filed as. Queued
    /// behind the count that caused it rather than cutting that count short.
    case adaptiveHeelsFlat
}

/// The marks `Coach` speaks the clock at, named by what the athlete needs to hear.
///
/// Declared in the order they arrive in a workout.
public enum ClockMark: CaseIterable, Sendable {
    /// Fifteen minutes to go.
    case fiveMinutesIn
    /// Ten minutes to go.
    case halfway
    /// Five minutes to go.
    case fiveMinutesLeft
    /// Two minutes to go, when the score so far is worth stating.
    case twoMinutesLeft
    /// One minute to go.
    case oneMinuteLeft
    /// Ten seconds to go.
    case tenSecondsLeft
}
