#!/usr/bin/env python3
"""Runs a named set of identity layouts through the production pipeline, or a later variant built
around a real identity lock, and prints/saves every scoring metric.

    python3 tools/video_regression/identity/run_identity.py
    python3 tools/video_regression/identity/run_identity.py --sets layouts startup
    python3 tools/video_regression/identity/run_identity.py --catalogue <catalogue.json>

Reports land in ``tests/reports/identity/`` (ignored by git, like the rest of ``tests/reports/``).
The clean (no-neighbour) detector run is cached per base clip under
``tests/reports/identity/cache/``, since it is identical for every layout that shares one; the
composited (two-person) run is cached per layout too, since re-running the detector is the slow
part. Neither cache is valid for a closed-loop variant (see :class:`Variant`), which is why one is
never consulted by one.
"""
from __future__ import annotations

import argparse
import json
import pickle
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable, Iterable, Iterator

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from cindy_sim.pose_detector import PoseDetector  # noqa: E402
from identity import composite, metrics  # noqa: E402

ROOT = Path(__file__).resolve().parents[3]
REPORTS_DIR = ROOT / "tests/reports/identity"
CACHE_DIR = REPORTS_DIR / "cache"
ASSET = "movenet_thunder.tflite"
ASSET_PATH = ROOT / "app/src/main/assets" / ASSET
STEP = 2  # 15 fps from the clips' 30 fps source


def movement_at(time_s: float) -> str:
    """Which Cindy movement is active at `time_s` into the garage clip: pull-ups from 0-26s,
    push-ups from 26-54s, squats from 54s on, each transition split at its midpoint against a
    measured phase table (pull-ups 0-24s, a walk to the mat 24-28s, push-ups 28-52s, a walk to the
    squat spot 52-56s, squats 56-80s). This only ever selects which verdict rule applies below --
    it never consults the counter, so it stays a fact about the clip's own phase table, not a
    metric derived from the engine under test.
    """
    if time_s < 26.0:
        return "pullup"
    if time_s < 54.0:
        return "pushup"
    return "squat"


@dataclass
class Layout:
    """One named scene to score: a set name (for grouping in the printed report), a layout name,
    and how to build and iterate it. `frame_source` defaults to the ordinary 15 fps run; the
    startup set overrides it to prepend the lead-in.
    """

    set_name: str
    name: str
    scene_factory: Callable[[], composite.Scene]
    frame_source: Callable[[composite.Scene], Iterator[composite.Frame]] = None

    def frames(self) -> Iterator[composite.Frame]:
        scene = self.scene_factory()
        source = self.frame_source or (lambda s: s.frames(step=STEP, neighbour=True))
        return source(scene)

    def clean_key(self) -> str:
        """Cache key for the clean (no-neighbour) run. Shared by every layout built from the same
        base clip and crop, since the athlete's own frames never depend on the neighbour.
        """
        scene = self.scene_factory()
        return f"{scene.base_clip.stem}_{scene.base_crop[0]}_{scene.base_crop[1]}_{STEP}"


# ---------------------------------------------------------------------------------------------
# Named layout sets. "layouts" is five fixed neighbour placements (A-E); the other three are the
# startup, walk-through and synchronised-pull-up composites.
# ---------------------------------------------------------------------------------------------

#: (scale, top-left) for layouts A-E: where the neighbour stands relative to the athlete, sized as
#: a fraction of their own placement box and positioned in the 480x640 output frame.
LAYOUT_ABCDE = {
    "A": dict(scale=0.62, at=(288, 262)),
    "B": dict(scale=0.90, at=(250, 140)),
    "C": dict(scale=0.90, at=(170, 140)),
    "D": dict(scale=1.05, at=(230, 100)),
    "E": dict(scale=0.62, at=(0, 262)),
}

#: The same three placements as three of the fixed layouts above, now built with a frozen
#: neighbour (see composite.stationary_bystander_frames) instead of a live, moving one.
STARTUP_CONFIGS = {
    "startup-small-back": dict(scale=0.62, at=(0, 262)),
    "startup-same-size-centre": dict(scale=0.90, at=(170, 140)),
    "startup-large-right": dict(scale=1.05, at=(230, 100)),
}


def _layout_sets() -> dict[str, list[Layout]]:
    layouts = [
        Layout("layouts", name, lambda cfg=cfg: composite.Scene(**cfg))
        for name, cfg in LAYOUT_ABCDE.items()
    ]
    startup = [
        Layout(
            "startup", name,
            lambda cfg=cfg: composite.Scene(**cfg, frozen_at_s=20.0),
            frame_source=lambda s: composite.stationary_bystander_frames(s, lead_s=5.0, step=STEP),
        )
        for name, cfg in STARTUP_CONFIGS.items()
    ]
    walkthrough = [
        Layout("walkthrough", "walkthrough", lambda: composite.walk_through_scene()),
    ]
    synchronised = [
        Layout("synchronised", "synchronised-pullups", lambda: composite.synchronised_pullups_scene()),
    ]
    return {
        "layouts": layouts,
        "startup": startup,
        "walkthrough": walkthrough,
        "synchronised": synchronised,
    }


