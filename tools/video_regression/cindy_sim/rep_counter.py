"""Line-by-line port of app/src/main/java/com/cindy/tracker/RepCounter.kt.

The Kotlin stores its state in 32-bit `Float`s, and the decay in `observe` accumulates every
frame, so a 64-bit port drifts away from the device over a long clip. Every value the Kotlin
holds in a `Float` field is therefore rounded through `f32` here, which keeps the two
implementations bit-comparable rather than merely close.
"""
from __future__ import annotations

import math
from enum import Enum

import numpy as np

NAN = math.nan


def f32(value: float) -> float:
    """Rounds to the nearest IEEE-754 single, the width Kotlin's `Float` fields carry."""
    return float(np.float32(value))


class Phase(Enum):
    UNKNOWN = "UNKNOWN"
    DOWN = "DOWN"
    UP = "UP"


class RepCounter:
    """Counts oscillations of a scalar signal by measuring how far it climbs off its trough.

    Callers must orient the signal so the *bottom* of the movement is the low value. A rep is
    booked at the top: lockout of a push-up, standing out of a squat, chin over the bar.

    Thresholds are learned from the range the athlete actually produces rather than fixed, so a
    phone on the floor -- which foreshortens everything above it and squashes the projected
    swing -- does not silently undercount. See the Kotlin for the full rationale.
    """

    NO_REP = -(2 ** 63)
    #: Share of the observed travel held back as dead zone at each end.
    MARGIN = 0.30
    #: How fast a stale extreme is forgotten, in signal units per frame.
    DECAY = 0.05

    def __init__(
        self,
        down_below: float,
        up_above: float,
        min_rep_ms: int = 350,
        smoothing: float = 0.4,
        min_range: float = 0.0,
    ) -> None:
        self.down_below = f32(down_below)
        self.up_above = f32(up_above)
        self.min_rep_ms = min_rep_ms
        self.smoothing = f32(smoothing)
        self.min_range = f32(min_range)

        self.phase = Phase.UNKNOWN
        self.count = 0
        self.smoothed = NAN

        self._seen_low = NAN
        self._seen_high = NAN
        #: Lowest value since the last booked rep -- the foot of the climb being measured.
        self._trough = NAN
        self._last_rep_at = self.NO_REP
        #: Cleared on each rep, set again only once the signal has genuinely come back down.
        #: Starts true so the first rep of a session, taken before any range is known, counts.
        self._armed = True

    # -- observations -----------------------------------------------------

    @property
    def learned_range(self) -> float:
        """Travel observed so far. Zero until samples arrive."""
        if math.isnan(self._seen_low) or math.isnan(self._seen_high):
            return 0.0
        return f32(self._seen_high - self._seen_low)

    @property
    def required_range(self) -> float:
        """Travel the calibration step should see before it trusts the camera placement."""
        return self.min_range

    @property
    def calibrated(self) -> bool:
        """True once the band is wide enough to set the thresholds itself."""
        return self.min_range > 0.0 and self.learned_range >= self.min_range

    def seed_band(self, low: float, high: float) -> None:
        """Seeds the band from a calibration rep, so rep one is judged against a real range."""
        if math.isnan(low) or math.isnan(high) or high <= low:
            return
        self._seen_low = f32(low)
        self._seen_high = f32(high)

    def update(self, raw: float, now: int, may_count: bool = True) -> bool:
        """Feeds one sample.

        `may_count` separates *observing* the signal from *booking* a rep. The band can only
        describe the athlete's real swing if the counter sees the whole oscillation, but a caller
        with its own gates -- the pull-up bar and head checks -- still needs to withhold the
        score on frames those gates reject. Passing False keeps the smoothing, band and phase
        current while guaranteeing no rep is booked.

        :return: True if this sample completed a rep.
        """
        if math.isnan(raw):
            return False
        self.smoothed = (
            f32(raw)
            if math.isnan(self.smoothed)
            else f32(self.smoothed + self.smoothing * (raw - self.smoothed))
        )
        s = self.smoothed

        self._observe(s)
        self._trough = s if math.isnan(self._trough) else min(self._trough, s)

        span = self.learned_range
        use_band = self.calibrated

        # How far the signal must climb off its trough, and how close to the top it must finish.
        needed = f32((1.0 - 2.0 * self.MARGIN) * span) if use_band else f32(self.up_above - self.down_below)
        top_of_band = f32(self._seen_high - self.MARGIN * span) if use_band else self.up_above
        bottom_of_band = f32(self._seen_low + self.MARGIN * span) if use_band else self.down_below

        if s <= bottom_of_band:
            self.phase = Phase.DOWN
            self._armed = True
        elif s >= top_of_band:
            self.phase = Phase.UP

        climbed = f32(s - self._trough)
        at_top = s >= top_of_band if use_band else s > self.up_above
        if (
            may_count
            and self._armed
            and climbed >= needed
            and at_top
            and (self._last_rep_at == self.NO_REP or now - self._last_rep_at >= self.min_rep_ms)
        ):
            self._last_rep_at = now
            self.count += 1
            self._armed = False
            # Restart the measurement from here so the descent establishes the next trough.
            self._trough = s
            return True
        return False

    def _observe(self, s: float) -> None:
        self._seen_low = s if math.isnan(self._seen_low) else min(self._seen_low, s)
        self._seen_high = s if math.isnan(self._seen_high) else max(self._seen_high, s)
        # Let stale extremes fade, but never shrink the band below the range worth trusting.
        if self._seen_high - self._seen_low > max(self.min_range, 1.0):
            self._seen_low = f32(self._seen_low + self.DECAY)
            self._seen_high = f32(self._seen_high - self.DECAY)

    # -- manual overrides -------------------------------------------------

    def force_increment(self) -> None:
        """Books a rep without a signal crossing -- used by the manual "+1" override."""
        self.count += 1
        self.phase = Phase.UNKNOWN
        self._armed = False
        self._trough = self.smoothed

    def force_decrement(self) -> None:
        """Takes a rep back off the score -- the "-1" override for a miscount."""
        if self.count == 0:
            return
        self.count -= 1
        self.phase = Phase.UNKNOWN
        self._armed = True
        self._trough = NAN

    def set_count(self, n: int) -> None:
        """Overwrites the score, for stepping back across a movement boundary."""
        self.count = max(n, 0)
        self.phase = Phase.UNKNOWN
        self._armed = True
        self._trough = NAN

    # -- resets -----------------------------------------------------------

    def reset_band(self) -> None:
        """Forgets the learned band without touching the score."""
        self._seen_low = NAN
        self._seen_high = NAN
        self._trough = NAN
        self.smoothed = NAN
        self.phase = Phase.UNKNOWN
        self._armed = True

    def require_fresh_down(self) -> None:
        """Discards an in-flight repetition while retaining the learned calibration band.

        Used when a pull-up loses bar contact or pose identity. The next valid low sample
        restores the DOWN phase and arms the counter; a recovered top frame cannot finish the
        old cycle.
        """
        self.phase = Phase.UNKNOWN
        self._trough = NAN
        self._armed = False

    def reset(self) -> None:
        self.phase = Phase.UNKNOWN
        self.count = 0
        self.smoothed = NAN
        self._last_rep_at = self.NO_REP
        self._trough = NAN
        self._armed = True
        self._seen_low = NAN
        self._seen_high = NAN

    def reset_count(self) -> None:
        """Drops the counted reps for the next movement but keeps the learned band."""
        self.count = 0
        self.phase = Phase.UNKNOWN
        self.smoothed = NAN
        self._trough = NAN
        self._armed = True
