"""Tests for the Freestyle scoring in run_recognition.py: per-movement totals against the labelled
reps, and derived set boundaries against labelled sets. Run with:

    python3 -m unittest tools/video_regression/test_freestyle_score.py

A check that quietly passes everything is a rubber stamp, so each case is one the check exists for.
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from cindy_sim import pose_fixtures
from cindy_sim.freestyle import FreestyleSet
from cindy_sim.workout_engine import Exercise
from run_recognition import (SET_TOLERANCE_MS, Frame, freestyle_session, score_set_boundaries, score_totals)

WINDOWS = [
    {"movement": "pullup", "fromMs": 0, "toMs": 1000},
    {"movement": "pushup", "fromMs": 1000, "toMs": 2000},
]
LABELLED = {"pullup": [100, 200, 300], "pushup": [1100, 1200]}


class ScoreTotalsTest(unittest.TestCase):
    def test_totals_equal_to_the_labelled_reps_pass(self):
        results = score_totals({"pullup": 3, "pushup": 2}, LABELLED, WINDOWS)
        self.assertEqual(["ok", "ok"], [r.status for r in results])
        self.assertFalse(any(r.fails for r in results))

    def test_a_total_that_differs_either_way_fails(self):
        results = score_totals({"pullup": 2, "pushup": 3}, LABELLED, WINDOWS)
        self.assertEqual(["wrong", "wrong"], [r.status for r in results])
        self.assertTrue(all(r.fails for r in results))

    def test_a_movement_never_banked_counts_as_zero_and_fails(self):
        results = score_totals({"pullup": 3}, LABELLED, WINDOWS)
        self.assertEqual("wrong", results[1].status)
        self.assertEqual(0, results[1].banked)

    def test_a_labelled_known_gap_is_reported_and_does_not_fail(self):
        windows = [dict(WINDOWS[0], knownGap="kipping, #184"), WINDOWS[1]]
        result = score_totals({"pullup": 1, "pushup": 2}, LABELLED, windows)[0]
        self.assertEqual("known_gap", result.status)
        self.assertFalse(result.fails)
        self.assertIn("kipping, #184", result.reason)

    def test_a_known_gap_that_has_closed_says_so(self):
        windows = [dict(WINDOWS[0], knownGap="kipping, #184"), WINDOWS[1]]
        self.assertEqual("gap_closed", score_totals({"pullup": 3, "pushup": 2}, LABELLED, windows)[0].status)

    def test_a_known_gap_excuses_only_its_own_movement(self):
        windows = [dict(WINDOWS[0], knownGap="kipping, #184"), WINDOWS[1]]
        results = score_totals({"pullup": 1, "pushup": 1}, LABELLED, windows)
        self.assertEqual(["known_gap", "wrong"], [r.status for r in results])

    def test_a_movement_with_no_labelled_reps_is_not_scored(self):
        self.assertEqual([], score_totals({"squat": 4}, {}, []))


def a_set(movement, start, end, reps=3):
    return FreestyleSet(movement, reps, start, end)


LABELLED_SETS = [{"movement": "pullup", "startMs": 1000, "endMs": 5000},
                 {"movement": "squat", "startMs": 9000, "endMs": 20000}]


class ScoreSetBoundariesTest(unittest.TestCase):
    def test_boundaries_within_the_tolerance_pass(self):
        derived = [a_set(Exercise.PULLUP, 1000 + SET_TOLERANCE_MS, 5000 - SET_TOLERANCE_MS),
                   a_set(Exercise.SQUAT, 9000, 20000)]
        self.assertEqual([], score_set_boundaries(derived, LABELLED_SETS))

    def test_a_boundary_outside_the_tolerance_fails_naming_it(self):
        derived = [a_set(Exercise.PULLUP, 1000, 5000 + SET_TOLERANCE_MS + 1), a_set(Exercise.SQUAT, 9000, 20000)]
        failures = score_set_boundaries(derived, LABELLED_SETS)
        self.assertEqual(1, len(failures))
        self.assertIn("ends", failures[0])

    def test_a_different_number_of_sets_fails(self):
        failures = score_set_boundaries([a_set(Exercise.PULLUP, 1000, 5000)], LABELLED_SETS)
        self.assertTrue(any("2 labelled sets" in f and "1 derived" in f for f in failures))

    def test_a_set_of_another_movement_fails(self):
        derived = [a_set(Exercise.PUSHUP, 1000, 5000), a_set(Exercise.SQUAT, 9000, 20000)]
        self.assertTrue(any("pushup" in f for f in score_set_boundaries(derived, LABELLED_SETS)))

    def test_the_scenarios_own_tolerance_wins(self):
        derived = [a_set(Exercise.PULLUP, 1400, 5000), a_set(Exercise.SQUAT, 9000, 20000)]
        self.assertEqual([], score_set_boundaries(derived, LABELLED_SETS))
        self.assertEqual(1, len(score_set_boundaries(derived, LABELLED_SETS, tolerance_ms=300)))


class FreestyleSessionTest(unittest.TestCase):
    def test_a_film_is_run_as_a_session_and_files_its_totals(self):
        frames = [Frame(t, pose_fixtures.empty(), True) for t in range(0, 500, 100)]
        self.assertIsNone(freestyle_session(frames))

    def test_reps_in_the_film_are_banked(self):
        frames, t = [], 0
        for pose in [pose_fixtures.pushup(175.0)] + [pose_fixtures.pushup(a) for _ in range(3) for a in (80.0, 175.0)]:
            for _ in range(10):
                frames.append(Frame(t, pose, True))
                t += 100
        filed = freestyle_session(frames)
        self.assertEqual({Exercise.PUSHUP: 3}, filed.totals)


if __name__ == "__main__":
    unittest.main()
