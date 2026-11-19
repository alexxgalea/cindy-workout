"""Port of app/src/main/java/com/cindy/tracker/Recogniser.kt.

Works out the athlete's position on every analysed frame: on the bar, on the floor, standing, or
none. The rules are the Kotlin's, line for line, and `recognition_parity_check.py` holds the two to
one frame-by-frame trace. Every value the Kotlin keeps in a `Float` is rounded through `f32`, since
the shin test is an exact comparison and a 64-bit port once diverged from the phone by one frame.

Time is the frame clock in milliseconds, never a frame count.
"""
from __future__ import annotations

import math
from dataclasses import dataclass
from enum import Enum
from typing import Sequence

from . import pose_geometry as geometry
from .keypoints import KP, Keypoint
from .rep_counter import f32


class Position(Enum):
    """Where the athlete's body is. A position is not a movement."""

    NONE = ("none", "no position")
    ON_THE_BAR = ("on_the_bar", "on the bar")
    ON_THE_FLOOR = ("on_the_floor", "on the floor")
    STANDING = ("standing", "standing")

    @property
    def id(self) -> str:
        return self.value[0]

    @property
    def label(self) -> str:
        return self.value[1]


@dataclass(frozen=True)
class Recognition:
    """What recognition makes of the frames so far."""

    position: Position


#: How long the frames must keep pointing at a position before it is entered.
ENTRY_MS = 500
#: How long the bar or standing is kept without its own rule holding.
KEEP_MS = 1_000
#: How far under its knee a seen ankle must be, in thighs, for the shin to stand.
SHIN_UNDER_KNEE_THIGHS = 0.5
#: A thigh shorter than this cannot be measured against.
MIN_THIGH_PX = 1.0
#: A torso shorter than this is shoulders and hips on top of each other, not a torso.
MIN_TORSO_PX = 1.0

_LEGS = (
    (KP.LEFT_HIP, KP.LEFT_KNEE, KP.LEFT_ANKLE),
    (KP.RIGHT_HIP, KP.RIGHT_KNEE, KP.RIGHT_ANKLE),
)


@dataclass(frozen=True)
class _Frame:
    hands_above_shoulders: bool
    shins_under_knees: bool
    upright: bool
    torso_seen: bool

    @property
    def points_to(self) -> Position:
        """The position this frame alone points at, or none."""
        if self.hands_above_shoulders:
            return Position.ON_THE_BAR
        if self.upright and self.shins_under_knees:
            return Position.STANDING
        if self.torso_seen:
            return Position.ON_THE_FLOOR
        return Position.NONE


_NO_EVIDENCE = _Frame(False, False, False, False)


def _hands_above_shoulders(k: Sequence[Keypoint]) -> bool:
    hands = geometry.midpoint(k, KP.LEFT_WRIST, KP.RIGHT_WRIST)
    if hands is None:
        return False
    shoulders = geometry.midpoint(k, KP.LEFT_SHOULDER, KP.RIGHT_SHOULDER)
    if shoulders is None:
        return False
    return hands.y < shoulders.y


def _shins_under_knees(k: Sequence[Keypoint]) -> bool:
    """Every shin that is seen stands under its knee, and at least one is seen.

    Each side is judged on its own joints. A shin that is seen but cannot be measured (no hip on
    its side) refuses, because a missing joint is never permission.
    """
    seen = 0
    for hip, knee, ankle in _LEGS:
        if not geometry.ok(k[knee]) or not geometry.ok(k[ankle]):
            continue
        if not geometry.ok(k[hip]):
            return False
        thigh = f32(math.hypot(f32(k[hip].x - k[knee].x), f32(k[hip].y - k[knee].y)))
        if thigh < MIN_THIGH_PX:
            return False
        if f32(k[ankle].y - k[knee].y) < f32(SHIN_UNDER_KNEE_THIGHS * thigh):
            return False
        seen += 1
    return seen > 0


def _read(k: Sequence[Keypoint]) -> _Frame:
    torso = geometry.torso_length(k)
    return _Frame(
        hands_above_shoulders=_hands_above_shoulders(k),
        shins_under_knees=_shins_under_knees(k),
        upright=geometry.upright(k),
        torso_seen=(torso if torso is not None else 0.0) >= MIN_TORSO_PX,
    )


class Recogniser:
    def __init__(self) -> None:
        self.reset()

    def reset(self) -> None:
        self._position = Position.NONE
        #: The position the frames are currently pointing at, and since when, for the entry dwell.
        self._pointing_at = Position.NONE
        self._pointing_since = 0
        #: The last time the kept position's own rule held, for the gap it may be kept through.
        self._last_held = 0

    def on_frame(self, k: Sequence[Keypoint], now: int, identity_stable: bool = True) -> Recognition:
        frame = _read(k) if identity_stable else _NO_EVIDENCE
        self._keep(frame, now)
        self._point(frame.points_to, now)
        self._enter(now)
        return Recognition(self._position)

    def _keep(self, frame: _Frame, now: int) -> None:
        """Leaves the bar or standing once its own rule has not held for longer than KEEP_MS."""
        if self._position is Position.ON_THE_BAR:
            holds = frame.hands_above_shoulders
        elif self._position is Position.STANDING:
            holds = frame.shins_under_knees
        else:
            return
        if holds:
            self._last_held = now
        elif now - self._last_held > KEEP_MS:
            self._position = Position.NONE
            # Whatever the frames were pointing at while the position was kept has not been held
            # since it was lost.
            self._pointing_at = Position.NONE

    def _point(self, reading: Position, now: int) -> None:
        if reading is not self._pointing_at:
            self._pointing_at = reading
            self._pointing_since = now

    def _enter(self, now: int) -> None:
        if self._pointing_at is Position.NONE or self._pointing_at is self._position:
            return
        if now - self._pointing_since < ENTRY_MS:
            return
        if not self._can_replace(self._position, self._pointing_at):
            return
        self._position = self._pointing_at
        self._last_held = now

    @staticmethod
    def _can_replace(kept: Position, entering: Position) -> bool:
        """What may take the place of the position being kept; everything may replace none."""
        if entering is Position.ON_THE_BAR:
            return True
        if entering is Position.STANDING:
            return kept is not Position.ON_THE_BAR
        if entering is Position.ON_THE_FLOOR:
            return kept is Position.NONE
        return False
