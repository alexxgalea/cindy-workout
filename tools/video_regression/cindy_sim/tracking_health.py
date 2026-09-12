"""Line-by-line port of TrackingHealth.kt from app/src/main/java/com/cindy/tracker/.

Kept in step with the Kotlin for the same reason the engine port is: a harness that has quietly
stopped agreeing with the phone gives confident, wrong verdicts. The thresholds here are the ones
measured by darkening real clips until they stopped counting -- see the Kotlin for the argument.
"""
from __future__ import annotations

import math
from collections import deque
from enum import Enum

from .workout_engine import Exercise


class TrackingHealth(Enum):
    #: The movement's joints are as legible as they have been all session.
    GOOD = "GOOD"
    #: Legibility is falling. Measured on darkened footage, the count is still right here.
    WEAK = "WEAK"
    #: Legibility has collapsed far enough that reps are being missed.
    LOST = "LOST"


class Tune:
    #: How much recent history a reading is taken over.
    WINDOW_MS = 4_000
    #: Samples the window needs before it describes anything.
    MIN_SAMPLES = 20
    #: Share of the session's own best legibility below which the camera is falling behind.
    FADING = 0.70
    #: And below which reps are being missed.
    LOSING = 0.50
    #: Recovery has to beat the warning threshold, so a reading sitting on it cannot flap.
    RECOVERED = 0.80
    #: How long a reading must hold before the athlete is told anything.
    DWELL_MS = 3_000
    #: Brightness gain past which the picture really was dark, rather than merely unreadable.
    DARK_GAIN = 2.0


class TrackingHealthMonitor:
    """Watches whether the camera can still read the athlete, and says so before the score goes
    wrong. See the Kotlin original for why the reading is relative to the session's own baseline
    and kept per movement."""

    def __init__(self) -> None:
        self._seen: deque[int] = deque()
        self._read: deque[int] = deque()
        self._baseline: dict[Exercise, float] = {}
        self._candidate = TrackingHealth.GOOD
        self._candidate_since = 0
        self._last_now = 0
        self._window_since = 0
        self._last_exercise: Exercise | None = None
        self.health = TrackingHealth.GOOD
        self.advice: str | None = None
        self.lost_ms = 0
        self.weak_ms = 0

    def update(
        self,
        exercise: Exercise,
        legible: bool,
        soft_gain: float,
        now: int,
    ) -> TrackingHealth:
        self._accrue(now)
        self._last_now = now

        # A window spanning a movement change describes neither of them.
        if exercise is not self._last_exercise:
            self._last_exercise = exercise
            self._seen.clear()
            self._read.clear()
            self._window_since = 0
            self._candidate_since = now

        if self._window_since == 0:
            self._window_since = now
        self._seen.append(now)
        if legible:
            self._read.append(now)
        cutoff = now - Tune.WINDOW_MS
        while self._seen and self._seen[0] < cutoff:
            self._seen.popleft()
        while self._read and self._read[0] < cutoff:
            self._read.popleft()

        if len(self._seen) < Tune.MIN_SAMPLES or now - self._window_since < Tune.WINDOW_MS:
            return self.health

        fraction = len(self._read) / len(self._seen)
        best = self._baseline.get(exercise, math.nan)
        if math.isnan(best) or fraction > best:
            self._baseline[exercise] = fraction

        reference = self._baseline[exercise]
        # A baseline of zero is the absence of one, not a lenient one: the camera has never read
        # this movement at all, which is a failure and not a clean slate.
        ratio = 0.0 if reference <= 0.0 else fraction / reference
        if ratio < Tune.LOSING:
            reading = TrackingHealth.LOST
        elif ratio < Tune.FADING:
            reading = TrackingHealth.WEAK
        elif ratio >= Tune.RECOVERED:
            reading = TrackingHealth.GOOD
        else:
            reading = self.health
        self._settle(reading, soft_gain, now)
        return self.health

    def _settle(self, reading: TrackingHealth, soft_gain: float, now: int) -> None:
        if reading is not self._candidate:
            self._candidate = reading
            self._candidate_since = now
            return
        if reading is self.health:
            return
        # Recovering is allowed to be instant.
        if reading is not TrackingHealth.GOOD and now - self._candidate_since < Tune.DWELL_MS:
            return
        self.health = reading
        if reading is TrackingHealth.GOOD:
            self.advice = None
        elif reading is TrackingHealth.WEAK:
            self.advice = "Losing you — more light helps"
        elif soft_gain >= Tune.DARK_GAIN:
            self.advice = "Too dark to count — tap +1"
        else:
            self.advice = "Can't see you — tap +1"

    def _accrue(self, now: int) -> None:
        if self._last_now == 0 or now <= self._last_now:
            return
        elapsed = now - self._last_now
        if self.health is TrackingHealth.LOST:
            self.lost_ms += elapsed
        elif self.health is TrackingHealth.WEAK:
            self.weak_ms += elapsed

    def reframe(self) -> None:
        """Forgets the learned baselines without clearing what the session has already suffered."""
        self._baseline.clear()
        self._seen.clear()
        self._read.clear()
        self._window_since = 0
        self._last_exercise = None
        self._candidate = self.health
        self._candidate_since = 0

    def reset(self) -> None:
        self._seen.clear()
        self._read.clear()
        self._baseline.clear()
        self.health = TrackingHealth.GOOD
        self.advice = None
        self._candidate = TrackingHealth.GOOD
        self._candidate_since = 0
        self._last_now = 0
        self._window_since = 0
        self._last_exercise = None
        self.lost_ms = 0
        self.weak_ms = 0
