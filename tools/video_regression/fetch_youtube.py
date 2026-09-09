#!/usr/bin/env python3
"""Re-provisions the third-party clip fixtures described by tests/fixtures/youtube/sources.json.

The clips are not redistributable, so they are gitignored and only the manifest is committed.
This rebuilds the fixture tree from that manifest on a fresh checkout.

    python3 tools/video_regression/fetch_youtube.py            # everything still missing
    python3 tools/video_regression/fetch_youtube.py --only AB5LE7WDvcQ
"""
from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "tests/fixtures/youtube/sources.json"
# A single pre-merged file is no longer offered for most videos, so video and audio are fetched
# separately and muxed; the harness only decodes video, but yt-dlp needs a valid container.
FORMAT = "bv*[height<=720]+ba/b[height<=720]/bv*+ba/b"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--manifest", type=Path, default=MANIFEST)
    parser.add_argument("--only", nargs="*", default=[], help="restrict to these clip ids")
    parser.add_argument("--force", action="store_true", help="re-download clips already present")
    args = parser.parse_args()

    if shutil.which("yt-dlp") is None and not (ROOT / ".venv/bin/yt-dlp").is_file():
        print("error: yt-dlp is not installed", file=sys.stderr)
        return 2
    yt = str(ROOT / ".venv/bin/yt-dlp") if (ROOT / ".venv/bin/yt-dlp").is_file() else "yt-dlp"

    clips = json.loads(args.manifest.read_text())["clips"]
    if args.only:
        clips = [c for c in clips if c["id"] in set(args.only)]

    failures = 0
    for clip in clips:
        target = args.manifest.parent / clip["group"] / f"{clip['id']}.mp4"
        if target.is_file() and not args.force:
            print(f"  have {target.relative_to(ROOT)}")
            continue
        target.parent.mkdir(parents=True, exist_ok=True)
        command = [yt, "-f", FORMAT, "--merge-output-format", "mp4", "--no-playlist",
                   "-o", str(target.with_suffix(".%(ext)s")),
                   f"https://www.youtube.com/watch?v={clip['id']}"]
        result = subprocess.run(command, capture_output=True, text=True)
        if result.returncode == 0 and target.is_file():
            print(f"  got  {target.relative_to(ROOT)}")
        else:
            failures += 1
            reason = (result.stderr or "").strip().splitlines()[-1:] or ["unknown error"]
            print(f"  FAIL {clip['id']}: {reason[0]}", file=sys.stderr)

    if failures:
        print(f"\n{failures} clip(s) could not be fetched; they may have been removed upstream.",
              file=sys.stderr)
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
