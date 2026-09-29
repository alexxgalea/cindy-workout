"""Scoring identity: turns a per-frame stream of "who is this" verdicts into every rate a fix
should be judged by, against ground truth rather than against the counter it feeds.

This module is deliberately variant-agnostic. It never touches ``PoseDetector``, ``AthleteLock``
or ``WorkoutEngine`` directly, and no function here may use the counter under test to decide
whether a frame is stolen -- that would grade the counter against itself. Instead a caller (today,
``run_identity.py``'s production variant; later, a variant built around a real lock) supplies a
:class:`Verdict` per frame however it sees fit, and this module scores it against ground truth
from ``composite.py`` or a real-clip catalogue.

Verdict mapping for the production pipeline (documented here because it has to be defined
somewhere: production has no identity lock yet, so there is no real CONFIRMED/UNCERTAIN/REFUSED
verdict to read)
------------------------------------------------------------------------------------------------
``run_identity.py``'s ``ProductionVariant`` synthesises a verdict matching what the engine
actually does today:

- no torso seen at all -> :attr:`Verdict.NONE` (the engine's existing no-torso path, unchanged by
  identity, and excluded from every verdict-based rate below);
- a torso is seen, and the movement is a pull-up -> :attr:`Verdict.CONFIRMED` if the detector's own
  ``tracking`` flag is true that frame (today, a pull-up is only scored while a crop is being
  tracked at all -- that flag is the whole of today's identity check), else
  :attr:`Verdict.UNCERTAIN`;
- a torso is seen, and the movement is a push-up or squat -> always :attr:`Verdict.CONFIRMED`,
  because push-ups and squats count whatever skeleton the detector hands them today, with no
  identity check of any kind.

:attr:`Verdict.REFUSED` therefore never occurs in the production mapping: nothing today actively
refuses a frame it can read, it either trusts it (push-up/squat, or a tracked pull-up) or ignores
identity (an untracked pull-up becomes UNCERTAIN, not REFUSED, since a lost crop is not evidence
that the *body in view* is the wrong one -- it is evidence that there is no crop). Metrics that are
specifically about refusal (``max_refused_run_ms``) read zero for production, which documents the
absence of a defence rather than a bug in the metric. A variant built around a real identity lock
can and should produce real REFUSED verdicts.

Per-frame classification
-------------------------
:func:`classify_frame` answers "on the athlete / on someone else / nothing" using only geometry:
whether a torso was detected at all, and if so, how far its centre sits from the athlete's own
*clean* torso centre (the ground-truth run) -- never whether the counter would accept it. This is
deliberately a *looser* test than the "stolen" definition below, which also requires landing inside
the neighbour's placement rectangle; that rectangle-gated definition is reproduced exactly by
:func:`whole_skeleton_stolen` and :func:`stolen_joint_count` for comparing against a known theft-
rate table, and used nowhere else, because a real clip's neighbour has no such rectangle.
"""
from __future__ import annotations

import math
from collections import defaultdict
from dataclasses import dataclass, field
from enum import Enum
from typing import Iterable, Mapping, Sequence

#: A keypoint tuple as every variant already carries it: (x, y, score). Matches
#: ``cindy_sim.keypoints.Keypoint`` field for field, so a caller can pass those objects directly
#: (attribute access) or plain tuples (index access) -- see ``_xy_score``.
KeypointLike = object

MIN_SCORE = 0.30
#: COCO-17 indices (cindy_sim.keypoints.KP), duplicated here so this module has no import-time
#: dependency on cindy_sim -- it must be usable against any keypoint source, real or synthetic.
LEFT_SHOULDER, RIGHT_SHOULDER = 5, 6
LEFT_HIP, RIGHT_HIP = 11, 12

#: A whole skeleton is stolen when its torso centre is more than this many torso lengths from the
#: athlete's, and inside the neighbour's rectangle.
STEAL_TORSOS = 0.5
#: The classification's looser threshold uses the same distance -- only the rectangle gate differs.
CLASSIFY_TORSOS = 0.5


def _xy_score(point) -> tuple[float, float, float]:
    if hasattr(point, "x"):
        return float(point.x), float(point.y), float(point.score)
    x, y, s = point
    return float(x), float(y), float(s)


