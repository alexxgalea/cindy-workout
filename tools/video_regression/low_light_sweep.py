#!/usr/bin/env python3
"""Measures what diminishing light does to the counting pipeline, on a clip of known ground truth.

This is the tool that turned "a tester said it stopped counting at sunset" into something that
could be worked on. There was no recording of the incident, so the only honest route was to take
clips whose correct score is known exactly and take the light away in measured steps.

    python3 tools/video_regression/low_light_sweep.py \\
        --video tests/fixtures/youtube/pullups/3aRP4o23HXo.mp4 --exercise pullup \\
        --pull band_assisted

What it found, and what the fixtures in tests/scenarios/youtube.json now guard:

* The failure is not a cliff, it is a **bleed**. A clip whose ground truth is 5 scored
  5, 5, 5, 3, 2, 1, 0 as the light fell — the score goes quietly wrong long before it stops.
* **Pull-ups fail roughly 16x sooner than push-ups**, because wrists held overhead are the first
  keypoints lost. "Show both hands" dominates every degraded run.
* **Nothing is ever over-counted.** Across every light level tested the count only moved down, so
  there is no phantom rep for a gate to catch and nothing for a `mayBook` veto to protect.
* **Mean frame luma cannot separate working from broken**: the pipeline counts perfectly at luma
  11 (dark, uncompensated) and is stone dead at luma 70 (bright, noise-limited). Use the legibility
  column, which is what TrackingHealthMonitor reads.
* **Brightness normalisation recovers the underexposed regime entirely** and does nothing at all
  for the noise-limited one. Run with --no-normalise to see the before.

Two light models, because a phone does not sit still while the sun goes down:

``uncompensated``
    ``out = frame * gain``. Exposure is already at its limit, so less light simply means a darker
    picture. Also what happens at any light level when auto-exposure meters on a bright background
    and leaves the subject underexposed.

``iso``
    ``out = frame * gain * iso + noise(sigma * iso)``. What the camera does first: raise gain to
    hold brightness up, amplifying read noise with it. The picture stays bright and gets dirty.
    This is the regime software cannot rescue.
"""
from __future__ import annotations

import argparse
import sys
from collections import Counter
from pathlib import Path

import cv2
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))

from cindy_sim.pose_detector import PoseDetector, Tune  # noqa: E402
from cindy_sim.tracking_health import TrackingHealth, TrackingHealthMonitor  # noqa: E402
from cindy_sim.workout_engine import (  # noqa: E402
    CindyProfile,
    Exercise,
    PullVariant,
    RepEvent,
    WorkoutEngine,
)

#: Read noise of a phone sensor at base gain, in 8-bit counts. Conservative.
READ_NOISE = 2.0
#: Ceiling on how far a camera will push its own gain to hold the brightness up.
ISO_CAP = 12.0

EXERCISES = {"pullup": Exercise.PULLUP, "pushup": Exercise.PUSHUP, "squat": Exercise.SQUAT}

#: Rejections meaning "I cannot read the joints", as opposed to "I can see you fine but you are
#: not in position". Only the first kind is evidence the camera is losing the athlete; the second
#: is a normal part of a workout with rest and transitions in it. Reported separately because the
#: two move in OPPOSITE directions as light falls, and blending them hides the signal.
UNREADABLE = {
    "Show both hands", "Step into frame", "Arms out of frame", "Tracking…",
    "Show your head", "Show your legs to the camera",
}


def light(frame: np.ndarray, gain: float, model: str, rng: np.random.Generator) -> np.ndarray:
    f = frame.astype(np.float32)
    if model == "iso":
        iso = min(1.0 / max(gain, 1e-6), ISO_CAP)
        out = f * gain * iso + rng.normal(0.0, READ_NOISE * iso, size=f.shape).astype(np.float32)
    else:
        out = f * gain
    return np.clip(out, 0, 255).astype(np.uint8)


def luma(rgb: np.ndarray) -> float:
    """Rec. 601 luma — the number a frame-brightness gate would read, and could not use."""
    return float(np.dot(rgb.reshape(-1, 3).mean(axis=0), (0.299, 0.587, 0.114)))


