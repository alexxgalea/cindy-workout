#!/usr/bin/env python3
"""Runs the recogniser over films: where the athlete was, and which movement it recognised, per frame.

The recogniser is the Python twin of the phone's (`cindy_sim/recogniser.py`, held to the Kotlin by
`recognition_parity_check.py`), so what this reports about a film is what the camera screen's
debug line would have said at the gym. Nothing here touches the workout's counting.

A scenario may carry `positionWindows`, labels for where the athlete really was:

    {"label": "kneeling rest", "fromMs": 36500, "toMs": 40500, "never": ["standing"]}
    {"label": "squats", "fromMs": 58000, "toMs": 78000, "always": "standing"}

`always` names the one position every frame of the window must be in, `never` the positions no
frame of it may be in. A window is half open: its first frame is in, its `toMs` frame is out.
The run exits 1 when any window fails.

A scenario may also carry `movementWindows`, labels for what the athlete was really doing:

    {"label": "push-ups", "fromMs": 29000, "toMs": 52500, "movement": "pushup"}
    {"label": "the walk to the mat", "fromMs": 24000, "toMs": 28500, "movement": "none"}

A movement is confirmed at one moment, when recognition first names it. The run prints each
confirmation with its time and the real rep it came at, counted from the scenario's
`labelledBottomsMs` (the labels are good to a fraction of a second, so a rep labelled up to
REP_SLACK_MS after the confirmation counts as already done). It fails on a confirmation inside a
window of another movement, inside a `none` window or inside no window, and on a movement window in
which that movement was never confirmed.

    python3 tools/video_regression/run_recognition.py --scenarios tests/scenarios/cindy.json
    python3 tools/video_regression/run_recognition.py --video clip.mp4
"""
from __future__ import annotations

import argparse
import csv
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Sequence

sys.path.insert(0, str(Path(__file__).resolve().parent))

from cindy_sim.recogniser import Movement, Position, Recognition, Recogniser
from cindy_sim.workout_engine import STANDARD_PROFILE, CindyProfile, PullVariant

#: The labels' names for the movements, as `labelledBottomsMs` and `movementWindows` spell them.
MOVEMENT_KEYS = {"pullup": Movement.PULL_UPS, "pushup": Movement.PUSH_UPS, "squat": Movement.SQUATS}
#: A labelled rep this much after a confirmation counts as done by it: labels are not to the frame.
REP_SLACK_MS = 250

ROOT = Path(__file__).resolve().parents[2]


@dataclass
class Frame:
    timestamp_ms: int
    keypoints: Sequence
    #: What the app passes as `identityStable`; the harness reads it one frame early, as the app does.
    tracking_stable: bool


def track_recognitions(
    frames: Sequence[Frame], profile: CindyProfile = STANDARD_PROFILE
) -> list[tuple[int, Recognition]]:
    """What recognition made of the film after every frame, with the frame's time."""
    recogniser = Recogniser(profile)
    return [
        (frame.timestamp_ms, recogniser.on_frame(frame.keypoints, frame.timestamp_ms, frame.tracking_stable))
        for frame in frames
    ]


def track_positions(
    frames: Sequence[Frame], profile: CindyProfile = STANDARD_PROFILE
) -> list[tuple[int, Position]]:
    """The position after every frame, with the frame's time."""
    return [(t, recognition.position) for t, recognition in track_recognitions(frames, profile)]


def confirmations(track: Sequence[tuple[int, Recognition]]) -> list[tuple[int, Movement]]:
    """Each moment recognition first names a movement it was not naming on the frame before."""
    out: list[tuple[int, Movement]] = []
    named: Movement | None = None
    for t, recognition in track:
        if recognition.movement is not None and recognition.movement is not named:
            out.append((t, recognition.movement))
        named = recognition.movement
    return out


def real_rep(labelled_ms: Sequence[int], at_ms: int) -> int:
    """How many labelled reps had been done when a movement was confirmed at `at_ms`."""
    return sum(1 for t in labelled_ms if t <= at_ms + REP_SLACK_MS)


def check_movement_windows(
    confirmed: Sequence[tuple[int, Movement]], windows: Sequence[dict]
) -> list[str]:
    """One message per wrong confirmation and per movement window never confirmed."""
    failures: list[str] = []
    for t, movement in confirmed:
        inside = [w for w in windows if w["fromMs"] <= t < w["toMs"]]
        label = ", ".join(w.get("label", w["movement"]) for w in inside)
        if not inside:
            failures.append(f"wrong confirmation: {movement.label} at {t} ms, inside no window")
        elif all(MOVEMENT_KEYS.get(w["movement"]) is not movement for w in inside):
            failures.append(f"wrong confirmation: {movement.label} at {t} ms, in the window '{label}'")
    for window in windows:
        wanted = MOVEMENT_KEYS.get(window["movement"])
        if wanted is None:
            continue
        label = window.get("label", window["movement"])
        if not any(m is wanted and window["fromMs"] <= t < window["toMs"] for t, m in confirmed):
            failures.append(f"{label}: {wanted.label} was never confirmed between "
                            f"{window['fromMs']} and {window['toMs']} ms")
    return failures


def runs(track: Sequence[tuple[int, Position]]) -> list[tuple[int, int, Position]]:
    """Each stretch of one position as (from, to, position), where `to` is when the next begins."""
    out: list[tuple[int, int, Position]] = []
    for t, position in track:
        if out and out[-1][2] is position:
            continue
        if out:
            out[-1] = (out[-1][0], t, out[-1][2])
        out.append((t, t, position))
    if out and track:
        out[-1] = (out[-1][0], track[-1][0], out[-1][2])
    return out


