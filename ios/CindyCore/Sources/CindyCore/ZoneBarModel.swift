import Foundation

/// One bar split by how long the heart rate spent in each `HeartZone`, in the heart colour at five
/// rising opacities: the harder the zone, the stronger the pink, so the bar reads as effort without
/// a second hue to learn. Port of the behaviour of `ZoneBarView`.
///
/// A zone with no time has no width, and so no stop for a screen reader and nothing to select; the
/// rows under the bar still name all five, so a missing sliver is never a missing zone.
public final class ZoneBarModel {

    public static let barHeight = 28.0
    public static let gap = 2.0
    /// The height a finger is given, whatever the bar's own.
    public static let touchHeight = 48.0
    /// How far the unheld zones step back while one is held.
    public static let dim = 0.4
    /// The heart colour's opacity in each zone, lowest to highest. The first is still plainly
    /// visible against black; the steps are even enough to be told apart side by side.
    public static let alpha: [Double] = [0.26, 0.42, 0.6, 0.8, 1.0]

    /// Reports the selected zone's index as it changes; nil when it is cleared.
    public var onSelect: ((Int?) -> Void)?
    public var onTick: (() -> Void)?

    /// The selected zone's index into the list given to `setZones`, or nil for none.
    public private(set) var selected: Int?

    private var ms: [Int64] = []
    private var total: Int64 = 0
    private var descriptions: [String] = []
    /// The zones with any time, in order: the bar's segments and the screen reader's stops.
    public private(set) var shown: [Int] = []
    private var touch = TouchTracker()

    public init() {}

    /// The number of stops.
    public var stopCount: Int { shown.count }

    /// What a screen reader says for each stop: the zones that have time, in order.
    public var stops: [String] { shown.map { descriptions.indices.contains($0) ? descriptions[$0] : "" } }

    /// True once there is any time to draw.
    public var hasTime: Bool { total > 0 }

    /// Replaces everything drawn. `zones` are the five in order; `descriptions` is what a screen
    /// reader says for each, by the same index. A selection that still has time in it is kept.
    /// Returns whether this was the first data, which the caller reveals.
    @discardableResult
    public func setZones(_ zones: [ZoneTime], descriptions: [String]) -> Bool {
        let firstData = total == 0 && zones.contains { $0.ms > 0 }
        ms = zones.map { $0.ms }
        total = ms.reduce(0, +)
        self.descriptions = descriptions
        shown = ms.indices.filter { ms[$0] > 0 }
        if let s = selected, !ms.indices.contains(s) || ms[s] == 0 { selected = nil }
        return firstData
    }

    /// Selects `zone` (nil clears), and reports it. A zone with no time cannot be selected.
    public func select(_ zone: Int?) {
        if let zone, ms.indices.contains(zone), ms[zone] > 0 { selected = zone } else { selected = nil }
        onSelect?(selected)
    }

    /// A screen reader activates stop `i`, the `i`th zone that has time.
    public func activate(stop i: Int) {
        guard shown.indices.contains(i) else { return }
        select(shown[i])
    }

    // MARK: geometry

    /// Where each zone's segment starts and ends across a bar `width` wide.
    public func spans(in width: Double) -> [(left: Double, right: Double)] {
        var out: [(Double, Double)] = []
        var x = 0.0
        for z in ms.indices {
            let left = x
            if total > 0 { x += width * Double(ms[z]) / Double(total) }
            out.append((left, x))
        }
        return out
    }

    /// The x at the middle of `zone`'s segment.
    public func centreOf(_ zone: Int, in width: Double) -> Double {
        let s = spans(in: width)[zone]
        return (s.left + s.right) / 2
    }

    /// The zone under `x`: the one whose segment holds it, else the nearest that has time.
    public func zoneAt(_ x: Double, in width: Double) -> Int {
        let s = spans(in: width)
        var best = -1
        var bestDistance = Double.greatestFiniteMagnitude
        for z in shown {
            let d: Double
            if x < s[z].left { d = s[z].left - x }
            else if x > s[z].right { d = x - s[z].right }
            else { d = 0 }
            if d < bestDistance {
                bestDistance = d
                best = z
            }
        }
        return best
    }

    // MARK: touch

    public func touchDown(x: Double, y: Double) {
        if total <= 0 { return }
        touch.down(x: x, y: y)
    }

    public func touchMove(x: Double, y: Double, in width: Double) {
        if total <= 0 { return }
        if touch.move(x: x, y: y) {
            let zone = zoneAt(x, in: width)
            if zone != selected {
                select(zone)
                onTick?()
            }
        }
    }

    public func touchUp(x: Double, y: Double, in width: Double) {
        if total <= 0 { return }
        if touch.up() {
            let zone = zoneAt(x, in: width)
            // A second tap on the held zone lets it go, as a second tap on a point does.
            select(zone == selected ? nil : zone)
        }
    }
}
