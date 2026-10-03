import Foundation

/// Where to look for the body next: a square around where it was last seen, following it, and
/// the whole frame again once it has been lost for a few frames running.
///
/// This is the decision half of `PoseDetector`'s region-of-interest tracking, with the model taken
/// out, so it can be tested and so a detector of any kind can use it.
///
/// ### Why the crop matters
///
/// A pose model resizes whatever it is given down to a small square. A phone standing on the floor
/// puts the athlete in a slice of a tall frame, so feeding it whole spends most of those pixels on
/// ceiling and carpet and leaves the body a few dozen pixels tall — which is where the keypoints
/// get mushy and the rep counter starts guessing.
///
/// So each frame is cropped to a square around where the body was last seen, and the model sees a
/// body that fills the input. The crop follows the athlete, grows a margin around them, and falls
/// back to the whole frame whenever tracking is lost.
///
/// All in upright-frame pixels, y down. A crop may reach outside the frame, which a detector that
/// can letterbox leaves black; one that cannot clamps it with `VisionGeometry`.
public final class RoiTracker {

    /// A square region of the frame, in pixels.
    public struct Region: Equatable, Sendable {
        public let left: Float, top: Float, right: Float, bottom: Float

        public init(left: Float, top: Float, right: Float, bottom: Float) {
            self.left = left; self.top = top; self.right = right; self.bottom = bottom
        }

        public var width: Float { right - left }
        public var height: Float { bottom - top }
    }

    /// A keypoint this unsure of is not evidence of where the body is.
    public static let minScore: Float = 0.30
    /// Confident keypoints needed to trust the crop for the next frame.
    public static let minTracked = 5
    /// Consecutive poor frames before giving up and re-scanning the whole image.
    public static let maxMisses = 5
    /// How much room to leave around the body, as a multiple of its bounding box.
    public static let margin: Float = 1.45
    /// Crop is never allowed below this share of the frame, to avoid chasing noise.
    public static let minCropFraction: Float = 0.25
    /// Per-frame follow rate of the crop, damping jitter.
    public static let follow: Float = 0.35

    /// Square crop in frame pixels; `nil` means "look at the whole frame".
    public private(set) var roi: Region?
    private var misses = 0

    /// True while the model is being fed a tracked crop rather than the whole frame.
    ///
    /// Set when a frame *begins*, so it describes the crop the frame being analysed was given,
    /// and is read after detection for that same frame.
    public private(set) var tracking = false

    public init() {}

    /// Forgets the tracked crop — call when the camera changes or a workout restarts.
    public func reset() {
        roi = nil
        misses = 0
        tracking = false
    }

    /// Picks this frame's crop and records whether it is a tracked one.
    public func beginFrame(frameWidth: Int, frameHeight: Int) -> Region {
        let region = roi ?? Self.fullFrameSquare(frameWidth, frameHeight)
        tracking = roi != nil
        return region
    }

    /// The whole frame expressed as a square, so a portrait image is letterboxed not cropped.
    public static func fullFrameSquare(_ width: Int, _ height: Int) -> Region {
        let side = Float(max(width, height))
        return Region(left: (Float(width) - side) / 2, top: (Float(height) - side) / 2,
                      right: (Float(width) + side) / 2, bottom: (Float(height) + side) / 2)
    }

    /// Re-aims the crop at wherever the body just was, or drops it if the body was lost.
    public func update(_ keypoints: [Keypoint], frameWidth: Int, frameHeight: Int) {
        let seen = keypoints.filter { $0.score >= Self.minScore }
        if seen.count < Self.minTracked {
            misses += 1
            if misses >= Self.maxMisses { reset() }
            return
        }
        misses = 0

        var left = Float.greatestFiniteMagnitude, top = Float.greatestFiniteMagnitude
        var right = -Float.greatestFiniteMagnitude, bottom = -Float.greatestFiniteMagnitude
        for p in seen {
            left = min(left, p.x); right = max(right, p.x)
            top = min(top, p.y); bottom = max(bottom, p.y)
        }

        let longest = max(Float(max(frameWidth, frameHeight)), 1)
        let side = min(max(max(right - left, bottom - top) * Self.margin, longest * Self.minCropFraction), longest)
        let cx = (left + right) / 2
        let cy = (top + bottom) / 2

        let target = Region(left: cx - side / 2, top: cy - side / 2, right: cx + side / 2, bottom: cy + side / 2)
        if let current = roi {
            let f = Self.follow
            roi = Region(
                left: current.left + (target.left - current.left) * f,
                top: current.top + (target.top - current.top) * f,
                right: current.right + (target.right - current.right) * f,
                bottom: current.bottom + (target.bottom - current.bottom) * f)
        } else {
            roi = target
        }
    }
}

/// A rectangle in Vision's normalised space: 0 to 1 on both axes, with the origin at the
/// **bottom left**, y up.
public struct NormalisedRect: Equatable, Sendable {
    public let x: Double, y: Double, width: Double, height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }

    /// The whole image.
    public static let full = NormalisedRect(x: 0, y: 0, width: 1, height: 1)
}

/// The two conversions between the app's upright pixels (origin top left, y down) and Vision's
/// normalised space (origin bottom left, y up). Pure, so the flip that is easy to get backwards
/// can be checked without a camera.
public enum VisionGeometry {

    /// The region to hand Vision for `region`, or the whole image when there is none.
    ///
    /// Vision only accepts a region inside the image, where the tracker's crop may reach outside it
    /// (a detector that letterboxes leaves that black). So a crop that is as large as the frame's
    /// short side or larger is the whole frame, which Vision looks at in full; a smaller one is
    /// kept the same size and slid back inside the frame. It stays square in pixels, not in
    /// normalised units, which would be a stretched rectangle in a portrait frame.
    public static func regionOfInterest(for region: RoiTracker.Region?, frameWidth: Int, frameHeight: Int) -> NormalisedRect {
        guard let region, frameWidth > 0, frameHeight > 0 else { return .full }
        let w = Double(frameWidth), h = Double(frameHeight)
        let side = Double(region.width)
        if side >= min(w, h) { return .full }

        let left = min(max(Double(region.left), 0), w - side)
        let top = min(max(Double(region.top), 0), h - side)
        return NormalisedRect(x: left / w, y: 1 - (top + side) / h, width: side / w, height: side / h)
    }

    /// A point Vision reported within `roi`, as pixels of the frame, y down.
    ///
    /// Vision's points are relative to the region it was restricted to, so the region is undone
    /// first and then the vertical axis flipped.
    public static func pixel(x: Double, y: Double, roi: NormalisedRect, frameWidth: Int, frameHeight: Int) -> (x: Float, y: Float) {
        let nx = roi.x + x * roi.width
        let ny = roi.y + y * roi.height
        return (Float(nx * Double(frameWidth)), Float((1 - ny) * Double(frameHeight)))
    }
}
