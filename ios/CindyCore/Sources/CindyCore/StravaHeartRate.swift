import Foundation

/// Places a `HeartRateTrace`'s samples onto the wall clock, and from there onto a payload's own
/// seconds-from-start axis.
///
/// A trace's samples are stamped on the workout clock, which stands still while the workout is
/// paused. Strava's stream wants real elapsed seconds instead, so every sample has to be walked
/// back onto the wall clock first: exactly the pauses that had already happened by that sample's
/// moment, added back in.
public enum StravaHeartRate {

    /// The wall-clock epoch ms `clockMs` on `trace`'s own workout clock actually happened at: the
    /// trace's start, plus the clock reading itself, plus every pause whose `atClockMs` had
    /// already passed by then.
    public static func wallMillis(_ trace: HeartRateTrace, _ clockMs: Int64) -> Int64 {
        trace.startedAtMillis + clockMs
            + trace.pauses.filter { $0.atClockMs <= clockMs }.reduce(0) { $0 + $1.lengthMs }
    }

    /// Every sample in `trace`, as seconds from `startMillis` via `wallMillis`, floored.
    public static func points(_ trace: HeartRateTrace, startMillis: Int64) -> [HrPoint] {
        trace.samples.map { sample in
            let seconds = Zone.floorDiv(wallMillis(trace, sample.clockMs) - startMillis, 1_000)
            return HrPoint(Int(seconds), sample.bpm)
        }
    }
}
