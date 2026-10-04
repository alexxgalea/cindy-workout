import Foundation

/// The one piece of arithmetic behind the camera-screen tour: where its caption card sits.
///
/// Free of any view so that the placement can be tested at the awkward sizes, a target at the very
/// bottom of a short screen being the one that matters. The caption is full width, so only its
/// height is ever in question. Port of `SpotlightMath.kt`.
public enum SpotlightMath {

    /// The top edge for a caption `captionHeight` tall, pointing at a target from `targetTop` to
    /// `targetBottom` on a screen `screenHeight` tall.
    ///
    /// Below the target when there is room for the whole card under it, because that is where the
    /// eye goes next. Above when there is not. Never off the screen: where neither side has room,
    /// the card is kept inside the screen and covers the target rather than vanishing, since a
    /// caption that cannot be read is worse than one that hides what it is about.
    public static func captionTop(targetTop: Float, targetBottom: Float, captionHeight: Float,
                                  screenHeight: Float, gap: Float, margin: Float) -> Float {
        let lowest = screenHeight - margin - captionHeight
        let below = targetBottom + gap
        if below <= lowest { return below }
        let above = targetTop - gap - captionHeight
        if above >= margin { return above }
        return max(lowest, margin)
    }
}