def torso_centre(keypoints: Sequence[KeypointLike], strict: bool = False) -> tuple[float, float, float] | None:
    """The torso centre and length every theft measure is built on: the midpoint of the seen
    shoulders averaged with the midpoint of the seen hips, and the distance between the two.

    ``strict=False`` (the default, and the theft definition) accepts a single shoulder or hip.
    ``strict=True`` demands both, which is noisier to lose but far steadier once seen -- a one-sided midpoint
    can jump by half the body's width when the other side drops below the confidence floor.
    Returns ``None`` if the torso cannot be built at all (no shoulder, or no hip, confidently seen).
    """
    shoulders = [LEFT_SHOULDER, RIGHT_SHOULDER]
    hips = [LEFT_HIP, RIGHT_HIP]
    if strict:
        pts = [_xy_score(keypoints[i]) for i in (*shoulders, *hips)]
        if any(s < MIN_SCORE for _, _, s in pts):
            return None
    s_pts = [_xy_score(keypoints[i]) for i in shoulders if _xy_score(keypoints[i])[2] >= MIN_SCORE]
    h_pts = [_xy_score(keypoints[i]) for i in hips if _xy_score(keypoints[i])[2] >= MIN_SCORE]
    if not s_pts or not h_pts:
        return None
    sx = sum(p[0] for p in s_pts) / len(s_pts)
    sy = sum(p[1] for p in s_pts) / len(s_pts)
    hx = sum(p[0] for p in h_pts) / len(h_pts)
    hy = sum(p[1] for p in h_pts) / len(h_pts)
    length = max(math.hypot(sx - hx, sy - hy), 1.0)
    return (sx + hx) / 2.0, (sy + hy) / 2.0, length


class Classification(Enum):
    """Where the detector's output sits this frame, relative to the ground-truth athlete."""

    ATHLETE = "athlete"
    OTHER = "other"
    NOTHING = "nothing"


class Verdict(Enum):
    """A frame's identity verdict. See the module docstring for the production mapping."""

    CONFIRMED = "CONFIRMED"
    UNCERTAIN = "UNCERTAIN"
    REFUSED = "REFUSED"
    #: No torso seen at all -- the engine's own existing path, unrelated to identity.
    NONE = "NONE"


def classify_frame(
    detected: Sequence[KeypointLike] | None, truth: Sequence[KeypointLike],
) -> Classification:
    """"on the athlete / on someone else / nothing", using only the distance from the detected
    torso centre to the ground-truth (clean-run) torso centre -- never a placement rectangle, so
    this works identically on a synthetic composite and a real two-person clip.

    `detected` is the keypoints the detector under test produced this frame; `truth` is the same
    clip's clean (no-neighbour, or real-clip-labelled) torso at the same instant.

    When `truth` itself has no torso this frame, the rate metrics exclude the frame anyway (via
    `ScoredFrame.truth_has_torso`, the "scored frames" convention) -- but this
    function still needs to answer sensibly for the metrics that do not filter on it, chiefly the
    startup ones: before the athlete arrives, truth has no torso by construction, and if the
    detector confidently reports *somebody* right then, that is definitely not the athlete, not
    nothing. So a torso detected while truth has none is OTHER; only detecting nobody, while truth
    has nobody either, is NOTHING.
    """
    a = torso_centre(truth)
    c = torso_centre(detected) if detected is not None else None
    if a is None:
        return Classification.OTHER if c is not None else Classification.NOTHING
    if c is None:
        return Classification.NOTHING
    dist = math.hypot(c[0] - a[0], c[1] - a[1])
    if dist <= STEAL_TORSOS * a[2]:
        return Classification.ATHLETE
    return Classification.OTHER


def whole_skeleton_stolen(
    detected: Sequence[KeypointLike] | None, truth: Sequence[KeypointLike], neighbour_cell,
) -> bool | None:
    """A stricter theft definition than `classify_frame`, for reproducing a known rectangle-gated
    theft-rate table: the detected torso centre is more than 0.5 torso lengths from the athlete's
    truth centre, *and* inside the neighbour's placement rectangle. Returns `None` (not scored)
    when `truth` has no torso.
    """
    a = torso_centre(truth)
    if a is None:
        return None
    c = torso_centre(detected) if detected is not None else None
    if c is None or neighbour_cell is None:
        return False
    dist = math.hypot(c[0] - a[0], c[1] - a[1])
    return dist > STEAL_TORSOS * a[2] and neighbour_cell.contains_point(c[0], c[1])


