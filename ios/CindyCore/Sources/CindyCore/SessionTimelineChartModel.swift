import Foundation

/// One value on a lane at one instant of the workout clock.
public struct TimelinePoint: Equatable, Sendable {
    public let clockMs: Int64
    public let value: Double

    public init(_ clockMs: Int64, _ value: Double) {
        self.clockMs = clockMs
        self.value = value
    }
}

/// One unbroken stretch of a lane's own series. Two runs are never joined, which is how a gap in a
/// heart-rate trace stays a gap; and a run is the unit of style, so a lane whose series is partly
/// measured and partly estimated is several runs, some of them `dashed`.
public struct TimelineRun: Equatable, Sendable {
    public let points: [TimelinePoint]
    public let dashed: Bool

    public init(_ points: [TimelinePoint], dashed: Bool = false) {
        self.points = points
        self.dashed = dashed
    }
}

/// What a lane is drawn in. The app maps each to its colour; the model only carries which.
public enum TimelineTint: Sendable { case reps, heart, energy }

/// One band of the timeline, stacked above or below the others on a shared clock axis.
///
/// Nothing here is about reps or heart rate: a lane is a label, a tint, some runs and a way to
/// write a value, which is what lets a third kind be one more entry in the list rather than
/// another special case in the drawing or in the spoken text.
public struct TimelineLane: Sendable {
    /// Said above the band, in capitals.
    public let label: String
    public let tint: TimelineTint
    public let runs: [TimelineRun]
    /// The session being measured against, drawn dashed behind `runs`; empty for none.
    public let comparison: [TimelinePoint]
    /// Writes an axis value.
    public let format: @Sendable (Double) -> String
    /// True for a value that is banked and then holds, like reps: the line steps up at each point
    /// and runs flat between them. False joins the points directly.
    public let stepped: Bool
    /// True to start the axis at zero rather than at the lowest value.
    public let zeroBased: Bool
    /// How long after a point the cursor still reports its value for the cursor's dot, or
    /// `Int64.max` for as long as nothing newer has arrived.
    public let holdMs: Int64
    /// Draw a dot at each point, for a series whose points are all there is.
    public let markPoints: Bool
    /// True for a running total whose points are the ends of stretches that rose steadily: the
    /// cursor's dot rides the line between two points instead of sitting on the last one.
    public let interpolate: Bool
    public let height: Double

    public init(label: String, tint: TimelineTint, runs: [TimelineRun], comparison: [TimelinePoint] = [],
                format: @escaping @Sendable (Double) -> String, stepped: Bool = false, zeroBased: Bool = false,
                holdMs: Int64 = Int64.max, markPoints: Bool = false, interpolate: Bool = false,
                height: Double = 96) {
        self.label = label
        self.tint = tint
        self.runs = runs
        self.comparison = comparison
        self.format = format
        self.stepped = stepped
        self.zeroBased = zeroBased
        self.holdMs = holdMs
        self.markPoints = markPoints
        self.interpolate = interpolate
        self.height = height
    }
}

/// One screen reader stop: the stretch of the clock it covers, and what it says.
public struct TimelineStop: Equatable, Sendable {
    public let startMs: Int64
    public let endMs: Int64
    public let description: String

    public init(_ startMs: Int64, _ endMs: Int64, _ description: String) {
        self.startMs = startMs
        self.endMs = endMs
        self.description = description
    }
}

/// Lanes of one session against a shared clock: cumulative reps, heart rate, and whatever is added
/// next. Port of the behaviour of `SessionTimelineView`; the drawing is `SessionTimelineChart`.
///
/// The selection is an instant on the clock rather than one of its points: the cursor crosses every
/// lane at once, and each lane puts a dot where its own series stood. A scrub ticks the haptic as
/// it passes each of the first lane's points and each round end, not at every pixel, so a drag
/// through two hundred reps feels like two hundred reps.
public final class SessionTimelineChartModel {

    /// The row above each lane that names it.
    public static let labelHeight = 18.0
    public static let laneGap = 10.0
    /// The row under the last lane that carries the clock's two ends.
    public static let axisHeight = 22.0
    /// Room on the right for the lane's top and bottom value.
    public static let rightMargin = 44.0
    /// The closest two ticks of a scrub may be along a line of samples.
    public static let snapGapMs: Int64 = 5_000
    /// How near the cursor a second tap must land to put it away.
    public static let cursorGrab = 24.0

    public var onSelect: ((Int64?) -> Void)?
    public var onTick: (() -> Void)?

