"""Port of FreestyleEngine.kt and FreestyleSets.kt (ADR 0010, spec #188).

A Freestyle is counted by recognition: recognition names the movement and counts its reps, and this
banks what recognition counts. A movement is confirmed at its 2nd counted rep with both banked; a
lone rep is never banked and shows nothing (a set of one rep is not counted, ADR 0010). Sets are derived from the rep marks at STOP. Cindy's counting is
not touched: the recogniser drives its own engines. `freestyle_parity_check.py` holds this to the
Kotlin on one trace.

Time is the frame clock in milliseconds. The minus and plus taps are not ported: a film has no
fingers, and the parity trace never presses them.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from typing import Sequence

from .keypoints import Keypoint
from .recogniser import Movement, Recogniser
from .workout_engine import STANDARD_PROFILE, CindyProfile, Exercise

#: The movement's line before recognition has confirmed one.
FREESTYLE_IDLE_LINE = "Freestyle · Count up"

#: PROVISIONAL: a later ticket (#198) measures it on the owner's films (about 10-15 s). One constant
#: here and one in FreestyleSets.kt; change both together.
REST_THRESHOLD_MS = 12_000


@dataclass(frozen=True)
class RepMark:
    clock_ms: int
    movement: Exercise
    manual: bool = False


@dataclass(frozen=True)
class FreestyleSet:
    movement: Exercise
    reps: int
    start_ms: int
    end_ms: int

    @property
    def length_ms(self) -> int:
        return self.end_ms - self.start_ms


class GapKind(Enum):
    REST = "rest"
    TRANSITION = "transition"


@dataclass(frozen=True)
class FreestyleGap:
    kind: GapKind
    start_ms: int
    end_ms: int


def derive_sets(marks: Sequence[RepMark]) -> tuple[list[FreestyleSet], list[FreestyleGap]]:
    """A set ends where the movement changes (a Transition) or where the gap since the previous rep
    inside one movement is longer than REST_THRESHOLD_MS (a Rest)."""
    sets: list[FreestyleSet] = []
    movement: Exercise | None = None
    reps = 0
    start = end = 0

    def close() -> None:
        if movement is not None:
            sets.append(FreestyleSet(movement, reps, start, end))

    for mark in sorted(marks, key=lambda m: m.clock_ms):
        if movement is not None and mark.movement is movement and mark.clock_ms - end <= REST_THRESHOLD_MS:
            reps += 1
            end = mark.clock_ms
            continue
        close()
        movement, reps, start, end = mark.movement, 1, mark.clock_ms, mark.clock_ms
    close()
    gaps = [
        FreestyleGap(GapKind.REST if a.movement is b.movement else GapKind.TRANSITION, a.end_ms, b.start_ms)
        for a, b in zip(sets, sets[1:])
    ]
    return sets, gaps


@dataclass(frozen=True)
class FiledSession:
    duration_ms: int
    paused_ms: int
    totals: dict[Exercise, int]
    manual_reps: int
    marks: list[RepMark]
    sets: list[FreestyleSet]
    gaps: list[FreestyleGap]

    @property
    def total_reps(self) -> int:
        return sum(self.totals.values())


@dataclass(frozen=True)
class FreestyleFrame:
    figure: int
    movement: Movement | None
    movement_total: int
    line: str
    adjustable: bool
    #: (movement, reps) banked by this frame, in movement order.
    banked: tuple[tuple[Movement, int], ...] = ()
    #: ("confirmed" | "count", movement or None, count), in order.
    voice: tuple[tuple[str, Movement | None, int], ...] = ()


class FreestyleEngine:
    def __init__(self, profile: CindyProfile = STANDARD_PROFILE) -> None:
        self._profile = profile
        self._recogniser = Recogniser(profile)
        self._started = False
        self._started_at = 0
        self._paused_ms = 0
        self._paused_at: int | None = None
        self._reset_counts()

    def _reset_counts(self) -> None:
        self._seen = (0, 0, 0)
        self._shown: Movement | None = None
        self._figure = 0
        self._banked = {m: 0 for m in Movement}
        self._marks: list[RepMark] = []

    def start(self, now: int) -> None:
        self._recogniser = Recogniser(self._profile)
        self._started = True
        self._started_at = now
        self._paused_ms = 0
        self._paused_at = None
        self._reset_counts()

    def pause(self, now: int) -> None:
        if self._started and self._paused_at is None:
            self._paused_at = now

    def resume(self, now: int) -> None:
        if self._paused_at is None:
            return
        self._paused_ms += now - self._paused_at
        self._paused_at = None

    def total_reps(self) -> int:
        return sum(self._banked.values())

    def on_frame(self, k: Sequence[Keypoint], now: int, identity_stable: bool = True) -> FreestyleFrame:
        if not self._counting():
            return self._frame()
        recognition = self._recogniser.on_frame(k, now, identity_stable)
        banked: list[tuple[Movement, int]] = []
        voice: list[tuple[str, Movement | None, int]] = []
        for index, movement in enumerate(Movement):
            delta = recognition.tally[index] - self._seen[index]
            if delta <= 0:
                continue
            confirmed = recognition.movement is not self._shown
            if confirmed:
                self._shown = recognition.movement
                self._figure = 0
            self._bank(movement, delta, now)
            banked.append((movement, delta))
            voice.append(("confirmed", movement, self._figure) if confirmed else ("count", None, self._figure))
        self._seen = recognition.tally
        return self._frame(tuple(banked), tuple(voice))

    def stop(self, now: int) -> FiledSession | None:
        if not self._started:
            return None
        self.resume(now)
        self._started = False
        if self.total_reps() == 0:
            return None
        sets, gaps = derive_sets(self._marks)
        return FiledSession(
            duration_ms=max(0, now - self._started_at - self._paused_ms),
            paused_ms=self._paused_ms,
            totals={m.exercise: self._banked[m] for m in Movement if self._banked[m] > 0},
            manual_reps=0,
            marks=list(self._marks),
            sets=sets,
            gaps=gaps,
        )

    def _counting(self) -> bool:
        return self._started and self._paused_at is None

    def _clock_at(self, now: int) -> int:
        return max(0, now - self._started_at - self._paused_ms)

    def _bank(self, movement: Movement, reps: int, now: int) -> None:
        self._banked[movement] += reps
        self._figure += reps
        self._marks.extend(RepMark(self._clock_at(now), movement.exercise, False) for _ in range(reps))

    def _frame(self, banked=(), voice=()) -> FreestyleFrame:
        movement = self._shown
        total = self._banked[movement] if movement is not None else 0
        line = FREESTYLE_IDLE_LINE if movement is None else f"{movement.label} · {total} total"
        return FreestyleFrame(self._figure, movement, total, line,
                              movement is not None and self._counting(), banked, voice)
