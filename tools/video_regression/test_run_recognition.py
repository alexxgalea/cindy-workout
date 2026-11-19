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
from cindy_sim.recogniser import Movement
from cindy_sim.workout_engine import CindyProfile, PullVariant
from run_recognition import (Frame, check_movement_windows, check_windows, confirmations, real_rep, runs,
                             track_positions, track_recognitions)


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


def squat_set(reps: int) -> list[Frame]:
    """Standing, then `reps` squats at 100 ms a frame."""
    frames = frames_of(pose_fixtures.squat(175.0), 0, 1000)
    t = 1000
    for _ in range(reps):
        frames += frames_of(pose_fixtures.squat(80.0), t, t + 800)
        frames += frames_of(pose_fixtures.squat(175.0), t + 800, t + 1600)
        t += 1600
    return frames


class ConfirmationsTest(unittest.TestCase):
    def test_a_movement_is_confirmed_once_at_its_second_rep(self):
        track = track_recognitions(squat_set(4))
        confirmed = confirmations(track)
        self.assertEqual([Movement.SQUATS], [m for _, m in confirmed])
        t = confirmed[0][0]
        self.assertEqual(Movement.SQUATS, dict(track)[t].movement)
        self.assertIsNone(dict(track)[t - 100].movement)
        self.assertEqual(2, dict(track)[t].tally_of(Movement.SQUATS))

    def test_one_rep_confirms_nothing(self):
        self.assertEqual([], confirmations(track_recognitions(squat_set(1))))

    def test_the_profile_reaches_the_recogniser(self):
        def hang(profile):
            frames = frames_of(pose_fixtures.hang_with_legs(120.0), 0, 4000)
            t = 4000
            for _ in range(4):
                frames += frames_of(pose_fixtures.hang_with_legs(60.0), t, t + 800)
                frames += frames_of(pose_fixtures.hang_with_legs(120.0), t + 800, t + 1600)
                t += 1600
            return confirmations(track_recognitions(frames, profile))

        self.assertEqual([], hang(CindyProfile()))
        self.assertEqual([Movement.PULL_UPS],
                         [m for _, m in hang(CindyProfile(pull=PullVariant.BAND_ASSISTED_PULL_UP))])


class RealRepTest(unittest.TestCase):
    LABELS = [9000, 11000, 14300]

    def test_counts_the_labelled_reps_done_by_then(self):
        self.assertEqual(0, real_rep(self.LABELS, 8000))
        self.assertEqual(2, real_rep(self.LABELS, 12000))
        self.assertEqual(3, real_rep(self.LABELS, 20000))

    def test_a_rep_labelled_a_moment_after_the_confirmation_counts_as_done(self):
        # The label is good to a fraction of a second, not to the frame.
        self.assertEqual(2, real_rep(self.LABELS, 10866))
        self.assertEqual(1, real_rep(self.LABELS, 10700))


class CheckMovementWindowsTest(unittest.TestCase):
    WINDOWS = [
        {"label": "push-ups", "fromMs": 0, "toMs": 5000, "movement": "pushup"},
        {"label": "walk", "fromMs": 5000, "toMs": 8000, "movement": "none"},
        {"label": "squats", "fromMs": 8000, "toMs": 20000, "movement": "squat"},
    ]

    def test_passes_when_each_movement_is_confirmed_in_its_own_window(self):
        confirmed = [(3000, Movement.PUSH_UPS), (12000, Movement.SQUATS)]
        self.assertEqual([], check_movement_windows(confirmed, self.WINDOWS))

    def test_a_confirmation_in_another_movements_window_is_wrong(self):
        confirmed = [(3000, Movement.SQUATS), (12000, Movement.SQUATS)]
        failures = check_movement_windows(confirmed, self.WINDOWS)
        self.assertTrue(any("wrong confirmation" in f and "push-ups" in f for f in failures))
        self.assertTrue(any("never confirmed" in f and "push-ups" in f for f in failures))

    def test_a_confirmation_while_doing_no_movement_is_wrong(self):
        confirmed = [(3000, Movement.PUSH_UPS), (6000, Movement.SQUATS), (12000, Movement.SQUATS)]
        failures = check_movement_windows(confirmed, self.WINDOWS)
        self.assertEqual(1, len(failures))
        self.assertIn("walk", failures[0])

    def test_a_confirmation_in_no_window_is_wrong(self):
        failures = check_movement_windows([(3000, Movement.PUSH_UPS), (12000, Movement.SQUATS),
                                           (25000, Movement.PULL_UPS)], self.WINDOWS)
        self.assertEqual(1, len(failures))
        self.assertIn("no window", failures[0])

    def test_a_movement_never_confirmed_in_its_window_fails(self):
        failures = check_movement_windows([(3000, Movement.PUSH_UPS)], self.WINDOWS)
        self.assertEqual(1, len(failures))
        self.assertIn("squats", failures[0])


if __name__ == "__main__":
    unittest.main()
