import Foundation

/// The progress chart: a line of attempts with a step line for the best so far, or one bar per
/// week. Port of the behaviour of `ProgressChartView`; the drawing is `ProgressChartView` in the
/// app.
///
/// Touch selects the nearest point (a tap) or scrubs through them (a sideways drag); a vertical
/// gesture is left alone so the scroll view around the chart keeps it. Each point is its own
/// screen reader stop. The earned colour is for what the athlete earned: the best-so-far line, a
/// record point, the best week.
public final class ProgressChartModel {

    public enum Mode: Sendable { case line, bars }

    /// How a point of the line is marked.
    public enum Mark: Sendable {
        /// The camera lost the athlete, so the score is a floor: a hollow ring.
        case ring
        /// A personal record when it was set: the earned colour.
        case record
        case plain
    }

    /// What colours a bar: the selected one, the best week, or the rest.
    public enum BarTone: Sendable { case selected, best, other }

    /// One bar, in the chart's own points.
    public struct Bar: Equatable, Sendable {
        public let left: Double
        public let right: Double
        public let top: Double
        public let bottom: Double
        /// Only the top corners are rounded; the foot sits flat on the axis.
        public let radius: Double
        public let tone: BarTone
    }

    /// Reports the selection as it changes; nil when it is cleared.
    public var onSelect: ((Int?) -> Void)?

    /// Told when a scrub moves onto another point, for a tick of haptics.
    public var onTick: (() -> Void)?

    /// The selected index, or nil when the selection is cleared.
    public private(set) var selected: Int?

    public private(set) var mode = Mode.line
    public private(set) var points: [ProgressPoint] = []
    public private(set) var best: [Double] = []
    public private(set) var xStart: Int64 = 0
    public private(set) var xEnd: Int64 = 0
    public private(set) var invertY = false
    public private(set) var edgeLabels: (first: String, second: String) = ("", "")
    public private(set) var ticks: [Double] = []
    /// The tallest week (the latest on a tie), or -1 when there is no best week to celebrate.
    public private(set) var bestBar = -1
    private var axisLabel: (Double) -> String = { _ in "" }
    private var describe: (Int) -> String = { _ in "" }
    private var touch = TouchTracker()

    /// Room left of the plot, above it, right of it (for the axis labels) and below it (for the
    /// edge dates).
    public static let topInset = 10.0
    public static let rightInset = 44.0
    public static let bottomInset = 22.0

    public init() {}

    public var pointCount: Int { points.count }

    /// What a screen reader says for each point: one stop each.
    public var stops: [String] { points.indices.map(describe) }

    /// One line of attempts. `best` is drawn as a step line in the earned colour.
    public func showLine(points: [ProgressPoint], best: [Double], xStart: Int64, xEnd: Int64, invertY: Bool,
                         edgeLabels: (String, String), axisLabel: @escaping (Double) -> String,
                         describe: @escaping (Int) -> String) {
        let values = points.map { $0.value } + best
        mode = .line
        self.points = points
        self.best = best
        self.xStart = xStart
        self.xEnd = xEnd
        self.invertY = invertY
        bestBar = -1
        ticks = values.isEmpty ? [] : Progress.niceTicks(values.min()!, values.max()!)
        adopt(edgeLabels, axisLabel, describe)
    }

    /// One bar per week; the tallest (latest on a tie) in the earned colour.
    public func showBars(points: [ProgressPoint], edgeLabels: (String, String),
                         axisLabel: @escaping (Double) -> String, describe: @escaping (Int) -> String) {
        let top = points.map { $0.value }.max() ?? 0.0
        mode = .bars
        self.points = points
        best = []
        invertY = false
        // A run of empty weeks has no best week to celebrate.
        bestBar = top > 0.0 ? (points.lastIndex { $0.value == top } ?? -1) : -1
        ticks = Progress.niceTicks(0.0, max(top, 1.0))
        adopt(edgeLabels, axisLabel, describe)
    }

    private func adopt(_ edgeLabels: (String, String), _ axisLabel: @escaping (Double) -> String,
                       _ describe: @escaping (Int) -> String) {
        self.edgeLabels = edgeLabels
        self.axisLabel = axisLabel
        self.describe = describe
        selected = nil
    }

    public func label(forTick value: Double) -> String { axisLabel(value) }

    /// Selects `index` (nil clears), and reports it.
    public func select(_ index: Int?) {
        selected = index
        onSelect?(index)
    }

    /// A screen reader activates the stop for point `i`.
    public func activate(stop i: Int) { select(i) }

