#!/usr/bin/env python3
"""Create Cindy video-regression catalogues from locally provisioned datasets.

No data is downloaded. Use --copy-videos only for data your licence allows to live under the
ignored tests/fixtures tree; inspect the resulting labels before making them test expectations.
"""
from __future__ import annotations

import argparse
import json
import math
import shutil
import sys
from pathlib import Path
from typing import Any, Iterator


INFINITE = {"pushup": ("pushups", "pushup"), "pushups": ("pushups", "pushup"),
            "squat": ("squats", "squat"), "squats": ("squats", "squat")}
REPCOUNT = {"pulling-up": ("pullups", "pullup"), "pullup": ("pullups", "pullup"),
            "squatting": ("squats", "squat"), "squat": ("squats", "squat")}
VIDEO_KEYS = ("video", "video_path", "video_file", "filename", "file_name", "path")
FPS_KEYS = ("fps", "frame_rate", "framerate", "video_fps")


def read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def walk(value: Any) -> Iterator[dict[str, Any]]:
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from walk(child)
    elif isinstance(value, list):
        for child in value:
            yield from walk(child)


def first(document: Any, keys: tuple[str, ...]) -> Any | None:
    wanted = {key.lower() for key in keys}
    for node in walk(document):
        for key, value in node.items():
            if key.lower() in wanted and value not in (None, ""):
                return value
    return None


def numbers(value: Any) -> list[float]:
    if isinstance(value, bool):
        return []
    if isinstance(value, (float, int)):
        return [float(value)] if math.isfinite(float(value)) else []
    if isinstance(value, list):
        return [number for item in value for number in numbers(item)]
    return []


def key_numbers(document: Any, wanted: str) -> list[float]:
    return [number for node in walk(document) for key, value in node.items()
            if key.lower() == wanted.lower() for number in numbers(value)]


def tag_metadata(document: Any) -> list[str]:
    tags = []
    for key in ("camera_pitch", "camera_height", "percent_in_fov", "percent_occlusion"):
        value = first(document, (key,))
        if value is not None:
            tags.append(f"{key}={value}")
    return tags


def action_from_path(path: Path) -> tuple[str, str] | None:
    for part in reversed(path.parts):
        key = part.lower().replace("_", "-").replace(" ", "-")
        if key in INFINITE:
            return INFINITE[key]
        if key.rstrip("s") in INFINITE:
            return INFINITE[key.rstrip("s")]
    return None


def fixture_path(source: Path, root: Path, group: str) -> Path:
    # Dataset IDs repeat across subject folders, so retain enough ancestry to make collisions rare.
    name = "_".join(source.with_suffix("").parts[-3:]).replace(" ", "_") + source.suffix.lower()
    return root / group / name


def copy_if_requested(source: Path, target: Path, enabled: bool, warnings: list[str]) -> None:
    if not enabled:
        return
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists():
        if target.stat().st_size != source.stat().st_size:
            warnings.append(f"not overwriting different fixture: {target}")
        return
    shutil.copy2(source, target)


def infiniterep(dataset: Path, fixture_root: Path, copy_videos: bool) -> tuple[list[dict[str, Any]], list[str]]:
    scenarios, warnings = [], []
    for video in sorted(dataset.rglob("*.mp4")):
        action = action_from_path(video.parent)
        if action is None:
            continue
        group, exercise = action
        annotation = video.with_suffix(".json")
        if not annotation.exists():
            warnings.append(f"missing paired annotation: {video}")
            continue
        try:
            document = read_json(annotation)
        except (OSError, json.JSONDecodeError) as error:
            warnings.append(f"cannot parse {annotation}: {error}")
            continue
        rep_count = key_numbers(document, "rep_count")
        if not rep_count:
            warnings.append(f"no valid rep_count in {annotation}")
            continue
        target = fixture_path(video, fixture_root, group)
        copy_if_requested(video, target, copy_videos, warnings)
        scenarios.append({
            "id": f"infiniterep_{group}_{video.stem}",
            "video": target.as_posix(),
            "exercise": exercise,
            "expectedReps": math.floor(rep_count[-1]),
            "expectedSetup": "valid",
            "tags": ["infiniterep", group, *tag_metadata(document)],
        })
    return scenarios, warnings