LAYOUT_SETS = _layout_sets()
ALL_SET_NAMES = list(LAYOUT_SETS)


# ---------------------------------------------------------------------------------------------
# Caching. Only the lightweight per-frame record is persisted -- never the RGB pixels -- so a
# cache file stays small even for a set with thousands of frames.
# ---------------------------------------------------------------------------------------------


@dataclass
class _Detection:
    index: int
    time_ms: int
    keypoints: list[tuple[float, float, float]]
    tracking: bool
    neighbour_cell: composite.Box | None
    occluded: bool
    athlete_present: bool
    phase: str


def _cache_path(name: str) -> Path:
    return CACHE_DIR / f"{name}.pkl"


def _load_cache(name: str) -> list | None:
    path = _cache_path(name)
    if path.exists():
        return pickle.loads(path.read_bytes())
    return None


def _save_cache(name: str, obj: list) -> None:
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    _cache_path(name).write_bytes(pickle.dumps(obj))


def _detect_clean(layout: Layout, use_cache: bool = True) -> dict[int, list[tuple[float, float, float]]]:
    """The athlete-alone detector run, keyed by frame index. Shared across every layout built
    from the same base clip (see `Layout.clean_key`), so it only ever needs computing once.
    """
    key = f"clean_{layout.clean_key()}"
    cached = _load_cache(key) if use_cache else None
    if cached is not None:
        return dict(cached)
    detector = PoseDetector(str(ASSET_PATH), ASSET)
    scene = layout.scene_factory()
    out = {f.index: [(p.x, p.y, p.score) for p in detector.detect(f.rgb)]
           for f in scene.frames(step=STEP, neighbour=False)}
    if use_cache:
        _save_cache(key, list(out.items()))
    return out


def _detect_composited(layout: Layout, use_cache: bool = True) -> list[_Detection]:
    """The two-person detector run for one named layout, open-loop (the detector runs exactly as
    it does today; nothing here feeds a lock's decisions back into the crop). Cached per layout
    name, since re-running the detector over a whole clip is the slow part of every later use.
    """
    cached = _load_cache(f"composited_{layout.name}") if use_cache else None
    if cached is not None:
        return cached
    detector = PoseDetector(str(ASSET_PATH), ASSET)
    out = []
    for f in layout.frames():
        k = detector.detect(f.rgb)
        out.append(_Detection(
            index=f.index, time_ms=round(f.time_s * 1000), keypoints=[(p.x, p.y, p.score) for p in k],
            tracking=detector.tracking, neighbour_cell=f.neighbour_cell, occluded=f.occluded,
            athlete_present=f.athlete_box is not None, phase=f.phase,
        ))
    if use_cache:
        _save_cache(f"composited_{layout.name}", out)
    return out


# ---------------------------------------------------------------------------------------------
# Variants. A variant turns one layout's frames into scored frames. `ProductionVariant` is the
# only one implemented here, since there is no identity lock to test yet; an open-loop variant
# built around one can also use `_detect_composited`'s cache and replay the lock over it frame by
# frame. A closed-loop variant cannot use that cache at all, if the lock drives the detector's own
# crop and mask -- it must call `layout.frames()` itself, feed each frame's pixels through
# `PoseDetector.detect`/`probe` under its own control, and build `metrics.ScoredFrame`s from its
# own verdicts as it goes. Either kind implements the same `score(layout)` method, so `main()`
# below never needs to know which it has.
# ---------------------------------------------------------------------------------------------


class Variant:
    name: str

    def score(self, layout: Layout) -> list[metrics.ScoredFrame]:
        raise NotImplementedError


