#!/usr/bin/env python3
"""Diffs the Python Freestyle twin in cindy_sim against the production Kotlin one, frame by frame.

A Freestyle is counted by recognition and banks what it counts (ADR 0010). The harness scores films
with the Python twin, so this is the gate that keeps it honest: the Kotlin FreestyleParityTraceTest
and this script run the same sessions and the two traces must agree on every column, and on the
sets and gaps derived at STOP. It is separate from parity_check.py and recognition_parity_check.py,
which hold the counting engine and recognition to their own traces; it reads, and never changes, theirs.

Sessions are the traces of tests/parity/recognition_plan.csv and tests/parity/freestyle_plan.csv
(committed, synthetic) and, when they exist, the films. A film is the keypoints the harness inferred,
dumped to tests/parity/films/<id>.csv (local, never committed), so both languages read the same
numbers and the pose model is not in the comparison. Films and the clip are the labelled scenarios of
tests/scenarios whose files can be found.

    python3 tools/video_regression/freestyle_parity_check.py --dump-films   # needs the films, OpenCV, the model
    ./gradlew testDebugUnitTest --tests 'com.cindy.tracker.FreestyleParityTraceTest'
    python3 tools/video_regression/freestyle_parity_check.py

Exits non-zero on the first frames that disagree, naming the trace, frame and column. With no film
dumps it checks the committed plan traces only and says so.
"""
from __future__ import annotations

import argparse
import csv
import math
import sys
from pathlib import Path
from typing import Sequence

sys.path.insert(0, str(Path(__file__).resolve().parent))

from cindy_sim import pose_fixtures
from cindy_sim.freestyle import FreestyleEngine, FiledSession
from cindy_sim.keypoints import Keypoint
from cindy_sim.recogniser import Movement
from cindy_sim.rep_counter import f32
from cindy_sim.workout_engine import STANDARD_PROFILE, CindyProfile, PullVariant, PushVariant, SquatVariant

ROOT = Path(__file__).resolve().parents[2]

TRACE_HEADER = [
    "traceId", "step", "tMs", "builder", "angle", "stable", "kpSum", "figure", "movement", "movementTotal",
    "adjustable", "line", "bankedPullUps", "bankedPushUps", "bankedSquats", "voice",
]
SETS_HEADER = ["traceId", "kind", "index", "what", "reps", "startMs", "endMs"]
JOINTS = 17


def rounded(value: float) -> str:
    return "nan" if math.isnan(value) else f"{value:.3f}"


def flag(value: bool) -> str:
    return "true" if value else "false"


class Row:
    """One input frame of a session: what the engine is fed, and how the trace labels it."""

    def __init__(self, trace_id: str, step: str, t_ms: int, builder: str, angle: str, stable: bool,
                 keypoints: Sequence[Keypoint]) -> None:
        self.trace_id, self.step, self.t_ms, self.builder = trace_id, step, t_ms, builder
        self.angle, self.stable, self.keypoints = angle, stable, keypoints


def plan_sessions(plan_path: Path) -> list[tuple[CindyProfile, list[Row]]]:
    with plan_path.open(newline="") as fh:
        rows = list(csv.DictReader(fh))
    out = []
    for trace_id in dict.fromkeys(row["traceId"] for row in rows):
        steps = [row for row in rows if row["traceId"] == trace_id]
        profile = CindyProfile(pull=PullVariant[steps[0]["pull"]], push=PushVariant[steps[0]["push"]],
                               squat=SquatVariant[steps[0]["squat"]])
        out.append((profile, [
            Row(trace_id, s["step"], int(s["tMs"]), s["builder"], s["angle"], s["stable"] == "true",
                pose_fixtures.BUILDERS[s["builder"]](f32(float(s["angle"]))))
            for s in steps]))
    return out


