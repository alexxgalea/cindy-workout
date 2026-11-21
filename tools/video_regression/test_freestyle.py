"""Tests for the Python Freestyle twin (cindy_sim/freestyle.py), through its inputs and outputs.
Run with:

    python3 -m unittest tools/video_regression/test_freestyle.py

The twin mirrors FreestyleEngine.kt and FreestyleSets.kt; the same cases are held in
FreestyleEngineTest.kt and FreestyleSetsTest.kt, and freestyle_parity_check.py diffs the two.
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from cindy_sim import pose_fixtures
from cindy_sim.freestyle import (FREESTYLE_IDLE_LINE, REST_THRESHOLD_MS, FreestyleEngine, GapKind, RepMark,
                                 derive_sets)
from cindy_sim.recogniser import Movement
from cindy_sim.workout_engine import Exercise


class Driver:
    def __init__(self) -> None:
        self.engine = FreestyleEngine()
        self.engine.start(0)
        self.clock = 0
        self.last = self.engine.on_frame(pose_fixtures.empty(), 0)
        self.banked_events: list = []
        self.said: list = []

    def hold(self, pose, for_ms: int = 1000) -> None:
        for _ in range(for_ms // 100):
            self.clock += 100
            self.last = self.engine.on_frame(pose, self.clock, True)
            self.banked_events += self.last.banked
            self.said += self.last.voice

    def pushup_rep(self) -> None:
        self.hold(pose_fixtures.pushup(80.0))
        self.hold(pose_fixtures.pushup(175.0))


class FreestyleEngineTest(unittest.TestCase):
    def test_a_lone_first_rep_shows_and_banks_nothing(self):
        d = Driver()
        d.hold(pose_fixtures.pushup(175.0))
        d.pushup_rep()
        self.assertEqual(0, d.last.figure)
        self.assertIsNone(d.last.movement)
        self.assertEqual(FREESTYLE_IDLE_LINE, d.last.line)
        self.assertEqual([], d.said)

    def test_the_2nd_rep_confirms_with_both_banked(self):
        d = Driver()
        d.hold(pose_fixtures.pushup(175.0))
        d.pushup_rep()
        d.pushup_rep()
        self.assertIs(Movement.PUSH_UPS, d.last.movement)
        self.assertEqual(2, d.last.figure)
        self.assertEqual("PUSH-UPS · 2 total", d.last.line)
        self.assertEqual([("confirmed", Movement.PUSH_UPS, 2)], d.said)
        d.pushup_rep()
        self.assertEqual(3, d.last.figure)
        self.assertEqual(("count", None, 3), d.said[-1])

    def test_stop_files_the_marks_and_the_derived_sets(self):
        d = Driver()
        d.hold(pose_fixtures.pushup(175.0))
        for _ in range(3):
            d.pushup_rep()
        filed = d.engine.stop(d.clock)
        self.assertEqual({Exercise.PUSHUP: 3}, filed.totals)
        self.assertEqual(3, len(filed.marks))
        self.assertEqual(1, len(filed.sets))
        self.assertEqual(3, filed.sets[0].reps)

    def test_nothing_banked_files_nothing(self):
        d = Driver()
        d.hold(pose_fixtures.empty())
        self.assertIsNone(d.engine.stop(d.clock))

    def test_frames_before_start_and_while_paused_count_nothing(self):
        engine = FreestyleEngine()
        frame = engine.on_frame(pose_fixtures.pushup(80.0), 100)
        self.assertEqual(0, frame.figure)
        self.assertEqual(0, engine.total_reps())


class DeriveSetsTest(unittest.TestCase):
    def marks(self, *pairs):
        return [RepMark(t, m, False) for t, m in pairs]

    def test_the_threshold_is_provisional_and_12_seconds(self):
        self.assertEqual(12_000, REST_THRESHOLD_MS)

    def test_a_gap_over_the_threshold_inside_one_movement_is_a_rest(self):
        sets, gaps = derive_sets(self.marks(
            (0, Exercise.PUSHUP), (2000, Exercise.PUSHUP), (14_001, Exercise.PUSHUP),
            (14_002 + REST_THRESHOLD_MS, Exercise.PUSHUP)))
        self.assertEqual([(2, 0, 2000), (1, 14_001, 14_001), (1, 26_002, 26_002)],
                         [(s.reps, s.start_ms, s.end_ms) for s in sets])
        self.assertEqual([GapKind.REST, GapKind.REST], [g.kind for g in gaps])

    def test_a_gap_of_exactly_the_threshold_stays_in_the_set(self):
        sets, _ = derive_sets(self.marks((0, Exercise.SQUAT), (REST_THRESHOLD_MS, Exercise.SQUAT)))
        self.assertEqual(1, len(sets))

    def test_a_change_of_movement_is_a_transition(self):
        sets, gaps = derive_sets(self.marks((0, Exercise.PULLUP), (1000, Exercise.PULLUP), (5000, Exercise.SQUAT)))
        self.assertEqual([Exercise.PULLUP, Exercise.SQUAT], [s.movement for s in sets])
        self.assertEqual([(GapKind.TRANSITION, 1000, 5000)], [(g.kind, g.start_ms, g.end_ms) for g in gaps])

    def test_no_marks_derive_no_sets(self):
        self.assertEqual(([], []), derive_sets([]))


if __name__ == "__main__":
    unittest.main()
