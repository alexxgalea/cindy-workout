#!/usr/bin/env python3
"""Lays MoveNet's score of each clip beside Vision's, against the truth, by evaluation category.

The two reports are the same JSON: `run_batch.py` writes the MoveNet one (or the Android job does,
pulled with adb), and `cindy-clips` (ios/CindyClips) writes the Vision one. Both score the same
catalogues in tests/scenarios with the same engine, so what differs between a pair of columns is
the pose model and the crop that fed it.

    python3 tools/video_regression/run_batch.py                      # tests/reports/python-regression.json
    swift run --package-path ios/CindyClips cindy-clips              # tests/reports/ios/vision-regression.json
    python3 tools/video_regression/compare_reports.py

Categories follow tests/README.md: clean-valid clips are judged on an exact count, difficult-but-valid
on the size of the error, and must-not-count on false positives, which may only be zero. They are
never blended into one number.

The last section applies Decision D1 (ios/PLAN.md) to the numbers: Vision stays unless it undercounts
clean-valid clips that MoveNet counts, or counts reps on a clip that must not count where MoveNet
does not. It is the rule the plan wrote down, applied mechanically; the decision is still the owner's.
"""
from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CATEGORIES = ("clean-valid", "difficult-but-valid", "must-not-count")
#: Clean-valid rows, scored by both, below which a verdict is not worth giving. A row is a clip, or
#: one movement of a Cindy clip.
MIN_CLEAN_ROWS = 3


@dataclass
class Side:
    """One model's result for one row: a count, or the reason there is none."""
    observed: int | None = None
    #: "skipped" (could not be run here), "missing" (no such scenario in the report) or "failed".
    note: str | None = None
    #: Why, in words, when it was skipped.
    reason: str | None = None

    @property
    def counted(self) -> bool:
        return self.observed is not None


@dataclass
class Row:
    id: str
    category: str
    truth: int
    movenet: Side
    vision: Side
    #: Set for a per-movement row of a Cindy scenario, e.g. "pullup".
    movement: str | None = None

    @property
    def label(self) -> str:
        return f"{self.id} · {self.movement}" if self.movement else self.id

    @property
    def comparable(self) -> bool:
        return self.movenet.counted and self.vision.counted

    def error(self, side: Side) -> int | None:
        return None if side.observed is None else side.observed - self.truth

    @property
    def verdict(self) -> str:
        if not self.comparable:
            return "not compared"
        m, v = abs(self.error(self.movenet)), abs(self.error(self.vision))
        if v == m:
            if self.error(self.vision) == self.error(self.movenet):
                return "same"
            return "same size, opposite sign"
        return "Vision closer" if v < m else "MoveNet closer"


@dataclass
class Comparison:
    rows: list[Row] = field(default_factory=list)

    def category(self, name: str) -> list[Row]:
        return [r for r in self.rows if r.category == name]


def load(path: Path) -> dict[str, dict]:
    """The scenarios of one report, by id."""
    data = json.loads(path.read_text())
    return {s["id"]: s for s in data.get("scenarios", [])}


def _side(scenario: dict | None, movement: str | None) -> Side:
    if scenario is None:
        return Side(note="missing", reason="not in this report")
    failures = scenario.get("failures") or []
    skipped = scenario.get("status") == "skipped" or (
        scenario.get("observedReps", 0) == 0 and any(f.startswith("missing fixture:") for f in failures))
    if skipped:
        reason = scenario.get("skipReason") or next((f for f in failures if f.startswith("missing fixture:")), "skipped")
        return Side(note="skipped", reason=reason)
    if failures and not scenario.get("frames") and scenario.get("setup") is None:
        # No frame was ever scored (the clip would not open, the exercise is unknown): the
        # scenario did not run, which is not the same as counting zero.
        return Side(note="failed", reason=failures[0])
    if movement is not None:
        per = (scenario.get("perMovement") or {}).get(movement)
        if per is None:
            return Side(note="missing", reason="no per-movement counts in this report")
        return Side(observed=int(per["observed"]))
    return Side(observed=int(scenario["observedReps"]))