def stolen_joint_count(
    detected: Sequence[KeypointLike] | None, truth: Sequence[KeypointLike], neighbour_cell,
) -> int:
    """A per-joint theft count: a joint landing more than 0.5 truth-torso-lengths from its own
    truth position, confidently seen, and inside the neighbour's rectangle. 0 when the truth torso
    itself is unavailable (nothing to measure joint distance against) or no neighbour is placed
    this frame.
    """
    a = torso_centre(truth)
    if a is None or detected is None or neighbour_cell is None:
        return 0
    count = 0
    for det_pt, truth_pt in zip(detected, truth):
        dx, dy, ds = _xy_score(det_pt)
        tx, ty, _ = _xy_score(truth_pt)
        if ds >= MIN_SCORE and math.hypot(dx - tx, dy - ty) > STEAL_TORSOS * a[2] and neighbour_cell.contains_point(dx, dy):
            count += 1
    return count


@dataclass(frozen=True)
class ScoredFrame:
    """One frame's worth of everything a :class:`Report` needs. A variant builds a list of these
    (see ``run_identity.py``'s variants) and hands it to :func:`score_run`.
    """

    time_ms: int
    classification: Classification
    verdict: Verdict
    stolen_joints: int = 0
    whole_stolen: bool = False
    #: Ground truth: could the athlete's own *clean* torso be built at all this frame? Independent
    #: of whether the detector under test found anything, which is what `classification`/`verdict`
    #: describe. A frame where this is False carries no identity information either way and is
    #: excluded from every rate below.
    truth_has_torso: bool = True
    #: Ground truth from the scene, not from the detector: is the athlete geometrically present
    #: and not hidden behind the neighbour this frame? (``composite.Frame.athlete_box``,
    #: ``composite.Frame.occluded``.) Used by blind time and "time to get back after a theft".
    athlete_visible: bool = True
    athlete_occluded: bool = False
    #: Ground truth for "time to get back after a real loss": the athlete's own pose (not the
    #: detector's) is back in the current movement's start position at their station. `None` when
    #: a set has no such ground truth yet (every composite here: none of them model a departure
    #: and return), which excludes it from that metric rather than reporting a false 0.
    athlete_at_start_position: bool | None = None
    #: For the cost metric (a lock-based variant only; always 0/None for production).
    lock_state: str | None = None
    extra_inferences: int = 0
    #: For counting metrics; `None` when a set carries no movement/rep information at all.
    movement: str | None = None


@dataclass
class RecoveryEvent:
    """One episode of the athlete becoming present again (visible and unoccluded, or back at the
    start position) after not being, paired with the next CONFIRMED-on-athlete frame.

    The duration is measured from the athlete *becoming present again* -- the first frame they are
    visible and unoccluded again, or back at the start position -- to their first CONFIRMED frame
    from that point on, not from whenever they were lost, which would also count time nobody could
    have done anything about.
    """

    present_again_at_ms: int
    recovered_at_ms: int | None  # None if the run ends before recovery

    @property
    def duration_ms(self) -> int | None:
        return None if self.recovered_at_ms is None else self.recovered_at_ms - self.present_again_at_ms


@dataclass
class Report:
    """Every identity metric, for one (layout, variant) run."""

    n_frames: int
    #: Percentages of *scored* frames (truth has a torso) in each classification.
    on_athlete_pct: float
    on_other_pct: float
    on_nothing_pct: float
    stolen_joints_total: int
    frames_with_stolen_joint_pct: float
    whole_stolen_pct: float
    #: Rates are of scored, torso-seen-by-truth frames (Verdict.NONE frames excluded).
    clean_rejection_pct: float
    wrong_acceptance_pct: float
    max_refused_run_ms: int
    blind_time_total_ms: int
    blind_time_longest_run_ms: int
    time_to_get_back_after_theft_ms: list[int] = field(default_factory=list)
    time_to_get_back_after_loss_ms: list[int] = field(default_factory=list)
    wrong_recovery_events: int = 0
    startup_wrong_confirmation: bool | None = None
    startup_time_to_confirmation_ms: int | None = None
    startup_reps_before_confirmation: int | None = None
    extra_inferences_per_second_by_state: dict[str, float] = field(default_factory=dict)
    reps_matched: dict[str, int] = field(default_factory=dict)
    reps_missed: dict[str, int] = field(default_factory=dict)
    false_reps: dict[str, int] = field(default_factory=dict)

    def as_dict(self) -> dict:
        d = dict(self.__dict__)
        d["on_athlete_pct"] = round(self.on_athlete_pct, 2)
        d["on_other_pct"] = round(self.on_other_pct, 2)
        d["on_nothing_pct"] = round(self.on_nothing_pct, 2)
        d["frames_with_stolen_joint_pct"] = round(self.frames_with_stolen_joint_pct, 2)
        d["whole_stolen_pct"] = round(self.whole_stolen_pct, 2)
        d["clean_rejection_pct"] = round(self.clean_rejection_pct, 2)
        d["wrong_acceptance_pct"] = round(self.wrong_acceptance_pct, 2)
        return d


