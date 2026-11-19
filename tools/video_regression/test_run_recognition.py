"""Tests for the pure parts of run_recognition.py: tracking positions over frames and checking
them against labelled windows. Run with:

    python3 -m unittest tools/video_regression/test_run_recognition.py

A check that quietly passes everything would turn the harness into a rubber stamp, so the check
itself is held to the cases it exists for.
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from cindy_sim import pose_fixtures
from cindy_sim.recogniser import Position
from run_recognition import Frame, check_windows, runs, track_positions


def frames_of(pose, from_ms: int, to_ms: int, step_ms: int = 100, stable: bool = True) -> list[Frame]:
    return [Frame(t, pose, stable) for t in range(from_ms, to_ms, step_ms)]


class TrackPositionsTest(unittest.TestCase):
    def test_returns_the_position_after_every_frame_with_its_time(self):
        hang = pose_fixtures.hang_with_legs(170.0)
        track = track_positions(frames_of(hang, 0, 1000))
        self.assertEqual(10, len(track))
        self.assertEqual((0, Position.NONE), track[0])
        self.assertEqual((900, Position.ON_THE_BAR), track[-1])

    def test_an_unstable_identity_is_passed_on_to_the_recogniser(self):
        hang = pose_fixtures.hang_with_legs(170.0)
        track = track_positions(frames_of(hang, 0, 2000, stable=False))
        self.assertEqual({Position.NONE}, {position for _, position in track})


class RunsTest(unittest.TestCase):
    def test_writes_each_stretch_of_one_position_once_with_where_it_ends(self):
        track = [(0, Position.NONE), (100, Position.NONE), (200, Position.STANDING), (300, Position.STANDING),
                 (400, Position.NONE)]
        self.assertEqual(
            [(0, 200, Position.NONE), (200, 400, Position.STANDING), (400, 400, Position.NONE)], runs(track))


class CheckWindowsTest(unittest.TestCase):
    TRACK = [(t, Position.ON_THE_FLOOR if t < 2000 else Position.STANDING) for t in range(0, 4000, 100)]

    def test_passes_when_every_frame_of_the_window_is_the_position_asked_for(self):
        windows = [{"label": "on the mat", "fromMs": 0, "toMs": 2000, "always": "on_the_floor"}]
        self.assertEqual([], check_windows(self.TRACK, windows))

    def test_fails_on_the_first_frame_that_is_another_position(self):
        windows = [{"label": "on the mat", "fromMs": 0, "toMs": 2500, "always": "on_the_floor"}]
        failures = check_windows(self.TRACK, windows)
        self.assertEqual(1, len(failures))
        self.assertIn("on the mat", failures[0])
        self.assertIn("2000", failures[0])
        self.assertIn("standing", failures[0])

    def test_the_window_includes_its_start_and_leaves_out_its_end(self):
        windows = [{"label": "w", "fromMs": 1900, "toMs": 2000, "always": "on_the_floor"}]
        self.assertEqual([], check_windows(self.TRACK, windows))
        windows = [{"label": "w", "fromMs": 2000, "toMs": 2100, "always": "standing"}]
        self.assertEqual([], check_windows(self.TRACK, windows))

    def test_never_fails_when_a_forbidden_position_appears(self):
        windows = [{"label": "rest", "fromMs": 1000, "toMs": 3000, "never": ["standing"]}]
        self.assertEqual(1, len(check_windows(self.TRACK, windows)))
        windows = [{"label": "rest", "fromMs": 0, "toMs": 2000, "never": ["standing", "on_the_bar"]}]
        self.assertEqual([], check_windows(self.TRACK, windows))

    def test_a_window_with_no_frames_in_it_fails_rather_than_passing_for_nothing(self):
        windows = [{"label": "past the end", "fromMs": 9000, "toMs": 9500, "always": "standing"}]
        failures = check_windows(self.TRACK, windows)
        self.assertEqual(1, len(failures))
        self.assertIn("no frames", failures[0])

    def test_a_window_that_asks_for_nothing_is_an_error(self):
        windows = [{"label": "empty", "fromMs": 0, "toMs": 100}]
        self.assertEqual(1, len(check_windows(self.TRACK, windows)))


if __name__ == "__main__":
    unittest.main()
