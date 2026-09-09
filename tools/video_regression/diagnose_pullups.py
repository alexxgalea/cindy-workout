#!/usr/bin/env python3
"""Explains, rep by rep, why a labelled pull-up clip scored what it did.

A count mismatch on its own is not a bug report: it says a rep is missing, not which gate refused
it. This finds the repetitions the athlete visibly performed, matches them against the reps the
engine booked, and for every unmatched one names the first gate that stood in the way.

The visual repetitions come from a deliberately dumb oracle -- hysteresis on the raw bilateral
elbow angle, with no bar, head or dead-hang gate involved -- so it cannot inherit the very
failure it is measuring.

    python3 tools/video_regression/diagnose_pullups.py --clip AB5LE7WDvcQ
    python3 tools/video_regression/diagnose_pullups.py --all --out-dir tests/reports/diagnostics

Writes <id>.events.jsonl, <id>.summary.json and <id>.timeline.csv per clip. Artifacts land in the
ignored tests/reports/ tree; nothing here is committed.
"""
from __future__ import annotations

import argparse
import csv
import json
import math
import sys
from dataclasses import dataclass, field
from pathlib import Path

import cv2

sys.path.insert(0, str(Path(__file__).resolve().parent))

from cindy_sim.keypoints import KP
from cindy_sim.pose_detector import PoseDetector
from cindy_sim.workout_engine import Exercise, RepEvent, WorkoutEngine

ROOT = Path(__file__).resolve().parents[2]
ELBOW = (KP.LEFT_SHOULDER, KP.LEFT_ELBOW, KP.LEFT_WRIST,
         KP.RIGHT_SHOULDER, KP.RIGHT_ELBOW, KP.RIGHT_WRIST)

#: Hysteresis for the independent oracle: the elbow must close past DOWN then open past UP.
ORACLE_FLEXED = 70.0
ORACLE_EXTENDED = 140.0
#: How far either side of an oracle top a booking still counts as the same repetition.
MATCH_WINDOW_MS = 1500

#: Rejection text -> the classification the plan asks for. The engine's hint is the single place
#: that already names the first failing gate, so it is the natural key.
REASONS = {
    "Show both hands": "WRIST_SCORE_LOW",
    "Show your head": "NOSE_SCORE_LOW",
    "Hang from the bar": "HANDS_NOT_OVERHEAD",
    "Get on the bar": "OUTSIDE_BAR_ZONE",
    "Arms out of frame": "POSE_UNREADABLE",
    "Return to a dead hang": "NO_VALID_DEAD_HANG",
    "Get your head over the bar": "HEAD_DID_NOT_CROSS_BAR",
    "Drive up": "REPCOUNTER_BAND_NOT_REACHED",
    "Tracking…": "TRACKING_ROI_LOST",
    "Step into frame": "POSE_UNREADABLE",
}


@dataclass
class Frame:
    index: int
    time_ms: int
    readable: bool
    dropout_frames: int
    left_wrist_score: float
    right_wrist_score: float
    nose_score: float
    elbow_angle: float
    dead_hang_threshold: float
    head_y: float | None
    bar_line_y: float | None
    torso: float | None
    identity_stable: bool
    bar_gate_open: bool
    head_above_bar: bool
    pullup_down_seen: bool
    booked: bool
    count: int
    state: str
    signal: float
    learned_range: float
    calibrated: bool
    hint: str
    rejection: str | None
    bar_established: bool

    def as_event(self) -> dict:
        d = {k: (None if isinstance(v, float) and math.isnan(v) else v)
             for k, v in self.__dict__.items()}
        for key in ("elbow_angle", "dead_hang_threshold", "head_y", "bar_line_y", "torso",
                    "signal", "learned_range"):
            if isinstance(d.get(key), float):
                d[key] = round(d[key], 3)
        for key in ("left_wrist_score", "right_wrist_score", "nose_score"):
            if isinstance(d.get(key), float):
                d[key] = round(d[key], 4)
        return d


@dataclass
class MissedCycle:
    top_time_ms: int
    classification: str
    detail: str
    window_hints: dict = field(default_factory=dict)