def compare(movenet: dict[str, dict], vision: dict[str, dict]) -> Comparison:
    """One row per scenario, or per movement of a Cindy scenario, in the order MoveNet's report has
    them (Vision's for any it lacks)."""
    ids = list(movenet) + [i for i in vision if i not in movenet]
    out = Comparison()
    for id in ids:
        m, v = movenet.get(id), vision.get(id)
        either = m or v
        movements = None
        for report in (m, v):
            if report and report.get("perMovement"):
                movements = list(report["perMovement"])
                break
        if movements:
            for name in movements:
                truth_from = next(r["perMovement"][name]["expected"] for r in (m, v) if r and (r.get("perMovement") or {}).get(name))
                out.rows.append(Row(id, either.get("category", "clean-valid"), int(truth_from),
                                    _side(m, name), _side(v, name), movement=name))
        else:
            out.rows.append(Row(id, either.get("category", "clean-valid"), int(either.get("expectedReps", 0)),
                                _side(m, None), _side(v, None)))
    return out


@dataclass
class Stats:
    rows: int
    exact: int
    mean_abs_error: float
    under: int
    over: int
    false_positives: int


def stats(rows: list[Row], side: str) -> Stats | None:
    """A model's numbers over the rows both models scored, so the two are measured on the same clips."""
    rows = [r for r in rows if r.comparable]
    if not rows:
        return None
    errors = [r.error(getattr(r, side)) for r in rows]
    return Stats(len(rows), sum(e == 0 for e in errors), sum(abs(e) for e in errors) / len(rows),
                 sum(e < 0 for e in errors), sum(e > 0 for e in errors),
                 sum(getattr(r, side).observed for r in rows if r.category == "must-not-count"))


@dataclass
class Reading:
    verdict: str          # "keep-vision", "add-movenet", "not-enough-clips"
    reasons: list[str]


def reading(c: Comparison) -> Reading:
    """Decision D1, applied. See the module docstring."""
    clean = [r for r in c.category("clean-valid") if r.comparable]
    reasons: list[str] = []
    under = [r for r in clean if r.error(r.vision) < 0 and r.error(r.movenet) >= 0]
    for r in under:
        reasons.append(f"Vision undercounts {r.label} ({r.error(r.vision):+d}) where MoveNet does not ({r.error(r.movenet):+d})")
    fp = [r for r in c.category("must-not-count") if r.comparable and r.vision.observed > 0 and r.movenet.observed == 0]
    for r in fp:
        reasons.append(f"Vision counts {r.vision.observed} on {r.label}, which must not count; MoveNet counts 0")
    if len(clean) < MIN_CLEAN_ROWS:
        # What was found is still said, as far as it goes, but it is not a verdict.
        return Reading("not-enough-clips",
                       [f"only {len(clean)} clean-valid row(s) were scored by both models; "
                        f"at least {MIN_CLEAN_ROWS} are needed for a reading"] + [f"so far: {r}" for r in reasons])
    if reasons:
        return Reading("add-movenet", reasons)
    return Reading("keep-vision", [f"on {len(clean)} clean-valid rows Vision undercounts none that MoveNet counts, "
                                   "and counts nothing on a clip that must not count where MoveNet does not"])


def _cell(side: Side, row: Row) -> str:
    if side.counted:
        return f"{side.observed} ({row.error(side):+d})"
    return {"skipped": "skipped", "missing": "not run", "failed": "FAILED"}.get(side.note or "", "—")


def _table(c: Comparison) -> list[list[str]]:
    out = [["clip", "truth", "MoveNet", "Vision", "closer"]]
    for category in CATEGORIES:
        rows = c.category(category)
        if not rows:
            continue
        out.append([category.upper(), "", "", "", ""])
        for r in rows:
            out.append([r.label, str(r.truth), _cell(r.movenet, r), _cell(r.vision, r),
                        r.verdict if r.comparable else ""])
    return out