def dump_film(frames, path: Path) -> None:
    """Writes a film's keypoints, rounded to the Floats the phone holds, one frame per line."""
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as fh:
        writer = csv.writer(fh)
        writer.writerow(["tMs", "stable"] + [f"{a}{j}" for j in range(JOINTS) for a in "xys"])
        for frame in frames:
            cells: list[str] = []
            for p in frame.keypoints:
                cells += [repr(f32(p.x)), repr(f32(p.y)), repr(f32(p.score))]
            writer.writerow([frame.timestamp_ms, flag(frame.tracking_stable)] + cells)


def film_sessions(directory: Path) -> list[tuple[CindyProfile, list[Row]]]:
    out = []
    for path in sorted(directory.glob("*.csv")):
        with path.open(newline="") as fh:
            reader = csv.reader(fh)
            next(reader)
            frames = []
            for i, cells in enumerate(reader):
                keypoints = [Keypoint(float(cells[2 + 3 * j]), float(cells[3 + 3 * j]), float(cells[4 + 3 * j]))
                             for j in range(JOINTS)]
                frames.append(Row(path.stem, str(i), int(cells[0]), "film", "0", cells[1] == "true", keypoints))
        out.append((STANDARD_PROFILE, frames))
    return out


def run_session(profile: CindyProfile, frames: Sequence[Row]) -> tuple[list[list[str]], list[list[str]], FiledSession | None]:
    """The Freestyle trace of one session, its sets rows, and what STOP filed."""
    engine = FreestyleEngine(profile)
    engine.start(frames[0].t_ms)
    banked = {m: 0 for m in Movement}
    trace: list[list[str]] = []
    for f in frames:
        out = engine.on_frame(f.keypoints, f.t_ms, f.stable)
        for movement, reps in out.banked:
            banked[movement] += reps
        voice = "|".join(f"confirmed:{m.id}:{n}" if kind == "confirmed" else f"count:{n}" for kind, m, n in out.voice)
        trace.append([
            f.trace_id, f.step, str(f.t_ms), f.builder, f.angle, flag(f.stable),
            rounded(sum(f32(p.x + p.y) for p in f.keypoints)),
            str(out.figure), out.movement.id if out.movement else "none", str(out.movement_total),
            flag(out.adjustable), out.line,
            str(banked[Movement.PULL_UPS]), str(banked[Movement.PUSH_UPS]), str(banked[Movement.SQUATS]), voice,
        ])
    trace_id = frames[0].trace_id
    filed = engine.stop(frames[-1].t_ms)
    if filed is None:
        return trace, [[trace_id, "filed", "0", "none", "0", "0", "0"]], None
    sets = [[trace_id, "filed", "0", "none", str(filed.total_reps), str(filed.duration_ms), str(len(filed.marks))]]
    sets += [[trace_id, "set", str(i), s.movement.name.lower(), str(s.reps), str(s.start_ms), str(s.end_ms)]
             for i, s in enumerate(filed.sets)]
    sets += [[trace_id, "gap", str(i), g.kind.value, "0", str(g.start_ms), str(g.end_ms)]
             for i, g in enumerate(filed.gaps)]
    return trace, sets, filed


def run_all(sessions) -> tuple[list[list[str]], list[list[str]]]:
    trace: list[list[str]] = []
    sets: list[list[str]] = []
    for profile, frames in sessions:
        t, s, _ = run_session(profile, frames)
        trace += t
        sets += s
    return trace, sets


