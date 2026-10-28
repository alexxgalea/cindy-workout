"""Replays an engine trace written by a debug build through the Python port, frame for frame.

A debug build writes every frame it gives the engine -- the keypoints, the clock it was handed,
what it decided -- to Android/data/com.cindy.tracker.debug/files/engine_trace/engine-<ms>.csv
(see EngineTrace.kt). This feeds the same frames to the port and reports:

- the reps each movement scored on the phone and in the replay, and the first frame where the
  two disagree, which says whether a miscount lives in the counting rules or around them;
- how the phone was analysing: frames per second, the gaps between analysed captures, frames
  the analyser refused while busy, how old a frame was when it was analysed, and the thermal
  status, so a miscount can be put next to what the phone was doing at the time.

    adb pull /sdcard/Android/data/com.cindy.tracker.debug/files/engine_trace/
    .venv/bin/python tools/video_regression/replay_trace.py engine_trace/engine-<ms>.csv

The athlete's own controls (+1, undo, skip) are not in the trace, so a session that used them
diverges from the replay at that point, and says so.
"""
from __future__ import annotations

import argparse
import csv
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from cindy_sim.keypoints import Keypoint  # noqa: E402
from cindy_sim.workout_engine import (  # noqa: E402
    CindyProfile,
    Exercise,
    PullVariant,
    PushVariant,
    RepEvent,
    SquatVariant,
    WorkoutEngine,
)

SCORED = {"REP", "EXERCISE_DONE", "ROUND_DONE"}
THERMAL = {-1: "unknown", 0: "none", 1: "light", 2: "moderate", 3: "severe", 4: "critical",
           5: "emergency", 6: "shutdown"}


def keypoints(row: dict) -> list[Keypoint]:
    return [Keypoint(float(row[f"k{i}_x"]), float(row[f"k{i}_y"]), float(row[f"k{i}_s"]))
            for i in range(17)]


def movement_scored(event: str, exercise: str) -> str:
    """The movement an event belongs to: an EXERCISE_DONE has already moved the engine on."""
    if event == "REP":
        return exercise
    return Exercise[exercise].previous().name


def replay(rows: list[dict]) -> int:
    first = rows[0]
    engine = WorkoutEngine(
        profile=CindyProfile(
            pull=PullVariant[first["pull"]],
            push=PushVariant[first["push"]],
            squat=SquatVariant[first["squat"]],
        ),
        smart_squats=first["smart_squats"] == "1",
    )
    if first["kind"] == "setup":
        engine.begin_setup()
    phone = {e.name: 0 for e in Exercise}
    port = {e.name: 0 for e in Exercise}
    divergence = None
    in_setup = first["kind"] == "setup"
    t0 = int(first["engine_ms"])
    for i, row in enumerate(rows):
        now = int(row["engine_ms"])
        tracking = row["tracking"] == "1"
        k = keypoints(row)
        if row["kind"] == "setup":
            s = engine.on_setup_frame(k, now, tracking)
            mine = (s.stage.name, s.reps)
            theirs = (row["setup_stage"], int(row["reps"]))
        else:
            if in_setup:
                # The app calls finishSetup between the READY frame and the first workout frame.
                engine.finish_setup()
                in_setup = False
            event = engine.on_frame(k, now, tracking)
            if event.name in SCORED:
                port[movement_scored(event.name, engine.exercise.name)] += 1
            if row["event"] in SCORED:
                phone[movement_scored(row["event"], row["exercise"])] += 1
            mine = (event.name, engine.exercise.name, engine.reps)
            theirs = (row["event"], row["exercise"], int(row["reps"]))
        if divergence is None and mine != theirs:
            divergence = (i, (now - t0) / 1000, row["kind"], theirs, mine,
                          engine.diagnostics.rejection_reason)

    print("reps by movement     phone  replay")
    for name in phone:
        print(f"  {name:<18} {phone[name]:>5}  {port[name]:>6}")
    if divergence is None:
        print("\nThe replay agrees with the phone on every frame: the counting rules, given these "
              "frames, decide exactly what the phone decided.")
        return 0
    i, t, kind, theirs, mine, why = divergence
    print(f"\nFirst disagreement at row {i} ({t:.2f}s, {kind}):\n  phone  {theirs}\n  replay {mine}"
          f"\n  replay's rejection: {why}")
    print("  (a +1, undo or skip on the phone is not in the trace and diverges here too)")
    return 1


def health(rows: list[dict], gap_ms: float) -> None:
    run = [r for r in rows if r["kind"] == "run"] or rows
    cap = np.array([int(r["capture_ns"]) for r in run], dtype=np.int64) / 1e6
    span = (cap[-1] - cap[0]) / 1000 if len(cap) > 1 else 0
    gaps = np.diff(cap)
    print(f"\nanalysis over {span:.1f}s of workout: {len(run)} frames, "
          f"{len(run) / span if span else 0:.1f}/s")
    if len(gaps):
        p = np.percentile(gaps, [50, 90, 99]).round(0)
        print(f"  gap between analysed captures: median {p[0]:.0f} ms, p90 {p[1]:.0f}, "
              f"p99 {p[2]:.0f}, max {gaps.max():.0f}")
    refused = sum(int(r["refused_before"]) for r in run)
    print(f"  refused while busy: {refused}")
    ages = [int(r["capture_age_ms"]) for r in run if r["capture_age_ms"]]
    if ages:
        a = np.percentile(ages, [50, 90, 99]).round(0)
        print(f"  frame age when analysed: median {a[0]:.0f} ms, p90 {a[1]:.0f}, p99 {a[2]:.0f}")
    infer = np.array([int(r["infer_ms"]) for r in run])
    print(f"  inference: median {np.median(infer):.0f} ms, p90 {np.percentile(infer, 90):.0f}")
    seen = sorted({int(r["thermal"]) for r in run})
    print(f"  thermal status seen: {', '.join(THERMAL.get(s, str(s)) for s in seen)}")
    t0 = int(rows[0]["engine_ms"])
    long_gaps = [(int(run[i + 1]["engine_ms"]) - t0, g, run[i + 1]["exercise"])
                 for i, g in enumerate(gaps) if g > gap_ms]
    if long_gaps:
        print(f"  gaps over {gap_ms:.0f} ms (session time, gap, movement):")
        for t, g, ex in long_gaps[:40]:
            print(f"    {t / 1000:7.2f}s  {g:5.0f} ms  {ex}")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("trace")
    ap.add_argument("--gap-ms", type=float, default=150.0, help="list analysis gaps longer than this")
    args = ap.parse_args()
    with open(args.trace, newline="") as f:
        rows = list(csv.DictReader(f))
    if not rows:
        print("empty trace")
        return 2
    code = replay(rows)
    health(rows, args.gap_ms)
    return code


if __name__ == "__main__":
    sys.exit(main())
