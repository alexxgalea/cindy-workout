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

A movement is confirmed at one moment, when recognition first names it. Each film is scored on
three metrics, from its `movementWindows` (a `none` window is a walk, a rest or a walk-in):

- wrong confirmations: a movement confirmed inside the window of another movement, or inside no window;
- idle recognitions: a movement confirmed inside a `none` window;
- the real rep each set (each window of a movement) was confirmed at, counted from the scenario's
  `labelledBottomsMs` inside that window (the labels are good to a fraction of a second, so a rep
  labelled up to REP_SLACK_MS after the confirmation counts as already done).

The run fails (exit 1) on any wrong confirmation, any idle recognition, a set confirmed after its 3rd
real rep, and a set never confirmed. A window with a `knownGap` reason (a sentence saying why) is
reported as KNOWN GAP when it is never confirmed, and does not fail the run; it says so loudly, and
when the gap has closed it reports the set as ok. A known gap never excuses a late confirmation, and
the closing line counts the known-gap sets apart from the films that held. Each film also prints a timeline of
window starts, positions and confirmations, so a miss can be found by its time.

A film is also run as a Freestyle (the Python twin of FreestyleEngine, `cindy_sim/freestyle.py`):
the reps recognition counts are banked and the sets derived. Two more thresholds hold it to numbers:

