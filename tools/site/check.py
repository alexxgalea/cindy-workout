#!/usr/bin/env python3
"""Checks the landing page in site/: its config, both languages and the files it points at.

    python3 tools/site/check.py            what CI runs
    python3 tools/site/check.py --deploy   also refuses a "testers" page with no group link
"""
import json
import re
import sys
from pathlib import Path

SITE = Path(__file__).resolve().parents[2] / "site"
errors = []


def fail(msg):
    errors.append(msg)


def config():
    text = (SITE / "config.js").read_text()
    body = re.search(r"window\.CINDY_SITE\s*=\s*(\{.*?\});", text, re.S).group(1)
    body = re.sub(r"(?m)^\s*//.*$", "", body)
    body = re.sub(r"(?m)^(\s*)(\w+):", r'\1"\2":', body)
    body = re.sub(r",\s*}", "}", body)
    return json.loads(body)


def translations(html):
    block = re.search(r"const T = \{(.*?)\n\};", html, re.S).group(1)
    langs = {}
    for lang in ("ro", "en"):
        part = re.search(rf"\b{lang}: \{{(.*?)\n  \}}", block, re.S).group(1)
        langs[lang] = set(re.findall(r'(?:^|",)\s*(\w+):', part, re.M))
    return langs


cfg = config()
html = (SITE / "index.html").read_text()

if cfg["mode"] not in ("testers", "play"):
    fail(f'mode must be "testers" or "play", not {cfg["mode"]!r}')
for key in ("optInUrl", "playUrl", "privacyUrl"):
    if not cfg[key].startswith("https://"):
        fail(f"{key} must be an https:// address")
if "--deploy" in sys.argv and cfg["mode"] == "testers" and not cfg["groupUrl"].startswith("https://"):
    fail('mode "testers" needs groupUrl set to the Google Group address before it is deployed')

langs = translations(html)
if langs["ro"] != langs["en"]:
    fail(f"Romanian and English differ in: {sorted(langs['ro'] ^ langs['en'])}")
used = set(re.findall(r'data-i18n(?:-html|-alt)?="(\w+)"', html)) - {"badge"}
for lang, keys in langs.items():
    if used - keys:
        fail(f"{lang} lacks keys the page uses: {sorted(used - keys)}")

for ref in re.findall(r'(?:src|href)="((?:img|fonts)/[^"]+)"', html) + re.findall(r'url\("([^"]+)"\)', html):
    if not (SITE / ref).exists():
        fail(f"missing file: site/{ref}")

if errors:
    print("\n".join(errors))
    sys.exit(1)
print("site ok")
