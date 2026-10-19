import Foundation

/// Where the burned-in recording puts its words, worked out apart from any drawing so that the one
/// rule that matters can be checked anywhere: **text is laid out inside the safe area, never the
/// frame.**
///
/// The skeleton wants the frame, because it has to sit on the body wherever the body is. Text does
/// not. Anchored to the frame's own edges, the clock, the round, the movement, the rep count and the
/// watermark all landed in the strip that fill-centre cuts off, and the file had none of them.
/// `OverlayTransform.visibleSource` is the part the file keeps, and everything here is measured
/// against it.
///
/// Port of `RecordingOverlay.drawHud`, `drawBanner` and `drawWatermark`. The widths of words are the
/// drawing's to say (`measure`), because a font is not something a Linux test has.
public struct RecordingLayout: Equatable, Sendable {

    public enum Align: Equatable, Sendable { case left, right, center }

    /// The two colours text is drawn in. Plain white is the clock and the count; `accent` is the
    /// secondary line; `faint` is the watermark's second line.
    public enum Tone: Equatable, Sendable { case white, accent, faint }

    /// A rounded box behind some text.
    public struct Panel: Equatable, Sendable {
        public let rect: SourceRect
        /// Of the panel's height: 0.28, as on Android.
        public let radius: Float
    }

    /// One piece of text: its baseline and the edge `align` refers to, in the frame's own coordinates.
    public struct Text: Equatable, Sendable {
        public let text: String
        public let x: Float
        public let baseline: Float
        public let size: Float
        public let align: Align
        public let tone: Tone
    }

    public let panels: [Panel]
    public let texts: [Text]

    /// Bone stroke width, as a fraction of frame height.
    ///
    /// Matches the live overlay's own weight: it draws 7 px bones and 9 px joint radii in view
    /// pixels, which on its roughly 2.25x preview scale is about 3.1 and 4 analysis-frame pixels. The
    /// film used to draw about twice that, and read as heavier and less faithful to the body than the
    /// one the athlete watched while training.
    public static let boneWidthFraction: Float = 0.0045

    /// Joint radius, as a fraction of frame height.
    public static let jointRadiusFraction: Float = 0.0055

    /// A joint or bone below this score is not drawn.
    public static let minScore: Float = 0.30

    /// The corner of a panel, as a fraction of its height.
    public static let cornerFraction: Float = 0.28

    /// Measures `text` at `size`, in the frame's units, in the bold face the film is drawn in.
    public typealias Measure = (String, Float) -> Float

    /// Everything the film says over the picture for one frame: the clock top left, the round top
    /// right, the movement and count bottom left, the banner in the middle while there is one, and
    /// the watermark bottom right.
    public static func make(hud: RecordedHudText, safe: SourceRect, measure: Measure) -> RecordingLayout {
        var panels: [Panel] = []
        var texts: [Text] = []
        let pad = safe.height * 0.018
        let big = safe.height * 0.045
        let small = safe.height * 0.025

        func panel(_ l: Float, _ t: Float, _ r: Float, _ b: Float) {
            panels.append(Panel(rect: SourceRect(left: l, top: t, right: r, bottom: b), radius: cornerFraction))
        }

        // top-left: the clock
        let clockWidth = measure(hud.clock, big)
        panel(safe.left + pad, safe.top + pad, safe.left + pad * 2 + clockWidth, safe.top + pad + big * 1.5)
        texts.append(Text(text: hud.clock, x: safe.left + pad * 1.5, baseline: safe.top + pad + big * 1.1,
                          size: big, align: .left, tone: .white))

        // top-right: the round
        let roundWidth = measure(hud.round, small)
        panel(safe.right - pad * 2 - roundWidth, safe.top + pad, safe.right - pad, safe.top + pad + small * 2)
        texts.append(Text(text: hud.round, x: safe.right - pad * 1.5, baseline: safe.top + pad + small * 1.4,
                          size: small, align: .right, tone: .accent))

        // bottom-left: movement and rep count
        let blockWidth = max(measure(hud.count, big), measure(hud.label, small))
        let blockTop = safe.bottom - pad - big * 1.6 - small * 1.4
        panel(safe.left + pad, blockTop, safe.left + pad * 2 + blockWidth, safe.bottom - pad)
        texts.append(Text(text: hud.label, x: safe.left + pad * 1.5, baseline: blockTop + small * 1.2,
                          size: small, align: .left, tone: .accent))
        texts.append(Text(text: hud.count, x: safe.left + pad * 1.5,
                          baseline: blockTop + small * 1.4 + big * 1.1, size: big, align: .left, tone: .white))

        // The few seconds of banner after the setup check ends, centred in the safe area like every
        // other piece of text here.
        if let banner = hud.banner {
            let size = safe.height * 0.034
            let half = measure(banner, size) / 2
            let cx = safe.left + safe.width / 2
            let cy = safe.top + safe.height / 2
            panel(cx - half - pad * 2, cy - size * 0.9, cx + half + pad * 2, cy + size * 0.6)
            texts.append(Text(text: banner, x: cx, baseline: cy + size * 0.32, size: size, align: .center, tone: .white))
        }

        // bottom-right: the watermark
        let markSize = safe.height * 0.030
        let subSize = safe.height * 0.016
        let right = safe.right - pad
        texts.append(Text(text: "CINDY", x: right, baseline: safe.bottom - pad - subSize * 1.4,
                          size: markSize, align: .right, tone: .accent))
        texts.append(Text(text: "cindy tracker", x: right, baseline: safe.bottom - pad,
                          size: subSize, align: .right, tone: .faint))

        return RecordingLayout(panels: panels, texts: texts)
    }
}
