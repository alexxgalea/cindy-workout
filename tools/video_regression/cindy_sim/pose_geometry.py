"""Pure pose-geometry helpers, mirroring app/src/main/java/com/cindy/tracker/PoseGeometry.kt.

Moved out of workout_engine.py so `AthleteLock` can judge start positions with the same
geometry instead of a second copy that could drift.

Kotlin stores this arithmetic in 32-bit `Float`s and compares against thresholds exactly, so
every value the Kotlin stores in a `Float` is rounded through `f32` here, in the same place it
was rounded before the move. See workout_engine.py for the fuller note.
"""
from __future__ import annotations

import math
from typing import Sequence

from .keypoints import KP, Keypoint
from .rep_counter import NAN, f32

MIN_SCORE = 0.30
#: How far the shoulders must sit above the hips, in torso lengths, to call the athlete
#: upright. A plank and a standing body both have straight legs, so the knee angle cannot
#: tell them apart -- only the direction the torso is pointing can.
UPRIGHT_TORSOS = 0.7
#: How far the knees must sit below the hips, in torso lengths, to call the athlete stood up
#: rather than gathered in a crouch. A vertical torso is not standing: people get up off the
#: floor by bringing the torso upright first and collecting themselves on their haunches,
#: which reads as upright for most of a second. An offset rather than a knee angle, on
#: purpose -- an angle threshold is what locked out the athlete whose foreshortened full
#: extension only read 145 degrees.
STANDING_TORSOS = 0.5


def ok(p: Keypoint) -> bool:
    return p.score >= MIN_SCORE


def midpoint(k: Sequence[Keypoint], a: int, b: int) -> Keypoint | None:
    pa, pb = k[a], k[b]
    if ok(pa) and ok(pb):
        return Keypoint(f32((pa.x + pb.x) / 2.0), f32((pa.y + pb.y) / 2.0),
                        min(pa.score, pb.score))
    if ok(pa):
        return pa
    if ok(pb):
        return pb
    return None


def torso_length(k: Sequence[Keypoint]) -> float | None:
    sh = midpoint(k, KP.LEFT_SHOULDER, KP.RIGHT_SHOULDER)
    if sh is None:
        return None
    hp = midpoint(k, KP.LEFT_HIP, KP.RIGHT_HIP)
    if hp is None:
        return None
    return f32(math.hypot(f32(sh.x - hp.x), f32(sh.y - hp.y)))


def angle(a: Keypoint, b: Keypoint, c: Keypoint) -> float:
    """Interior angle at `b`, in degrees, or NaN if any vertex is not confidently seen."""
    if not ok(a) or not ok(b) or not ok(c):
        return NAN
    abx, aby = f32(a.x - b.x), f32(a.y - b.y)
    cbx, cby = f32(c.x - b.x), f32(c.y - b.y)
    mag = f32(f32(math.hypot(abx, aby)) * f32(math.hypot(cbx, cby)))
    if mag < f32(1e-4):
        return NAN
    dot = f32(f32(abx * cbx) + f32(aby * cby))
    cos = max(-1.0, min(1.0, f32(dot / mag)))
    return f32(math.degrees(math.acos(cos)))


def bilateral_angle(
    k: Sequence[Keypoint], la: int, lb: int, lc: int, ra: int, rb: int, rc: int
) -> float:
    l = angle(k[la], k[lb], k[lc])
    r = angle(k[ra], k[rb], k[rc])
    if not math.isnan(l) and not math.isnan(r):
        return f32((l + r) / 2.0)
    if not math.isnan(l):
        return l
    if not math.isnan(r):
        return r
    return NAN


def upright(k: Sequence[Keypoint]) -> bool:
    """True when the shoulders sit well above the hips: torso vertical, not lying down."""
    sh = midpoint(k, KP.LEFT_SHOULDER, KP.RIGHT_SHOULDER)
    if sh is None:
        return False
    hp = midpoint(k, KP.LEFT_HIP, KP.RIGHT_HIP)
    if hp is None:
        return False
    torso = f32(math.hypot(f32(sh.x - hp.x), f32(sh.y - hp.y)))
    if torso < 1.0:
        return False
    return f32(hp.y - sh.y) >= f32(UPRIGHT_TORSOS * torso)


def standing(k: Sequence[Keypoint]) -> bool:
    """Upright *and* stood up on the legs, rather than folded over them in a crouch."""
    if not upright(k):
        return False
    hp = midpoint(k, KP.LEFT_HIP, KP.RIGHT_HIP)
    if hp is None:
        return False
    kn = midpoint(k, KP.LEFT_KNEE, KP.RIGHT_KNEE)
    if kn is None:
        return False
    torso = torso_length(k)
    if torso is None:
        return False
    return f32(kn.y - hp.y) >= f32(STANDING_TORSOS * torso)


def hanging_from_bar(k: Sequence[Keypoint]) -> bool:
    """Hands overhead, tested against the hips rather than the shoulders."""
    hip = midpoint(k, KP.LEFT_HIP, KP.RIGHT_HIP)
    if hip is None:
        return False
    wr = midpoint(k, KP.LEFT_WRIST, KP.RIGHT_WRIST)
    if wr is None:
        return False
    return wr.y < hip.y


def hands_overhead(k: Sequence[Keypoint], hands: Keypoint) -> bool:
    """Whether the hands are above the head, separating a hang from a chest-height grip.

    At a dead hang the arms are overhead by definition, so the hands sit clearly above the
    nose; holding a band in front of the chest puts them clearly below it. Only gates whether
    an *unknown* bar may be learned -- once one exists, ``BarZone.holds`` constrains refining.

    A head that cannot be seen blocks nothing, so rear-view and occluded footage that already
    counts keeps working; this rejects one specific wrong posture, not an unclear view.
    """
    nose = k[KP.NOSE]
    return not ok(nose) or hands.y < nose.y


def missing_joints(k: Sequence[Keypoint], exercise: Exercise) -> list[str]:
    # Imported here rather than at module level: workout_engine imports this module for its
    # geometry, so importing Exercise back from workout_engine at the top would be a cycle.
    from .workout_engine import Exercise

    if exercise in (Exercise.PULLUP, Exercise.PUSHUP):
        needed = [
            ("shoulders", (KP.LEFT_SHOULDER, KP.RIGHT_SHOULDER)),
            ("elbows", (KP.LEFT_ELBOW, KP.RIGHT_ELBOW)),
            ("hands", (KP.LEFT_WRIST, KP.RIGHT_WRIST)),
            ("hips", (KP.LEFT_HIP, KP.RIGHT_HIP)),
        ]
    else:
        needed = [
            ("shoulders", (KP.LEFT_SHOULDER, KP.RIGHT_SHOULDER)),
            ("hips", (KP.LEFT_HIP, KP.RIGHT_HIP)),
            ("knees", (KP.LEFT_KNEE, KP.RIGHT_KNEE)),
            ("ankles", (KP.LEFT_ANKLE, KP.RIGHT_ANKLE)),
        ]
    return [name for name, (a, b) in needed if midpoint(k, a, b) is None]