def write(path: Path, header: list[str], rows: list[list[str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as fh:
        writer = csv.writer(fh, quoting=csv.QUOTE_ALL, lineterminator="\n")
        writer.writerow(header)
        writer.writerows(rows)


def compare(name: str, header: list[str], want: list[list[str]], got: list[list[str]], limit: int) -> int:
    """Prints how the two traces compare; returns how many fields differ (or 1 for a length mismatch)."""
    if len(want) != len(got):
        print(f"FAIL {name}: JVM has {len(want)} rows, python produced {len(got)}", file=sys.stderr)
        return 1
    mismatches = []
    for w, g in zip(want, got):
        for column, column_name in enumerate(header):
            if w[column] != g[column]:
                mismatches.append(f"{g[0]} row {g[1]} (t={g[2]}): {column_name} jvm={w[column]!r} python={g[column]!r}")
    if mismatches:
        print(f"FAIL {name}: {len(mismatches)} field(s) differ across {len(got)} rows", file=sys.stderr)
        for line in mismatches[:limit]:
            print(f"  {line}", file=sys.stderr)
        if len(mismatches) > limit:
            print(f"  ... and {len(mismatches) - limit} more", file=sys.stderr)
        return len(mismatches)
    print(f"PASS {name}: {len(got)} rows match")
    return 0


def read_reference(path: Path, header: list[str]) -> list[list[str]] | None:
    if not path.is_file():
        return None
    with path.open(newline="") as fh:
        rows = list(csv.reader(fh))
    return rows[1:] if rows and rows[0] == header else rows


def labelled_scenarios() -> list[dict]:
    import run_batch

    catalogues = ROOT / "tests/scenarios"
    paths = sorted(catalogues.glob("*.json")) + sorted(catalogues.glob("recognition/*.json"))
    return [s for s in run_batch.load_catalogues(paths) if s.get("movementWindows")]


def dump_films(directory: Path) -> int:
    import run_recognition

    done = 0
    for scenario in labelled_scenarios():
        video = Path(scenario["video"])
        video = video if video.is_absolute() else ROOT / video
        if not video.is_file():
            print(f"skipped {scenario['id']}: missing film {video}")
            continue
        frames = run_recognition.infer(video, scenario)
        if isinstance(frames, str):
            print(f"skipped {scenario['id']}: {frames}")
            continue
        dump_film(frames, directory / f"{scenario['id']}.csv")
        print(f"dumped {scenario['id']}: {len(frames)} frames")
        done += 1
    return done


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--parity", type=Path, default=ROOT / "tests/parity")
    parser.add_argument("--dump-films", action="store_true", help="infer the labelled films and dump their keypoints")
    parser.add_argument("--max-report", type=int, default=15)
    args = parser.parse_args()
    parity = args.parity

    if args.dump_films:
        dump_films(parity / "films")

    plans = [parity / "recognition_plan.csv", parity / "freestyle_plan.csv"]
    for plan in plans:
        if not plan.is_file():
            print(f"error: missing plan at {plan}", file=sys.stderr)
            return 2
    sessions = [s for plan in plans for s in plan_sessions(plan)]
    trace, sets = run_all(sessions)
    write(parity / "freestyle_trace_py.csv", TRACE_HEADER, trace)
    write(parity / "freestyle_sets_py.csv", SETS_HEADER, sets)

    failures = 0
    suites = [("plans", "freestyle_trace_jvm.csv", "freestyle_sets_jvm.csv", trace, sets)]
    films = film_sessions(parity / "films") if (parity / "films").is_dir() else []
    if films:
        film_trace, film_sets = run_all(films)
        write(parity / "freestyle_film_trace_py.csv", TRACE_HEADER, film_trace)
        write(parity / "freestyle_film_sets_py.csv", SETS_HEADER, film_sets)
        suites.append((f"{len(films)} film(s)", "freestyle_film_trace_jvm.csv", "freestyle_film_sets_jvm.csv",
                       film_trace, film_sets))
    else:
        print("no film dumps in tests/parity/films: films and the clip were NOT compared")

    for label, trace_name, sets_name, got_trace, got_sets in suites:
        want_trace = read_reference(parity / trace_name, TRACE_HEADER)
        want_sets = read_reference(parity / sets_name, SETS_HEADER)
        if want_trace is None or want_sets is None:
            print(f"error: no reference trace for {label} ({trace_name}). Generate it with:\n"
                  "  ./gradlew testDebugUnitTest --tests 'com.cindy.tracker.FreestyleParityTraceTest'", file=sys.stderr)
            return 2
        failures += compare(f"{label} trace", TRACE_HEADER, want_trace, got_trace, args.max_report)
        failures += compare(f"{label} sets", SETS_HEADER, want_sets, got_sets, args.max_report)
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
