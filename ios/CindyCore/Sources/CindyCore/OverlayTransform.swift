import Foundation

/// The affine map from the upright analysis frame onto a recorded video buffer.
///
/// Deliberately free of `CGAffineTransform`: this is the calculation that put the whole overlay in a
/// corner at a fraction of its size on Android, and platform classes are unavailable in a Linux
/// test, so it could not be checked there. In plain Swift it can be.
///
/// Row-major affine:
/// ```
/// | a c tx |
/// | b d ty |
/// | 0 0  1 |
/// ```
public struct Affine: Equatable, Sendable {
    public let a: Float, b: Float
    public let c: Float, d: Float
    public let tx: Float, ty: Float

    public init(a: Float, b: Float, c: Float, d: Float, tx: Float, ty: Float) {
        self.a = a; self.b = b; self.c = c; self.d = d; self.tx = tx; self.ty = ty
    }

    /// Applies this transform, then `next` — the same order as Android's `Matrix.postConcat`.
    public func then(_ next: Affine) -> Affine {
        Affine(
            a: next.a * a + next.c * b,
            b: next.b * a + next.d * b,
            c: next.a * c + next.c * d,
            d: next.b * c + next.d * d,
            tx: next.a * tx + next.c * ty + next.tx,
            ty: next.b * tx + next.d * ty + next.ty)
    }

    public func mapX(_ x: Float, _ y: Float) -> Float { a * x + c * y + tx }
    public func mapY(_ x: Float, _ y: Float) -> Float { b * x + d * y + ty }

    /// The transform that undoes this one, or `nil` if it collapses the plane.
    ///
    /// Needed to walk a destination backwards to its source: filling an input by asking, for each
    /// output pixel, which camera pixel feeds it. That is the direction a sampler works in, and it
    /// is the opposite of the direction everything else here is built to go.
    public func invert() -> Affine? {
        let det = a * d - c * b
        if abs(det) < 1e-9 { return nil }
        let ia = d / det
        let ib = -b / det
        let ic = -c / det
        let id = a / det
        return Affine(a: ia, b: ib, c: ic, d: id, tx: -(ia * tx + ic * ty), ty: -(ib * tx + id * ty))
    }

    /// In the order Android's `Matrix.setValues` wants: scaleX, skewX, transX, skewY, scaleY,
    /// transY, 0, 0, 1.
    public func values() -> [Float] { [a, c, tx, b, d, ty, 0, 0, 1] }

    public static let identity = Affine(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)

    public static func scale(_ sx: Float, _ sy: Float) -> Affine {
        Affine(a: sx, b: 0, c: 0, d: sy, tx: 0, ty: 0)
    }

    public static func translate(_ dx: Float, _ dy: Float) -> Affine {
        Affine(a: 1, b: 0, c: 0, d: 1, tx: dx, ty: dy)
    }

    /// Clockwise in screen coordinates, matching `Matrix.postRotate`.
    public static func rotate(_ degrees: Float) -> Affine {
        // Java's Math.toRadians multiplies by this constant, in Double.
        let r = Double(degrees) * 0.017453292519943295
        // Snap the quarter turns so 90 does not arrive as 6.1e-17.
        let cos = clean(Float(Foundation.cos(r)))
        let sin = clean(Float(Foundation.sin(r)))
        return Affine(a: cos, b: sin, c: -sin, d: cos, tx: 0, ty: 0)
    }

    public static func scaleAbout(_ sx: Float, _ sy: Float, _ px: Float, _ py: Float) -> Affine {
        translate(-px, -py).then(scale(sx, sy)).then(translate(px, py))
    }

    private static func clean(_ v: Float) -> Float {
        // Kotlin's roundToInt rounds halves up.
        let rounded = (v + 0.5).rounded(.down)
        return abs(v - rounded) < 1e-6 ? rounded : v
    }
}

/// A rectangle in the upright source frame's own coordinates.
///
/// Used for the region of that frame the recording actually keeps; see
/// `OverlayTransform.visibleSource`.
public struct SourceRect: Equatable, Sendable {
    public let left: Float, top: Float
    public let right: Float, bottom: Float

    public init(left: Float, top: Float, right: Float, bottom: Float) {
        self.left = left; self.top = top; self.right = right; self.bottom = bottom
    }

    public var width: Float { right - left }
    public var height: Float { bottom - top }
}

public enum OverlayTransform {

    private static func normalised(_ degrees: Int) -> Int { ((degrees % 360) + 360) % 360 }

    /// Builds the map from an upright frame of `srcWidth` x `srcHeight` onto a video buffer of
    /// `bufferWidth` x `bufferHeight` that must be turned `rotationDegrees` clockwise to display.
    ///
    /// The fit is fill-centre, the same as the preview uses, so the recording is framed like the
    /// screen and nothing is stretched. `mirror` flips horizontally, for when the keypoints were
    /// mirrored for the selfie camera but the recorded buffer was not, or the other way about.
    public static func build(
        srcWidth: Int, srcHeight: Int, bufferWidth: Int, bufferHeight: Int,
        rotationDegrees: Int, mirror: Bool
    ) -> Affine {
        if srcWidth <= 0 || srcHeight <= 0 || bufferWidth <= 0 || bufferHeight <= 0 { return .identity }
        let rotation = normalised(rotationDegrees)
        let quarterTurned = rotation % 180 != 0
        // At 90 and 270 the buffer is stored with its axes swapped relative to the display.
        let displayW = quarterTurned ? Float(bufferHeight) : Float(bufferWidth)
        let displayH = quarterTurned ? Float(bufferWidth) : Float(bufferHeight)

        let scale = max(displayW / Float(srcWidth), displayH / Float(srcHeight))
        var m = Affine.scale(scale, scale).then(
            Affine.translate((displayW - Float(srcWidth) * scale) / 2, (displayH - Float(srcHeight) * scale) / 2))

        if mirror { m = m.then(Affine.scaleAbout(-1, 1, displayW / 2, displayH / 2)) }

        // Out of display orientation and into the buffer's own.
        let turn = Affine.rotate(Float(-rotation))
        m = m.then(turn)

        // Rotating about the origin walks the rect off it; bring it back.
        var left = Float.greatestFiniteMagnitude
        var top = Float.greatestFiniteMagnitude
        for (x, y) in [(Float(0), Float(0)), (displayW, 0), (0, displayH), (displayW, displayH)] {
            left = min(left, turn.mapX(x, y))
            top = min(top, turn.mapY(x, y))
        }
        return m.then(Affine.translate(-left, -top))
    }