    /// The selected instant on the workout clock, or nil when the selection is cleared.
    public private(set) var selectedMs: Int64?

    public private(set) var lanes: [TimelineLane] = []
    public private(set) var durationMs: Int64 = 0
    public private(set) var roundEnds: [Int64] = []
    public private(set) var stops: [TimelineStop] = []
    private var snapClocks: [Int64] = []
    public private(set) var laneLo: [Double] = []
    public private(set) var laneHi: [Double] = []
    public private(set) var laneTicks: [[Double]] = []
    public private(set) var tickLabelLow: [String] = []
    public private(set) var tickLabelHigh: [String] = []
    public private(set) var endLabel = ""

    private var touch = TouchTracker()
    private var lastSnap = -1
    private var lastStop = -1

    /// Told when the selection lands on another round, for the screen reader to announce.
    public var onStopChanged: ((Int) -> Void)?

    public init() {}

    public var laneCount: Int { lanes.count }
    public var stopCount: Int { stops.count }

    /// Replaces everything drawn. `durationMs` is the shared axis; `roundEndsMs` are hairlines
    /// through every lane; `stops` are what a screen reader steps through, in clock order. A
    /// selection that is still on the clock is kept, so swapping the dashed comparison does not
    /// lose the place the athlete was looking at. Returns whether this was the first data.
    @discardableResult
    public func setLanes(_ lanes: [TimelineLane], durationMs: Int64, roundEndsMs: [Int64] = [],
                         stops: [TimelineStop] = []) -> Bool {
        let firstData = self.lanes.isEmpty && !lanes.isEmpty
        self.lanes = lanes
        self.durationMs = durationMs
        roundEnds = roundEndsMs
        self.stops = stops
        laneLo = Array(repeating: 0, count: lanes.count)
        laneHi = Array(repeating: 0, count: lanes.count)
        laneTicks = lanes.enumerated().map { i, lane in
            let values = lane.runs.flatMap { $0.points.map { $0.value } } + lane.comparison.map { $0.value }
            let lo = lane.zeroBased ? 0.0 : (values.min() ?? 0.0)
            let ticks = Progress.niceTicks(lo, max(values.max() ?? 1.0, lo + 1.0))
            laneLo[i] = ticks.first!
            laneHi[i] = ticks.last!
            return ticks
        }
        tickLabelLow = lanes.indices.map { lanes[$0].format(laneLo[$0]) }
        tickLabelHigh = lanes.indices.map { lanes[$0].format(laneHi[$0]) }
        endLabel = formatDuration(durationMs)
        snapClocks = Self.snapPoints(lanes.first, roundEndsMs)
        if let s = selectedMs, s > durationMs { selectedMs = nil }
        return firstData
    }

    /// The instants a scrub ticks on: the first lane's own points and the round ends, in order.
    static func snapPoints(_ first: TimelineLane?, _ ends: [Int64]) -> [Int64] {
        var clocks: [Int64] = []
        // A line of samples a second apart would tick on every one of them, which is a buzz and
        // not a texture; a stepped lane's points are events, and each of those is worth a tick.
        var lastKept = Int64.min
        if let first {
            for run in first.runs {
                for p in run.points where first.stepped || p.clockMs &- lastKept >= snapGapMs {
                    clocks.append(p.clockMs)
                    lastKept = p.clockMs
                }
            }
        }
        clocks.append(contentsOf: ends)
        return Array(Set(clocks)).sorted()
    }

    /// Selects the instant `clockMs` (nil clears), and reports it and the round it is in.
    public func select(_ clockMs: Int64?) {
        selectedMs = clockMs.map { min(max($0, 0), durationMs) }
        if selectedMs == nil { lastStop = -1 }
        onSelect?(selectedMs)
        guard let at = selectedMs else { return }
        let stop = stopAt(at)
        if stop >= 0 && stop != lastStop { onStopChanged?(stop) }
        lastStop = stop
    }

    /// A screen reader activates stop `i`: the cursor goes to the end of that round.
    public func activate(stop i: Int) {
        guard stops.indices.contains(i) else { return }
        select(stops[i].endMs)
    }

    // MARK: geometry

    /// The height the lanes need.
    public var height: Double {
        var wanted = Self.axisHeight
        for (i, lane) in lanes.enumerated() { wanted += lane.height + (i > 0 ? Self.laneGap : 0) }
        return wanted
    }

    /// The plot's left and right edges inside a chart `width` wide.
    public func plot(width: Double) -> (left: Double, right: Double) { (0, width - Self.rightMargin) }

