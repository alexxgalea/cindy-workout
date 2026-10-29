import Foundation

/// Notices that the bar is what is wrong, not the athlete.
///
/// A bar is learned from one hang and then refuses every grip that is not on it. If it was learned
/// in the wrong place, nothing else corrects it: refining the bar needs a grip it already accepts,
/// and the one recovery that exists needs the athlete to change size in the frame. Four recorded
/// sessions sat at "Get on the bar" for as long as the athlete kept pulling up.
///
/// So the engine tells this watch, on every frame it reads a pull-up, whether the bar refused it.
/// When the bar has refused half of what it was shown across four seconds, it is asked to be
/// forgotten and learned again from the next hang. An athlete who has stepped off the bar is refused
/// for just as long, and the next hang they make is then taken for the bar: that is the price of
/// being able to recover from a bar learned in the wrong place, and the owner's choice to pay it.
public final class BarRefusalWatch {

    /// How far back the refusals are counted.
    private static let windowMs: Int64 = 4_000
    /// Fewer frames than this say nothing, however many were refused.
    private static let minFrames = 20
    /// How much of the window the frames must really span, so a burst is not four seconds.
    private static let minSpanMs: Int64 = 3_500

    private var times: [Int64] = []
    private var refusals: [Bool] = []
    private var refused = 0

    public init() {}

    /// Notes one frame: whether the bar refused it, at `now` in the engine's clock.
    /// Returns true when the bar has refused enough of the last four seconds to be doubted, and
    /// starts counting again from nothing.
    public func record(now: Int64, refusedByBar: Bool) -> Bool {
        times.append(now)
        refusals.append(refusedByBar)
        if refusedByBar { refused += 1 }
        while now - times[0] > Self.windowMs {
            times.removeFirst()
            if refusals.removeFirst() { refused -= 1 }
        }
        if times.count < Self.minFrames || now - times[0] < Self.minSpanMs { return false }
        // Half or more of the frames. In whole numbers, so no engine can round it differently.
        if refused * 2 < times.count { return false }
        clear()
        return true
    }

    /// Forgets what was counted, as when the bar itself has been forgotten.
    public func clear() {
        times.removeAll()
        refusals.removeAll()
        refused = 0
    }
}