def run(video: Path, exercise: Exercise, profile: CindyProfile, gain: float, model: str,
        normalise: bool, seed: int = 7) -> dict:
    rng = np.random.default_rng(seed)
    capture = cv2.VideoCapture(str(video))
    fps = capture.get(cv2.CAP_PROP_FPS) or 30.0
    detector = PoseDetector(str(ROOT / "app/src/main/assets/movenet_thunder.tflite"),
                            "movenet_thunder.tflite")
    engine = WorkoutEngine(fixed_exercise=exercise, profile=profile)
    health = TrackingHealthMonitor()

    original_target = Tune.TARGET_LUMA
    if not normalise:
        # Target zero and the clamp pins every gain to 1.0, which is the pipeline as it was.
        Tune.TARGET_LUMA = 0.0

    rejections: Counter[str] = Counter()
    lumas: list[float] = []
    gains: list[float] = []
    legible = 0
    worst = TrackingHealth.GOOD
    index = 0
    try:
        while True:
            ok, bgr = capture.read()
            if not ok:
                break
            rgb = light(cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB), gain, model, rng)
            lumas.append(luma(rgb))
            ts = int(index * 1000.0 / fps)
            tracking = detector.tracking
            k = detector.detect(rgb)
            gains.append(detector.soft_gain)
            engine.on_frame(k, ts, tracking)
            d = engine.diagnostics
            if d.pose_legible:
                legible += 1
            health.update(engine.exercise, d.pose_legible, detector.soft_gain, ts)
            if health.health is TrackingHealth.LOST or (
                health.health is TrackingHealth.WEAK and worst is TrackingHealth.GOOD
            ):
                worst = health.health
            rejections[d.rejection_reason or "(scored/none)"] += 1
            index += 1
    finally:
        Tune.TARGET_LUMA = original_target
        capture.release()
        detector.close()

    frames = max(index, 1)
    unread = sum(v for k_, v in rejections.items() if k_ in UNREADABLE)
    return {
        "reps": engine.reps,
        "luma": float(np.mean(lumas)) if lumas else 0.0,
        "gain": float(np.mean(gains)) if gains else 1.0,
        "legible": 100.0 * legible / frames,
        "unread": 100.0 * unread / frames,
        "health": worst.name,
        "frames": frames,
    }


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--video", type=Path, required=True)
    ap.add_argument("--exercise", default="pullup", choices=sorted(EXERCISES))
    ap.add_argument("--pull", choices=["strict", "band_assisted"])
    ap.add_argument("--expect", type=int, help="ground truth, marked against each row")
    ap.add_argument("--model", default="uncompensated", choices=["uncompensated", "iso"])
    ap.add_argument("--no-normalise", action="store_true",
                    help="disable the analysis-crop brightness lift, to measure what it is worth")
    ap.add_argument("--gains", type=float, nargs="*",
                    default=[1.0, 0.3, 0.15, 0.10, 0.07, 0.05, 0.03])
    args = ap.parse_args()

    if not args.video.is_file():
        print(f"error: no such clip: {args.video}", file=sys.stderr)
        return 2

    profile = CindyProfile()
    if args.pull == "band_assisted":
        profile = CindyProfile(pull=PullVariant.BAND_ASSISTED_PULL_UP)

    normalise = not args.no_normalise
    print(f"\n{args.video.name}  [{args.exercise}]  light: {args.model}  "
          f"normalise: {'on' if normalise else 'off'}")
    print(f"{'light':>7} {'luma':>7} {'softgain':>9} {'legible':>8} {'unread':>7} "
          f"{'reps':>5} {'':>2} {'tracking':>9}")
    print("-" * 64)
    for g in args.gains:
        r = run(args.video, EXERCISES[args.exercise], profile, g, args.model, normalise)
        mark = ""
        if args.expect is not None:
            mark = "ok" if r["reps"] == args.expect else "XX"
        print(f"{g:>7.3f} {r['luma']:>7.1f} {r['gain']:>9.2f} {r['legible']:>7.1f}% "
              f"{r['unread']:>6.1f}% {r['reps']:>5} {mark:>2} {r['health']:>9}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
