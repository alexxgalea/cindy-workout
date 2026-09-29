#!/usr/bin/env python3
"""Proves the Python port of AthleteLock still matches the production Kotlin, frame by frame.

`LockParityTraceTest` (a JVM unit test) replays tests/parity/lock_plan.csv through the real lock
and writes tests/parity/lock_trace_jvm.csv. This replays the same plan through
`cindy_sim.athlete_lock` and compares every column. State, verdict, reason and every flag must
match exactly; box edges are written to three decimals and must agree to within a thousandth,
because Java and Python round an exact decimal tie in opposite directions.

    ./gradlew testDebugUnitTest --tests 'com.cindy.tracker.LockParityTraceTest'
    .venv/bin/python tools/video_regression/lock_parity_check.py
"""
from __future__ import annotations

import csv
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from cindy_sim import pose_fixtures  # noqa: E402
from cindy_sim.athlete_lock import AthleteLock, LockContext, PoseBox  # noqa: E402
from cindy_sim.lock_fixtures import moved, scaled, with_score  # noqa: E402
from cindy_sim.pose_geometry import MIN_SCORE  # noqa: E402
from cindy_sim.rep_counter import f32  # noqa: E402
from cindy_sim.workout_engine import Exercise  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
PLAN = ROOT / "tests/parity/lock_plan.csv"
JVM = ROOT / "tests/parity/lock_trace_jvm.csv"
OUT = ROOT / "tests/parity/lock_trace_py.csv"
HEADER = ["traceId", "step", "tMs", "state", "verdict", "reason", "candidateChanged", "ambiguous",
          "probeWanted", "secondLookWanted", "steer", "refusedBox", "knownOthers", "probeExclusions", "second"]
BOX_COLUMNS = {"steer", "refusedBox", "knownOthers", "probeExclusions"}
MOVEMENTS = {"pullup": Exercise.PULLUP, "pushup": Exercise.PUSHUP, "squat": Exercise.SQUAT}


class Bar:
    def __init__(self, left, top, right, bottom):
        self.left, self.top, self.right, self.bottom = left, top, right, bottom


def pose(spec: str):
    builder, angle, dx, dy, scale, blind = spec.split(":")
    k = {"pullup": pose_fixtures.pullup, "pushup": pose_fixtures.pushup, "squat": pose_fixtures.squat}[builder](
        f32(float(angle)))
    if f32(float(scale)) != 1.0:
        k = scaled(k, f32(float(scale)))
    k = moved(k, f32(float(dx)), f32(float(dy)))
    if blind:
        k = with_score(k, 0.0, *(int(j) for j in blind.split("|")))
    return k


def bar(spec: str):
    if not spec:
        return None
    left, top, right, bottom = (f32(float(v)) for v in spec.split("|"))
    return Bar(left, top, right, bottom)


def box(b: PoseBox) -> str:
    return "|".join(f"{v:.3f}" for v in (b.left, b.top, b.right, b.bottom))


def extent(k) -> PoseBox:
    seen = [p for p in k if p.score >= MIN_SCORE]
    return PoseBox(min(p.x for p in seen), min(p.y for p in seen), max(p.x for p in seen), max(p.y for p in seen))


def replay() -> list[list[str]]:
    rows = list(csv.DictReader(PLAN.open()))
    out: list[list[str]] = []
    locks: dict[str, AthleteLock] = {}
    for step in rows:
        lock = locks.setdefault(step["traceId"], AthleteLock())
        now = int(step["tMs"])
        control = step["control"]
        if control == "beginAcquiring":
            lock.begin_acquiring(now)
        elif control == "confirm":
            lock.confirm(now)
        elif control == "lose":
            lock.lose(now, clear_stations=False)
        elif control == "loseClear":
            lock.lose(now, clear_stations=True)
        elif control == "reset":
            lock.reset()
        elif control:
            raise ValueError(f"unknown control {control!r}")
        ctx = LockContext(MOVEMENTS[step["movement"]], 480, 640, bar(step["bar"]), int(step["calibReps"]),
                          step["running"] == "1")
        probes = [pose(step["probe"])] if step["probe"] else []
        lock.on_frame(pose(step["primary"]), probes, now, ctx)
        wanted = lock.second_look_wanted
        second = ""
        if wanted and step["second"]:
            lock.reconsider(pose(step["second"]), now)
            second = f"{lock.verdict.name}/{lock.reason}"
        out.append([
            step["traceId"], step["step"], step["tMs"], lock.state.name, lock.verdict.name, lock.reason,
            str(lock.candidate_changed).lower(), str(lock.ambiguous).lower(), str(lock.probe_wanted).lower(),
            str(wanted).lower(), box(extent(lock.steer)) if lock.steer is not None else "",
            box(lock.refused_box) if lock.refused_box is not None else "",
            ";".join(box(b) for b in lock.known_others()),
            ";".join(box(b) for b in lock.probe_exclusions()),
            second,
        ])
    return out


def boxes_agree(a: str, b: str) -> bool:
    if a == b:
        return True
    pa, pb = a.split(";"), b.split(";")
    if len(pa) != len(pb):
        return False
    for x, y in zip(pa, pb):
        vx, vy = x.split("|"), y.split("|")
        if len(vx) != len(vy) or any(abs(float(i) - float(j)) > 0.0011 for i, j in zip(vx, vy)):
            return False
    return True


def main() -> int:
    ours = replay()
    with OUT.open("w", newline="") as f:
        w = csv.writer(f)
        w.writerow(HEADER)
        w.writerows(ours)
    print(f"python lock trace: {len(ours)} frames -> {OUT}")
    if not JVM.is_file():
        print(f"FAIL: no JVM trace at {JVM}; run LockParityTraceTest first")
        return 1
    theirs = list(csv.reader(JVM.open()))[1:]
    if len(theirs) != len(ours):
        print(f"FAIL: {len(theirs)} JVM frames against {len(ours)} Python frames")
        return 1
    failures = 0
    for mine, jvm in zip(ours, theirs):
        for col, a, b in zip(HEADER, mine, jvm):
            same = boxes_agree(a, b) if col in BOX_COLUMNS else a == b
            if not same:
                failures += 1
                if failures <= 20:
                    print(f"DIFF {mine[0]} step {mine[1]} {col}: python={a!r} jvm={b!r}")
    if failures:
        print(f"FAIL: {failures} differing fields")
        return 1
    print(f"PASS: python lock matches the production Kotlin lock on all {len(ours)} frames")
    return 0


if __name__ == "__main__":
    sys.exit(main())