- per-movement totals equal to the labelled reps (`labelledBottomsMs`) on every film that labels them.
  A movement with a `knownGap` window may differ: it is reported as KNOWN GAP and does not fail, and
  when the totals match again it says the gap has closed. Kipping pull-ups (#184) are the known gap.
- derived set boundaries within SET_TOLERANCE_MS of the labels, when a scenario carries `labelledSets`
  (the owner's labels, #198): one entry per set in order, as the first and last rep of the set
  `{"movement": "pullup", "startMs": 17466, "endMs": 27966}`, with an optional `setToleranceMs`. The
  derived set count and movements must match too. A film with no `labelledSets` has its derived sets
  printed and nothing enforced.

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

from cindy_sim.freestyle import FiledSession, FreestyleEngine, FreestyleSet
from cindy_sim.recogniser import Movement, Position, Recognition, Recogniser
from cindy_sim.workout_engine import STANDARD_PROFILE, CindyProfile, PullVariant

#: The labels' names for the movements, as `labelledBottomsMs` and `movementWindows` spell them.
MOVEMENT_KEYS = {"pullup": Movement.PULL_UPS, "pushup": Movement.PUSH_UPS, "squat": Movement.SQUATS}


def key_of(movement: Movement) -> str:
    """The scenario key ("pullup", "pushup", "squat") of a movement."""
    return next(k for k, m in MOVEMENT_KEYS.items() if m is movement)


def movement_label(window: dict) -> str:
    """A movement window's label, or its movement when it has none."""
    return window.get("label", window["movement"])


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


#: A set must be confirmed by the end of this real rep (the issue's threshold: not after the 3rd).
LATEST_CONFIRMING_REP = 3


@dataclass
class SetResult:
    """How recognition did on one labelled set: when it confirmed the movement, and at which real rep."""

    label: str
    movement: str
    confirmed_ms: int | None
    real_rep: int | None
    #: ok, late (after the 3rd real rep), never, or known_gap (never confirmed, but marked a known gap)
    status: str
    reason: str = ""


@dataclass
class FilmScore:
    """The three metrics of one film. Wrong confirmations and idle recognitions are messages, one each."""

    wrong: list[str]
    idle: list[str]
    sets: list[SetResult]

    @property
    def known_gaps(self) -> int:
        return sum(1 for s in self.sets if s.status == "known_gap")

    @property
    def failed(self) -> bool:
        return bool(self.wrong or self.idle or any(s.status in ("late", "never") for s in self.sets))

    def failures(self) -> list[str]:
        out = list(self.wrong) + list(self.idle)
        for s in self.sets:
            if s.status == "never":
                out.append(f"{s.label}: {s.movement} was never confirmed")
            elif s.status == "late":
                out.append(f"{s.label}: confirmed at {s.confirmed_ms} ms, at real rep {s.real_rep} "
                           f"(the latest allowed is {LATEST_CONFIRMING_REP})")
        return out


def score_film(
    confirmed: Sequence[tuple[int, Movement]], windows: Sequence[dict], labelled: dict[str, Sequence[int]]
) -> FilmScore:
    """The film's metrics: wrong confirmations, idle recognitions, and the real rep each set was confirmed at.

    A confirmation inside a window of another movement or inside no window is wrong; inside a `none`
    window it is an idle recognition. A set is a window of a movement: it is confirmed by the first
    confirmation of that movement inside it. A set `knownGap`-marked with a reason is reported but
    does not fail the run when it is never confirmed; a late confirmation still fails.
    """
    wrong: list[str] = []
    idle: list[str] = []
    for t, movement in confirmed:
        inside = [w for w in windows if w["fromMs"] <= t < w["toMs"]]
        names = ", ".join(movement_label(w) for w in inside)
        if not inside:
            wrong.append(f"wrong confirmation: {movement.label} at {t} ms, inside no window")
        elif any(MOVEMENT_KEYS.get(w["movement"]) is movement for w in inside):
            continue
        elif all(w["movement"] == "none" for w in inside):
            idle.append(f"idle recognition: {movement.label} at {t} ms, in the none window '{names}'")
        else:
            wrong.append(f"wrong confirmation: {movement.label} at {t} ms, in the window '{names}'")
    sets: list[SetResult] = []
    for window in windows:
        wanted = MOVEMENT_KEYS.get(window["movement"])
        if wanted is None:
            continue
        label = movement_label(window)
        reason = window.get("knownGap") or ""
        hits = [t for t, m in confirmed if m is wanted and window["fromMs"] <= t < window["toMs"]]
        if not hits:
            sets.append(SetResult(label, window["movement"], None, None, "known_gap" if reason else "never", reason))
            continue
        reps = [t for t in (labelled.get(window["movement"]) or []) if window["fromMs"] <= t < window["toMs"]]
        rep = real_rep(reps, hits[0])
        status = "ok" if rep <= LATEST_CONFIRMING_REP else "late"
        sets.append(SetResult(label, window["movement"], hits[0], rep, status, reason))
    return FilmScore(wrong, idle, sets)


def check_movement_windows(
    confirmed: Sequence[tuple[int, Movement]], windows: Sequence[dict]
) -> list[str]:
    """One message per wrong confirmation, idle recognition and movement window never confirmed."""
    return score_film(confirmed, windows, {}).failures()


def timeline_lines(
    positions: Sequence[tuple[int, int, Position]],
    confirmed: Sequence[tuple[int, Movement]],
    windows: Sequence[dict],
    labelled: dict[str, Sequence[int]],
) -> list[str]:
    """Window starts, position runs and confirmations in time order, so a miss can be found by its time."""
    events: list[tuple[int, int, str]] = []
    for w in windows:
        events.append((w["fromMs"], 0, f"[window] {movement_label(w)}: {w['movement']}, "
                                       f"{w['fromMs'] / 1000:.2f}s to {w['toMs'] / 1000:.2f}s"))
    for start, end, position in positions:
        events.append((start, 1, f"position {position.label}, until {end / 1000:.2f}s"))
    for t, movement in confirmed:
        key = key_of(movement)
        windows_of = [w for w in windows if w["movement"] == key and w["fromMs"] <= t < w["toMs"]]
        reps = [x for x in (labelled.get(key) or []) if not windows_of
                or windows_of[0]["fromMs"] <= x < windows_of[0]["toMs"]]
        events.append((t, 2, f"CONFIRMED {movement.label}, at real rep {real_rep(reps, t)} of {len(reps)}"))
    return [f"{t / 1000:7.2f}s  {text}" for t, _, text in sorted(events)]


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


def run_scenario(scenario: dict, out_dir: Path, pull: str | None = None) -> tuple[bool, int]:
    """Run one film; whether it passed, and how many of its sets are known gaps."""
    video = Path(scenario["video"])
    if not video.is_absolute():
        video = ROOT / video
    print(f"\nScenario: {scenario['id']}")
    if not video.is_file():
        print(f"  missing fixture: {video}")
        return False, 0
    frames = infer(video, scenario)
    if isinstance(frames, str):
        print(f"  {frames}")
        return False, 0

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
        key = key_of(movement)
        times = labelled.get(key) or []
        rep = f"at real rep {real_rep(times, t)} of {len(times)}" if times else "(no labelled reps)"
        print(f"    {t / 1000:7.2f}s  {movement.label}  {rep}")
    if not confirmed:
        print("    none")
    movement_windows = scenario.get("movementWindows") or []
    passed = not failures
    known_gaps = 0
    if movement_windows:
        score = score_film(confirmed, movement_windows, labelled)
        print(f"  Metrics: wrong confirmations {len(score.wrong)}, idle recognitions {len(score.idle)}")
        for message in score.wrong + score.idle:
            print(f"    - {message}")
        print(f"  Sets (the latest confirming real rep is {LATEST_CONFIRMING_REP}):")
        for s in score.sets:
            print("    " + describe_set(s))
        print("  Timeline:")
        for line in timeline_lines(runs(track), confirmed, movement_windows, labelled):
            print("    " + line)
        passed = passed and not score.failed
        known_gaps = score.known_gaps
    if movement_windows or scenario.get("labelledSets"):
        passed, known_gaps = score_freestyle(scenario, frames, labelled, movement_windows, passed, known_gaps)
    return passed, known_gaps


def score_freestyle(scenario, frames, labelled, windows, passed, known_gaps) -> tuple[bool, int]:
    """Runs the film as a Freestyle and holds it to its totals and, when labelled, its set boundaries."""
    filed = freestyle_session(frames)
    print("  Freestyle (banks what recognition counts):")
    totals = {k: filed.totals.get(m.exercise, 0) for k, m in MOVEMENT_KEYS.items()} if filed else {}
    results = score_totals(totals, labelled, windows)
    print("    Totals (equal to the labelled reps):")
    for r in results:
        print("      " + describe_total(r))
    if any(r.fails for r in results):
        passed = False
    known_gaps += sum(1 for r in results if r.status == "known_gap")
    print("    Derived sets:")
    for line in describe_derived(filed):
        print("      " + line)
    labelled_sets = scenario.get("labelledSets")
    if not labelled_sets:
        print("    Set boundaries: no labelledSets on this film, nothing enforced")
        return passed, known_gaps
    tolerance = scenario.get("setToleranceMs", SET_TOLERANCE_MS)
    failures = score_set_boundaries(filed.sets if filed else [], labelled_sets, tolerance)
    print(f"    Set boundaries (within {tolerance} ms of the labels): "
          f"{'held' if not failures else str(len(failures)) + ' failure(s)'}")
    for message in failures:
        print(f"      - {message}")
    return passed and not failures, known_gaps


#: How far a derived set's first or last rep may be from the label. PROVISIONAL, with the rest
#: threshold (#198): a Freestyle banks the two confirming reps together at the 2nd, so a set's derived
#: start is up to a rep late, and a label is a rep's bottom while the engine marks it when counted.
#: On the three films today a derived first rep lands 1.5 to 3.2 s after its labelled bottom (the
#: 3.2 s is the clip's push-ups, which lose a rep entering the floor) and a last rep within 0.5 s.
SET_TOLERANCE_MS = 3_500


def freestyle_session(frames: Sequence[Frame], profile: CindyProfile = STANDARD_PROFILE) -> FiledSession | None:
    """The film run as a Freestyle from its first frame to its last: what STOP would have filed, or none."""
    if not frames:
        return None
    engine = FreestyleEngine(profile)
    engine.start(frames[0].timestamp_ms)
    for frame in frames:
        engine.on_frame(frame.keypoints, frame.timestamp_ms, frame.tracking_stable)
    return engine.stop(frames[-1].timestamp_ms)


@dataclass
class TotalResult:
    """One movement's banked reps against the labelled ones."""

    movement: str
    banked: int
    labelled: int
    #: ok, wrong, known_gap (differs, but marked a known gap) or gap_closed (marked, and now equal)
    status: str
    reason: str = ""

    @property
    def fails(self) -> bool:
        return self.status == "wrong"


def score_totals(
    totals: dict[str, int], labelled: dict[str, Sequence[int]], windows: Sequence[dict]
) -> list[TotalResult]:
    """Each labelled movement's banked total against its labelled reps; `totals` is keyed by scenario key."""
    results: list[TotalResult] = []
    for key in MOVEMENT_KEYS:
        reps = labelled.get(key)
        if not reps:
            continue
        banked = totals.get(key, 0)
        reason = next((w["knownGap"] for w in windows if w["movement"] == key and w.get("knownGap")), "")
        if banked == len(reps):
            status = "gap_closed" if reason else "ok"
        else:
            status = "known_gap" if reason else "wrong"
        results.append(TotalResult(key, banked, len(reps), status, reason))
    return results


def score_set_boundaries(
    derived: Sequence[FreestyleSet], labelled_sets: Sequence[dict], tolerance_ms: int = SET_TOLERANCE_MS
) -> list[str]:
    """One message per way the derived sets differ from the labelled ones; an empty list is a pass."""
    if len(derived) != len(labelled_sets):
        return [f"{len(labelled_sets)} labelled sets, {len(derived)} derived"]
    failures: list[str] = []
    for i, (got, want) in enumerate(zip(derived, labelled_sets), start=1):
        if got.movement.name.lower() != want["movement"]:
            failures.append(f"set {i}: labelled {want['movement']}, derived {got.movement.name.lower()}")
            continue
        for edge, derived_ms, labelled_ms in (("starts", got.start_ms, want["startMs"]),
                                              ("ends", got.end_ms, want["endMs"])):
            if abs(derived_ms - labelled_ms) > tolerance_ms:
                failures.append(f"set {i} ({want['movement']}) {edge} at {derived_ms} ms, labelled {labelled_ms} ms "
                                f"(more than {tolerance_ms} ms apart)")
    return failures


def describe_total(r: TotalResult) -> str:
    counts = f"banked {r.banked} of {r.labelled} labelled"
    if r.status == "ok":
        return f"ok          {r.movement}: {counts}"
    if r.status == "wrong":
        return f"WRONG TOTAL {r.movement}: {counts}"
    if r.status == "gap_closed":
        return f"ok          {r.movement}: {counts} (the known gap has closed; drop its knownGap)"
    return f"KNOWN GAP   {r.movement}: {counts}; {r.reason}"


def describe_derived(filed: FiledSession | None) -> list[str]:
    """The derived sets and the gaps between them, as the session page would list them."""
    if filed is None:
        return ["nothing banked: STOP files nothing"]
    lines = []
    for i, s in enumerate(filed.sets):
        lines.append(f"set {i + 1}: {s.movement.name.lower()} x{s.reps}, {s.start_ms / 1000:.2f}s to {s.end_ms / 1000:.2f}s")
        if i < len(filed.gaps):
            g = filed.gaps[i]
            lines.append(f"  {g.kind.value} {(g.end_ms - g.start_ms) / 1000:.1f}s")
    return lines


def summary_line(held: int, films: int, known_gaps: int) -> str:
    """The closing line: how many films held, and how many sets are known gaps rather than confirmed."""
    line = f"{held} of {films} films held every window and confirmed every movement"
    if known_gaps:
        line += f"; {known_gaps} known gap {'set' if known_gaps == 1 else 'sets'}"
    return line


def describe_set(s: SetResult) -> str:
    """One line for a set: ok, LATE, NEVER CONFIRMED or KNOWN GAP, with the real rep it was confirmed at."""
    when = "" if s.confirmed_ms is None else f"confirmed {s.confirmed_ms / 1000:.2f}s at real rep {s.real_rep}"
    if s.status == "ok":
        return f"ok          {s.label} ({s.movement}): {when}"
    if s.status == "late":
        return f"LATE        {s.label} ({s.movement}): {when}"
    if s.status == "never":
        return f"NEVER CONFIRMED  {s.label} ({s.movement})"
    return f"KNOWN GAP   {s.label} ({s.movement}): {when or 'never confirmed'}; {s.reason}"


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

        catalogues = ROOT / "tests/scenarios"
        paths = args.scenarios or sorted(catalogues.glob("*.json")) + sorted(catalogues.glob("recognition/*.json"))
        scenarios = [s for s in run_batch.load_catalogues(paths) if s.get("positionWindows") or s.get("movementWindows")]
    if not scenarios:
        print("No scenarios with positionWindows or movementWindows to run.", file=sys.stderr)
        return 2

    results = [run_scenario(scenario, args.out, args.pull) for scenario in scenarios]
    print("\n" + "=" * 62)
    print(summary_line(sum(1 for passed, _ in results if passed), len(results), sum(gaps for _, gaps in results)))
    return 0 if all(passed for passed, _ in results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