    // MARK: geometry

    /// The plot inside a chart `width` by `height`.
    public func plot(width: Double, height: Double) -> ChartRect {
        ChartRect(left: 0, top: Self.topInset, right: width - Self.rightInset, bottom: height - Self.bottomInset)
    }

    private func lineX(_ atMillis: Int64, _ plot: ChartRect) -> Double {
        if xEnd <= xStart { return plot.centreX }
        let f = min(max(Double(atMillis - xStart) / Double(xEnd - xStart), 0.0), 1.0)
        return plot.left + f * plot.width
    }

    private func barCentre(_ i: Int, _ n: Int, _ plot: ChartRect) -> Double {
        plot.left + plot.width / Double(n) * (Double(i) + 0.5)
    }

    /// Bars grow from the bottom; on an inverted axis a smaller value sits higher.
    public func y(forValue value: Double, plot: ChartRect) -> Double {
        let lo = ticks.first ?? 0.0
        let hi = ticks.last ?? 1.0
        let f = hi - lo < 1e-9 ? 0.5 : (value - lo) / (hi - lo)
        return invertY ? plot.top + f * plot.height : plot.bottom - f * plot.height
    }

    /// The x of every point.
    public func xs(width: Double, height: Double) -> [Double] {
        let p = plot(width: width, height: height)
        let n = points.count
        return points.indices.map { mode == .bars ? barCentre($0, n, p) : lineX(points[$0].atMillis, p) }
    }

    /// The y of every point.
    public func ys(width: Double, height: Double) -> [Double] {
        let p = plot(width: width, height: height)
        return points.map { y(forValue: $0.value, plot: p) }
    }

    public func pointCentreX(_ i: Int, width: Double, height: Double) -> Double {
        xs(width: width, height: height)[i]
    }

    /// The step line of the best so far: it holds each value until the next point, then steps, and
    /// runs on to the right edge. Empty unless there is one best for every point.
    public func bestSteps(width: Double, height: Double) -> [(x: Double, y: Double)] {
        let n = points.count
        guard best.count == n, n > 0 else { return [] }
        let p = plot(width: width, height: height)
        let xs = self.xs(width: width, height: height)
        var out = [(x: xs[0], y: y(forValue: best[0], plot: p))]
        if n > 1 {
            for i in 1..<n {
                out.append((xs[i], y(forValue: best[i - 1], plot: p)))
                out.append((xs[i], y(forValue: best[i], plot: p)))
            }
        }
        out.append((p.right, y(forValue: best[n - 1], plot: p)))
        return out
    }

    /// How point `i` of the line is marked: the ring wins over the record.
    public func mark(_ i: Int) -> Mark {
        let p = points[i]
        if p.lowerBound { return .ring }
        if p.record { return .record }
        return .plain
    }

    /// The bars, left to right; a week with nothing in it has none.
    public func bars(width: Double, height: Double) -> [Bar?] {
        let n = points.count
        guard n > 0 else { return [] }
        let p = plot(width: width, height: height)
        let slot = p.width / Double(n)
        let half = max(2.0, slot * 0.62) / 2.0
        let corner = 3.0
        let xs = self.xs(width: width, height: height)
        let ys = self.ys(width: width, height: height)
        return (0..<n).map { i in
            let top = ys[i]
            if p.bottom - top < 1.0 { return nil }
            let tone: BarTone = i == selected ? .selected : (i == bestBar ? .best : .other)
            return Bar(left: xs[i] - half, right: xs[i] + half, top: top, bottom: p.bottom,
                       radius: min(corner, p.bottom - top), tone: tone)
        }
    }

    /// The nearest point to `x`.
    public func nearest(x: Double, width: Double, height: Double) -> Int {
        Progress.nearestIndex(xs(width: width, height: height).map { Float($0) }, Float(x))
    }

    // MARK: touch

    public func touchDown(x: Double, y: Double) {
        if points.isEmpty { return }
        touch.down(x: x, y: y)
    }

    public func touchMove(x: Double, y: Double, width: Double, height: Double) {
        if points.isEmpty { return }
        if touch.move(x: x, y: y) {
            let i = nearest(x: x, width: width, height: height)
            if i != selected {
                select(i)
                onTick?()
            }
        }
    }

    public func touchUp(x: Double, y: Double, width: Double, height: Double) {
        if points.isEmpty { return }
        if touch.up() {
            let i = nearest(x: x, width: width, height: height)
            select(i == selected ? nil : i)
        }
    }
}
