import Foundation

/// A rectangle in the camera screen's own coordinates, in points. Foundation only, so that the tour
/// can be tested without a view.
public struct SpotlightRect: Equatable, Sendable {
    public var x: Float
    public var y: Float
    public var width: Float
    public var height: Float

    public init(x: Float, y: Float, width: Float, height: Float) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var minX: Float { x }
    public var minY: Float { y }
    public var maxX: Float { x + width }
    public var maxY: Float { y + height }

    /// Whether it has been given a size.
    public var hasSize: Bool { width > 0 && height > 0 }

    /// The part of this inside `other`, or this unchanged where the two do not meet: the same
    /// answer `RectF.intersect` leaves behind when it returns false.
    func clipped(to other: SpotlightRect) -> SpotlightRect {
        let left = max(minX, other.minX), top = max(minY, other.minY)
        let right = min(maxX, other.maxX), bottom = min(maxY, other.maxY)
        guard left < right, top < bottom else { return self }
        return SpotlightRect(x: left, y: top, width: right - left, height: bottom - top)
    }
}

/// A tour of the camera screen: the screen dimmed, one control left bright, and a card that says
/// what it is for. Port of `SpotlightView`'s state and arithmetic; the dimming, the ring and the
/// card are drawn by the screen.
///
/// It exists because the HUD is icons, and an icon is a thing you have to already know. The pages
/// before the camera say what Cindy is; this says what each button on the screen does, pointing at
/// the real one rather than describing it. It is taken once, on the first run, and again whenever
/// Help is asked.
///
/// While it is showing it takes every touch: a tap anywhere moves on, so nothing it highlights can
/// be pressed by accident, START least of all. Where the card goes is `SpotlightMath`'s decision.
///
/// A value, not an object: `start`, `advance` and `skip` say whether this call is the one that ended
/// the tour, and the owner calls its "done" on exactly that, which is what makes it once however
/// many times the tour is ended.
public struct SpotlightTour: Equatable, Sendable {

    /// The bright window stands this far off the control on every side.
    public static let padding: Float = 8
    /// The card sits this far from the window, and this far from the edge of the screen.
    public static let captionGap: Float = 14
    public static let captionMargin: Float = 16
    /// The ring's corners, kept under half the window's shorter side.
    public static let cornerRadius: Float = 18

    private var steps: [HudTour.Step] = []
    private var index = 0
    private var showing = false

    public init() {}

    /// Whether the tour is on the screen.
    public var isShowing: Bool { showing }

    /// How many controls the tour is pointing at, once any that are not showing are left out.
    public var stepCount: Int { steps.count }

    /// The control it is pointing at now, from zero.
    public var stepIndex: Int { index }

    /// The step being shown, or nil when the tour is not.
    public var current: HudTour.Step? { showing ? steps[index] : nil }

    public var isLastStep: Bool { index == steps.count - 1 }

    /// The button on the card.
    public var nextLabel: String { isLastStep ? "DONE" : "NEXT" }

    public static let skipLabel = "SKIP TOUR"
    public static let skipDescription = "Skip the tour"
    public static let paneTitle = "Tour"

    /// Said on every step rather than left to be found: a screen reader cannot see where the light
    /// has gone.
    public var announcement: String? { current.map { "\($0.title). \($0.body)" } }

    /// While the tour is showing it takes every touch, so a tap on the dimmed screen moves on and
    /// reaches nothing beneath.
    public var takesEveryTouch: Bool { showing }

    /// While the tour is showing the screen under it is for nobody. The dim keeps it from sight and
    /// from touch; this keeps it from a screen reader, so that swiping cannot reach START any more
    /// than a tap can.
    public var hidesScreenBeneath: Bool { showing }

    /// Starts the tour at the first of `candidates` that is showing, and says whether there is
    /// anything to point at. When there is not, the tour is never shown and the owner is done at
    /// once.
    ///
    /// `frame` is where a control is, or nil when it is hidden, or something above it is. A control
    /// that is hidden, or that has no size yet, is left out rather than lit as an empty hole: the
    /// tour is for what the athlete can see.
    public mutating func start(_ candidates: [HudTour.Step], frame: (HudTour.Target) -> SpotlightRect?) -> Bool {
        let visible = candidates.filter { Self.isShowable(frame($0.target)) }
        guard !visible.isEmpty else { return false }
        steps = visible
        index = 0
        showing = true
        return true
    }

    /// Whether a control with this frame is lit: it is showing, and it has been given a size.
    public static func isShowable(_ frame: SpotlightRect?) -> Bool { frame?.hasSize ?? false }

    /// Moves to the next step, or ends the tour after the last. True when this call ended it.
    public mutating func advance() -> Bool {
        guard showing else { return false }
        if index < steps.count - 1 {
            index += 1
            return false
        }
        return skip()
    }

    /// Ends the tour where it is. True when this call ended it, false when it was already over.
    public mutating func skip() -> Bool {
        guard showing else { return false }
        showing = false
        steps = []
        index = 0
        return true
    }

    // MARK: geometry

    /// The bright window around a control, in the screen's own coordinates, kept on the screen.
    public static func window(around control: SpotlightRect, in bounds: SpotlightRect) -> SpotlightRect {
        SpotlightRect(x: control.x - padding, y: control.y - padding,
                      width: control.width + 2 * padding, height: control.height + 2 * padding)
            .clipped(to: bounds)
    }

    /// The top edge of the card for this window and this card height, on a screen this tall.
    public static func captionTop(window: SpotlightRect, captionHeight: Float, screenHeight: Float) -> Float {
        SpotlightMath.captionTop(targetTop: window.minY, targetBottom: window.maxY, captionHeight: captionHeight,
                                 screenHeight: screenHeight, gap: captionGap, margin: captionMargin)
    }

    /// The radius of the window's corners: the ring's, but never more than half its shorter side.
    public static func cornerRadius(of window: SpotlightRect) -> Float {
        min(cornerRadius, min(window.width, window.height) / 2)
    }
}
