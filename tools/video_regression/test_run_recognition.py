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
                             score_film, timeline_lines, track_positions, track_recognitions)


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


class ScoreFilmTest(unittest.TestCase):
    """The three metrics of #181 and the thresholds that fail a run."""

    WINDOWS = [
        {"label": "push-ups", "fromMs": 0, "toMs": 20000, "movement": "pushup"},
        {"label": "walk", "fromMs": 20000, "toMs": 25000, "movement": "none"},
        {"label": "squats", "fromMs": 25000, "toMs": 50000, "movement": "squat"},
    ]
    LABELS = {"pushup": [2000, 4000, 6000, 8000, 10000], "squat": [27000, 29000, 31000, 33000]}

    def score(self, confirmed, windows=None):
        return score_film(confirmed, windows or self.WINDOWS, self.LABELS)

    def test_a_clean_film_has_no_wrong_no_idle_and_each_set_confirmed_by_its_third_rep(self):
        score = self.score([(5000, Movement.PUSH_UPS), (30000, Movement.SQUATS)])
        self.assertEqual(([], []), (score.wrong, score.idle))
        self.assertEqual([("pushup", 5000, 2, "ok"), ("squat", 30000, 2, "ok")],
                         [(s.movement, s.confirmed_ms, s.real_rep, s.status) for s in score.sets])
        self.assertFalse(score.failed)

    def test_a_confirmation_in_another_movements_window_is_wrong_not_idle(self):
        score = self.score([(5000, Movement.PUSH_UPS), (6000, Movement.SQUATS), (30000, Movement.SQUATS)])
        self.assertEqual(1, len(score.wrong))
        self.assertIn("6000", score.wrong[0])
        self.assertEqual([], score.idle)
        self.assertTrue(score.failed)

    def test_a_confirmation_inside_a_none_window_is_idle_not_wrong(self):
        score = self.score([(5000, Movement.PUSH_UPS), (22000, Movement.SQUATS), (30000, Movement.SQUATS)])
        self.assertEqual([], score.wrong)
        self.assertEqual(1, len(score.idle))
        self.assertIn("walk", score.idle[0])
        self.assertTrue(score.failed)

    def test_a_confirmation_in_no_window_is_wrong(self):
        score = self.score([(5000, Movement.PUSH_UPS), (30000, Movement.SQUATS), (60000, Movement.PULL_UPS)])
        self.assertEqual(1, len(score.wrong))
        self.assertIn("no window", score.wrong[0])

    def test_a_set_confirmed_at_its_third_real_rep_passes_and_at_its_fourth_fails(self):
        self.assertFalse(self.score([(6000, Movement.PUSH_UPS), (30000, Movement.SQUATS)]).failed)
        late = self.score([(8500, Movement.PUSH_UPS), (30000, Movement.SQUATS)])
        self.assertEqual(("late", 4), (late.sets[0].status, late.sets[0].real_rep))
        self.assertTrue(late.failed)

    def test_the_real_rep_counts_only_reps_labelled_inside_the_sets_own_window(self):
        labels = {"pushup": [2000, 4000], "squat": [27000, 29000, 31000, 33000]}
        score = score_film([(5000, Movement.PUSH_UPS), (30000, Movement.SQUATS)], self.WINDOWS, labels)
        self.assertEqual([2, 2], [s.real_rep for s in score.sets])

    def test_a_set_never_confirmed_is_reported_and_fails(self):
        score = self.score([(5000, Movement.PUSH_UPS)])
        self.assertEqual(("squat", None, None, "never"),
                         (score.sets[1].movement, score.sets[1].confirmed_ms, score.sets[1].real_rep,
                          score.sets[1].status))
        self.assertTrue(score.failed)

    def test_a_known_gap_never_confirmed_is_reported_loudly_and_does_not_fail(self):
        windows = [dict(w, knownGap="the engine counts 1 of 5") if w["movement"] == "squat" else w
                   for w in self.WINDOWS]
        score = self.score([(5000, Movement.PUSH_UPS)], windows)
        self.assertEqual("known_gap", score.sets[1].status)
        self.assertEqual("the engine counts 1 of 5", score.sets[1].reason)
        self.assertFalse(score.failed)

    def test_a_known_gap_does_not_excuse_a_wrong_confirmation(self):
        windows = [dict(w, knownGap="x") if w["movement"] == "squat" else w for w in self.WINDOWS]
        self.assertTrue(self.score([(5000, Movement.PUSH_UPS), (22000, Movement.SQUATS)], windows).failed)

    def test_a_known_gap_confirmed_in_time_is_a_pass_that_says_the_gap_is_closed(self):
        windows = [dict(w, knownGap="x") if w["movement"] == "squat" else w for w in self.WINDOWS]
        score = self.score([(5000, Movement.PUSH_UPS), (30000, Movement.SQUATS)], windows)
        self.assertEqual("ok", score.sets[1].status)
        self.assertFalse(score.failed)

    def test_a_window_shifted_off_its_film_fails_the_run(self):
        # The deliberate failure: the same confirmations, every window moved 20 s later.
        shifted = [dict(w, fromMs=w["fromMs"] + 20000, toMs=w["toMs"] + 20000) for w in self.WINDOWS]
        self.assertTrue(self.score([(5000, Movement.PUSH_UPS), (30000, Movement.SQUATS)], shifted).failed)


class TimelineTest(unittest.TestCase):
    def test_lists_window_starts_positions_and_confirmations_in_time_order(self):
        windows = [{"label": "walk", "fromMs": 0, "toMs": 4000, "movement": "none"},
                   {"label": "squats", "fromMs": 4000, "toMs": 9000, "movement": "squat"}]
        positions = [(0, 4000, Position.NONE), (4000, 9000, Position.STANDING)]
        lines = timeline_lines(positions, [(6500, Movement.SQUATS)], windows, {"squat": [5000, 6000, 7000]})
        text = "\n".join(lines)
        self.assertLess(text.index("walk"), text.index("squats"))
        self.assertLess(text.index("standing"), text.index("CONFIRMED"))
        self.assertIn("6.50s", text)
        self.assertIn("real rep 2 of 3", text)


if __name__ == "__main__":
    unittest.main()
