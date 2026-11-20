#!/usr/bin/env python3
"""Tests for WorkoutEngine.drop_climb_on_arrival, the twin of app/src/test/.../ArrivalTest.kt.

    python3 tools/video_regression/test_workout_engine_arrival.py
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from cindy_sim import pose_fixtures as fx
from cindy_sim.workout_engine import CindyProfile, Exercise, PullVariant, RepEvent, WorkoutEngine


class Driver:
    def __init__(self, engine: WorkoutEngine) -> None:
        self.engine = engine
        self.clock = 0

    def hold(self, pose, frames: int = 10) -> int:
        reps = 0
        for _ in range(frames):
            if self.engine.on_frame(pose, self.clock) is RepEvent.REP:
                reps += 1
            self.clock += 100
        return reps


class ArrivalTest(unittest.TestCase):
    def test_a_squat_climb_in_flight_when_the_athlete_arrives_is_not_booked(self):
        d = Driver(WorkoutEngine(fixed_exercise=Exercise.SQUAT))
        d.hold(fx.squat(80.0))
        d.engine.drop_climb_on_arrival()
        self.assertEqual(0, d.hold(fx.squat(175.0)))
        self.assertEqual(0, d.engine.reps)

    def test_without_it_the_same_climb_is_booked(self):
        d = Driver(WorkoutEngine(fixed_exercise=Exercise.SQUAT))
        d.hold(fx.squat(80.0))
        self.assertEqual(1, d.hold(fx.squat(175.0)))

    def test_a_squat_rep_after_arriving_counts_with_no_start_gate(self):
        d = Driver(WorkoutEngine(fixed_exercise=Exercise.SQUAT))
        d.hold(fx.squat(80.0))
        d.engine.drop_climb_on_arrival()
        d.hold(fx.squat(175.0))
        d.hold(fx.squat(80.0))
        self.assertEqual(1, d.hold(fx.squat(175.0)))

    def test_a_push_up_climb_in_flight_is_not_booked_and_the_next_rep_is(self):
        d = Driver(WorkoutEngine(fixed_exercise=Exercise.PUSHUP))
        d.hold(fx.pushup(80.0))
        d.engine.drop_climb_on_arrival()
        self.assertEqual(0, d.hold(fx.pushup(175.0)))
        d.hold(fx.pushup(80.0))
        self.assertEqual(1, d.hold(fx.pushup(175.0)))

    def test_it_does_not_arm_the_start_gate(self):
        engine = WorkoutEngine(fixed_exercise=Exercise.PUSHUP)
        engine.drop_climb_on_arrival()
        self.assertFalse(engine.awaiting_start)

    def _pullup_engine_on_the_bar(self) -> Driver:
        d = Driver(WorkoutEngine(fixed_exercise=Exercise.PULLUP,
                                 profile=CindyProfile(pull=PullVariant.BAND_ASSISTED_PULL_UP)))
        d.hold(fx.pullup(170.0), frames=35)
        return d

    def test_a_pull_up_rep_from_a_hang_counts(self):
        d = self._pullup_engine_on_the_bar()
        d.hold(fx.pullup(170.0))
        self.assertEqual(1, d.hold(fx.pullup(60.0)))

    def test_a_pull_up_climb_in_flight_when_the_athlete_arrives_is_not_booked(self):
        d = self._pullup_engine_on_the_bar()
        d.hold(fx.pullup(170.0))
        d.engine.drop_climb_on_arrival()
        self.assertEqual(0, d.hold(fx.pullup(60.0)))


if __name__ == "__main__":
    unittest.main()