def _runs(frames: Sequence[ScoredFrame], predicate) -> list[tuple[int, int]]:
    """(start_ms, end_ms) of every maximal run of consecutive frames where `predicate` holds,
    `end_ms` being the timestamp *after* the run's last true frame (the next frame's time, or the
    last frame's time if the run reaches the end of the clip -- so a single-frame run at the tail
    still reports a duration of 0 rather than crashing on a missing successor).
    """
    out = []
    start = None
    for i, f in enumerate(frames):
        hit = predicate(f)
        if hit and start is None:
            start = f.time_ms
        if not hit and start is not None:
            out.append((start, f.time_ms))
            start = None
    if start is not None:
        out.append((start, frames[-1].time_ms))
    return out


def score_run(
    frames: Sequence[ScoredFrame],
    labelled_reps_ms: Mapping[str, Sequence[int]] | None = None,
    rep_events_ms: Mapping[str, Sequence[int]] | None = None,
    rep_tolerance_ms: int = 500,
) -> Report:
    """Turns a variant's per-frame stream into every number task 3 asks for.

    `labelled_reps_ms` / `rep_events_ms` are optional, keyed by movement ("pullup"/"pushup"/
    "squat"): eye-labelled rep timestamps and the counting engine's own rep-event timestamps, for
    the "counts" metric. Neither is available for the plain composite layouts (they carry no rep
    labels); both are for the Cindy-mode clip and a real labelled two-person clip (task 7).
    """
    # Every rate below is of "scored" frames (1,155 of 1,189 for the garage clip alone): truth had a torso at all, regardless of what the detector under test found.
    # A frame classified NOTHING because the *detector* found nobody still counts here; only
    # `truth_has_torso=False` (34 of 1,189 frames for the garage clip alone) is excluded.
    truth_had_torso = [f for f in frames if f.truth_has_torso]
    n = len(truth_had_torso) or 1

    on_athlete = sum(1 for f in truth_had_torso if f.classification is Classification.ATHLETE)
    on_other = sum(1 for f in truth_had_torso if f.classification is Classification.OTHER)
    on_nothing = sum(1 for f in truth_had_torso if f.classification is Classification.NOTHING)

    clean_rejection = sum(
        1 for f in truth_had_torso if f.classification is Classification.ATHLETE and f.verdict is not Verdict.CONFIRMED
    )
    wrong_acceptance = sum(
        1 for f in truth_had_torso if f.classification is Classification.OTHER and f.verdict is Verdict.CONFIRMED
    )

    refused_runs = _runs(frames, lambda f: f.verdict is Verdict.REFUSED)
    max_refused = max((b - a for a, b in refused_runs), default=0)

    blind = lambda f: f.athlete_visible and not f.athlete_occluded and not (
        f.classification is Classification.ATHLETE and f.verdict is Verdict.CONFIRMED
    )
    blind_runs = _runs(frames, blind)
    blind_total = sum(b - a for a, b in blind_runs)
    blind_longest = max((b - a for a, b in blind_runs), default=0)

    theft_recoveries = _recovery_events(
        frames, present=lambda f: f.athlete_visible and not f.athlete_occluded,
    )
    loss_recoveries = _recovery_events(
        frames, present=lambda f: bool(f.athlete_at_start_position),
        eligible=lambda f: f.athlete_at_start_position is not None,
    )

    wrong_recovery_events = 0
    prev_wrong = False
    for f in frames:
        wrong = f.classification is Classification.OTHER and f.verdict is Verdict.CONFIRMED
        if wrong and not prev_wrong:
            wrong_recovery_events += 1
        prev_wrong = wrong

    startup_wrong = startup_time = startup_reps_before = None
    confirmed_athlete = [f for f in frames if f.classification is Classification.ATHLETE and f.verdict is Verdict.CONFIRMED]
    confirmed_other_before = [
        f for f in frames if f.classification is Classification.OTHER and f.verdict is Verdict.CONFIRMED
        and (not confirmed_athlete or f.time_ms < confirmed_athlete[0].time_ms)
    ]
    if frames:
        startup_wrong = len(confirmed_other_before) > 0
        startup_time = confirmed_athlete[0].time_ms - frames[0].time_ms if confirmed_athlete else None
        if rep_events_ms is not None and startup_time is not None:
            cutoff = confirmed_athlete[0].time_ms
            startup_reps_before = sum(1 for times in rep_events_ms.values() for t in times if t < cutoff)

    cost: dict[str, list[int]] = defaultdict(list)
    for f in frames:
        cost[f.lock_state or "n/a"].append(f.extra_inferences)
    duration_s = max((frames[-1].time_ms - frames[0].time_ms) / 1000.0, 1e-6) if frames else 1.0
    cost_per_state = {state: sum(vals) / duration_s for state, vals in cost.items()}

    matched, missed, false = ({}, {}, {})
    if labelled_reps_ms is not None and rep_events_ms is not None:
        matched, missed, false = match_reps(labelled_reps_ms, rep_events_ms, rep_tolerance_ms)

    return Report(
        n_frames=len(frames),
        on_athlete_pct=100.0 * on_athlete / n,
        on_other_pct=100.0 * on_other / n,
        on_nothing_pct=100.0 * on_nothing / n,
        stolen_joints_total=sum(f.stolen_joints for f in frames),
        frames_with_stolen_joint_pct=100.0 * sum(1 for f in truth_had_torso if f.stolen_joints > 0) / n,
        whole_stolen_pct=100.0 * sum(1 for f in truth_had_torso if f.whole_stolen) / n,
        clean_rejection_pct=100.0 * clean_rejection / n,
        wrong_acceptance_pct=100.0 * wrong_acceptance / n,
        max_refused_run_ms=max_refused,
        blind_time_total_ms=blind_total,
        blind_time_longest_run_ms=blind_longest,
        time_to_get_back_after_theft_ms=[e.duration_ms for e in theft_recoveries if e.duration_ms is not None],
        time_to_get_back_after_loss_ms=[e.duration_ms for e in loss_recoveries if e.duration_ms is not None],
        wrong_recovery_events=wrong_recovery_events,
        startup_wrong_confirmation=startup_wrong,
        startup_time_to_confirmation_ms=startup_time,
        startup_reps_before_confirmation=startup_reps_before,
        extra_inferences_per_second_by_state=cost_per_state,
        reps_matched=matched,
        reps_missed=missed,
        false_reps=false,
    )


