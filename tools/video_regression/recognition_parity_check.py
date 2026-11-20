#!/usr/bin/env python3
"""Diffs the Python recogniser in cindy_sim against the production Kotlin one, frame by frame.

The harness runs the recognition rules (position, then movement) over films in Python so what the
phone makes of an athlete can be tried on a desktop. Two implementations of the same rules drift, and a harness that has quietly
stopped agreeing with the phone gives confident, wrong verdicts about a film, so this is the gate
that keeps it honest. It is separate from parity_check.py, which holds the counting engine to its
own plan and trace.

Generate the reference trace first (it is written by a JVM unit test, not by this script):

    ./gradlew testDebugUnitTest --tests 'com.cindy.tracker.RecognitionParityTraceTest'
    python3 tools/video_regression/recognition_parity_check.py

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
from cindy_sim.rep_counter import f32
from cindy_sim.recogniser import Movement, Recogniser
from cindy_sim.workout_engine import CindyProfile, PullVariant, PushVariant, SquatVariant

HEADER = [
    "traceId", "step", "tMs", "builder", "angle", "stable", "kpSum", "position", "movement",
    "candidate", "candidateReps", "tallyPullUps", "tallyPushUps", "tallySquats",
]


def rounded(value: float) -> str:
    """NaN has no stable cross-language spelling, so it is normalised the way the Kotlin does."""
    return "nan" if math.isnan(value) else f"{value:.3f}"


def run_plan(plan_path: Path) -> list[list[str]]:
    with plan_path.open(newline="") as fh:
        rows = list(csv.DictReader(fh))

    out: list[list[str]] = []
    for trace_id in dict.fromkeys(row["traceId"] for row in rows):
        steps = [row for row in rows if row["traceId"] == trace_id]
        # The profile is a column of the trace's first row, as in the counting plan.
        recogniser = Recogniser(CindyProfile(
            pull=PullVariant[steps[0]["pull"]],
            push=PushVariant[steps[0]["push"]],
            squat=SquatVariant[steps[0]["squat"]],
        ))
        for step in steps:
            # The Kotlin reads the angle as a Float, so the twin rounds it to one too.
            angle = f32(float(step["angle"]))
            now = int(step["tMs"])
            keypoints = pose_fixtures.BUILDERS[step["builder"]](angle)
            recognition = recogniser.on_frame(keypoints, now, step["stable"] == "true")
            out.append([
                trace_id,
                step["step"],
                str(now),
                step["builder"],
                step["angle"],
                step["stable"],
                # Guards the fixture geometry itself, so a divergence in the synthetic body is
                # distinguishable from a divergence in the position rules.
                # The Kotlin adds x and y as Floats and the sum as a Double, and so does this.
                rounded(sum(f32(p.x + p.y) for p in keypoints)),
                recognition.position.id,
                recognition.movement.id if recognition.movement else "none",
                recognition.candidate.id if recognition.candidate else "none",
                str(recognition.candidate_reps),
                *(str(recognition.tally_of(m)) for m in Movement),
            ])
    return out


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    root = Path(__file__).resolve().parents[2]
    parser.add_argument("--plan", type=Path, default=root / "tests/parity/recognition_plan.csv")
    parser.add_argument("--reference", type=Path, default=root / "tests/parity/recognition_trace_jvm.csv")
    parser.add_argument("--output", type=Path, default=root / "tests/parity/recognition_trace_py.csv")
    parser.add_argument("--max-report", type=int, default=15)
    args = parser.parse_args()

    if not args.plan.is_file():
        print(f"error: missing recognition plan at {args.plan}", file=sys.stderr)
        return 2

    rows = run_plan(args.plan)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", newline="") as fh:
        writer = csv.writer(fh)
        writer.writerow(HEADER)
        writer.writerows(rows)
    print(f"python recognition trace: {len(rows)} frames -> {args.output}")

    if not args.reference.is_file():
        print(
            f"error: no reference trace at {args.reference}. Generate it with:\n"
            "  ./gradlew testDebugUnitTest --tests 'com.cindy.tracker.RecognitionParityTraceTest'",
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
    for want, got in zip(reference, rows):
        for column, name in enumerate(HEADER):
            if want[column] != got[column]:
                mismatches.append(
                    f"{got[0]} frame {got[1]} (t={got[2]}ms, {got[3]} {got[4]}): "
                    f"{name} jvm={want[column]!r} python={got[column]!r}"
                )

    if mismatches:
        print(f"FAIL: {len(mismatches)} field(s) differ across {len(rows)} frames", file=sys.stderr)
        for line in mismatches[: args.max_report]:
            print(f"  {line}", file=sys.stderr)
        if len(mismatches) > args.max_report:
            print(f"  ... and {len(mismatches) - args.max_report} more", file=sys.stderr)
        return 1

    print(f"PASS: python recogniser matches the production Kotlin on all {len(rows)} frames")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