    /// The map from the camera's raw analysis buffer onto the upright frame the app reasons in.
    ///
    /// ### Why this exists instead of a rotated bitmap
    ///
    /// Turning a frame upright by allocating a second full-frame image and handing that to the
    /// detector costs two resamples of every pixel and a second allocation per frame, all to
    /// produce an intermediate nobody ever looks at. The detector already draws through a
    /// transform; composing this in front of that one gets the rotation for free, and a *sharper*
    /// input, because a pure quarter turn needs no resampling at all.
    ///
    /// Returned as an `Affine` rather than a platform matrix so the geometry can be checked
    /// anywhere instead of only on a phone.
    public static func upright(srcWidth: Int, srcHeight: Int, rotationDegrees: Int, mirror: Bool) -> Affine {
        if srcWidth <= 0 || srcHeight <= 0 { return .identity }
        let rotation = normalised(rotationDegrees)
        let turn = Affine.rotate(Float(rotation))

        // Rotating about the origin walks the frame off it; bring its corner back to (0,0).
        var left = Float.greatestFiniteMagnitude
        var top = Float.greatestFiniteMagnitude
        let w = Float(srcWidth), h = Float(srcHeight)
        for (x, y) in [(Float(0), Float(0)), (w, 0), (0, h), (w, h)] {
            left = min(left, turn.mapX(x, y))
            top = min(top, turn.mapY(x, y))
        }
        var m = turn.then(Affine.translate(-left, -top))

        // Mirrored after the rotation, matching how the preview flips the front camera.
        if mirror {
            m = m.then(Affine.scaleAbout(-1, 1, uprightWidth(srcWidth: srcWidth, srcHeight: srcHeight, rotationDegrees: rotation) / 2, 0))
        }
        return m
    }

    /// Width of the frame `upright` produces. At a quarter turn the axes swap.
    public static func uprightWidth(srcWidth: Int, srcHeight: Int, rotationDegrees: Int) -> Float {
        normalised(rotationDegrees) % 180 != 0 ? Float(srcHeight) : Float(srcWidth)
    }

    /// Height of the frame `upright` produces.
    public static func uprightHeight(srcWidth: Int, srcHeight: Int, rotationDegrees: Int) -> Float {
        normalised(rotationDegrees) % 180 != 0 ? Float(srcWidth) : Float(srcHeight)
    }

    /// The part of the upright source frame that actually survives into the buffer.
    ///
    /// Fill-centre keeps the picture's proportions by overflowing the buffer on one axis and
    /// cutting off whatever hangs over the edge. That is right for the skeleton, which has to land
    /// on the body wherever the body happens to be, but it is not a safe place to put text. The
    /// analysis frame is 3:4 and the recording is 9:16, so filling the height overflows the width
    /// by a third and 12.5% of the frame is cropped from each side — while the HUD was laid out
    /// 1.8% in from the frame's own edges, which put the clock, the round, the movement, the rep
    /// count and the watermark all inside the strip that is cut.
    ///
    /// Anything that has to be readable in the finished file belongs inside this rect.
    ///
    /// Mirroring is not a parameter because it cannot change the answer: the visible region is
    /// centred, so a horizontal flip about the centre maps it onto itself.
    public static func visibleSource(
        srcWidth: Int, srcHeight: Int, bufferWidth: Int, bufferHeight: Int, rotationDegrees: Int
    ) -> SourceRect {
        let full = SourceRect(left: 0, top: 0, right: Float(max(srcWidth, 0)), bottom: Float(max(srcHeight, 0)))
        if srcWidth <= 0 || srcHeight <= 0 || bufferWidth <= 0 || bufferHeight <= 0 { return full }

        let rotation = normalised(rotationDegrees)
        let quarterTurned = rotation % 180 != 0
        let displayW = quarterTurned ? Float(bufferHeight) : Float(bufferWidth)
        let displayH = quarterTurned ? Float(bufferWidth) : Float(bufferHeight)

        // The same scale build() uses, read backwards: how much of the source the buffer covers.
        let scale = max(displayW / Float(srcWidth), displayH / Float(srcHeight))
        let visibleW = min(Float(srcWidth), displayW / scale)
        let visibleH = min(Float(srcHeight), displayH / scale)
        return SourceRect(
            left: (Float(srcWidth) - visibleW) / 2,
            top: (Float(srcHeight) - visibleH) / 2,
            right: (Float(srcWidth) + visibleW) / 2,
            bottom: (Float(srcHeight) + visibleH) / 2)
    }
}
