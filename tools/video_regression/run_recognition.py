#!/usr/bin/env python3
"""Runs the position recogniser over films and writes where the athlete was on every frame.

The recogniser is the Python twin of the phone's (`cindy_sim/recogniser.py`, held to the Kotlin by
`recognition_parity_check.py`), so what this reports about a film is what the camera screen's
debug line would have said at the gym. Nothing here counts a rep or touches the counting engine.

A scenario may carry `positionWindows`, labels for where the athlete really was:

    {"label": "kneeling rest", "fromMs": 36500, "toMs": 40500, "never": ["standing"]}
    {"label": "squats", "fromMs": 58000, "toMs": 78000, "always": "standing"}

`always` names the one position every frame of the window must be in, `never` the positions no
frame of it may be in. A window is half open: its first frame is in, its `toMs` frame is out.
The run exits 1 when any window fails.

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

from cindy_sim.recogniser import Position, Recogniser

ROOT = Path(__file__).resolve().parents[2]


@dataclass
class Frame:
    timestamp_ms: int
    keypoints: Sequence
    #: What the app passes as `identityStable`; the harness reads it one frame early, as the app does.
    tracking_stable: bool


def track_positions(frames: Sequence[Frame]) -> list[tuple[int, Position]]:
    """The position after every frame, with the frame's time."""
    recogniser = Recogniser()
    return [
        (frame.timestamp_ms,
         recogniser.on_frame(frame.keypoints, frame.timestamp_ms, frame.tracking_stable).position)
        for frame in frames
    ]


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


def write_positions(track: Sequence[tuple[int, Position]], path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as fh:
        writer = csv.writer(fh)
        writer.writerow(["timestampMs", "position"])
        writer.writerows((t, position.id) for t, position in track)


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


def run_scenario(scenario: dict, out_dir: Path) -> bool:
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

    track = track_positions(frames)
    target = out_dir / f"{scenario['id']}.positions.csv"
    write_positions(track, target)
    print(f"  {len(track)} frames -> {target}")
    for start, end, position in runs(track):
        print(f"  {start / 1000:7.2f}s - {end / 1000:6.2f}s  {position.id}")

    windows = scenario.get("positionWindows") or []
    failures = check_windows(track, windows)
    print(f"  Windows: {len(windows) - len(failures)} of {len(windows)} held")
    for failure in failures:
        print(f"    - {failure}")
    return not failures


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--scenarios", type=Path, nargs="*", default=[],
                        help="catalogues to read; only scenarios with positionWindows are run")
    parser.add_argument("--video", type=Path, help="write the positions of a single clip, unchecked")
    parser.add_argument("--out", type=Path, default=ROOT / "tests/reports/recognition")
    args = parser.parse_args()

    if args.video:
        scenarios = [{"id": args.video.stem, "video": str(args.video)}]
    else:
        import run_batch

        paths = args.scenarios or sorted((ROOT / "tests/scenarios").glob("*.json"))
        scenarios = [s for s in run_batch.load_catalogues(paths) if s.get("positionWindows")]
    if not scenarios:
        print("No scenarios with positionWindows to run.", file=sys.stderr)
        return 2

    results = [run_scenario(scenario, args.out) for scenario in scenarios]
    print("\n" + "=" * 62)
    print(f"{sum(results)} of {len(results)} scenarios held every window")
    return 0 if all(results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
