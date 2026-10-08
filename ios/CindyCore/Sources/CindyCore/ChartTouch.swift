import Foundation

/// A rectangle in a chart's own points, top left origin.
public struct ChartRect: Equatable, Sendable {
    public var left: Double
    public var top: Double
    public var right: Double
    public var bottom: Double

    public init(left: Double, top: Double, right: Double, bottom: Double) {
        self.left = left
        self.top = top
        self.right = right
        self.bottom = bottom
    }

    public var width: Double { right - left }
    public var height: Double { bottom - top }
    public var centreX: Double { (left + right) / 2 }
    public var centreY: Double { (top + bottom) / 2 }
}

/// Tells a tap from a sideways drag, the way the Android charts do: a gesture becomes a drag once
/// it has moved further than the slop and further across than down, and from then on it scrubs. A
/// vertical gesture never becomes one, so the scroll view around the chart keeps it.
public struct TouchTracker: Sendable {

    /// How far a finger may wander and still be tapping. Android's `scaledTouchSlop` is 8 dp.
    public static let defaultSlop = 8.0

    public let slop: Double
    private var downX = 0.0
    private var downY = 0.0

    /// True from the moment the gesture became a sideways drag.
    public private(set) var dragging = false

    public init(slop: Double = TouchTracker.defaultSlop) { self.slop = slop }

    public mutating func down(x: Double, y: Double) {
        downX = x
        downY = y
        dragging = false
    }

    /// The finger moved. Returns whether this gesture is a drag, and so should scrub.
    @discardableResult
    public mutating func move(x: Double, y: Double) -> Bool {
        let dx = abs(x - downX)
        if !dragging && dx > slop && dx > abs(y - downY) { dragging = true }
        return dragging
    }

    /// The finger lifted. Returns whether it was a tap, and resets for the next gesture.
    public mutating func up() -> Bool {
        let tap = !dragging
        dragging = false
        return tap
    }

    public mutating func cancel() { dragging = false }
}
