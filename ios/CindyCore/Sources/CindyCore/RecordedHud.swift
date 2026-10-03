import Foundation

/// What the burned-in recording HUD shows for one rendered frame.
///
/// Kept apart from the four on-screen views because the film and the screen read differently in
/// two situations: the setup check, which the screen narrates with "SET UP" and a bare rep count,
/// and the few seconds after it ends, when the film alone carries a banner saying what just
/// happened. The recording overlay draws this and nothing else.
public struct RecordedHudText: Equatable, Sendable {
    public let clock: String
    public let round: String
    public let label: String
    public let count: String
    /// A line shown for a few seconds after the setup check ends, or `nil` the rest of the time.
    public let banner: String?
}

/// Produces `RecordedHudText` from what the workout screen already knows about the workout and the
/// setup check.
///
/// Framework-free, like `OverlayTransform`: the one part of this with any real logic — whether the
/// banner is still inside its three seconds — depends on a clock, and a clock the caller hands in
/// rather than one this class reads for itself is a clock a test can move.
public final class RecordedHud {

    /// The calibration target the setup check counts against, read by the workout screen too so
    /// the on-screen "/2" and the burned-in one never say different numbers.
    ///
    /// Mirrors `WorkoutEngine`'s own constant of the same value. Duplicated rather than read from
    /// there because that one is private to the engine; if it is ever retuned, this one has to be
    /// told by hand.
    public static let calibrationReps = 2

    /// How long the post-check banner stays burned into the film.
    public static let bannerMs: Int64 = 3_000

    // Mirrors the screen's own round and rep views, which is where ROUND and the target it
    // drops a weight and a shade behind actually live; the film wants them as one string each.
    private var workoutRound = "ROUND 1"
    private var workoutCount = "0 / 5"

    private var bannerText: String?
    private var bannerShownAt: Int64 = 0

    public init() {}

    /// Called wherever the screen's own round and rep views are, so the film agrees with them.
    public func workout(rounds: Int, reps: Int, target: Int) {
        workoutRound = "ROUND \(rounds + 1)"
        workoutCount = "\(reps) / \(target)"
    }

    /// Starts the three-second "calibrated" banner. Called once, where the setup check succeeds.
    public func calibrated(now: Int64) {
        bannerText = "CALIBRATED · \(Self.calibrationReps) REPS"
        bannerShownAt = now
    }

    /// Starts the three-second "skipped" banner. Called once, where SKIP leaves the check early.
    public func skipped(now: Int64) {
        bannerText = "CALIBRATION SKIPPED"
        bannerShownAt = now
    }

    /// The film's HUD for a running workout: byte-for-byte what it has always shown.
    public func forWorkout(now: Int64, clock: String, label: String) -> RecordedHudText {
        RecordedHudText(clock: clock, round: workoutRound, label: label, count: workoutCount,
                        banner: bannerAt(now))
    }

    /// The film's HUD while the setup check runs: its own clock and round panel, the movement
    /// marked not scored, and a count against `calibrationReps` rather than the movement's real
    /// target — so the two calibration pull-ups read as calibration instead of the first two of a
    /// round that has not started.
    ///
    /// `setup` is `nil` for the one frame that can be rendered before the analysis thread has
    /// produced its first setup reading; that reads the same as a fresh `SetupStage.framing`
    /// would, which is what it would say a frame later anyway.
    public func forSetup(now: Int64, setup: Setup?, label: String) -> RecordedHudText {
        let count: String
        if let setup, setup.stage != .framing {
            count = "\(setup.reps) / \(Self.calibrationReps)"
        } else {
            count = "– / \(Self.calibrationReps)"
        }
        return RecordedHudText(clock: "SETUP", round: "CALIBRATION", label: "\(label) · NOT SCORED",
                               count: count, banner: bannerAt(now))
    }

    private func bannerAt(_ now: Int64) -> String? {
        guard let text = bannerText else { return nil }
        return now - bannerShownAt < Self.bannerMs ? text : nil
    }
}
