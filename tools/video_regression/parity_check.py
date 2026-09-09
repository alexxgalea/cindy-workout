#!/usr/bin/env python3
"""Diffs the Python port in cindy_sim against the production Kotlin engine, frame by frame.

The port exists so counting bugs can be reproduced on a desktop against real video. Two
implementations of the same rules drift, and a harness that has silently stopped agreeing with
the phone gives confident, wrong verdicts -- so this is the gate that keeps it honest.

Generate the reference trace first (it is written by a JVM unit test, not by this script):

    ./gradlew testDebugUnitTest --tests 'com.cindy.tracker.EngineParityTraceTest'
    python3 tools/video_regression/parity_check.py

Exits non-zero on the first frames that disagree, naming the trace, frame and column.
"""
from __future__ import annotations

import argparse
import csv
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from cindy_sim import pose_fixtures
from cindy_sim.workout_engine import Exercise, WorkoutEngine

HEADER = [
    "traceId", "step", "tMs", "angle", "kpSum", "event", "count", "state", "signal",
    "learnedRange", "calibrated", "hint", "minConfidence", "confidenceAdequate",
    "barGateOpen", "headAboveBar", "resetSeen", "rejection",
]
EXERCISES = {"pullup": Exercise.PULLUP, "pushup": Exercise.PUSHUP, "squat": Exercise.SQUAT}


def rounded(value: float) -> str:
    """NaN has no stable cross-language spelling, so it is normalised the way the Kotlin does."""
    return "nan" if math.isnan(value) else f"{value:.3f}"


def run_plan(plan_path: Path) -> list[list[str]]:
    with plan_path.open(newline="") as fh:
        rows = list(csv.DictReader(fh))

    out: list[list[str]] = []
    for trace_id in dict.fromkeys(row["traceId"] for row in rows):
        steps = [row for row in rows if row["traceId"] == trace_id]
        engine = WorkoutEngine(fixed_exercise=EXERCISES[steps[0]["exercise"]])
        for step in steps:
            angle = float(step["angle"])
            now = int(step["stepMs"]) * int(step["step"])
            keypoints = pose_fixtures.BUILDERS[step["builder"]](angle)
            event = engine.on_frame(keypoints, now)
            d = engine.diagnostics
            out.append([
                trace_id,
                step["step"],
                str(now),
                step["angle"],
                # Guards the fixture geometry itself, so a divergence in the synthetic body is
                # distinguishable from a divergence in the counting rules.
                rounded(sum(p.x + p.y for p in keypoints)),
                event.name,
                str(engine.reps),
                engine.counting_state,
                rounded(engine.signal),
                rounded(engine.learned_range),
                str(engine.calibrated).lower(),
                engine.hint,
                rounded(d.minimum_confidence),
                str(d.scoring_confidence_adequate).lower(),
                str(d.bar_gate_open).lower(),
                str(d.head_above_bar).lower(),
                str(d.reset_below_bar_seen).lower(),
                d.rejection_reason or "",
            ])
    return out


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    root = Path(__file__).resolve().parents[2]
    parser.add_argument("--plan", type=Path, default=root / "tests/parity/plan.csv")
    parser.add_argument("--reference", type=Path, default=root / "tests/parity/trace_jvm.csv")
    parser.add_argument("--output", type=Path, default=root / "tests/parity/trace_py.csv")
    parser.add_argument("--max-report", type=int, default=15)
    args = parser.parse_args()

    if not args.plan.is_file():
        print(f"error: missing parity plan at {args.plan}", file=sys.stderr)
        return 2

    rows = run_plan(args.plan)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", newline="") as fh:
        writer = csv.writer(fh)
        writer.writerow(HEADER)
        writer.writerows(rows)
    print(f"python trace: {len(rows)} frames -> {args.output}")

    if not args.reference.is_file():
        print(
            f"error: no reference trace at {args.reference}. Generate it with:\n"
            "  ./gradlew testDebugUnitTest --tests 'com.cindy.tracker.EngineParityTraceTest'",
            file=sys.stderr,
        )
        return 2

    with args.reference.open(newline="") as fh:
        reference = list(csv.reader(fh))
    if reference and reference[0] == HEADER:
        reference = reference[1:]

    if len(reference) != len(rows):
        print(f"FAIL: JVM trace has {len(reference)} frames, python produced {len(rows)}", file=sys.stderr)
        return 1

    mismatches: list[str] = []
    for index, (want, got) in enumerate(zip(reference, rows)):
        for column, name in enumerate(HEADER):
            if want[column] != got[column]:
                mismatches.append(
                    f"{got[0]} frame {got[1]} (t={got[2]}ms, angle={got[3]}): "
                    f"{name} jvm={want[column]!r} python={got[column]!r}"
                )

    if mismatches:
        print(f"FAIL: {len(mismatches)} field(s) differ across {len(rows)} frames", file=sys.stderr)
        for line in mismatches[: args.max_report]:
            print(f"  {line}", file=sys.stderr)
        if len(mismatches) > args.max_report:
            print(f"  ... and {len(mismatches) - args.max_report} more", file=sys.stderr)
        return 1

    print(f"PASS: python port matches the production Kotlin engine on all {len(rows)} frames")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
