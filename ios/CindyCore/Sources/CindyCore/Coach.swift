import Foundation

/// Decides what the voice should say about the athlete's position, and about the clock.
///
/// Silence is ambiguous. An athlete who has just got on the bar cannot tell "you are in a good
/// position and the next rep will count" from "the app has lost you and is saying nothing about
/// it", and mid-set there is no way to check the screen. So this speaks in both directions: it
/// says what is wrong when something is, and it confirms when the movement is countable again.
///
/// The clock half is here for the same reason. The time announcements used to be a `switch` over
/// seconds-remaining on the camera screen, saying only the time; an athlete mid-Cindy already has
/// the clock in front of them, and what they cannot work out on the bar is whether the pace they
/// are keeping gets them where they wanted to be. So each mark now carries a figure with it.
///
/// Free of platform types on purpose — the whole value here is in the timing rules, and those are
/// only worth having if they can be tested. `WorkoutEngine.blocked` supplies the position input;
/// the workout clock supplies the rest. What is said is a `VoiceLine`, and the words for it belong
/// to the `Phrasebook` of the voice that ends up speaking, so this decides *when* and *what about*
/// and never *how it sounds*.
public final class Coach {

    /// How long a fault must stand before it is worth interrupting for.
    private static let faultAfterMs: Int64 = 4_000
    /// And how often it may be repeated while nothing improves. A coach, not a nag.
    private static let faultEveryMs: Int64 = 12_000
    /// How long nothing may have been counting before getting going again is worth confirming.
    ///
    /// Above the gap between two reps of a set, so working through a movement stays silent —
    /// the confirmation is for arriving, resting, or recovering from a fault, not for reps.
    private static let confirmAfterBlockedMs: Int64 = 1_500
    /// How long the good position must hold, so a single lucky frame does not confirm.
    private static let confirmHoldMs: Int64 = 400
    /// The length of a Cindy, which is what a pace is projected against.
    private static let workoutMs: Int64 = 20 * 60_000

    /// The movement the last frame belonged to, so a new one earns its own confirmation.
    private var exercise: Exercise?
    /// Set when something has happened that the athlete deserves to hear the end of.
    private var confirmOwed = false
    private var goodSince: Int64 = 0
    /// When anything at all started going wrong, across however many different faults.
    private var faultingSince: Int64 = 0
    /// When *this* fault started, which is what the athlete is given time to fix.
    private var faultSince: Int64 = 0
    private var spokenFault = ""
    private var lastFaultAt: Int64 = 0

    public init() {}

    /// Feeds one frame of the running workout and returns what to say, or `nil` to stay quiet.
    ///
    /// `blocked` is the engine's own judgement that this frame could not score for a reason the
    /// athlete could fix by moving — as opposed to merely being mid-rep, which is not a fault.
    public func onFrame(_ exercise: Exercise, blocked: Bool, hint: String, now: Int64) -> VoiceLine? {
        if exercise != self.exercise {
            self.exercise = exercise
            // Arriving at a movement always earns a confirmation, even if nothing went wrong.
            confirmOwed = true
            goodSince = 0
            clearFault()
        }
        return blocked ? fault(hint, now) : confirm(now)
    }

    private func fault(_ hint: String, _ now: Int64) -> VoiceLine? {
        goodSince = 0
        if faultingSince == 0 { faultingSince = now }
        // Long enough out of action that getting going again is worth hearing about.
        if now - faultingSince >= Self.confirmAfterBlockedMs { confirmOwed = true }

        // The clock runs per distinct fault: a changing hint is a moving problem, not a standing
        // one, and interrupting for each of them in turn would be noise.
        if hint != spokenFault {
            spokenFault = hint
            lastFaultAt = 0
            faultSince = now
            return nil
        }
        if now - faultSince < Self.faultAfterMs { return nil }
        if lastFaultAt != 0 && now - lastFaultAt < Self.faultEveryMs { return nil }
        lastFaultAt = now
        return .fault(hint: hint)
    }