class ProductionVariant(Variant):
    """Today's pipeline, with the verdict mapping task 3 asks be defined and documented (see the
    metrics module docstring): CONFIRMED for push-ups/squats whenever a torso is seen (no identity
    check exists), CONFIRMED for pull-ups only while `PoseDetector.tracking` is true (today's
    `identityStable`), UNCERTAIN otherwise, and NONE where no torso was detected at all. REFUSED
    never occurs: production has no mechanism that actively refuses a frame it can read.
    """

    name = "production"

    def __init__(self, use_cache: bool = True) -> None:
        self.use_cache = use_cache

    def score(self, layout: Layout) -> list[metrics.ScoredFrame]:
        clean = _detect_clean(layout, self.use_cache)
        composited = _detect_composited(layout, self.use_cache)
        scored = []
        for d in composited:
            truth = clean.get(d.index)
            truth_has_torso = truth is not None and metrics.torso_centre(truth) is not None
            classification = metrics.classify_frame(d.keypoints, truth or [(0.0, 0.0, 0.0)] * 17)
            movement = movement_at(d.time_ms / 1000.0)
            detected_torso = metrics.torso_centre(d.keypoints) is not None
            if not detected_torso:
                verdict = metrics.Verdict.NONE
            elif movement == "pullup":
                verdict = metrics.Verdict.CONFIRMED if d.tracking else metrics.Verdict.UNCERTAIN
            else:
                verdict = metrics.Verdict.CONFIRMED
            whole_stolen = truth is not None and bool(
                metrics.whole_skeleton_stolen(d.keypoints, truth, d.neighbour_cell)
            )
            stolen_joints = 0 if truth is None else metrics.stolen_joint_count(d.keypoints, truth, d.neighbour_cell)
            scored.append(metrics.ScoredFrame(
                time_ms=d.time_ms, classification=classification, verdict=verdict,
                stolen_joints=stolen_joints, whole_stolen=whole_stolen, truth_has_torso=truth_has_torso,
                athlete_visible=d.athlete_present, athlete_occluded=d.occluded,
                athlete_at_start_position=None, movement=movement,
            ))
        return scored


VARIANTS: dict[str, Callable[[], Variant]] = {"production": ProductionVariant}


# ---------------------------------------------------------------------------------------------
# A catalogue of real two-person clips. Schema documented in tests/README.md.
# ---------------------------------------------------------------------------------------------


@dataclass
class RealClip:
    id: str
    scenario: str
    video: Path
    reps_ms: dict[str, list[int]]
    ground_truth: Path


def load_catalogue(path: Path) -> list[RealClip]:
    """Loads a local catalogue of real two-person clips (see tests/README.md for the schema). The
    catalogue, its clips and their ground truth are not expected to live anywhere this repo
    tracks -- real footage of named people is never committed, so this function only needs a path
    and works the same wherever that path points.
    """
    data = json.loads(path.read_text())
    base = path.parent
    clips = []
    for entry in data.get("clips", []):
        video = Path(entry["video"])
        video = video if video.is_absolute() else base / video
        gt = Path(entry["groundTruth"])
        gt = gt if gt.is_absolute() else base / gt
        clips.append(RealClip(
            id=entry["id"], scenario=entry["scenario"], video=video,
            reps_ms={k: list(v) for k, v in entry.get("repsMs", {}).items()}, ground_truth=gt,
        ))
    return clips


def _load_ground_truth(path: Path) -> dict[int, dict]:
    """The per-frame athlete box/torso file a catalogue entry points to. Keyed by frame index at
    the recording's own analysed rate (task 7: 'a per-frame athlete box and torso file').
    """
    data = json.loads(path.read_text())
    return {int(row["index"]): row for row in data["frames"]}


def score_real_clip(clip: RealClip, variant_name: str, use_cache: bool = True) -> metrics.Report:
    """Scores one catalogue clip: the production detector against the labelled ground truth, with
    the same verdict mapping :class:`ProductionVariant` uses. A real clip has no "clean" run (both
    people are in every frame of the source video), so truth comes from the labelled file instead
    of a second detector pass.
    """
    truth_frames = _load_ground_truth(clip.ground_truth)
    cache_key = f"real_{clip.id}"
    cached = _load_cache(cache_key) if use_cache else None
    if cached is None:
        detector = PoseDetector(str(ASSET_PATH), ASSET)
        cap_frames = _decode_frames(clip.video, step=STEP)
        cached = []
        for index, time_ms, rgb in cap_frames:
            k = detector.detect(rgb)
            cached.append((index, time_ms, [(p.x, p.y, p.score) for p in k], detector.tracking))
        if use_cache:
            _save_cache(cache_key, cached)
    scored = []
    for index, time_ms, keypoints, tracking in cached:
        row = truth_frames.get(index)
        truth = row["torso"] if row else None
        truth_has_torso = truth is not None and metrics.torso_centre(truth) is not None
        classification = metrics.classify_frame(keypoints, truth or [(0.0, 0.0, 0.0)] * 17)
        movement = movement_at(time_ms / 1000.0)
        detected_torso = metrics.torso_centre(keypoints) is not None
        if not detected_torso:
            verdict = metrics.Verdict.NONE
        elif movement == "pullup":
            verdict = metrics.Verdict.CONFIRMED if tracking else metrics.Verdict.UNCERTAIN
        else:
            verdict = metrics.Verdict.CONFIRMED
        scored.append(metrics.ScoredFrame(
            time_ms=time_ms, classification=classification, verdict=verdict, truth_has_torso=truth_has_torso,
            athlete_visible=bool(row and row.get("athleteBox")), athlete_occluded=bool(row and row.get("occluded")),
            movement=movement,
        ))
    labelled = clip.reps_ms or None
    return metrics.score_run(scored, labelled_reps_ms=labelled, rep_events_ms=None)