def analyse(clip: Path, model: str) -> tuple[list[Frame], list[int], list[int], int]:
    """Replays the clip once, returning per-frame diagnostics, bookings, oracle tops and resets."""
    capture = cv2.VideoCapture(str(clip))
    fps = capture.get(cv2.CAP_PROP_FPS)
    if not fps or fps <= 0:
        raise SystemExit(f"{clip}: no usable FPS metadata")
    detector = PoseDetector(str(ROOT / "app/src/main/assets" / model), model)
    engine = WorkoutEngine(fixed_exercise=Exercise.PULLUP)
    counter = engine._counters[Exercise.PULLUP]

    frames: list[Frame] = []
    booked: list[int] = []
    oracle_tops: list[int] = []
    bar_resets = 0
    oracle_state = "extended"
    index = 0
    was_established: float | None = None

    while True:
        ok, bgr = capture.read()
        if not ok:
            break
        rgb = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)
        tracking = detector.tracking
        k = detector.detect(rgb)
        time_ms = int(index * 1000.0 / fps)

        # Read the raw geometry before the engine touches anything; these helpers are pure.
        elbow = engine._bilateral_angle(k, *ELBOW)
        torso = engine._torso_length(k)
        threshold = engine._dead_hang_degrees()

        event = engine.on_frame(k, time_ms, tracking)
        d = engine.diagnostics

        # The bar never reads as un-established: the frame that abandons it re-establishes it
        # from the new hands in the same pass. A discontinuity in the line is the observable.
        line = engine._bar.line_y
        if was_established is not None and line is not None and torso:
            if abs(line - was_established) > 0.5 * torso:
                bar_resets += 1
        was_established = line

        if not math.isnan(elbow):
            if oracle_state == "extended" and elbow < ORACLE_FLEXED:
                oracle_state = "flexed"
                oracle_tops.append(time_ms)
            elif oracle_state == "flexed" and elbow > ORACLE_EXTENDED:
                oracle_state = "extended"

        if event is not RepEvent.NONE:
            booked.append(time_ms)

        frames.append(Frame(
            index=index, time_ms=time_ms,
            readable=d.rejection_reason not in ("Show both hands", "Show your head",
                                                "Arms out of frame", "Step into frame"),
            dropout_frames=engine._pullup_dropout_frames,
            left_wrist_score=k[KP.LEFT_WRIST].score, right_wrist_score=k[KP.RIGHT_WRIST].score,
            nose_score=k[KP.NOSE].score, elbow_angle=elbow, dead_hang_threshold=threshold,
            head_y=k[KP.NOSE].y if k[KP.NOSE].score >= engine.MIN_SCORE else None,
            bar_line_y=engine._bar.line_y, torso=torso,
            identity_stable=d.identity_stable, bar_gate_open=d.bar_gate_open,
            head_above_bar=d.head_above_bar, pullup_down_seen=d.reset_below_bar_seen,
            booked=event is not RepEvent.NONE, count=engine.reps,
            state=engine.counting_state, signal=counter.smoothed,
            learned_range=counter.learned_range, calibrated=counter.calibrated,
            hint=engine.hint, rejection=d.rejection_reason,
            bar_established=engine._bar.established,
        ))
        index += 1

    capture.release()
    detector.close()
    return frames, booked, oracle_tops, bar_resets


def classify_miss(frames: list[Frame], top_ms: int) -> MissedCycle:
    """Names the first decisive gate over the ascent leading into an unbooked repetition."""
    window = [f for f in frames if top_ms - MATCH_WINDOW_MS <= f.time_ms <= top_ms + 500]
    if not window:
        return MissedCycle(top_ms, "NO_DATA", "no frames around this repetition")

    hints: dict[str, int] = {}
    for f in window:
        if f.rejection:
            hints[f.rejection] = hints.get(f.rejection, 0) + 1

    # A dropout run that hit the cap is decisive regardless of what the last frame said, because
    # it is what discarded the cycle rather than merely declining to score it.
    longest_dropout = max((f.dropout_frames for f in window), default=0)
    if longest_dropout > WorkoutEngine.MAX_DROPOUT_FRAMES:
        return MissedCycle(top_ms, "POSE_DROPOUT_EXCEEDED",
                           f"dropout run reached {longest_dropout} frames", hints)

    # Otherwise the gate that spoke most over the ascent is the one that held the rep back.
    if hints:
        reason, n = max(hints.items(), key=lambda kv: kv[1])
        detail = f"'{reason}' on {n} of {len(window)} frames"
        if reason == "Return to a dead hang":
            angles = [f.elbow_angle for f in window if not math.isnan(f.elbow_angle)]
            peak = max(angles) if angles else float("nan")
            threshold = window[-1].dead_hang_threshold
            shortfall = threshold - peak
            detail += (f"; peak elbow {peak:.1f} vs threshold {threshold:.1f}"
                       f" (short by {shortfall:.1f})")
            if shortfall > 0:
                # The arms never straightened enough for this camera's threshold.
                return MissedCycle(
                    top_ms,
                    "DEAD_HANG_NARROWLY_MISSED" if shortfall <= 10 else "NO_VALID_DEAD_HANG",
                    detail, hints)
            # The arms did straighten, so what blocked arming was the head-reset line: the nose
            # never came back far enough below the bar. A different gate with a different fix.
            straight = [f for f in window
                        if not math.isnan(f.elbow_angle) and f.elbow_angle >= f.dead_hang_threshold
                        and f.head_y is not None and f.bar_line_y is not None and f.torso]
            if straight:
                best = min(f.bar_line_y + WorkoutEngine.HEAD_RESET_TORSOS * f.torso - f.head_y
                           for f in straight)
                detail += f"; closest approach to the reset line {best:.0f}px short"
            return MissedCycle(top_ms, "HEAD_NOT_BELOW_RESET_LINE", detail, hints)
        return MissedCycle(top_ms, REASONS.get(reason, "UNKNOWN"), detail, hints)
    return MissedCycle(top_ms, "REPCOUNTER_BAND_NOT_REACHED",
                       "all gates open but the counter never booked", hints)