    private func confirm(_ now: Int64) -> VoiceLine? {
        clearFault()
        if !confirmOwed { return nil }
        if goodSince == 0 {
            goodSince = now
            return nil
        }
        if now - goodSince < Self.confirmHoldMs { return nil }
        confirmOwed = false
        goodSince = 0
        return .ready
    }

    private func clearFault() {
        faultingSince = 0
        faultSince = 0
        spokenFault = ""
        lastFaultAt = 0
    }

    // MARK: - the clock

    /// The marks the voice speaks at, each with the milliseconds *remaining* it falls on.
    ///
    /// Counted down rather than up because Cindy is a twenty-minute AMRAP and what an athlete
    /// mid-round wants is how much is left, not how much is gone. Chosen so no two land close
    /// enough to run together, and so the last one is early enough to still be worth acting on.
    ///
    /// Paired rather than kept as bare times beside a `switch`, so a mark cannot be given a time
    /// without a name, or a name without a time, and be announced as the wrong one.
    private let marks: [(at: Int64, mark: ClockMark)] = [
        (15 * 60_000, .fiveMinutesIn),
        (10 * 60_000, .halfway),
        (5 * 60_000, .fiveMinutesLeft),
        (2 * 60_000, .twoMinutesLeft),
        (60_000, .oneMinuteLeft),
        (10_000, .tenSecondsLeft)
    ]

    /// Marks already spoken, so a 200ms ticker cannot say one five times.
    private var spokenMarks: Set<ClockMark> = []

    /// What to say about the clock, or `nil` between marks.
    ///
    /// Every line pairs the time with something the athlete has actually done, because the time
    /// alone is the half they can already read off the screen. The pace figure is the one a
    /// twenty-minute AMRAP turns on: rounds so far, projected forward at the rate they have kept
    /// so far, is the number that tells them whether to push or to settle — and it is only worth
    /// saying once there is enough of the workout behind them for it to mean anything.
    ///
    /// Encouragement is attached to a fact rather than issued on its own. "You're doing great" at
    /// minute ten is noise; "Halfway. Six rounds — on for twelve" is the same reassurance, earned.
    public func onClock(elapsedMs: Int64, remainingMs: Int64, rounds: Int, totalReps: Int) -> VoiceLine? {
        guard let due = marks.first(where: { remainingMs <= $0.at && !spokenMarks.contains($0.mark) })
        else { return nil }
        spokenMarks.insert(due.mark)
        return .clock(mark: due.mark, rounds: rounds, totalReps: totalReps,
                      projectedRounds: projectedRounds(elapsedMs, rounds))
    }

    /// Where the rate so far lands at twenty minutes, or `nil` while it would not mean anything.
    ///
    /// Projected from elapsed time rather than from the round splits, so a workout that started
    /// slowly and sped up is described by all of itself. Withheld before the first round is in,
    /// and in the first minute, where a projection off a fraction of a round would be a wild
    /// number stated confidently.
    private func projectedRounds(_ elapsedMs: Int64, _ rounds: Int) -> Int? {
        if rounds < 1 || elapsedMs < 60_000 { return nil }
        return Int(Int64(rounds) * Self.workoutMs / elapsedMs)
    }

    /// The workout stopped. Nothing said before the break should carry over it, and coming back
    /// to the bar afterwards is exactly the moment a confirmation is worth hearing.
    public func interrupted() {
        clearFault()
        goodSince = 0
        confirmOwed = true
    }

    /// Back to a clean slate, for a workout that has been reset.
    public func reset() {
        interrupted()
        exercise = nil
        confirmOwed = false
        // Not cleared by `interrupted`: a pause is the middle of one workout, and hearing
        // "halfway" a second time on the way back to the bar would be a lie about the clock.
        spokenMarks.removeAll()
    }
}