def check_windows(track: Sequence[tuple[int, Position]], windows: Sequence[dict]) -> list[str]:
    """One message per window that fails; an empty list is a pass."""
    failures: list[str] = []
    for window in windows:
        label = window.get("label", f"{window['fromMs']}-{window['toMs']} ms")
        always = window.get("always")
        never = list(window.get("never") or [])
        if always is None and not never:
            failures.append(f"{label}: the window asks for nothing (needs 'always' or 'never')")
            continue
        inside = [(t, p) for t, p in track if window["fromMs"] <= t < window["toMs"]]
        if not inside:
            failures.append(f"{label}: no frames between {window['fromMs']} and {window['toMs']} ms")
            continue
        if always is not None:
            wrong = [(t, p) for t, p in inside if p.id != always]
            if wrong:
                t, p = wrong[0]
                failures.append(
                    f"{label}: {len(wrong)} of {len(inside)} frames not {always}; "
                    f"first at {t} ms, which is {p.id}")
        for forbidden in never:
            seen = [t for t, p in inside if p.id == forbidden]
            if seen:
                failures.append(
                    f"{label}: {len(seen)} of {len(inside)} frames {forbidden}; first at {seen[0]} ms")
    return failures


def write_recognitions(track: Sequence[tuple[int, Recognition]], path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as fh:
        writer = csv.writer(fh)
        writer.writerow(["timestampMs", "position", "movement", "candidate", "candidateReps",
                         "tallyPullUps", "tallyPushUps", "tallySquats"])
        writer.writerows(
            (t, r.position.id, r.movement.id if r.movement else "none",
             r.candidate.id if r.candidate else "none", r.candidate_reps, *r.tally)
            for t, r in track)


def infer(video: Path, scenario: dict) -> list[Frame] | str:
    """The film's frames, or why they cannot be had. Imported late: it needs OpenCV and the model."""
    import run_batch

    model = run_batch.MODELS.get((scenario.get("model") or "").lower() or None)
    if model is None:
        return f"unsupported model '{scenario.get('model')}'"
    errors: list[str] = []
    inferred = run_batch.infer_video(video, model, errors, scenario.get("light"))
    if not inferred:
        return "; ".join(errors) or "no frames"
    return [Frame(f.timestamp_ms, f.keypoints, f.tracking_stable) for f in inferred]


def profile_of(pull: str | None) -> CindyProfile:
    """The recogniser's profile: the athlete's variations, strict unless the run says otherwise."""
    if pull is None:
        return STANDARD_PROFILE
    return CindyProfile(pull=PullVariant[pull.upper()])


def run_scenario(scenario: dict, out_dir: Path, pull: str | None = None) -> bool:
    video = Path(scenario["video"])
    if not video.is_absolute():
        video = ROOT / video
    print(f"\nScenario: {scenario['id']}")
    if not video.is_file():
        print(f"  missing fixture: {video}")
        return False
    frames = infer(video, scenario)
    if isinstance(frames, str):
        print(f"  {frames}")
        return False

    recognitions = track_recognitions(frames, profile_of(pull))
    track = [(t, r.position) for t, r in recognitions]
    target = out_dir / f"{scenario['id']}.positions.csv"
    write_recognitions(recognitions, target)
    print(f"  {len(track)} frames -> {target}")
    for start, end, position in runs(track):
        print(f"  {start / 1000:7.2f}s - {end / 1000:6.2f}s  {position.id}")

    windows = scenario.get("positionWindows") or []
    failures = check_windows(track, windows)
    print(f"  Windows: {len(windows) - len(failures)} of {len(windows)} held")
    for failure in failures:
        print(f"    - {failure}")

    confirmed = confirmations(recognitions)
    labelled = scenario.get("labelledBottomsMs") or {}
    print(f"  Confirmations ({pull or 'standard profile'}):")
    for t, movement in confirmed:
        key = next(k for k, m in MOVEMENT_KEYS.items() if m is movement)
        times = labelled.get(key) or []
        rep = f"at real rep {real_rep(times, t)} of {len(times)}" if times else "(no labelled reps)"
        print(f"    {t / 1000:7.2f}s  {movement.label}  {rep}")
    if not confirmed:
        print("    none")
    movement_windows = scenario.get("movementWindows") or []
    move_failures = check_movement_windows(confirmed, movement_windows) if movement_windows else []
    if movement_windows:
        print(f"  Movement windows: {len(movement_windows)} labelled, {len(move_failures)} failure(s)")
    for failure in move_failures:
        print(f"    - {failure}")
    return not failures and not move_failures


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--scenarios", type=Path, nargs="*", default=[],
                        help="catalogues to read; only scenarios with positionWindows or movementWindows are run")
    parser.add_argument("--pull", choices=["strict_pull_up", "band_assisted_pull_up"],
                        help="the pull-up variation recognition is built with (default: strict)")
    parser.add_argument("--video", type=Path, help="write the positions of a single clip, unchecked")
    parser.add_argument("--out", type=Path, default=ROOT / "tests/reports/recognition")
    args = parser.parse_args()

    if args.video:
        scenarios = [{"id": args.video.stem, "video": str(args.video)}]
    else:
        import run_batch

        paths = args.scenarios or sorted((ROOT / "tests/scenarios").glob("*.json"))
        scenarios = [s for s in run_batch.load_catalogues(paths) if s.get("positionWindows") or s.get("movementWindows")]
    if not scenarios:
        print("No scenarios with positionWindows or movementWindows to run.", file=sys.stderr)
        return 2

    results = [run_scenario(scenario, args.out, args.pull) for scenario in scenarios]
    print("\n" + "=" * 62)
    print(f"{sum(results)} of {len(results)} scenarios held every window and confirmed every movement")
    return 0 if all(results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
