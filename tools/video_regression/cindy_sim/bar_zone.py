"""Line-by-line port of app/src/main/java/com/cindy/tracker/BarZone.kt."""
from __future__ import annotations

import math

from .keypoints import Keypoint
from .rep_counter import NAN, f32


class BarZone:
    """Where the pull-up bar is, learned from the athlete hanging on it.

    Elbow flexion alone cannot tell a pull-up from someone standing on the floor waving their
    arms about, and "wrists above the hips" is a weak substitute -- it is true of anyone reaching
    overhead. Knowing roughly where the hands sit when they are actually on the bar turns that
    into a real test.

    Tolerances are multiples of torso length, never pixels, so stepping toward or away from the
    camera does not move the gate.
    """

    #: How fast the estimate follows new observations.
    FOLLOW = 0.15
    #: Vertical slack around the bar, in torso lengths.
    Y_TOLERANCE = 0.75
    #: Horizontal slack beyond the observed grip, in torso lengths.
    X_PADDING = 0.6

    def __init__(self) -> None:
        self._y = NAN
        self._x_min = NAN
        self._x_max = NAN
        self._manual = False

    @property
    def established(self) -> bool:
        """True once a dead hang has been seen and the zone means something."""
        return not math.isnan(self._y)

    @property
    def line_y(self) -> float | None:
        """The centre line of the bar, in the same pixel space as the keypoints."""
        return None if math.isnan(self._y) else self._y

    def configure_manual(self, y: float, x_min: float, x_max: float) -> None:
        """Uses a fixed bar for a recorded regression clip, measured from that clip."""
        if not (math.isfinite(y) and math.isfinite(x_min) and math.isfinite(x_max) and x_min <= x_max):
            raise ValueError("Manual bar bounds must be finite and ordered")
        self._y = f32(y)
        self._x_min = f32(x_min)
        self._x_max = f32(x_max)
        self._manual = True

    def observe_hang(self, hands_x: float, hands_y: float, half_grip: float) -> None:
        """Records where the hands were during a confirmed dead hang."""
        if self._manual:
            return
        low = f32(hands_x - half_grip)
        high = f32(hands_x + half_grip)
        if not self.established:
            self._y = f32(hands_y)
            self._x_min = low
            self._x_max = high
            return
        self._y = f32(self._y + self.FOLLOW * (hands_y - self._y))
        self._x_min = f32(self._x_min + self.FOLLOW * (min(self._x_min, low) - self._x_min))
        self._x_max = f32(self._x_max + self.FOLLOW * (max(self._x_max, high) - self._x_max))

    def holds(self, left: Keypoint, right: Keypoint, torso: float) -> bool:
        """Whether *both* wrists, on a body of this scale, are plausibly on the bar.

        Each wrist is tested independently: a pull-up needs both grips, and testing the midpoint
        would let one hand leave the bar while the other kept a rep alive.
        """
        if not self.established or torso <= 0.0:
            return True  # nothing learned yet: do not block counting
        slack = f32(self.Y_TOLERANCE * torso)
        if abs(f32(left.y - self._y)) > slack or abs(f32(right.y - self._y)) > slack:
            return False
        # Scenario bars are explicit regions, so do not silently widen them. Learned bars still
        # need a torso-scaled allowance for a natural regrip along the bar.
        pad = 0.0 if self._manual else f32(self.X_PADDING * torso)
        low, high = f32(self._x_min - pad), f32(self._x_max + pad)
        return left.x >= low and left.x <= high and right.x >= low and right.x <= high

    def reset(self) -> None:
        """Forgets the bar -- the camera has moved, so its position in the frame is meaningless."""
        self._y = NAN
        self._x_min = NAN
        self._x_max = NAN
        self._manual = False
