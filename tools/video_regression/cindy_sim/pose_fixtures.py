"""Port of app/src/test/java/com/cindy/tracker/PoseFixtures.kt.

Synthetic keypoint bodies, so the rep logic can be exercised without a camera. All coordinates
are in "pixels" with y growing downward, matching what PoseDetector emits.
"""
from __future__ import annotations

import math

from .keypoints import KP, Keypoint
from .rep_counter import f32

LIMB = 100.0
TORSO = 100.0


def _blank() -> list[Keypoint]:
    return [Keypoint(0.0, 0.0, 0.0) for _ in range(KP.COUNT)]


def _put(k: list[Keypoint], index: int, x: float, y: float, score: float = 0.9) -> None:
    # Kotlin's Keypoint holds 32-bit Floats, so the synthetic bodies must be stored at that
    # width too or the parity trace diverges on rounding rather than on behaviour.
    k[index] = Keypoint(f32(x), f32(y), f32(score))


def _put_pair(k: list[Keypoint], left: int, right: int, x: float, y: float) -> None:
    """Places both of a bilateral pair at the same spot; the engine averages the two sides."""
    _put(k, left, x - 10.0, y)
    _put(k, right, x + 10.0, y)


def squat(knee_deg: float) -> list[Keypoint]:
    """A body squatting with the given knee angle. 180 is standing, 90 is below parallel."""
    k = _blank()
    hip_x = LIMB * math.sin(math.radians(knee_deg))
    hip_y = LIMB * math.cos(math.radians(knee_deg))
    _put_pair(k, KP.LEFT_KNEE, KP.RIGHT_KNEE, 0.0, 0.0)
    _put_pair(k, KP.LEFT_ANKLE, KP.RIGHT_ANKLE, 0.0, LIMB)
    _put_pair(k, KP.LEFT_HIP, KP.RIGHT_HIP, hip_x, hip_y)
    _put_pair(k, KP.LEFT_SHOULDER, KP.RIGHT_SHOULDER, hip_x, hip_y - TORSO)
    _put(k, KP.NOSE, hip_x, hip_y - TORSO - 30.0)
    return k


def on_the_floor() -> list[Keypoint]:
    """A body face down at the end of a set of push-ups, legs straight.

    The knee angle here is a full 180 degrees -- the same reading a standing body gives -- so
    this is the pose that proves a squat cannot be gated on leg extension alone.
    """
    k = _blank()
    _put_pair(k, KP.LEFT_SHOULDER, KP.RIGHT_SHOULDER, 0.0, 0.0)
    _put_pair(k, KP.LEFT_HIP, KP.RIGHT_HIP, -TORSO, 0.0)
    # Hip, knee and ankle collinear along the floor: the legs are locked out.
    _put_pair(k, KP.LEFT_KNEE, KP.RIGHT_KNEE, -TORSO - 80.0, 0.0)
    _put_pair(k, KP.LEFT_ANKLE, KP.RIGHT_ANKLE, -TORSO - 160.0, 0.0)
    _put_pair(k, KP.LEFT_ELBOW, KP.RIGHT_ELBOW, 0.0, LIMB)
    _put_pair(k, KP.LEFT_WRIST, KP.RIGHT_WRIST, 0.0, 2.0 * LIMB)
    _put(k, KP.NOSE, 60.0, 0.0)
    return k


def pushup(elbow_deg: float) -> list[Keypoint]:
    """A body mid push-up with the given elbow angle. 180 is lockout, 90 is chest down."""
    k = _blank()
    sh_x = LIMB * math.sin(math.radians(elbow_deg))
    sh_y = LIMB * math.cos(math.radians(elbow_deg))
    _put_pair(k, KP.LEFT_ELBOW, KP.RIGHT_ELBOW, 0.0, 0.0)
    _put_pair(k, KP.LEFT_WRIST, KP.RIGHT_WRIST, 0.0, LIMB)
    _put_pair(k, KP.LEFT_SHOULDER, KP.RIGHT_SHOULDER, sh_x, sh_y)
    # Hips trail behind the shoulders along the body's long axis, keeping torso length fixed.
    _put_pair(k, KP.LEFT_HIP, KP.RIGHT_HIP, sh_x - TORSO, sh_y)
    _put_pair(k, KP.LEFT_KNEE, KP.RIGHT_KNEE, sh_x - TORSO - 80.0, sh_y)
    return k


