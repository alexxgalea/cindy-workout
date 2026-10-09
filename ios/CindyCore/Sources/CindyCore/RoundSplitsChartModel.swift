import Foundation

/// The round splits: one bar per round, taller meaning slower, each stacked from the bottom into
/// pull-ups, push-ups and squats where the record can say where the time went. Port of the
/// behaviour of `RoundSplitsView`; the drawing is `RoundSplitsChart` in the app.
///
/// A short tick over a bar is where the comparison's round at the same position ended, so a bar
/// poking above its tick is slower than that session and one under it is faster. The round the
/// clock stopped in is outlined rather than filled, because it is a time so far and not a split.
///
/// A tap selects the nearest bar, a sideways drag scrubs, and every bar is its own screen reader stop.
public final class RoundSplitsChartModel {

    /// Room above the plot for the fastest round's dot, below it for the round numbers.
    public static let topInset = 16.0
    public static let bottomInset = 20.0

    public var onSelect: ((Int?) -> Void)?
    public var onTick: (() -> Void)?

    public private(set) var bars: [RoundSplits.Bar] = []
    public private(set) var reference: [Int64?] = []
    public private(set) var fastest = -1
    public private(set) var averageMs: Int64 = 0
    public private(set) var averageLabel: String?
    public private(set) var selected: Int?
    private var describe: (Int) -> String = { _ in "" }
    /// The tallest thing drawn sets the scale, so a tick above every bar is not clipped.
    public private(set) var maxMs: Int64 = 1

    /// The round numbers under the bars.
    public private(set) var roundLabels: [String] = []
    /// The rep count above an open bar: "12/30", or "≥12/30" when the camera lost the athlete.
    public private(set) var repLabels: [String?] = []

    private var touch = TouchTracker()

    public init() {}

    public var barCount: Int { bars.count }

    /// What a screen reader says for each bar.
    public var stops: [String] { bars.indices.map(describe) }

    /// Shows `bars`, dropping any selection. `averageLabel` is what the dashed average line is
    /// called, or nil to leave it undrawn; the chart holds raw milliseconds and does not format them.
    public func show(bars: [RoundSplits.Bar], fastest: Int, averageMs: Int64, averageLabel: String?,
                     describe: @escaping (Int) -> String) {
        self.bars = bars
        self.fastest = fastest
        self.averageMs = averageMs
        self.averageLabel = averageLabel
        self.describe = describe
        reference = []
        roundLabels = bars.map { String($0.round) }
        repLabels = bars.map { b in
            b.repsToQuote.map { reps in "\(b.atLeast ? "≥" : "")\(reps)/\(RoundSplits.roundTarget)" }
        }
        selected = nil
        rescale()
    }

    /// Sets the tick over each bar: `reference` is the comparison's split at that bar's round, or
    /// nil where it has none. Kept apart from `show` so choosing another comparison moves the ticks
    /// without losing the selection.
    public func setReference(_ reference: [Int64?]) {
        self.reference = reference
        rescale()
    }

    private func rescale() {
        var top: Int64 = 1
        for b in bars { top = max(top, b.ms) }
        for r in reference { if let r { top = max(top, r) } }
        maxMs = top
    }

    /// Selects `index` (nil clears), and reports it.
    public func select(_ index: Int?) {
        selected = index
        onSelect?(index)
    }

    /// A screen reader activates the stop for bar `i`.
    public func activate(stop i: Int) { select(i) }

    // MARK: geometry

    /// The plot inside a chart `width` by `height`.
    public func plot(width: Double, height: Double) -> ChartRect {
        ChartRect(left: 0, top: Self.topInset, right: width, bottom: height - Self.bottomInset)
    }

    public func slot(width: Double) -> Double { bars.isEmpty ? 0 : width / Double(bars.count) }

    public func centreX(_ i: Int, width: Double) -> Double { slot(width: width) * (Double(i) + 0.5) }

    /// The bar whose slot `x` falls in, so a finger between two bars still picks one.
    public func nearest(x: Double, width: Double) -> Int {
        let slot = slot(width: width)
        if slot <= 0 { return 0 }
        return min(max(Int(x / slot), 0), bars.count - 1)
    }

    /// The y of a duration in a plot, tallest at the top.
    public func y(forMs ms: Int64, plot: ChartRect) -> Double {
        plot.bottom - Double(ms) / Double(maxMs) * plot.height
    }

    /// Which round numbers are drawn: thinned until they stop touching, the selected one always.
    public func numberIndices(width: Double, textSize: Double = 11) -> [Int] {
        let slot = slot(width: width)
        if slot <= 0 { return [] }
        let wanted = textSize * 2.2
        let step = max(1, Int((wanted / slot).rounded(.up)))
        var out: [Int] = []
        for i in bars.indices {
            let isSelected = i == selected
            if !isSelected && i % step != 0 { continue }
            // A neighbour of the selected number would overlap it.
            if !isSelected, let chosen = selected, Double(abs(i - chosen)) * slot < wanted { continue }
            out.append(i)
        }
        return out
    }

    // MARK: touch

    public func touchDown(x: Double, y: Double) {
        if bars.isEmpty { return }
        touch.down(x: x, y: y)
    }

    public func touchMove(x: Double, y: Double, width: Double) {
        if bars.isEmpty { return }
        if touch.move(x: x, y: y) {
            let i = nearest(x: x, width: width)
            if i != selected {
                select(i)
                onTick?()
            }
        }
    }

    public func touchUp(x: Double, y: Double, width: Double) {
        if bars.isEmpty { return }
        if touch.up() {
            let i = nearest(x: x, width: width)
            select(i == selected ? nil : i)
        }
    }
}
