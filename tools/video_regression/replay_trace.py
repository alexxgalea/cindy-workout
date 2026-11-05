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

The athlete's controls (skip, +1, undo) and every recalibration are `control` rows, applied to
the replay where they happened and listed with their times.

`voice` rows say when each spoken count was asked for and when the engine started to sound it.
The replay skips them and reports, per scored frame, how long the count took to be heard, from
the moment the frame was captured. --max-voice-ms fails the run when the median is over it.
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
NOT_FRAMES = {"control", "voice"}
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


CONTROLS = {
    "SKIP_SETUP": None,  # the setup -> workout boundary already calls finish_setup
    "SKIP_EXERCISE": WorkoutEngine.skip_exercise,
    "MANUAL_REP": WorkoutEngine.manual_rep,
    "UNDO_REP": WorkoutEngine.undo_rep,
    "RECALIBRATE_CAMERA_MOVED": WorkoutEngine.recalibrate,
    "RECALIBRATE_RESUMED": WorkoutEngine.recalibrate,
    "RECALIBRATE_LENS_FLIPPED": WorkoutEngine.recalibrate,
}


def replay(rows: list[dict]) -> int:
    first = next(r for r in rows if r["kind"] not in NOT_FRAMES)
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
    controls = []
    phone = {e.name: 0 for e in Exercise}
    port = {e.name: 0 for e in Exercise}
    divergence = None
    in_setup = first["kind"] == "setup"
    t0 = int(first["engine_ms"])
    for i, row in enumerate(rows):
        now = int(row["engine_ms"])
        if row["kind"] == "voice":
            continue
        if row["kind"] == "control":
            name = row["event"]
            controls.append(((now - t0) / 1000, name, engine.exercise.name))
            action = CONTROLS[name]
            if action is not None:
                action(engine)
            continue
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

    print("reps by movement     phone  replay   (counted from frames; +1 not included)")
    for name in phone:
        print(f"  {name:<18} {phone[name]:>5}  {port[name]:>6}")
    if controls:
        print("controls and recalibrations (session time, what, movement):")
        for t, name, ex in controls:
            print(f"  {t:7.2f}s  {name:<26} {ex}")
    if divergence is None:
        print("\nThe replay agrees with the phone on every frame: the counting rules, given these "
              "frames, decide exactly what the phone decided.")
        return 0
    i, t, kind, theirs, mine, why = divergence
    print(f"\nFirst disagreement at row {i} ({t:.2f}s, {kind}):\n  phone  {theirs}\n  replay {mine}"
          f"\n  replay's rejection: {why}")
    return 1


def health(rows: list[dict], gap_ms: float) -> None:
    run = [r for r in rows if r["kind"] == "run"] or [r for r in rows if r["kind"] not in NOT_FRAMES]
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
    t0 = int(next(r for r in rows if r["kind"] not in NOT_FRAMES)["engine_ms"])
    long_gaps = [(int(run[i + 1]["engine_ms"]) - t0, g, run[i + 1]["exercise"])
                 for i, g in enumerate(gaps) if g > gap_ms]
    if long_gaps:
        print(f"  gaps over {gap_ms:.0f} ms (session time, gap, movement):")
        for t, g, ex in long_gaps[:40]:
            print(f"    {t / 1000:7.2f}s  {g:5.0f} ms  {ex}")


def voice_latency(rows: list[dict]) -> list[tuple]:
    """For each scored frame, the count's journey: captured, analysed, asked for, started to sound.

    A scored frame is matched to the first ASKED row after it with the same count, and that to its
    utterance's STARTED row. Times are milliseconds on the engine's clock. Returns one tuple per
    scored frame: (session s, movement, count, capture->engine, engine->asked, asked->started,
    capture->started, cut off), with None where the voice row is missing.
    """
    t0 = int(next(r for r in rows if r["kind"] not in NOT_FRAMES)["engine_ms"])
    started, stopped = {}, set()
    for r in rows:
        if r["kind"] == "voice" and r["event"] == "STARTED":
            started.setdefault(r["phase"], int(r["engine_ms"]))
        if r["kind"] == "voice" and r["event"] == "STOPPED":
            stopped.add(r["phase"])
    out = []
    for i, r in enumerate(rows):
        if r["kind"] != "run" or r["event"] not in SCORED:
            continue
        cap = int(r["capture_ns"]) / 1e6
        eng = int(r["engine_ms"])
        count = r["reps"] if r["event"] == "REP" else None
        asked = None
        for q in rows[i + 1:]:
            if q["kind"] == "run" and q["event"] in SCORED:
                break
            if q["kind"] == "voice" and q["event"] == "ASKED":
                asked = q
                break
        a = int(asked["engine_ms"]) if asked else None
        s = started.get(asked["phase"]) if asked else None
        out.append(((eng - t0) / 1000, movement_scored(r["event"], r["exercise"]),
                    asked["reps"] if asked else count, eng - cap,
                    a - eng if a is not None else None,
                    s - a if s is not None and a is not None else None,
                    s - cap if s is not None else None,
                    bool(asked) and asked["phase"] in stopped and s is None))
    return out


def report_voice(rows: list[dict], max_ms: float | None, verbose: bool) -> int:
    lat = voice_latency(rows)
    if not any(r[6] is not None for r in lat):
        if not any(r["kind"] == "voice" for r in rows):
            print("\nno voice rows: this trace is from a build that does not time the spoken count")
        else:
            print("\nvoice rows present but no scored count was heard")
        return 0
    heard = [r for r in lat if r[6] is not None]
    print(f"\nspoken count, from capture to the voice starting ({len(heard)} of {len(lat)} "
          "scored frames heard):")
    for name, k in (("capture -> engine", 3), ("engine -> asked", 4), ("asked -> sounding", 5),
                    ("capture -> sounding", 6)):
        v = np.array([r[k] for r in heard], dtype=float)
        print(f"  {name:<20} median {np.median(v):4.0f} ms, p90 {np.percentile(v, 90):4.0f}, "
              f"max {v.max():4.0f}")
    lost = [r for r in lat if r[6] is None]
    if lost:
        print(f"  never heard: {len(lost)}" + (f" ({sum(r[7] for r in lost)} cut off by the next)"
                                               if any(r[7] for r in lost) else ""))
    if verbose:
        print("  session s  movement  count  cap>eng  eng>ask  ask>snd  cap>snd")
        for t, mv, n, a, b, c, d, _ in lat:
            f = lambda x: "    -" if x is None else f"{x:5.0f}"  # noqa: E731
            print(f"  {t:9.2f}  {mv:<8} {n or '':>5}  {f(a)}    {f(b)}    {f(c)}    {f(d)}")
    if max_ms is not None:
        med = float(np.median([r[6] for r in heard]))
        if med > max_ms:
            print(f"  FAIL: median {med:.0f} ms is over {max_ms:.0f} ms")
            return 1
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("trace")
    ap.add_argument("--gap-ms", type=float, default=150.0, help="list analysis gaps longer than this")
    ap.add_argument("--max-voice-ms", type=float, help="fail when the spoken count's median delay "
                    "from capture is over this")
    ap.add_argument("--voice-rows", action="store_true", help="list every scored frame's delays")
    args = ap.parse_args()
    with open(args.trace, newline="") as f:
        rows = list(csv.DictReader(f))
    if not rows:
        print("empty trace")
        return 2
    code = replay(rows)
    health(rows, args.gap_ms)
    return code or report_voice(rows, args.max_voice_ms, args.voice_rows)


if __name__ == "__main__":
    sys.exit(main())