def pullup(elbow_deg: float) -> list[Keypoint]:
    """A body on the bar with the given elbow angle. 170 is a dead hang, 60 is chin over the bar.

    The shoulders rise past the hands at the top, exactly as on a real pull-up.
    """
    k = _blank()
    sh_x = LIMB * math.sin(math.radians(elbow_deg))
    sh_y = -LIMB * math.cos(math.radians(elbow_deg))
    _put_pair(k, KP.LEFT_ELBOW, KP.RIGHT_ELBOW, 0.0, 0.0)
    _put_pair(k, KP.LEFT_WRIST, KP.RIGHT_WRIST, 0.0, -LIMB)
    _put_pair(k, KP.LEFT_SHOULDER, KP.RIGHT_SHOULDER, sh_x, sh_y)
    _put_pair(k, KP.LEFT_HIP, KP.RIGHT_HIP, sh_x, sh_y + TORSO)
    # Nose is the head proxy emitted by COCO-17: past the wrist/bar line at the top, below the
    # reset line at a dead hang.
    _put(k, KP.NOSE, sh_x, sh_y - 120.0)
    return k


def empty() -> list[Keypoint]:
    """Nothing confidently detected -- the "step into frame" case."""
    return _blank()


def band_setup(_unused: float = 0.0) -> list[Keypoint]:
    """Standing holding a resistance band at chest height, arms straight.

    The posture that taught a bar in the wrong place on real band footage: hands above the hips
    with the elbows extended, but below the head, because the band is held in front of the chest
    rather than gripped overhead. Takes an ignored angle so it can be driven from the parity plan
    like the other builders.
    """
    k = _blank()
    _put_pair(k, KP.LEFT_SHOULDER, KP.RIGHT_SHOULDER, 0.0, 0.0)
    _put_pair(k, KP.LEFT_HIP, KP.RIGHT_HIP, 0.0, TORSO)
    _put_pair(k, KP.LEFT_ELBOW, KP.RIGHT_ELBOW, 0.0, 0.2 * TORSO)
    _put_pair(k, KP.LEFT_WRIST, KP.RIGHT_WRIST, 0.0, 0.4 * TORSO)
    _put(k, KP.NOSE, 0.0, -0.4 * TORSO)
    _put_pair(k, KP.LEFT_KNEE, KP.RIGHT_KNEE, 0.0, 2.0 * TORSO)
    _put_pair(k, KP.LEFT_ANKLE, KP.RIGHT_ANKLE, 0.0, 3.0 * TORSO)
    return k


def inverted_row(elbow_deg: float) -> list[Keypoint]:
    """A body mid inverted row: hands on a low bar overhead, body running away horizontally.

    The arm chain is exactly ``pullup``'s, because that is the point -- the elbow swings the same
    range, the wrists sit above the hips and the head reaches the bar line. Every pull-up gate
    except the torso's direction is satisfied by a row.
    """
    k = _blank()
    sh_x = LIMB * math.sin(math.radians(elbow_deg))
    sh_y = -LIMB * math.cos(math.radians(elbow_deg))
    _put_pair(k, KP.LEFT_ELBOW, KP.RIGHT_ELBOW, 0.0, 0.0)
    _put_pair(k, KP.LEFT_WRIST, KP.RIGHT_WRIST, 0.0, -LIMB)
    _put_pair(k, KP.LEFT_SHOULDER, KP.RIGHT_SHOULDER, sh_x, sh_y)
    # The body runs out sideways from the shoulders rather than hanging under them.
    _put_pair(k, KP.LEFT_HIP, KP.RIGHT_HIP, sh_x + TORSO, sh_y)
    _put_pair(k, KP.LEFT_KNEE, KP.RIGHT_KNEE, sh_x + TORSO + 80.0, sh_y)
    _put_pair(k, KP.LEFT_ANKLE, KP.RIGHT_ANKLE, sh_x + TORSO + 160.0, sh_y)
    _put(k, KP.NOSE, sh_x, sh_y - 120.0)
    return k


def hang_with_legs(elbow_deg: float) -> list[Keypoint]:
    """A body on the bar with its legs in frame: ``pullup`` plus knees and ankles hanging straight
    below the hips, a thigh and a shin of LIMB each.

    A hang is upright with straight legs, so everything that reads standing is true of it; the hands
    on the bar are the only thing that says otherwise.
    """
    k = pullup(elbow_deg)
    hip_x = f32(LIMB * math.sin(math.radians(elbow_deg)))
    hip_y = f32(f32(-LIMB * math.cos(math.radians(elbow_deg))) + TORSO)
    _put_pair(k, KP.LEFT_KNEE, KP.RIGHT_KNEE, hip_x, f32(hip_y + LIMB))
    _put_pair(k, KP.LEFT_ANKLE, KP.RIGHT_ANKLE, hip_x, f32(hip_y + 2.0 * LIMB))
    return k