def _recovery_events(frames: Sequence[ScoredFrame], present, eligible=None) -> list[RecoveryEvent]:
    """Episodes where `present(frame)` goes False -> True, paired with the first CONFIRMED-on-
    athlete frame at or after the moment it becomes True again. `eligible` restricts which frames
    even carry the ground truth needed (e.g. `athlete_at_start_position is not None`); frames
    outside it are skipped rather than counted as "absent".
    """
    usable = [f for f in frames if eligible is None or eligible(f)]
    events: list[RecoveryEvent] = []
    was_present = True  # do not count the run's own opening frame as a "recovery"
    for idx, f in enumerate(usable):
        now_present = present(f)
        if not was_present and now_present:
            # Visible (or back at the station) again: find the first confirmation from here on,
            # including this same frame if it is itself already confirmed.
            recovered_at = None
            for later in usable[idx:]:
                if later.classification is Classification.ATHLETE and later.verdict is Verdict.CONFIRMED:
                    recovered_at = later.time_ms
                    break
            events.append(RecoveryEvent(f.time_ms, recovered_at))
        was_present = now_present
    return events


def match_reps(
    labelled_ms: Mapping[str, Sequence[int]], events_ms: Mapping[str, Sequence[int]], tolerance_ms: int = 500,
) -> tuple[dict[str, int], dict[str, int], dict[str, int]]:
    """Matches a counting engine's rep events against eye labels, per movement, greedily and in
    time order (one label matches at most one event, and vice versa). Returns (matched, missed,
    false) counts per movement, where "false" is a count event with no labelled rep within
    `tolerance_ms` -- a rep the identity fix must not be inventing.
    """
    matched: dict[str, int] = {}
    missed: dict[str, int] = {}
    false: dict[str, int] = {}
    for movement in set(labelled_ms) | set(events_ms):
        labels = sorted(labelled_ms.get(movement, []))
        events = sorted(events_ms.get(movement, []))
        used_labels = [False] * len(labels)
        n_matched = n_false = 0
        for e in events:
            best = None
            best_gap = tolerance_ms + 1
            for i, label_t in enumerate(labels):
                if used_labels[i]:
                    continue
                gap = abs(e - label_t)
                if gap <= tolerance_ms and gap < best_gap:
                    best, best_gap = i, gap
            if best is None:
                n_false += 1
            else:
                used_labels[best] = True
                n_matched += 1
        matched[movement] = n_matched
        false[movement] = n_false
        missed[movement] = used_labels.count(False)
    return matched, missed, false
