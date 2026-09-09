#!/usr/bin/env python3
"""Renders a timestamped contact sheet from a clip, for counting reps by eye.

Scenario labels must come from somewhere other than the pipeline being tested, or the regression
suite just asserts that today's bugs are still present. This builds a tiled, time-stamped sheet
so a human can count the reps in a clip and write the number into a scenario file.

    python3 tools/video_regression/contact_sheet.py clip.mp4 --fps 3 --grid 6x5
"""
from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path


def has_drawtext() -> bool:
    """Not every ffmpeg build ships the freetype-backed drawtext filter."""
    probe = subprocess.run(["ffmpeg", "-v", "quiet", "-filters"], capture_output=True, text=True)
    return " drawtext " in probe.stdout


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("video", type=Path)
    parser.add_argument("--fps", type=float, default=3.0, help="frames sampled per second")
    parser.add_argument("--grid", default="6x5", help="tile layout, e.g. 6x5")
    parser.add_argument("--width", type=int, default=240, help="tile width in pixels")
    parser.add_argument("--start", type=float, default=0.0, help="seek, in seconds")
    parser.add_argument("--output", type=Path, help="defaults to <video stem>_sheet.png")
    args = parser.parse_args()

    if shutil.which("ffmpeg") is None:
        print("error: ffmpeg is not installed", file=sys.stderr)
        return 2
    if not args.video.is_file():
        print(f"error: no such video: {args.video}", file=sys.stderr)
        return 2

    output = args.output or args.video.with_name(f"{args.video.stem}_sheet.png")
    # A rep counted at 4100ms in a report has to be checkable against the tile that actually
    # shows the athlete at the top, so every tile needs a known time. drawtext stamps it into the
    # image where the local ffmpeg has it; otherwise the tiles are still evenly spaced, so the
    # mapping printed below serves the same purpose.
    stamped = has_drawtext()
    chain = f"fps={args.fps},scale={args.width}:-1,"
    if stamped:
        chain += (
            r"drawtext=text='%{pts\:hms}':x=4:y=4:fontsize=14:fontcolor=yellow:"
            "box=1:boxcolor=black@0.65,"
        )
    chain += f"tile={args.grid}:margin=4:padding=3:color=black"
    command = ["ffmpeg", "-y", "-v", "error"]
    if args.start:
        command += ["-ss", str(args.start)]
    command += ["-i", str(args.video), "-vf", chain, "-frames:v", "1", str(output)]

    result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode != 0:
        print(result.stderr.strip() or "ffmpeg failed", file=sys.stderr)
        return 1
    print(output)
    columns, rows = (int(part) for part in args.grid.lower().split("x"))
    print(f"tiles: {columns}x{rows} left-to-right, top-to-bottom, {args.fps} fps")
    print(f"tile n (0-based) shows t = {args.start:g}s + n/{args.fps:g}s"
          f"; last tile = {args.start + (columns * rows - 1) / args.fps:.2f}s")
    if not stamped:
        print("note: this ffmpeg has no drawtext filter, so tiles are not stamped")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