def diagnose(clip_id: str, clip: Path, expected: int | None, model: str, out_dir: Path) -> dict:
    frames, booked, oracle_tops, bar_resets = analyse(clip, model)

    matched, missed = [], []
    remaining = list(booked)
    for top in oracle_tops:
        hit = next((b for b in remaining if abs(b - top) <= MATCH_WINDOW_MS), None)
        if hit is None:
            missed.append(classify_miss(frames, top))
        else:
            remaining.remove(hit)
            matched.append(top)

    rejected_by_gate: dict[str, int] = {}
    for f in frames:
        key = REASONS.get(f.rejection or "", "(counted/none)") if f.rejection else "(counted/none)"
        rejected_by_gate[key] = rejected_by_gate.get(key, 0) + 1

    out_dir.mkdir(parents=True, exist_ok=True)
    with (out_dir / f"{clip_id}.events.jsonl").open("w") as fh:
        for f in frames:
            fh.write(json.dumps(f.as_event()) + "\n")

    with (out_dir / f"{clip_id}.timeline.csv").open("w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["timeMs", "elbowAngle", "deadHangThreshold", "headY", "barLineY",
                    "pullupDownSeen", "headAboveBar", "barGateOpen", "dropoutFrames",
                    "signal", "learnedRange", "booked", "count", "rejection"])
        for f in frames:
            w.writerow([f.time_ms, round(f.elbow_angle, 2) if not math.isnan(f.elbow_angle) else "",
                        round(f.dead_hang_threshold, 2),
                        round(f.head_y, 1) if f.head_y is not None else "",
                        round(f.bar_line_y, 1) if f.bar_line_y is not None else "",
                        f.pullup_down_seen, f.head_above_bar, f.bar_gate_open, f.dropout_frames,
                        round(f.signal, 2) if not math.isnan(f.signal) else "",
                        round(f.learned_range, 2), f.booked, f.count, f.rejection or ""])

    summary = {
        "scenarioId": clip_id,
        "expectedReps": expected,
        "actualReps": frames[-1].count if frames else 0,
        "signedError": (frames[-1].count - expected) if (frames and expected is not None) else None,
        "visualRepsFromOracle": len(oracle_tops),
        "matchedReps": len(matched),
        "unexplainedBookings": len(remaining),
        "countTimestampsMs": booked,
        "oracleTopTimestampsMs": oracle_tops,
        "barRelearningEvents": bar_resets,
        "longestDropoutRun": max((f.dropout_frames for f in frames), default=0),
        "framesByGate": dict(sorted(rejected_by_gate.items(), key=lambda kv: -kv[1])),
        "missedCycles": [
            {"topTimeMs": m.top_time_ms, "classification": m.classification,
             "detail": m.detail, "windowHints": m.window_hints} for m in missed
        ],
    }
    (out_dir / f"{clip_id}.summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    return summary


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--clip", action="append", default=[], help="clip id, repeatable")
    parser.add_argument("--all", action="store_true", help="every pull-up clip in the manifest")
    parser.add_argument("--model", default="movenet_thunder.tflite")
    parser.add_argument("--out-dir", type=Path, default=ROOT / "tests/reports/diagnostics")
    args = parser.parse_args()

    manifest = json.loads((ROOT / "tests/fixtures/youtube/sources.json").read_text())
    labels = {}
    for s in json.loads((ROOT / "tests/scenarios/youtube.json").read_text())["scenarios"]:
        labels[Path(s["video"]).stem] = s["expectedReps"]

    wanted = [c for c in manifest["clips"] if c["group"] == "pullups"] if args.all \
        else [c for c in manifest["clips"] if c["id"] in set(args.clip)]
    if not wanted:
        parser.error("nothing selected; pass --clip <id> or --all")

    summaries = []
    for clip in wanted:
        path = ROOT / "tests/fixtures/youtube" / clip["group"] / f"{clip['id']}.mp4"
        if not path.is_file():
            print(f"missing fixture: {path} (run fetch_youtube.py)", file=sys.stderr)
            continue
        s = diagnose(clip["id"], path, labels.get(clip["id"], clip.get("reps")), args.model,
                     args.out_dir)
        summaries.append(s)

        print(f"\n=== {s['scenarioId']} ===")
        print(f"  expected {s['expectedReps']}  actual {s['actualReps']}  "
              f"error {s['signedError']}")
        print(f"  oracle saw {s['visualRepsFromOracle']} visual reps, "
              f"{s['matchedReps']} matched a booking")
        print(f"  bar relearning events: {s['barRelearningEvents']}   "
              f"longest dropout run: {s['longestDropoutRun']}")
        for m in s["missedCycles"]:
            print(f"  MISSED @{m['topTimeMs']}ms  {m['classification']}  — {m['detail']}")
        if s["unexplainedBookings"]:
            print(f"  {s['unexplainedBookings']} booking(s) matched no visual repetition")

    print(f"\nartifacts: {args.out_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