def kneeling_up(ankle_behind: float) -> list[Keypoint]:
    """Kneeling up, torso upright and hips a thigh above the knees, with the ankles seen with full
    confidence ``ankle_behind`` pixels behind the knee and on the floor with it (a twentieth of a
    thigh below it, the worst the Cindy clip ever showed).

    ``PoseGeometry.standing`` reads this as standing; only the shins say it is not.
    """
    k = _blank()
    _put_pair(k, KP.LEFT_KNEE, KP.RIGHT_KNEE, 0.0, 0.0)
    _put_pair(k, KP.LEFT_ANKLE, KP.RIGHT_ANKLE, -ankle_behind, f32(f32(0.05) * LIMB))
    _put_pair(k, KP.LEFT_HIP, KP.RIGHT_HIP, 0.0, -LIMB)
    _put_pair(k, KP.LEFT_SHOULDER, KP.RIGHT_SHOULDER, 0.0, -LIMB - TORSO)
    _put(k, KP.NOSE, 0.0, -LIMB - TORSO - 30.0)
    return k


def head_on_plank(_unused: float = 0.0) -> list[Keypoint]:
    """A plank filmed from in front: the foreshortened torso points up the picture, so the
    shoulders sit well above the hips. Knees a long way below the hips and ankles up beside the
    knees, so today's posture test reads this as standing. Takes an ignored angle so it can be
    driven from a plan like the other builders.
    """
    k = _blank()
    _put_pair(k, KP.LEFT_SHOULDER, KP.RIGHT_SHOULDER, 0.0, 0.0)
    _put_pair(k, KP.LEFT_HIP, KP.RIGHT_HIP, 0.0, 80.0)
    _put_pair(k, KP.LEFT_KNEE, KP.RIGHT_KNEE, 0.0, 140.0)
    _put_pair(k, KP.LEFT_ANKLE, KP.RIGHT_ANKLE, 0.0, 150.0)
    _put_pair(k, KP.LEFT_ELBOW, KP.RIGHT_ELBOW, 0.0, 70.0)
    _put_pair(k, KP.LEFT_WRIST, KP.RIGHT_WRIST, 0.0, 160.0)
    _put(k, KP.NOSE, 0.0, -30.0)
    return k


def leaning_squat(knee_deg: float) -> list[Keypoint]:
    """The bottom of a squat as it is really done: ``squat``'s legs, with the torso leaning 60
    degrees forward over the knees. The shoulders sit only half a torso above the hips, so the body
    is not upright, but the shins are still a full shin's length under the knees.
    """
    k = squat(knee_deg)
    hip_x = f32(LIMB * math.sin(math.radians(knee_deg)))
    hip_y = f32(LIMB * math.cos(math.radians(knee_deg)))
    lean = math.radians(60.0)
    shoulder_x = f32(hip_x - f32(TORSO * math.sin(lean)))
    shoulder_y = f32(hip_y - f32(TORSO * math.cos(lean)))
    _put_pair(k, KP.LEFT_SHOULDER, KP.RIGHT_SHOULDER, shoulder_x, shoulder_y)
    _put(k, KP.NOSE, shoulder_x - 20.0, shoulder_y - 25.0)
    return k


def walking(dx: float) -> list[Keypoint]:
    """Standing and walking: ``squat``'s straight-legged stand, ``dx`` pixels to the side."""
    k = squat(175.0)
    return [Keypoint(f32(p.x + dx), p.y, p.score) if p.score > 0.0 else p for p in k]


BUILDERS = {
    "squat": squat, "pushup": pushup, "pullup": pullup,
    "bandsetup": band_setup, "invertedrow": inverted_row,
    # The builders the recognition plan draws on. `empty` and `onthefloor` take an ignored angle.
    "empty": lambda _unused=0.0: empty(),
    "onthefloor": lambda _unused=0.0: on_the_floor(),
    "hangwithlegs": hang_with_legs, "kneelingup": kneeling_up, "headonplank": head_on_plank,
    "leaningsquat": leaning_squat, "walking": walking,
}
