#!/usr/bin/env python3
"""
Renders the store listing and the privacy policy for one build of the app, for Google Play (play/)
or for the App Store (appstore/).

The sources in play/ and appstore/ are written once for two kinds of build, one made with a strava.properties
and one without. Text that only makes sense where Strava exists sits between {{#strava}} and
{{/strava}}; text for the build without it sits between {{^strava}} and {{/strava}}. A policy that
described Strava for a build that has none, or the reverse, would be wrong in the way that matters
most to Google Play, so each build is rendered from the same source and never edited by hand.

The policy also needs three facts only its publisher knows: the developer's name exactly as it is
on the store listing, a privacy contact, and the date it takes effect. They are placeholders in
the source, never in the repository's history, and this script refuses to write anything while one
is left over.

    tools/play/render.py --strava    --name "Your Name" --email you@example.com
    tools/play/render.py --no-strava --name "Your Name" --email you@example.com --store appstore

Writes <store>/dist/privacy-policy.html, which is the page to publish, and <store>/dist/listing/
with the rendered texts (and, for the App Store, review-notes.txt), to paste into the store's
console. `--check` renders both builds of both stores with stand-in values and exits 1 on any
problem, for CI. Standard library only.
"""

import argparse
import datetime
import html
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]

# What differs between the two stores: where the sources are, which listing files there are, and
# the limit each is held to (printed, and checked by PlayListingTest and AppStoreListingTests).
STORES = {
    "play": {
        "dir": ROOT / "play",
        "files": [("title.txt", 30), ("short-description.txt", 80), ("full-description.txt", 4000)],
        "notes_limit": 500,
        "extra": [],
    },
    "appstore": {
        "dir": ROOT / "appstore",
        "files": [("name.txt", 30), ("subtitle.txt", 30), ("promotional-text.txt", 170),
                  ("description.txt", 4000), ("keywords.txt", 100)],
        "notes_limit": 4000,
        # Not part of the listing, but written once for two builds like it and rendered with it.
        "extra": [("review-notes.txt", 4000)],
    },
}

# {{#strava}}...{{/strava}} is kept for a build with Strava, {{^strava}}...{{/strava}} for one
# without. Blocks do not nest.
BLOCK = re.compile(r"\{\{([#^])strava\}\}(.*?)\{\{/strava\}\}\n?", re.S)
LEFTOVER = re.compile(r"\{\{[^}]*\}\}")
EMAIL = re.compile(r"^[^@\s<>\"]+@[^@\s<>\"]+\.[^@\s<>\"]+$")


def resolve(text: str, with_strava: bool) -> str:
    def pick(m: re.Match) -> str:
        keep = with_strava if m.group(1) == "#" else not with_strava
        return m.group(2).lstrip("\n") if keep else ""

    return BLOCK.sub(pick, text)


def fill(text: str, values: dict) -> str:
    for key, value in values.items():
        text = text.replace("{{" + key + "}}", html.escape(value, quote=True))
    return text


def render(store: str, with_strava: bool, name: str, email: str, date: str):
    """The policy page and the listing texts for one build of one store, or raises ValueError."""
    config = STORES[store]
    base = config["dir"]
    release_notes = base / "listing" / "en-US" / "release-notes"
    if not name.strip():
        raise ValueError("--name is empty")
    if not EMAIL.match(email):
        raise ValueError(f"--email does not look like an address: {email!r}")
    datetime.date.fromisoformat(date)

    policy = fill(
        resolve((base / "privacy-policy.html").read_text(), with_strava),
        {"DEVELOPER_NAME": name.strip(), "CONTACT_EMAIL": email.strip(), "EFFECTIVE_DATE": date},
    )
    names = [f for f, _ in config["files"]] + [f"release-notes/{p.name}" for p in sorted(release_notes.glob("*.txt"))]
    listing = {
        f: resolve((base / "listing" / "en-US" / f).read_text(), with_strava).strip() + "\n"
        for f in names
    }
    for f, _ in config["extra"]:
        listing[f] = resolve((base / f).read_text(), with_strava).strip() + "\n"

    for where, text in [("privacy-policy.html", policy)] + list(listing.items()):
        left = LEFTOVER.findall(text)
        if left:
            raise ValueError(f"{where} still has {sorted(set(left))} after rendering")
    if not with_strava:
        for where, text in [("privacy-policy.html", policy)] + list(listing.items()):
            if "strava" in text.lower():
                raise ValueError(f"{where} mentions Strava in a build that has none")
    return policy, listing


def main(argv) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    group = ap.add_mutually_exclusive_group(required=True)
    group.add_argument("--strava", dest="strava", action="store_true")
    group.add_argument("--no-strava", dest="strava", action="store_false")
    group.add_argument("--check", action="store_true", help="render both builds with stand-in values")
    ap.add_argument("--store", choices=sorted(STORES), default="play")
    ap.add_argument("--name")
    ap.add_argument("--email")
    ap.add_argument("--date", default=datetime.date.today().isoformat())
    ap.add_argument("--out")
    args = ap.parse_args(argv)

    try:
        if args.check:
            for store in STORES:
                for with_strava in (True, False):
                    render(store, with_strava, "Example Developer", "privacy@example.com", "2026-01-01")
                print(f"{store}/: the listing and the policy render for both builds")
            return 0
        if not args.name or not args.email:
            ap.error("--name and --email are required")
        policy, listing = render(args.store, args.strava, args.name, args.email, args.date)
    except ValueError as e:
        print(f"render.py: {e}", file=sys.stderr)
        return 1

    config = STORES[args.store]
    out = pathlib.Path(args.out) if args.out else config["dir"] / "dist"
    (out / "listing" / "release-notes").mkdir(parents=True, exist_ok=True)
    (out / "privacy-policy.html").write_text(policy)
    for f, text in listing.items():
        # What is not a listing file goes beside the listing's folder, not in it.
        target = out / f if f in dict(config["extra"]) else out / "listing" / f
        target.write_text(text)
    variant = "with Strava" if args.strava else "without Strava"
    print(f"Rendered {variant} into {out}")
    for f, limit in config["files"] + config["extra"]:
        print(f"  {f:<24} {len(listing[f].strip()):>4} / {limit}")
    for f, text in listing.items():
        if f.startswith("release-notes/"):
            print(f"  {f:<24} {len(text.strip()):>4} / {config['notes_limit']}")
    print(f"Publish {out / 'privacy-policy.html'} as the policy page.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