def action_name(node: dict[str, Any]) -> str | None:
    for key in ("action_type", "action", "activity", "label", "class"):
        value = node.get(key)
        if isinstance(value, str):
            return value.lower().replace("_", "-").replace(" ", "-")
    return None


def frame_rate(node: dict[str, Any], document: Any) -> float | None:
    try:
        value = first(node, FPS_KEYS) or first(document, FPS_KEYS)
        return float(value) if float(value) > 0 else None
    except (TypeError, ValueError):
        return None


def paired_video(node: dict[str, Any], annotation: Path, dataset: Path) -> Path | None:
    value = first(node, VIDEO_KEYS)
    candidates = [annotation.with_suffix(".mp4")]
    if isinstance(value, str):
        candidates = [Path(value), annotation.parent / value, dataset / value, *candidates]
    return next((path.resolve() for path in candidates
                 if path.exists() and path.suffix.lower() in {".mp4", ".mov", ".avi"}), None)


def period_end(value: Any) -> float | None:
    if isinstance(value, dict):
        for key in ("end_ms", "end_time_ms", "end", "stop", "frame_end", "end_frame"):
            if key in value and numbers(value[key]):
                return numbers(value[key])[-1]
    found = numbers(value)
    return found[-1] if found else None


def cycle_events(node: dict[str, Any], document: Any) -> list[int]:
    """Turn RepCount cycle locations/action-period endpoints into timestamps in milliseconds."""
    locations: list[tuple[float, bool]] = []
    for key in ("cycle_locations_ms", "cycle_location_ms", "cycle_times_ms"):
        locations.extend((value, True) for value in numbers(node.get(key)))
    for key in ("cycle_locations", "cycle_location", "cycles"):
        value = node.get(key)
        if isinstance(value, list) and value and isinstance(value[0], dict):
            locations.extend((end, False) for item in value if (end := period_end(item)) is not None)
        else:
            locations.extend((value, False) for value in numbers(value))
    if not locations:
        for key in ("action_periods", "periods", "actions"):
            value = node.get(key)
            if isinstance(value, list):
                locations.extend((end, False) for item in value if (end := period_end(item)) is not None)
    fps = frame_rate(node, document)
    return sorted(set(round(value) if milliseconds else round(value * 1000 / fps)
                      for value, milliseconds in locations if milliseconds or fps))


def repcount(dataset: Path, fixture_root: Path, copy_videos: bool) -> tuple[list[dict[str, Any]], list[str]]:
    scenarios, warnings = [], []
    for annotation in sorted(dataset.rglob("*.json")):
        try:
            document = read_json(annotation)
        except (OSError, json.JSONDecodeError) as error:
            warnings.append(f"cannot parse {annotation}: {error}")
            continue
        for index, node in enumerate(walk(document)):
            action = action_name(node)
            if action not in REPCOUNT:
                continue
            group, exercise = REPCOUNT[action]
            video, events = paired_video(node, annotation, dataset), cycle_events(node, document)
            if video is None or not events:
                warnings.append(f"skipping {annotation} action {index}: missing video or cycle locations/FPS")
                continue
            target = fixture_path(video, fixture_root, group)
            copy_if_requested(video, target, copy_videos, warnings)
            scenarios.append({
                "id": f"repcount_{group}_{annotation.stem}_{index}",
                "video": target.as_posix(),
                "exercise": exercise,
                "expectedReps": len(events),
                "expectedRepEventsMs": events,
                "expectedSetup": "valid",
                "tags": ["repcount", group, f"action={action}"],
            })
    return scenarios, warnings


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", choices=("infiniterep", "repcount"))
    parser.add_argument("--dataset", required=True, type=Path)
    parser.add_argument("--fixture-root", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--copy-videos", action="store_true")
    args = parser.parse_args()
    if not args.dataset.is_dir():
        parser.error(f"dataset directory does not exist: {args.dataset}")
    builder = infiniterep if args.source == "infiniterep" else repcount
    scenarios, warnings = builder(args.dataset.resolve(), args.fixture_root, args.copy_videos)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps({"version": 1, "source": args.source, "scenarios": scenarios}, indent=2) + "\n")
    print(f"wrote {len(scenarios)} {args.source} scenario(s) to {args.output}")
    for warning in warnings:
        print(f"warning: {warning}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
