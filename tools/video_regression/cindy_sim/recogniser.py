"""Port of app/src/main/java/com/cindy/tracker/Recogniser.kt.

Works out the athlete's position on every analysed frame (on the bar, on the floor, standing, or
none) and, from the reps counted in it, the movement. The rules are the Kotlin's, line for line, and `recognition_parity_check.py` holds the two to
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
from .workout_engine import STANDARD_PROFILE, CindyProfile, Exercise, RepEvent, WorkoutEngine


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


class Movement(Enum):
    """What the athlete is doing, as recognition names it. Each movement starts from one position."""

    PULL_UPS = ("pull_ups", Exercise.PULLUP, Position.ON_THE_BAR)
    PUSH_UPS = ("push_ups", Exercise.PUSHUP, Position.ON_THE_FLOOR)
    SQUATS = ("squats", Exercise.SQUAT, Position.STANDING)

    @property
    def id(self) -> str:
        return self.value[0]

    @property
    def exercise(self) -> Exercise:
        return self.value[1]

    @property
    def position(self) -> Position:
        return self.value[2]

    @property
    def label(self) -> str:
        return self.exercise.label

    @staticmethod
    def at(position: Position) -> "Movement | None":
        """The movement that starts from the position, or none for no position."""
        for movement in Movement:
            if movement.position is position:
                return movement
        return None


#: The rep at which a movement is confirmed. One could be a stray gesture.
CONFIRMING_REPS = 2


@dataclass(frozen=True)
class Recognition:
    """What recognition makes of the frames so far.

    ``movement`` is the movement recognised, or none; it stays until a different one is confirmed.
    ``candidate`` and ``candidate_reps`` are a movement in its position that has counted some reps
    but not yet CONFIRMING_REPS: nothing there is recognised. ``tally`` is the reps recognition has
    seen per movement, confirming reps included; a candidate's reps are not in it until confirmed.
    """

    position: Position
    movement: Movement | None = None
    candidate: Movement | None = None
    candidate_reps: int = 0
    tally: tuple[int, int, int] = (0, 0, 0)

    def tally_of(self, movement: Movement) -> int:
        return self.tally[list(Movement).index(movement)]


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
#: How far above the shoulders the hands must be, in torsos, to enter the bar. Measured on the
#: owner's gym films and the Cindy clip: hands behind the head in a squat never went past about
#: 0.35 of a torso, a hang reached 0.8 to 1.2, and 0.4 to 0.6 scored the same.
HANDS_OVERHEAD_TORSOS = 0.5

_LEGS = (
    (KP.LEFT_HIP, KP.LEFT_KNEE, KP.LEFT_ANKLE),
    (KP.RIGHT_HIP, KP.RIGHT_KNEE, KP.RIGHT_ANKLE),
)


@dataclass(frozen=True)
class _Frame:
    hands_overhead: bool
    hands_above_shoulders: bool
    shins_under_knees: bool
    upright: bool
    torso_seen: bool

    @property
    def points_to(self) -> Position:
        """The position this frame alone points at, or none."""
        if self.hands_overhead:
            return Position.ON_THE_BAR
        if self.upright and self.shins_under_knees:
            return Position.STANDING
        if self.torso_seen:
            return Position.ON_THE_FLOOR
        return Position.NONE


_NO_EVIDENCE = _Frame(False, False, False, False, False)


def _hands_above_shoulders(k: Sequence[Keypoint]) -> bool:
    hands = geometry.midpoint(k, KP.LEFT_WRIST, KP.RIGHT_WRIST)
    if hands is None:
        return False
    shoulders = geometry.midpoint(k, KP.LEFT_SHOULDER, KP.RIGHT_SHOULDER)
    if shoulders is None:
        return False
    return hands.y < shoulders.y


def _hands_overhead(k: Sequence[Keypoint], torso: float | None) -> bool:
    """The hands are above the shoulders by HANDS_OVERHEAD_TORSOS, as they are on a bar and are
    not behind the head. Without a torso to measure by, the hands are not overhead."""
    if torso is None or torso < MIN_TORSO_PX:
        return False
    hands = geometry.midpoint(k, KP.LEFT_WRIST, KP.RIGHT_WRIST)
    if hands is None:
        return False
    shoulders = geometry.midpoint(k, KP.LEFT_SHOULDER, KP.RIGHT_SHOULDER)
    if shoulders is None:
        return False
    return f32(shoulders.y - hands.y) >= f32(HANDS_OVERHEAD_TORSOS * torso)


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
        hands_overhead=_hands_overhead(k, torso),
        hands_above_shoulders=_hands_above_shoulders(k),
        shins_under_knees=_shins_under_knees(k),
        upright=geometry.upright(k),
        torso_seen=(torso if torso is not None else 0.0) >= MIN_TORSO_PX,
    )


class Recogniser:
    """Mirror of Recogniser.kt. One fixed-movement engine per movement, built from the profile;
    only the engine of the position that is entered is fed a frame."""

    def __init__(self, profile: CindyProfile = STANDARD_PROFILE) -> None:
        self._profile = profile
        self.reset()

    def reset(self) -> None:
        self._engines = {
            m: WorkoutEngine(fixed_exercise=m.exercise, profile=self._profile) for m in Movement
        }
        self._movement: Movement | None = None
        self._candidate: Movement | None = None
        self._candidate_reps = 0
        self._tally = {m: 0 for m in Movement}
        self._position = Position.NONE
        #: The position the frames are currently pointing at, and since when, for the entry dwell.
        self._pointing_at = Position.NONE
        self._pointing_since = 0
        #: The last time the kept position's own rule held, for the gap it may be kept through.
        self._last_held = 0

    def on_frame(self, k: Sequence[Keypoint], now: int, identity_stable: bool = True) -> Recognition:
        before = self._position
        frame = _read(k) if identity_stable else _NO_EVIDENCE
        self._keep(frame, now)
        self._point(frame.points_to, now)
        self._enter(now)
        if self._position is not before:
            self._arrive()
        self._count(k, now, identity_stable)
        return Recognition(
            self._position, self._movement, self._candidate, self._candidate_reps,
            tuple(self._tally[m] for m in Movement),
        )

    def _arrive(self) -> None:
        """The position has changed: the visit counting candidate reps is over, and the engine of
        the position now entered must not book the climb that brought the athlete here."""
        self._candidate = None
        self._candidate_reps = 0
        movement = Movement.at(self._position)
        if movement is not None:
            self._engines[movement].drop_climb_on_arrival()

    def _count(self, k: Sequence[Keypoint], now: int, identity_stable: bool) -> None:
        """Feeds this frame to the one engine whose position is entered, and books its rep."""
        counting = Movement.at(self._position)
        if counting is None:
            return
        if self._engines[counting].on_frame(k, now, identity_stable) is not RepEvent.REP:
            return
        if counting is self._movement:
            self._tally[counting] += 1
            return
        self._candidate = counting
        self._candidate_reps += 1
        if self._candidate_reps < CONFIRMING_REPS:
            return
        # The confirming reps are the movement's first reps, not reps spent on finding it.
        self._movement = counting
        self._tally[counting] += self._candidate_reps
        self._candidate = None
        self._candidate_reps = 0

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
