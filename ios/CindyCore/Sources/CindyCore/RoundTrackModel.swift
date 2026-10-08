import Foundation

/// One pill per round, ten to a row, each split into pull-ups, push-ups and squats in the 5:10:15
/// proportion of the scheme and filled by how much of each the athlete reached. Port of the
/// behaviour of `RoundTrackView`; the drawing is `RoundTrackView` in the app.
///
/// What was not done stays an outline, so a skipped pull-up set is a hollow stretch at the front of
/// its pill rather than a round that quietly looks complete, and the round the clock ran out on is
/// simply the last, part-filled one. A filled segment is never longer than the reps behind it.
///
/// A tap selects (a second tap clears), a sideways drag scrubs, and each round is its own screen
/// reader stop. What a selection says is the caller's to show, through `onSelect`.
public final class RoundTrackModel {

    public static let columns = 10
    /// The whole touch target of one round: a full row high, so it clears a finger.
    public static let cellHeight = 48.0
    public static let pillHeight = 32.0
    public static let pillGap = 4.0
    public static let corner = 8.0

    /// Reports the selection as it changes; nil when it is cleared.
    public var onSelect: ((Int?) -> Void)?

    /// Told when a scrub moves onto another round, for a tick of haptics.
    public var onTick: (() -> Void)?

    public private(set) var rounds: [RoundStat] = []
    public private(set) var selected: Int?
    private var describe: (Int) -> String = { _ in "" }
    private var touch = TouchTracker()

    public init() {}

    /// Shows `rounds`, clearing any selection. `describe` is what a screen reader says for round `i`.
    public func show(_ rounds: [RoundStat], describe: @escaping (Int) -> String) {
        self.rounds = rounds
        self.describe = describe
        selected = nil
    }

    /// The number of pills.
    public var pillCount: Int { rounds.count }

    /// What a screen reader says for each round: one stop each.
    public var stops: [String] { rounds.indices.map(describe) }

    /// The height the pills need, a full row for each ten.
    public var height: Double {
        let rows = (rounds.count + Self.columns - 1) / Self.columns
        return Double(rows) * Self.cellHeight
    }

    public func cellWidth(in width: Double) -> Double { width / Double(Self.columns) }

    /// The whole touch target of round `i`.
    public func cell(_ i: Int, in width: Double) -> ChartRect {
        let w = cellWidth(in: width)
        let left = Double(i % Self.columns) * w
        let top = Double(i / Self.columns) * Self.cellHeight
        return ChartRect(left: left, top: top, right: left + w, bottom: top + Self.cellHeight)
    }

    public func centre(_ i: Int, in width: Double) -> (x: Double, y: Double) {
        let c = cell(i, in: width)
        return (c.centreX, c.centreY)
    }

    /// The round under a point, clamped to the grid so a touch in the margin still lands.
    public func nearest(x: Double, y: Double, in width: Double) -> Int {
        let rows = (rounds.count + Self.columns - 1) / Self.columns
        let column = min(max(Int(x / max(cellWidth(in: width), 1)), 0), Self.columns - 1)
        let row = min(max(Int(y / Self.cellHeight), 0), max(rows - 1, 0))
        return min(row * Self.columns + column, rounds.count - 1)
    }

    /// Selects `index` (nil clears), and reports it.
    public func select(_ index: Int?) {
        selected = index
        onSelect?(index)
    }

    /// A screen reader activates the stop for round `i`.
    public func activate(stop i: Int) { select(i) }

    // MARK: touch

    public func touchDown(x: Double, y: Double) {
        if rounds.isEmpty { return }
        touch.down(x: x, y: y)
    }

    public func touchMove(x: Double, y: Double, in width: Double) {
        if rounds.isEmpty { return }
        if touch.move(x: x, y: y) {
            let i = nearest(x: x, y: y, in: width)
            if i != selected {
                select(i)
                onTick?()
            }
        }
    }

    public func touchUp(x: Double, y: Double, in width: Double) {
        if rounds.isEmpty { return }
        if touch.up() {
            let i = nearest(x: x, y: y, in: width)
            select(i == selected ? nil : i)
        }
    }

    // MARK: drawing

    /// One part of a pill: where it starts and how long it is as a share of the pill, and how
    /// much of it the athlete reached.
    public struct Segment: Equatable, Sendable {
        public let movement: Exercise
        public let start: Double
        public let length: Double
        /// 0...1: how much of the segment is filled.
        public let reached: Double
    }

    /// The three segments of round `i` across a pill `pillWidth` wide.
    public func segments(round i: Int, pillWidth: Double) -> [Segment] {
        let total = Double(Exercise.allCases.reduce(0) { $0 + $1.target })
        var x = 0.0
        return rounds[i].parts.map { part in
            let length = pillWidth * Double(part.movement.target) / total
            let reached = min(max(Double(part.reps) / Double(part.movement.target), 0), 1)
            defer { x += length }
            return Segment(movement: part.movement, start: x, length: length, reached: reached)
        }
    }

    /// The pill for round `i` inside its cell: inset by half the gap, centred in the row.
    public func pill(_ i: Int, in width: Double) -> ChartRect {
        let c = cell(i, in: width)
        let inset = Self.pillGap / 2
        let top = c.centreY - Self.pillHeight / 2
        return ChartRect(left: c.left + inset, top: top, right: c.right - inset, bottom: top + Self.pillHeight)
    }
}
