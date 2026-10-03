#!/usr/bin/env python3
"""
Renders the Google Play store graphics from their SVG sources, and checks them against Play's rules.

    tools/play/render_graphics.py

Reads play/graphics/icon.svg and feature-graphic.svg and writes icon.png and feature-graphic.png
beside them. Play wants the icon as a 512 x 512 32-bit PNG under 1 MB, and the feature graphic as a
1024 x 500 PNG or JPEG with no transparency, so the script ends by reading each file's header back
and exits 1 if either rule is broken.

Needs a Chromium or Chrome to draw the SVG, because only a browser loads the app's own Manrope font
from the SVG's @font-face rule, and ImageMagick's `convert` to fix the pixel format. Set CHROME to
a binary to use another. Standard library otherwise.
"""

import glob
import os
import pathlib
import shutil
import struct
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
GRAPHICS = ROOT / "play" / "graphics"

# name, width, height, ImageMagick output format, may it be transparent
ASSETS = [
    ("icon", 512, 512, "PNG32", True),
    ("feature-graphic", 1024, 500, "PNG24", False),
]


def find_chrome() -> str:
    candidates = [os.environ.get("CHROME", "")]
    candidates += sorted(glob.glob("/opt/pw-browsers/chromium-*/chrome-linux/chrome"), reverse=True)
    candidates += [shutil.which(n) or "" for n in ("chromium", "chromium-browser", "google-chrome")]
    for c in candidates:
        if c and os.access(c, os.X_OK):
            return c
    sys.exit("render_graphics.py: no Chromium found; set CHROME to one")


def png_header(path: pathlib.Path):
    """Width, height, bit depth and colour type from the IHDR chunk."""
    data = path.read_bytes()[:33]
    if data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        raise ValueError(f"{path.name} is not a PNG")
    w, h, depth, colour = struct.unpack(">IIBB", data[16:26])
    return w, h, depth, colour


def render(chrome: str, name: str, w: int, h: int, fmt: str) -> pathlib.Path:
    svg = GRAPHICS / f"{name}.svg"
    out = GRAPHICS / f"{name}.png"
    with tempfile.TemporaryDirectory() as tmp:
        shot = pathlib.Path(tmp) / "shot.png"
        subprocess.run(
            [chrome, "--headless", "--no-sandbox", "--disable-gpu", "--hide-scrollbars",
             # The window is taller than the page it shows: browser chrome takes some of it even
             # headless, and a window of exactly w x h gives a viewport shorter than h and a
             # clipped graphic. Ask for slack and crop to the real size from the top.
             "--force-device-scale-factor=1", f"--window-size={w},{h + 200}",
             "--allow-file-access-from-files", f"--screenshot={shot}", svg.as_uri()],
            check=True, capture_output=True, timeout=120,
        )
        # Chromium's screenshot is the window, which can be taller than the page; crop to the
        # graphic, flatten onto its own black so there is no stray transparency, and fix the format.
        subprocess.run(
            ["convert", str(shot), "-crop", f"{w}x{h}+0+0", "+repage",
             "-background", "black", "-alpha", "remove", "-alpha", "off",
             f"{fmt}:{out}"],
            check=True,
        )
    return out


def verify(name: str, w: int, h: int, may_be_transparent: bool) -> list:
    path = GRAPHICS / f"{name}.png"
    problems = []
    gw, gh, depth, colour = png_header(path)
    if (gw, gh) != (w, h):
        problems.append(f"{name}.png is {gw} x {gh}, Play wants {w} x {h}")
    if depth != 8:
        problems.append(f"{name}.png has bit depth {depth}, expected 8")
    has_alpha = colour in (4, 6)
    if name == "icon" and not has_alpha:
        problems.append("icon.png should be a 32-bit PNG (RGBA)")
    if not may_be_transparent and has_alpha:
        problems.append(f"{name}.png has an alpha channel; Play rejects transparency here")
    # Both graphics are drawn on black right out to the edges. A page that came out shorter than
    # asked for left a white band along the bottom and clipped the art, and still passed the format
    # checks above, so look at the pixels the art must not have reached: the corners and the
    # middle of every edge.
    for x, y in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1), (w // 2, 0), (w // 2, h - 1),
                 (0, h // 2), (w - 1, h // 2)]:
        lit = subprocess.run(
            ["convert", str(path), "-format", f"%[fx:p{{{x},{y}}}.r+p{{{x},{y}}}.g+p{{{x},{y}}}.b]", "info:"],
            capture_output=True, text=True, check=True,
        ).stdout.strip()
        if float(lit) > 0.05:
            problems.append(f"{name}.png is not black at ({x}, {y}); the page was clipped or has a margin")
    limit = 1_000_000 if name == "icon" else 15_000_000
    if path.stat().st_size > limit:
        problems.append(f"{name}.png is {path.stat().st_size} bytes, over the {limit} limit")
    return problems


def main() -> int:
    if not shutil.which("convert"):
        sys.exit("render_graphics.py: ImageMagick's `convert` is needed")
    chrome = find_chrome()
    problems = []
    for name, w, h, fmt, transparent in ASSETS:
        render(chrome, name, w, h, fmt)
        found = verify(name, w, h, transparent)
        size = (GRAPHICS / f"{name}.png").stat().st_size
        print(f"{name}.png  {w} x {h}  {size:,} bytes  {'ok' if not found else 'FAILED'}")
        problems += found
    for p in problems:
        print(f"  {p}", file=sys.stderr)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
