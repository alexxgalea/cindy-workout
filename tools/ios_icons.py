#!/usr/bin/env python3
"""Draws the iPhone app's icons from the Android vector drawables.

Run from the repository root, with no arguments:

    python3 tools/ios_icons.py

Every app/src/main/res/drawable/ic_*.xml except ic_launcher_foreground.xml becomes an SVG imageset
under ios/CindyTracker/Assets.xcassets/Icons/. The folder is rewritten from scratch each time.
CindyCore's IconParityTests holds the result to the drawables.
"""
import json
import re
import shutil
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ANDROID = "{http://schemas.android.com/apk/res/android}"
ROOT = Path(__file__).resolve().parent.parent
DRAWABLES = ROOT / "app/src/main/res/drawable"
COLORS = ROOT / "app/src/main/res/values/colors.xml"
ICONS = ROOT / "ios/CindyTracker/Assets.xcassets/Icons"
SKIPPED = {"ic_launcher_foreground"}
WHITE = "#FFFFFF"


def named_colors():
    return {c.get("name"): c.text.strip() for c in ET.parse(COLORS).getroot().iter("color")}


def resolve(value, colors):
    """Android colour -> (#RRGGBB, alpha 0...255), or None when there is none."""
    if value is None:
        return None
    if value.startswith("@color/"):
        value = colors[value[len("@color/"):]]
    digits = value.lstrip("#")
    if len(digits) == 6:
        digits = "FF" + digits
    alpha = int(digits[:2], 16)
    return "#" + digits[2:].upper(), alpha


def paint(attribute, value, colors, out):
    """Writes fill or stroke. Always explicit: SVG's default fill is black, Android's is none."""
    colour = resolve(value, colors)
    if colour is None or colour[1] == 0:
        out.append(f'{attribute}="none"')
        return None
    rgb, alpha = colour
    out.append(f'{attribute}="{rgb}"')
    if alpha < 255:
        out.append(f'{attribute}-opacity="{round(alpha / 255, 3):g}"')
    return rgb


def svg(vector, colors):
    """The SVG text, and whether any colour in it is something other than white."""
    width = vector.get(ANDROID + "width").removesuffix("dp")
    height = vector.get(ANDROID + "height").removesuffix("dp")
    box = f'0 0 {vector.get(ANDROID + "viewportWidth")} {vector.get(ANDROID + "viewportHeight")}'
    lines = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="{box}">']
    own_colour = False
    for path in vector.iter("path"):
        attributes = [f'd="{path.get(ANDROID + "pathData")}"']
        for rgb in (paint("fill", path.get(ANDROID + "fillColor"), colors, attributes),
                    paint("stroke", path.get(ANDROID + "strokeColor"), colors, attributes)):
            own_colour = own_colour or (rgb is not None and rgb != WHITE)
        for source, target in (("strokeWidth", "stroke-width"),
                               ("strokeLineCap", "stroke-linecap"),
                               ("strokeLineJoin", "stroke-linejoin")):
            if path.get(ANDROID + source) is not None:
                attributes.append(f'{target}="{path.get(ANDROID + source)}"')
        if path.get(ANDROID + "fillType") == "evenOdd":
            attributes.append('fill-rule="evenodd"')
        lines.append("  <path " + " ".join(attributes) + "/>")
    lines.append("</svg>")
    return "\n".join(lines) + "\n", own_colour


def contents(name, original):
    return {
        "images": [{"filename": f"{name}.svg", "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
        "properties": {
            "preserves-vector-representation": True,
            "template-rendering-intent": "original" if original else "template",
        },
    }


def main():
    colors = named_colors()
    if ICONS.exists():
        shutil.rmtree(ICONS)
    ICONS.mkdir(parents=True)
    (ICONS / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
    count = 0
    for source in sorted(DRAWABLES.glob("ic_*.xml")):
        name = source.stem
        if name in SKIPPED:
            continue
        text, original = svg(ET.parse(source).getroot(), colors)
        folder = ICONS / f"{name}.imageset"
        folder.mkdir()
        (folder / f"{name}.svg").write_text(text)
        (folder / "Contents.json").write_text(json.dumps(contents(name, original), indent=2) + "\n")
        count += 1
    print(f"{count} icons written to {ICONS.relative_to(ROOT)}")


if __name__ == "__main__":
    sys.exit(main())