def _stat_lines(c: Comparison) -> list[str]:
    lines: list[str] = []
    for category in CATEGORIES:
        rows = c.category(category)
        m, v = stats(rows, "movenet"), stats(rows, "vision")
        if m is None or v is None:
            continue
        lines.append(f"{category}  ({m.rows} row(s) scored by both)")
        lines.append(f"  exact count:         MoveNet {m.exact}/{m.rows}   Vision {v.exact}/{v.rows}")
        lines.append(f"  mean absolute error: MoveNet {m.mean_abs_error:.2f}   Vision {v.mean_abs_error:.2f}")
        lines.append(f"  under / over:        MoveNet {m.under} / {m.over}   Vision {v.under} / {v.over}")
        if category == "must-not-count":
            lines.append(f"  false positives:     MoveNet {m.false_positives}   Vision {v.false_positives}")
        lines.append("")
    return lines


def _not_compared(c: Comparison) -> list[str]:
    lines = []
    for r in c.rows:
        if r.comparable:
            continue
        why = []
        for name, side in (("MoveNet", r.movenet), ("Vision", r.vision)):
            if not side.counted:
                why.append(f"{name} {side.note}: {side.reason}")
        lines.append(f"  {r.label}: " + "; ".join(why))
    return lines


def render_text(c: Comparison) -> str:
    table = _table(c)
    widths = [max(len(row[i]) for row in table) for i in range(5)]
    out = ["  ".join(cell.ljust(widths[i]) if i == 0 else cell.rjust(widths[i]) if i in (1, 2, 3) else cell
                     for i, cell in enumerate(row)).rstrip() for row in table]
    out += ["", "Counts are what each model counted, with the signed error against the truth in brackets.",
            "A row is a clip, or one movement of a Cindy clip.", ""]
    out += _stat_lines(c)
    skipped = _not_compared(c)
    if skipped:
        out += ["Not compared (a row counts for neither model unless both scored it):"] + skipped + [""]
    r = reading(c)
    out += ["Decision D1, applied to these numbers: " + {
        "keep-vision": "KEEP VISION",
        "add-movenet": "ADD A MOVENET CORE ML SOURCE (the next phase)",
        "not-enough-clips": "NO READING YET"}[r.verdict]]
    out += [f"  - {reason}" for reason in r.reasons]
    return "\n".join(out)


def render_markdown(c: Comparison) -> str:
    table = _table(c)
    out = ["| " + " | ".join(table[0]) + " |", "|---|--:|--:|--:|---|"]
    for row in table[1:]:
        out.append("| " + " | ".join((f"**{cell}**" if i == 0 and not row[1] else cell) for i, cell in enumerate(row)) + " |")
    out += [""] + [("    " + l if l else l) for l in _stat_lines(c)]
    skipped = _not_compared(c)
    if skipped:
        out += ["", "Not compared:", ""] + [f"- {l.strip()}" for l in skipped]
    r = reading(c)
    out += ["", "**Decision D1 applied:** " + {
        "keep-vision": "keep Vision",
        "add-movenet": "add a MoveNet Core ML source",
        "not-enough-clips": "no reading yet"}[r.verdict]]
    out += [f"- {reason}" for reason in r.reasons]
    return "\n".join(out)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--movenet", type=Path, default=ROOT / "tests/reports/python-regression.json",
                        help="MoveNet's report: run_batch.py's, or the Android job's")
    parser.add_argument("--vision", type=Path, default=ROOT / "tests/reports/ios/vision-regression.json",
                        help="Vision's report: cindy-clips'")
    parser.add_argument("--markdown", type=Path, help="also write the table as Markdown, for a pull request")
    args = parser.parse_args(argv)

    for label, path in (("MoveNet", args.movenet), ("Vision", args.vision)):
        if not path.is_file():
            print(f"compare_reports: no {label} report at {path}", file=sys.stderr)
            return 2
    comparison = compare(load(args.movenet), load(args.vision))
    print(render_text(comparison))
    if args.markdown:
        args.markdown.write_text(render_markdown(comparison) + "\n")
        print(f"\nMarkdown written to {args.markdown}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