def _decode_frames(video: Path, step: int) -> Iterable[tuple[int, int, "np.ndarray"]]:
    import cv2

    cap = cv2.VideoCapture(str(video))
    fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    i = 0
    while True:
        ok, bgr = cap.read()
        if not ok:
            break
        i += 1
        if i % step:
            continue
        rgb = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)
        yield i, round(i / fps * 1000), rgb
    cap.release()


# ---------------------------------------------------------------------------------------------
# Reporting.
# ---------------------------------------------------------------------------------------------

TABLE_COLUMNS = [
    ("frames", "n_frames", "{}"),
    ("on athlete", "on_athlete_pct", "{:.1f}%"),
    ("on other", "on_other_pct", "{:.1f}%"),
    ("nothing", "on_nothing_pct", "{:.1f}%"),
    ("whole stolen", "whole_stolen_pct", "{:.1f}%"),
    ("stolen joints", "stolen_joints_total", "{}"),
    ("clean rej.", "clean_rejection_pct", "{:.2f}%"),
    ("wrong acc.", "wrong_acceptance_pct", "{:.2f}%"),
    ("max refused", "max_refused_run_ms", "{}ms"),
    ("blind total", "blind_time_total_ms", "{}ms"),
    ("blind longest", "blind_time_longest_run_ms", "{}ms"),
]


def print_report(set_name: str, layout_name: str, report: metrics.Report) -> None:
    print(f"\n{set_name} / {layout_name}")
    row = " ".join(f"{label}={fmt.format(getattr(report, field))}" for label, field, fmt in TABLE_COLUMNS)
    print(f"  {row}")
    if report.time_to_get_back_after_theft_ms:
        vals = report.time_to_get_back_after_theft_ms
        print(f"  time to get back (theft, athlete never left): n={len(vals)} "
              f"max={max(vals)}ms mean={sum(vals)/len(vals):.0f}ms {vals}")
    if report.time_to_get_back_after_loss_ms:
        vals = report.time_to_get_back_after_loss_ms
        print(f"  time to get back (real loss): n={len(vals)} max={max(vals)}ms {vals}")
    if report.wrong_recovery_events:
        print(f"  wrong recovery events: {report.wrong_recovery_events}")
    if report.startup_time_to_confirmation_ms is not None:
        print(f"  startup: wrong_confirmation={report.startup_wrong_confirmation} "
              f"time_to_confirmation={report.startup_time_to_confirmation_ms}ms "
              f"reps_before={report.startup_reps_before_confirmation}")
    if report.reps_matched or report.reps_missed or report.false_reps:
        print(f"  reps: matched={report.reps_matched} missed={report.reps_missed} false={report.false_reps}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--sets", nargs="*", choices=ALL_SET_NAMES, default=ALL_SET_NAMES,
                         help="which named layout sets to run (default: all)")
    parser.add_argument("--variant", choices=sorted(VARIANTS), default="production")
    parser.add_argument("--catalogue", type=Path, help="path to a real two-person clip catalogue (task 7)")
    parser.add_argument("--report", type=Path, default=REPORTS_DIR / "report.json")
    parser.add_argument("--no-cache", action="store_true", help="ignore and do not write the detector-run caches")
    args = parser.parse_args()

    variant = VARIANTS[args.variant]()
    if isinstance(variant, ProductionVariant):
        variant.use_cache = not args.no_cache

    results = []
    for set_name in args.sets:
        for layout in LAYOUT_SETS[set_name]:
            started = time.time()
            scored = variant.score(layout)
            report = metrics.score_run(scored)
            elapsed = time.time() - started
            print_report(set_name, layout.name, report)
            results.append({"set": set_name, "layout": layout.name, "variant": variant.name,
                             "seconds": round(elapsed, 1), **report.as_dict()})

    if args.catalogue:
        if args.catalogue.is_file():
            for clip in load_catalogue(args.catalogue):
                started = time.time()
                report = score_real_clip(clip, args.variant, use_cache=not args.no_cache)
                elapsed = time.time() - started
                print_report(f"real:{clip.scenario}", clip.id, report)
                results.append({"set": "real", "layout": clip.id, "scenario": clip.scenario,
                                 "variant": variant.name, "seconds": round(elapsed, 1), **report.as_dict()})
        else:
            print(f"\nno catalogue at {args.catalogue} -- real clips are the owner's task 7, "
                  f"nothing to score yet", file=sys.stderr)

    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(results, indent=2, default=list))
    print(f"\nwrote {args.report}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