    /// The top and bottom of every lane.
    public func laneBounds() -> [(top: Double, bottom: Double)] {
        var y = 0.0
        return lanes.map { lane in
            let top = y + Self.labelHeight
            let bottom = y + lane.height
            y = bottom + Self.laneGap
            return (top, bottom)
        }
    }

    public func x(forClock clockMs: Int64, width: Double) -> Double {
        let p = plot(width: width)
        if durationMs <= 0 { return p.left }
        return p.left + Double(clockMs) / Double(durationMs) * (p.right - p.left)
    }

    public func clock(forX x: Double, width: Double) -> Int64 {
        let p = plot(width: width)
        if p.right - p.left <= 0 { return 0 }
        let f = min(max((x - p.left) / (p.right - p.left), 0), 1)
        return JavaText.roundToLong(f * Double(durationMs))
    }

    public func y(lane: Int, value: Double) -> Double {
        let lo = laneLo[lane], hi = laneHi[lane]
        let b = laneBounds()[lane]
        let f = hi - lo < 1e-9 ? 0.5 : (value - lo) / (hi - lo)
        return b.bottom - f * (b.bottom - b.top)
    }

    /// The stop covering `clockMs`, or -1 for none. A stop covers its own end, as a round does.
    public func stopAt(_ clockMs: Int64) -> Int {
        for i in stops.indices where clockMs <= stops[i].endMs { return i }
        return stops.isEmpty ? -1 : stops.count - 1
    }

    /// How many snap instants are at or before `clockMs`.
    func snapIndex(_ clockMs: Int64) -> Int {
        var lo = 0, hi = snapClocks.count
        while lo < hi {
            let mid = (lo + hi) >> 1
            if snapClocks[mid] <= clockMs { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    // MARK: the cursor's dots

    /// Where lane `i`'s own series stood at `clockMs`, or nil: the latest run that has begun.
    public func value(lane i: Int, at clockMs: Int64) -> Double? {
        let lane = lanes[i]
        for run in lane.runs.reversed() where !run.points.isEmpty && run.points[0].clockMs <= clockMs {
            return Self.valueAt(run.points, clockMs, stepped: lane.stepped, holdMs: lane.holdMs, interpolate: lane.interpolate)
        }
        return nil
    }

    /// Where the comparison stood at `clockMs`, or nil.
    public func comparisonValue(lane i: Int, at clockMs: Int64) -> Double? {
        let lane = lanes[i]
        return Self.valueAt(lane.comparison, clockMs, stepped: lane.stepped, holdMs: lane.holdMs, interpolate: false)
    }

    /// The latest point at or before `clockMs` (never a position between two, unless `interpolate`),
    /// or nil when there is none, or for a lane with a hold when it is older than that.
    static func valueAt(_ points: [TimelinePoint], _ clockMs: Int64, stepped: Bool, holdMs: Int64,
                        interpolate: Bool) -> Double? {
        var lo = 0, hi = points.count
        while lo < hi {
            let mid = (lo + hi) >> 1
            if points[mid].clockMs <= clockMs { lo = mid + 1 } else { hi = mid }
        }
        if lo == 0 { return nil }
        let p = points[lo - 1]
        if interpolate && lo < points.count {
            let q = points[lo]
            return p.value + (q.value - p.value) * Double(clockMs - p.clockMs) / Double(q.clockMs - p.clockMs)
        }
        if !stepped && clockMs - p.clockMs > holdMs { return nil }
        return p.value
    }

    // MARK: touch

    public func touchDown(x: Double, y: Double) {
        if lanes.isEmpty { return }
        touch.down(x: x, y: y)
    }

    public func touchMove(x: Double, y: Double, width: Double) {
        if lanes.isEmpty { return }
        if touch.move(x: x, y: y) { scrub(to: x, width: width) }
    }

    public func touchUp(x: Double, y: Double, width: Double) {
        if lanes.isEmpty { return }
        if touch.up() {
            // A second tap on the cursor puts it away, as a second tap on a point does.
            if let current = selectedMs, abs(self.x(forClock: current, width: width) - x) <= Self.cursorGrab {
                select(nil)
            } else {
                let at = clock(forX: x, width: width)
                lastSnap = snapIndex(at)
                select(at)
            }
        }
    }

    private func scrub(to x: Double, width: Double) {
        let at = clock(forX: x, width: width)
        if at == selectedMs { return }
        select(at)
        let snap = snapIndex(at)
        if snap != lastSnap {
            lastSnap = snap
            onTick?()
        }
    }
}
