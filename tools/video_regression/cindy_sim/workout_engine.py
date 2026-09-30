"""Line-by-line port of app/src/main/java/com/cindy/tracker/WorkoutEngine.kt.

Side effects on `hint` are preserved exactly, including the places where the Kotlin assigns
`diagnostics` twice in one frame and the first assignment therefore carries the *previous*
frame's hint. Those quirks are load-bearing for the harness reports, so the port keeps them.

Kotlin holds this state in 32-bit `Float`s and compares against thresholds exactly
(`elbow >= DEAD_HANG_DEGREES`), so every value the Kotlin stores in a `Float` is rounded through
`f32` here. Without that, frames landing exactly on a threshold take the other branch.
"""
from __future__ import annotations

import dataclasses
import math
from dataclasses import dataclass
from enum import Enum
from typing import Sequence

from . import pose_geometry
from .bar_zone import BarZone
from .keypoints import KP, Keypoint
from .pose_geometry import (
    bilateral_angle,
    hands_overhead,
    hanging_from_bar,
    missing_joints,
    ok,
    standing,
    torso_length,
    upright,
)
from .rep_counter import NAN, Phase, RepCounter, SmartSquatCounter, f32


class Exercise(Enum):
    """One round of Cindy: 5 pull-ups, 10 push-ups, 15 air squats.

    `starts_from_position` marks the movements entered from a posture the athlete has to assume
    first. Getting up off the floor after push-ups traces the second half of a squat exactly, and
    the knee angle alone cannot tell them apart. Pull-ups are excluded: their bar and dead-hang
    gates already do this.
    """

    PULLUP = ("PULL-UPS", "pull ups", 5, False, "Hang from the bar")
    PUSHUP = ("PUSH-UPS", "push ups", 10, True, "Get set on the floor")
    SQUAT = ("SQUATS", "squats", 15, True, "Stand up to start")

    def __init__(self, label: str, spoken: str, target: int,
                 starts_from_position: bool, start_cue: str) -> None:
        self.label = label
        self.spoken = spoken
        self.target = target
        self.starts_from_position = starts_from_position
        self.start_cue = start_cue

    @property
    def ordinal(self) -> int:
        return list(Exercise).index(self)

    def next(self) -> "Exercise":
        order = list(Exercise)
        return order[(self.ordinal + 1) % len(order)]

    def previous(self) -> "Exercise":
        order = list(Exercise)
        return order[(self.ordinal + len(order) - 1) % len(order)]


class RepEvent(Enum):
    """What the last analysed frame produced."""

    NONE = "NONE"
    REP = "REP"
    UNDO = "UNDO"
    EXERCISE_DONE = "EXERCISE_DONE"
    ROUND_DONE = "ROUND_DONE"


class SetupStage(Enum):
    """How the pre-workout check is getting on."""

    FRAMING = "FRAMING"
    MOVING = "MOVING"
    READY = "READY"
    POOR = "POOR"


@dataclass(frozen=True)
class Setup:
    """A frame's worth of pre-workout check."""

    stage: SetupStage
    missing: list[str]
    reps: int
    range: float
    needed: float


@dataclass(frozen=True)
class FrameDiagnostics:
    """The gate decisions behind the most recently analysed frame."""

    minimum_confidence: float = 0.0
    #: True only when the keypoints building the current exercise signal are usable.
    scoring_confidence_adequate: bool = False
    #: True when *every* joint the current movement scores from was confidently seen.
    #:
    #: Stricter than `scoring_confidence_adequate` on purpose. That flag asks whether this frame
    #: could be scored, and the geometry helpers behind it fall back to whichever side of the body
    #: is visible, so it stays true through the single-sided view that precedes a real failure.
    #: This asks the blunter question -- how well can the camera read the athlete at all -- so
    #: that it degrades *before* counting does. An early warning is worthless if it arrives with
    #: the miscount.
    pose_legible: bool = False
    identity_stable: bool = False
    bar_gate_open: bool = False
    head_above_bar: bool = False
    dead_hang_since_last_rep: bool = False
    reset_below_bar_seen: bool = False
    rejection_reason: str | None = None


@dataclass(frozen=True)
class PullupSample:
    signal: float
    dead_hang_below_reset: bool
    head_above_bar: bool
    bar_gate_open: bool


class PullVariant(Enum):
    """What happened on the bar. Mirrors ``Variations.kt``."""

    STRICT_PULL_UP = "STRICT_PULL_UP"
    BAND_ASSISTED_PULL_UP = "BAND_ASSISTED_PULL_UP"
    INVERTED_ROW = "INVERTED_ROW"
    FOOT_ASSISTED_PULL_UP = "FOOT_ASSISTED_PULL_UP"
    NEGATIVE_PULL_UP = "NEGATIVE_PULL_UP"


class PushVariant(Enum):
    STANDARD_PUSH_UP = "STANDARD_PUSH_UP"
    KNEE_PUSH_UP = "KNEE_PUSH_UP"
    INCLINE_PUSH_UP = "INCLINE_PUSH_UP"


class SquatVariant(Enum):
    AIR_SQUAT = "AIR_SQUAT"
    HEELS_FLAT = "HEELS_FLAT"
    BOX_SQUAT = "BOX_SQUAT"
    SUPPORTED_SQUAT = "SUPPORTED_SQUAT"


@dataclass(frozen=True)
class CindyProfile:
    """The movements a session is counting, fixed before the clock starts."""

    pull: PullVariant = PullVariant.STRICT_PULL_UP
    push: PushVariant = PushVariant.STANDARD_PUSH_UP
    squat: SquatVariant = SquatVariant.AIR_SQUAT


STANDARD_PROFILE = CindyProfile()


class WorkoutEngine:
    """Turns a stream of keypoints into a Cindy scorecard.

    Only the signal for the *current* exercise is evaluated: the three movements share joints,
    and scoring all of them at once lets a push-up lockout leak into the squat counter.
    """

    #: Kept for callers outside the engine (diagnose_pullups.py reads `engine.MIN_SCORE`); the
    #: value itself now lives in pose_geometry, which is what `ok()` actually uses.
    MIN_SCORE = pose_geometry.MIN_SCORE
    CALIBRATION_REPS = 2
    POOR_AFTER_MS = 20_000
    DEAD_HANG_DEGREES = 150.0
    #: How far below the straightest arms yet seen still reads as a dead hang. 150 degrees
    #: assumes the camera sees the elbow square on; a phone on the floor foreshortens the upper
    #: arm, so a locked-out hang can project as 140 and a fixed threshold then refuses to arm a
    #: single rep. Same argument that made RepCounter learn its band rather than trust fixed
    #: thresholds, applied to the gate in front of it.
    DEAD_HANG_SLACK_DEGREES = 15.0
    #: Floor under the derived dead-hang angle. Without it the derivation eats itself: an athlete
    #: only ever seen with bent arms teaches a small "extension", which drops the threshold far
    #: enough that those bent arms then qualify as a hang.
    DEAD_HANG_FLOOR_DEGREES = 130.0
    #: Body-scale change past which a learned bar describes a geometry that has gone. The bar's
    #: tolerances are multiples of torso length, so an estimate learned while the athlete stood
    #: close to the camera does not fit them hanging further away.
    BAR_SCALE_CHANGE = 1.6
    #: Straight-armed hangs rejected at that different scale before the bar is abandoned.
    MAX_BAR_CONTRADICTIONS = 30
    #: How long hands must hang overhead without moving before their position is taken as the
    #: bar, when no dead hang has managed to establish one. Long on purpose: this is the slow
    #: fallback behind the dead-hang route, and stillness is the weaker evidence of the two.
    BAR_SETTLE_MS = 3_000
    #: How far the hands may drift, in torso lengths, and still count as held still.
    BAR_SETTLE_DRIFT_TORSOS = 0.2
    #: How far below the bar the head must return before another pull-up can arm.
    HEAD_RESET_TORSOS = 0.25
    #: Consecutive overhead frames before a bar may be learned on the strength of a nose that
    #: could not be seen. `pose_geometry.hands_overhead` answers true when the nose is unseen,
    #: deliberately, so rear views are not locked out -- but that turns a missing keypoint into
    #: permission, and one dropped nose frame was enough to teach a false bar at chest height
    #: that can never recover. A visible nose below the hands is real evidence and still learns
    #: on the first frame.
    OVERHEAD_HOLD_FRAMES = 5
    #: Unusable frames tolerated mid-rep before the cycle is abandoned. A pull-up occludes its
    #: own keypoints exactly where it matters -- at the top, where the head tilts back and the
    #: wrists disappear behind it -- so treating the first sub-threshold frame as "left the bar"
    #: threw the rep away at the moment it was earned.
    MAX_DROPOUT_FRAMES = 8
    #: How long the starting posture must hold, without extending further, to be taken up.
    START_POSITION_MS = 500
    #: Further extension than this, within the dwell, means they are still getting up.
    START_SETTLE_DEGREES = 3.0
    #: Smoothing on the settling signal, so raw jitter does not read as still rising.
    START_SETTLE_SMOOTHING = 0.4
    #: The least a heels-flat squat has to close the knee, in degrees, to be a rep. Heels flat on
    #: the floor stop the knees travelling forward, so the knee closes less than it does up on the
    #: toes. A quarter squat from chest height travels 30 to 35, so this is the line between them,
    #: and the one number to retune after trying it on a phone.
    HEELS_FLAT_MIN_TRAVEL = 35.0
    #: How much of the learned travel, from the bottom, counts as having gone down. Sixty percent
    #: where every other movement uses thirty, so a heels-flat rep after a deep one still arms.
    HEELS_FLAT_BOTTOM_MARGIN = 0.6
    #: Where an uncalibrated heels-flat squat has to have got to, in knee degrees. The climb from
    #: here to the lockout (38) is just over HEELS_FLAT_MIN_TRAVEL, as the air squat's is over its own.
    HEELS_FLAT_DOWN_BELOW = 120.0
    #: Reps only the heels-flat counter has to accept, in one block, before smart counting goes
    #: over to it.
    SMART_SQUAT_SPOT_REPS = 3

    def __init__(
        self,
        fixed_exercise: Exercise | None = None,
        profile: CindyProfile = STANDARD_PROFILE,
        smart_squats: bool = False,
    ) -> None:
        self._fixed_exercise = fixed_exercise
        #: Immutable for the life of the engine: a rep's meaning must not change halfway
        #: through the score it contributes to.
        self.profile = profile
        #: Whether an air-squat session may notice heels-flat squats and start counting them as
        #: such. Off unless asked for, and fixed for the life of the engine like the profile.
        self.smart_squats = smart_squats
        self._counters = {
            Exercise.PULLUP: RepCounter(-140.0, -100.0, min_rep_ms=400, min_range=40.0),
            Exercise.PUSHUP: RepCounter(100.0, 150.0, min_rep_ms=350, min_range=45.0),
            Exercise.SQUAT: self._squat_counter(),
        }
        self.exercise = fixed_exercise or Exercise.PULLUP
        self.rounds = 0
        self.hint = "Step into frame"
        self.body_visible = False
        self.diagnostics = FrameDiagnostics()
        #: True while waiting for the athlete to take up the movement's starting position.
        self.awaiting_start = False
        #: True when this frame was refused for a reason the athlete could fix by moving.
        self.blocked = False
        #: When the current run of correct, no-longer-extending posture began, or 0 if broken.
        self._start_position_since = 0
        #: Smoothed signal while taking up a position, and the value the dwell was measured from.
        self._start_smoothed = NAN
        self._start_reference = NAN

        self._moving_since = 0
        self._bar = BarZone()
        self._setup_in_progress = False
        #: A fresh, on-bar dead hang is required before every pull-up count.
        self._pullup_down_seen = False
        #: Consecutive unusable frames since the last good one, while a cycle is in flight.
        self._pullup_dropout_frames = 0
        #: Straightest elbow angle seen while hanging, which scales the dead-hang test.
        self._pullup_extended_elbow = NAN
        #: Torso length when the current bar estimate was first established.
        self._bar_torso = NAN
        #: Consecutive dead hangs a bar learned at a very different scale has refused.
        self._bar_contradictions = 0
        #: When the current run of still, overhead hands began, or 0 while broken.
        self._overhead_frames = 0
        self._bar_settle_since = 0
        #: Hand position the current still run is measured from, or None while broken.
        self._bar_settle_hands: Keypoint | None = None
        #: The score the movement had reached when the last event fired.
        self.reps_at_last_event = 0
        #: What each movement of the round in progress actually scored, as it was left.
        self._banked_this_round: dict[Exercise, int] = {}
        #: The same for every finished round, kept per round so undo can step back into one.
        self._banked_rounds: list[dict[Exercise, int]] = []

    def _squat_counter(self):
        """The counter for the chosen squat. Only the air squat is ever made smart."""
        squat = self.profile.squat
        if squat is SquatVariant.HEELS_FLAT:
            return self._heels_flat_counter()
        if squat is SquatVariant.AIR_SQUAT:
            if not self.smart_squats:
                return self._air_squat_counter()
            credit_cap = Exercise.SQUAT.target if self._fixed_exercise is None else 2 ** 31 - 1
            return SmartSquatCounter(
                self._air_squat_counter(), self._heels_flat_counter(),
                self.SMART_SQUAT_SPOT_REPS, credit_cap,
            )
        return self._air_squat_counter()

    @staticmethod
    def _air_squat_counter() -> RepCounter:
        return RepCounter(100.0, 158.0, min_rep_ms=350, min_range=55.0)

    @classmethod
    def _heels_flat_counter(cls) -> RepCounter:
        return RepCounter(
            cls.HEELS_FLAT_DOWN_BELOW, 158.0, min_rep_ms=350,
            min_range=cls.HEELS_FLAT_MIN_TRAVEL,
            bottom_margin=cls.HEELS_FLAT_BOTTOM_MARGIN,
            min_travel=cls.HEELS_FLAT_MIN_TRAVEL,
        )

    # -- observable state -------------------------------------------------

    @property
    def heels_flat_spotted(self) -> bool:
        """True once smart squat counting has noticed heels-flat squats and taken over."""
        counter = self._counters[Exercise.SQUAT]
        return isinstance(counter, SmartSquatCounter) and counter.switched

    @property
    def counted_profile(self) -> CindyProfile:
        """What the session was actually counted as: the choice, unless smart counting took over."""
        if self.heels_flat_spotted:
            return dataclasses.replace(self.profile, squat=SquatVariant.HEELS_FLAT)
        return self.profile

    @property
    def counting_state(self) -> str:
        """Stable spelling for scenario files; hides RepCounter's implementation enum."""
        return {Phase.UNKNOWN: "idle", Phase.DOWN: "down", Phase.UP: "up"}[self.phase]

    @property
    def bar_known(self) -> bool:
        return self._bar.established

    @property
    def reps(self) -> int:
        return self._counters[self.exercise].count

    @property
    def phase(self) -> Phase:
        return self._counters[self.exercise].phase

    @property
    def signal(self) -> float:
        return self._counters[self.exercise].smoothed

    @property
    def learned_range(self) -> float:
        return self._counters[self.exercise].learned_range

    @property
    def calibrated(self) -> bool:
        return self._counters[self.exercise].calibrated

    @property
    def reps_this_round(self) -> int:
        """Reps since the round started, counting what each movement actually scored.

        The movements already left contribute their real counts, not their targets. Those two
        only differ when something was skipped, which is the case this used to get wrong.
        """
        return sum(self._banked_this_round.values()) + self.reps

    @property
    def total_reps(self) -> int:
        return sum(sum(r.values()) for r in self._banked_rounds) + self.reps_this_round

    # -- configuration ----------------------------------------------------

    def configure_manual_bar(
        self,
        y_normalized: float,
        x_min_normalized: float,
        x_max_normalized: float,
        frame_width: int,
        frame_height: int,
    ) -> None:
        """Configures a recorded clip's bar from normalised video coordinates."""
        if not (frame_width > 0 and frame_height > 0):
            raise ValueError("Frame dimensions must be positive")
        self._bar.configure_manual(
            y=y_normalized * frame_height,
            x_min=x_min_normalized * frame_width,
            x_max=x_max_normalized * frame_width,
        )
        self._pullup_down_seen = False
        self._overhead_frames = 0
        self._bar_settle_since = 0
        self._bar_settle_hands = None
        self._counters[Exercise.PULLUP].require_fresh_down()

    def reset(self) -> None:
        for counter in self._counters.values():
            counter.reset()
        self.exercise = self._fixed_exercise or Exercise.PULLUP
        self.rounds = 0
        self.hint = "Step into frame"
        self.body_visible = False
        self._moving_since = 0
        self._setup_in_progress = False
        self._pullup_down_seen = False
        self._pullup_extended_elbow = NAN
        self._bar_torso = NAN
        self._bar_contradictions = 0
        self._overhead_frames = 0
        self._bar_settle_since = 0
        self._bar_settle_hands = None
        self.awaiting_start = False
        self._start_position_since = 0
        self._start_smoothed = NAN
        self._start_reference = NAN
        self.blocked = False
        self.reps_at_last_event = 0
        self._banked_this_round.clear()
        self._banked_rounds.clear()
        self.diagnostics = FrameDiagnostics()
        self._bar.reset()

    def skip_exercise(self) -> RepEvent:
        return self._advance()

    def manual_rep(self) -> RepEvent:
        self._counters[self.exercise].force_increment()
        return self._settle()

    def undo_rep(self) -> RepEvent:
        self.awaiting_start = False
        counter = self._counters[self.exercise]
        if counter.count > 0:
            counter.force_decrement()
            self.reps_at_last_event = counter.count
            return RepEvent.UNDO
        if self.exercise is not Exercise.PULLUP:
            self.exercise = self.exercise.previous()
            self._step_back_into(self.exercise)
            return RepEvent.UNDO
        if self.rounds == 0:
            return RepEvent.NONE
        self.rounds -= 1
        # The round being stepped back into is the one just filed away.
        self._banked_this_round.clear()
        if self._banked_rounds:
            self._banked_this_round.update(self._banked_rounds.pop())
        self.exercise = Exercise.SQUAT
        self._step_back_into(Exercise.SQUAT)
        return RepEvent.UNDO

    def _step_back_into(self, movement: Exercise) -> None:
        """Re-enters a movement already left, at one rep below what it actually scored.

        "One below its target" was the old answer, and it handed back reps nobody did to anyone
        who had skipped the movement.
        """
        banked = self._banked_this_round.pop(movement, movement.target)
        self._counters[movement].set_count(max(banked - 1, 0))
        self.reps_at_last_event = self._counters[movement].count

    def recalibrate(self) -> None:
        for counter in self._counters.values():
            counter.reset_band()
        self._bar.reset()
        self._pullup_down_seen = False
        self._pullup_extended_elbow = NAN
        self._bar_torso = NAN
        self._bar_contradictions = 0
        self._overhead_frames = 0
        self._bar_settle_since = 0
        self._bar_settle_hands = None
        self.diagnostics = FrameDiagnostics()

    # -- scoring ----------------------------------------------------------

    def on_frame(self, k: Sequence[Keypoint], now: int, identity_stable: bool = True) -> RepEvent:
        """Scores a running-workout frame.

        `identity_stable` comes from PoseDetector's tracked ROI. A lost ROI is the one reliable
        signal that this is no longer the same body.
        """
        if self._setup_in_progress:
            self.hint = "Finish setup first"
            self.blocked = False
            self.diagnostics = self._frame_diagnostics(k, identity_stable, rejection=self.hint)
            return RepEvent.NONE

        torso = torso_length(k)
        if torso is None or torso < 1.0:
            self.body_visible = False
            self.hint = "Step into frame"
            self.blocked = True
            if self.exercise is Exercise.PULLUP:
                self._tolerate_pullup_dropout()
            self.diagnostics = self._frame_diagnostics(k, identity_stable, rejection=self.hint)
            return RepEvent.NONE
        self.body_visible = True

        if self.exercise is Exercise.PULLUP:
            return self._on_pullup_frame(k, now, identity_stable)

        s = self._signal_for(k)
        if math.isnan(s):
            self.blocked = True
            self.diagnostics = self._frame_diagnostics(k, identity_stable, rejection=self.hint)
            return RepEvent.NONE

        counter = self._counters[self.exercise]

        if self.awaiting_start:
            # Deliberately not fed to the counter at all. Lying face down reads as a full 180
            # degrees of knee extension, and letting that into the learned band lifts the top of
            # it above anything the athlete can reach standing -- which stops every squat
            # counting rather than just the phantom one.
            self.blocked = True
            self.hint = self.exercise.start_cue
            self._take_up_position(k, s, now, counter)
            self.diagnostics = self._frame_diagnostics(
                k, identity_stable, scoring_confidence_adequate=True, rejection=self.hint
            )
            return RepEvent.NONE

        counted = counter.update(s, now)
        self.diagnostics = self._frame_diagnostics(
            k, identity_stable, scoring_confidence_adequate=True,
            rejection=None if counted else self.hint,
        )
        if not counted:
            self.hint = "Drive up" if self.phase is Phase.DOWN else "Go down"
            self.blocked = False
            self.diagnostics = self._frame_diagnostics(
                k, identity_stable, scoring_confidence_adequate=True, rejection=self.hint
            )
            return RepEvent.NONE
        self.blocked = False
        return self._settle()

    def _take_up_position(
        self, k: Sequence[Keypoint], s: float, now: int, counter: RepCounter
    ) -> None:
        """Watches the athlete take up the movement, and opens the gate once they have.

        Two things have to be true together, and neither is sufficient alone. The posture has to
        be right -- standing for squats, down for push-ups -- which rules out arriving while
        still on the floor. And the joint that scores the movement has to have stopped opening,
        which rules out arriving halfway up.
        """
        if not self._in_start_position(k):
            self._start_position_since = 0
            self._start_smoothed = NAN
            self._start_reference = NAN
            return
        if math.isnan(self._start_smoothed):
            self._start_smoothed = s
        else:
            self._start_smoothed = f32(
                self._start_smoothed
                + f32(self.START_SETTLE_SMOOTHING * f32(s - self._start_smoothed))
            )
        # Any further opening restarts the clock, however slowly it is happening.
        if (self._start_position_since == 0
                or self._start_smoothed > f32(self._start_reference + self.START_SETTLE_DEGREES)):
            self._start_position_since = now
            self._start_reference = self._start_smoothed
            return
        if now - self._start_position_since < self.START_POSITION_MS:
            return
        self.awaiting_start = False
        self.blocked = False
        # Arriving is not the top of a rep. Throwing away the climb that got here is the whole
        # point: otherwise standing up off the floor books one.
        counter.require_fresh_down()

    def _in_start_position(self, k: Sequence[Keypoint]) -> bool:
        """Standing, or down on the floor, as the current movement requires."""
        if self.exercise is Exercise.PULLUP:
            # The bar, head and dead-hang gates already refuse anything that is not a pull-up.
            return True
        if self.exercise is Exercise.PUSHUP:
            return not upright(k)
        return standing(k)

    def _settle(self) -> RepEvent:
        if self._fixed_exercise is None and self.reps >= self.exercise.target:
            return self._advance()
        self.reps_at_last_event = self.reps
        return RepEvent.REP

    def _advance(self) -> RepEvent:
        # Read before the counter is cleared: after a skip this is the only record that the
        # movement did not reach its target.
        self.reps_at_last_event = self.reps
        self._banked_this_round[self.exercise] = self.reps
        self._counters[self.exercise].reset_count()
        was_last = self.exercise is Exercise.SQUAT
        self.exercise = self.exercise.next()
        self._counters[self.exercise].reset_count()
        # Whatever the athlete does to get from the last movement into this one must not score.
        self.awaiting_start = self.exercise.starts_from_position
        self._start_position_since = 0
        self._start_smoothed = NAN
        self._start_reference = NAN
        if was_last:
            self.rounds += 1
            self._banked_rounds.append(dict(self._banked_this_round))
            self._banked_this_round.clear()
            return RepEvent.ROUND_DONE
        return RepEvent.EXERCISE_DONE

    # -- pre-workout check ------------------------------------------------

    def begin_setup(self) -> None:
        self._counters[self.exercise].reset()
        self._moving_since = 0
        self._bar.reset()
        self._setup_in_progress = True
        self._pullup_down_seen = False
        self._pullup_extended_elbow = NAN
        self._bar_torso = NAN
        self._bar_contradictions = 0
        self._overhead_frames = 0
        self._bar_settle_since = 0
        self._bar_settle_hands = None
        self.diagnostics = FrameDiagnostics()

    def on_setup_frame(self, k: Sequence[Keypoint], now: int, identity_stable: bool = True) -> Setup:
        counter = self._counters[self.exercise]
        missing = missing_joints(k, self.exercise)
        if missing:
            self._moving_since = 0
            if self.exercise is Exercise.PULLUP:
                self._tolerate_pullup_dropout()
            self.diagnostics = self._frame_diagnostics(
                k, identity_stable, rejection="Missing " + ", ".join(missing)
            )
            return Setup(SetupStage.FRAMING, missing, counter.count, counter.learned_range,
                         counter.required_range)
        if self._moving_since == 0:
            self._moving_since = now

        if self.exercise is Exercise.PULLUP:
            self._on_pullup_frame(k, now, identity_stable, settle_workout=False)
        else:
            s = self._signal_for(k)
            if not math.isnan(s):
                counter.update(s, now)
            self.diagnostics = self._frame_diagnostics(
                k, identity_stable, scoring_confidence_adequate=not math.isnan(s),
                rejection=self.hint if math.isnan(s) else None,
            )

        enough = (counter.count >= self.CALIBRATION_REPS
                  and counter.learned_range >= counter.required_range)
        if enough:
            stage = SetupStage.READY
        elif now - self._moving_since > self.POOR_AFTER_MS:
            stage = SetupStage.POOR
        else:
            stage = SetupStage.MOVING
        return Setup(stage, [], counter.count, counter.learned_range, counter.required_range)

    def finish_setup(self) -> None:
        self._counters[self.exercise].reset_count()
        self._setup_in_progress = False
        # Setup may have ended at the top of its second calibration rep. A new counted rep still
        # has to begin with a fresh dead hang below the reset line.
        self._pullup_down_seen = False
        if self.exercise is Exercise.PULLUP:
            self._counters[self.exercise].require_fresh_down()

    def _signal_for(self, k: Sequence[Keypoint]) -> float:
        if self.exercise is Exercise.PULLUP:
            # Pull-ups are handled by _on_pullup_frame, which owns the bar/head/reset gates.
            return NAN
        if self.exercise is Exercise.PUSHUP:
            return self._pushup_signal(k)
        return self._squat_signal(k)

    # -- pull-ups ---------------------------------------------------------

    def _on_pullup_frame(
        self, k: Sequence[Keypoint], now: int, identity_stable: bool, settle_workout: bool = True
    ) -> RepEvent:
        """Scores a pull-up only after the physical gates are true."""
        if not identity_stable:
            self.hint = "Tracking…"
            self.blocked = True
            self._tolerate_pullup_dropout()
            self.diagnostics = self._frame_diagnostics(k, False, rejection=self.hint)
            return RepEvent.NONE

        sample = self._pullup_sample(k, now)
        if sample is None:
            self.blocked = True
            self._tolerate_pullup_dropout()
            self.diagnostics = self._frame_diagnostics(k, True, rejection=self.hint)
            return RepEvent.NONE

        self._pullup_dropout_frames = 0

        counter = self._counters[Exercise.PULLUP]

        # Every readable on-bar frame is observed, so the band learns the athlete's real swing
        # even while the gates are shut. Only a frame that clears all of them may book a rep,
        # which is what stops an elbow-only partial from scoring. Withholding the samples
        # instead -- the previous approach -- left the counter judging reps against a band built
        # from a fraction of the movement.
        may_count = (not sample.dead_hang_below_reset and sample.head_above_bar
                     and self._pullup_down_seen)
        counted = counter.update(sample.signal, now, may_count=may_count)

        if sample.dead_hang_below_reset:
            # Observing here makes RepCounter's DOWN phase agree with the physical reset.
            if counter.phase is Phase.DOWN:
                self._pullup_down_seen = True
            # Hanging at the bottom is where a pull-up starts, not a fault worth announcing.
            # But the athlete is told "Ready" off the back of this, and that has to mean the
            # next rep will actually score -- which a hang that has not yet armed will not.
            self.blocked = not self._pullup_down_seen
            self.diagnostics = self._frame_diagnostics(
                k, True, scoring_confidence_adequate=True,
                bar_gate_open=sample.bar_gate_open, head_above_bar=sample.head_above_bar,
            )
            return RepEvent.NONE

        if not may_count:
            self.blocked = True
            if self._pullup_down_seen:
                self.hint = "Get your head over the bar"
            elif self._requires_dead_hang:
                self.hint = "Return to a dead hang"
            else:
                self.hint = "Lower all the way down"
            self.diagnostics = self._frame_diagnostics(
                k, True, scoring_confidence_adequate=True,
                bar_gate_open=sample.bar_gate_open, head_above_bar=sample.head_above_bar,
                rejection=self.hint,
            )
            return RepEvent.NONE

        self.diagnostics = self._frame_diagnostics(
            k, True, scoring_confidence_adequate=True,
            bar_gate_open=sample.bar_gate_open, head_above_bar=sample.head_above_bar,
            rejection=None if counted else "Drive up",
        )
        self.blocked = False
        if not counted:
            self.hint = "Drive up"
            return RepEvent.NONE

        # A second count cannot inherit this rep: a fresh reset below the bar is required.
        self._pullup_down_seen = False
        return self._settle() if settle_workout else RepEvent.NONE

    def _pullup_sample(self, k: Sequence[Keypoint], now: int) -> PullupSample | None:
        """Validates a pull-up pose without mutating the counter."""
        left_wrist = k[KP.LEFT_WRIST]
        right_wrist = k[KP.RIGHT_WRIST]
        if not ok(left_wrist) or not ok(right_wrist):
            self.hint = "Show both hands"
            return None
        if not hanging_from_bar(k):
            self.hint = "Hang from the bar"
            return None
        # Hands overhead is not enough to call this a hang: an inverted row also puts the wrists
        # above the hips, and every remaining gate then passes. Only the torso's direction
        # separates the families. Measured as (hip.y - shoulder.y) / torso on a progression clip:
        # vertical pulls 0.92-1.00, low/mid rows 0.33-0.86, a HIGH row 0.86-0.98 -- so the row
        # family separates but a steeply inclined high row sits inside the range real hangs
        # occupy, and is left unseparated rather than rejected by an invented threshold.
        #
        # Returning None routes the frame through _tolerate_pullup_dropout(), so a brief wobble
        # mid-rep is absorbed by the existing dropout window while a sustained row never arms.
        if not upright(k):
            self.hint = "Hang vertically from the bar"
            return None
        hands = Keypoint(
            f32((left_wrist.x + right_wrist.x) / 2.0),
            f32((left_wrist.y + right_wrist.y) / 2.0),
            min(left_wrist.score, right_wrist.score),
        )
        torso = torso_length(k)
        if torso is None:
            self.hint = "Step into frame"
            return None
        elbow = bilateral_angle(
            k,
            KP.LEFT_SHOULDER, KP.LEFT_ELBOW, KP.LEFT_WRIST,
            KP.RIGHT_SHOULDER, KP.RIGHT_ELBOW, KP.RIGHT_WRIST,
        )
        if math.isnan(elbow):
            self.hint = "Arms out of frame"
            return None
        self._pullup_extended_elbow = (
            elbow if math.isnan(self._pullup_extended_elbow)
            else max(self._pullup_extended_elbow, elbow)
        )
        dead_hang = self._dead_hang_degrees()

        # Refinement requires already passing the gate, so a bar learned in the wrong place can
        # otherwise lock the athlete out for the rest of the workout -- which is exactly what a
        # clip mis-established during a walk-up did, rejecting 2377 of 2888 frames. A sustained
        # dead hang refused at a very different body scale is evidence that the estimate, not the
        # athlete, is in the wrong place.
        if (self._bar.established and elbow >= dead_hang
                and not self._bar.holds(left_wrist, right_wrist, torso)):
            if math.isnan(self._bar_torso) or self._bar_torso <= 0.0 or torso <= 0.0:
                ratio = 1.0
            else:
                ratio = max(torso / self._bar_torso, self._bar_torso / torso)
            if ratio > self.BAR_SCALE_CHANGE:
                self._bar_contradictions += 1
                if self._bar_contradictions > self.MAX_BAR_CONTRADICTIONS:
                    self._bar.reset()
                    self._bar_torso = NAN
                    self._bar_contradictions = 0
                    self._bar_settle_since = 0
                    self._bar_settle_hands = None
        else:
            self._bar_contradictions = 0

        # A straight-armed hang establishes an unknown bar. Once known, only observations already
        # on that bar may refine it; otherwise stepping off could drag the line to the floor.
        #
        # Establishing one from scratch additionally needs the hands *overhead*. Setting up a
        # resistance band means standing holding it at chest height with straight arms, which
        # satisfies every other test here -- hands above the hips, elbows extended -- and taught
        # the bar at the athlete's chest, hundreds of pixels below the real one; every later rep
        # was then refused with "Get on the bar" with no way back, since refinement requires
        # already passing the gate. Strict pull-ups have no such phase, so only band footage
        # found it.
        overhead = hands_overhead(k, hands)
        self._overhead_frames = self._overhead_frames + 1 if overhead else 0
        # Seeing the nose below the hands is evidence and is acted on at once; permission inferred
        # from a nose that could *not* be seen is not, and has to persist.
        may_learn = overhead and (
            ok(k[KP.NOSE]) or self._overhead_frames >= self.OVERHEAD_HOLD_FRAMES
        )
        gate_ok = (
            self._bar.holds(left_wrist, right_wrist, torso)
            if self._bar.established else may_learn
        )
        if elbow >= dead_hang and gate_ok:
            was_established = self._bar.established
            half = self._grip_half_width(k)
            self._bar.observe_hang(hands.x, hands.y, 0.0 if half is None else half)
            if not was_established:
                self._bar_torso = torso
        if self._bar.established:
            self._bar_settle_since = 0
            self._bar_settle_hands = None
        elif overhead:
            half = self._grip_half_width(k)
            self._settle_bar(hands, 0.0 if half is None else half, torso, now)
        else:
            # Not a hang, so the stillness of holding a band must not accumulate toward one.
            self._bar_settle_since = 0
            self._bar_settle_hands = None
        if not self._bar.holds(left_wrist, right_wrist, torso):
            self.hint = "Get on the bar"
            return None

        nose = k[KP.NOSE]
        bar_y = self._bar.line_y
        if not ok(nose) or bar_y is None:
            self.hint = "Show your head" if not ok(nose) else "Hang from the bar"
            return None
        return PullupSample(
            signal=-elbow,
            dead_hang_below_reset=(not self._requires_dead_hang or elbow >= dead_hang)
            and nose.y >= f32(bar_y + f32(self.HEAD_RESET_TORSOS * torso)),
            head_above_bar=nose.y < bar_y,
            bar_gate_open=True,
        )

    def _dead_hang_degrees(self) -> float:
        """The angle at which the arms read as straight for *this* camera placement.

        Never stricter than `DEAD_HANG_DEGREES`; a foreshortened view relaxes it to whatever
        full extension actually projects as.
        """
        if math.isnan(self._pullup_extended_elbow):
            return self.DEAD_HANG_DEGREES
        return min(
            self.DEAD_HANG_DEGREES,
            max(self.DEAD_HANG_FLOOR_DEGREES,
                f32(self._pullup_extended_elbow - self.DEAD_HANG_SLACK_DEGREES)),
        )

    def _invalidate_pullup_cycle(self) -> None:
        """Forget a partial pull-up until a fresh on-bar dead hang is observed.

        This is the hard reset, for when the athlete has genuinely left the bar. A frame that is
        merely unreadable goes through `_tolerate_pullup_dropout` instead.
        """
        self._pullup_down_seen = False
        self._pullup_dropout_frames = 0
        self._counters[Exercise.PULLUP].require_fresh_down()

    def _tolerate_pullup_dropout(self) -> None:
        """Absorbs a frame the pull-up gates could not read.

        A cycle already in flight survives a short run of them; a sustained run is
        indistinguishable from having left the bar, so it ends the cycle.
        """
        if not self._pullup_down_seen:
            self._invalidate_pullup_cycle()
            return
        self._pullup_dropout_frames += 1
        if self._pullup_dropout_frames > self.MAX_DROPOUT_FRAMES:
            self._invalidate_pullup_cycle()

    @property
    def _requires_dead_hang(self) -> bool:
        """Whether the bottom of a rep has to be a straight-armed hang.

        It does for a strict pull-up: that is the movement. It cannot for a band-assisted one --
        the band takes enough weight that the arms may never straighten, so requiring it means
        the reset never arms and the athlete scores zero all session behind a gate they cannot
        open. What remains is the head dropping back below the reset line, which is a
        torso-scaled offset rather than an angle and so survives the camera's viewpoint.
        """
        return self.profile.pull is PullVariant.STRICT_PULL_UP

    def _settle_bar(self, hands: Keypoint, half_grip: float, torso: float, now: int) -> None:
        """Locates the bar from hands simply held still overhead, when no dead hang has.

        Strictly a fallback. A straight-armed hang still establishes the bar on the frame it
        happens, so nothing about a strict pull-up reaches this. It exists because the dead-hang
        route can never fire for some athletes: an elbow that does not reach
        ``DEAD_HANG_FLOOR_DEGREES`` -- limited extension, or a band taking enough weight that the
        arms never straighten -- leaves the bar unknown, and an unknown bar has no ``line_y``, so
        every pull-up frame is refused before the gates are consulted and the whole workout
        scores zero under "Hang from the bar". Failing to *find* the bar is not a movement
        standard, it is a lockout; the head and bar gates still apply afterwards, and on the
        strict variant so does the dead hang.

        Stillness is the evidence rather than the elbow, because stillness is what separates
        hanging from the walk-up that previously taught a bar in the wrong place.
        """
        reference = self._bar_settle_hands
        drift = (
            NAN if reference is None
            else f32(math.hypot(f32(hands.x - reference.x), f32(hands.y - reference.y)))
        )
        if reference is None or drift > f32(self.BAR_SETTLE_DRIFT_TORSOS * torso):
            self._bar_settle_since = now
            self._bar_settle_hands = hands
            return
        if now - self._bar_settle_since < self.BAR_SETTLE_MS:
            return
        self._bar.observe_hang(hands.x, hands.y, half_grip)
        self._bar_torso = torso
        self._bar_settle_since = 0
        self._bar_settle_hands = None

    def _grip_half_width(self, k: Sequence[Keypoint]) -> float | None:
        l = k[KP.LEFT_WRIST]
        r = k[KP.RIGHT_WRIST]
        if not ok(l) or not ok(r):
            return None
        return f32(abs(f32(l.x - r.x)) / 2.0)

    # -- signals ----------------------------------------------------------

    def _pushup_signal(self, k: Sequence[Keypoint]) -> float:
        if hanging_from_bar(k):
            self.hint = "Get on the floor"
            return NAN
        return bilateral_angle(
            k,
            KP.LEFT_SHOULDER, KP.LEFT_ELBOW, KP.LEFT_WRIST,
            KP.RIGHT_SHOULDER, KP.RIGHT_ELBOW, KP.RIGHT_WRIST,
        )

    def _squat_signal(self, k: Sequence[Keypoint]) -> float:
        value = bilateral_angle(
            k,
            KP.LEFT_HIP, KP.LEFT_KNEE, KP.LEFT_ANKLE,
            KP.RIGHT_HIP, KP.RIGHT_KNEE, KP.RIGHT_ANKLE,
        )
        if math.isnan(value):
            self.hint = "Show your legs to the camera"
        return value

    def _frame_diagnostics(
        self,
        k: Sequence[Keypoint],
        identity_stable: bool,
        scoring_confidence_adequate: bool = False,
        bar_gate_open: bool = False,
        head_above_bar: bool = False,
        rejection: str | None = None,
    ) -> FrameDiagnostics:
        return FrameDiagnostics(
            minimum_confidence=min((p.score for p in k), default=0.0),
            scoring_confidence_adequate=scoring_confidence_adequate,
            pose_legible=self._pose_legible(k),
            identity_stable=identity_stable,
            bar_gate_open=bar_gate_open,
            head_above_bar=head_above_bar,
            dead_hang_since_last_rep=self._pullup_down_seen,
            reset_below_bar_seen=self._pullup_down_seen,
            rejection_reason=rejection,
        )

    def _pose_legible(self, k: Sequence[Keypoint]) -> bool:
        """Whether every joint the current movement scores from was confidently seen.

        The joint lists are the ones each signal actually consults: pull-ups and push-ups both run
        on the shoulder-elbow-wrist chain with the hips supplying torso scale, and squats on the
        hip-knee-ankle chain with the shoulders doing the same. Asking for *all* of them, rather
        than enough of them to compute an angle, is what makes this fall before the score does.

        Wrists are the joint that matters most here and the one that goes first: darkening a clip
        until it stopped counting left "Show both hands" as the dominant refusal every time, which
        is why pull-ups fail so much sooner than the other two movements.
        """
        if self.exercise is Exercise.SQUAT:
            joints = (KP.LEFT_SHOULDER, KP.RIGHT_SHOULDER, KP.LEFT_HIP, KP.RIGHT_HIP,
                      KP.LEFT_KNEE, KP.RIGHT_KNEE, KP.LEFT_ANKLE, KP.RIGHT_ANKLE)
        else:
            joints = (KP.LEFT_SHOULDER, KP.RIGHT_SHOULDER, KP.LEFT_ELBOW, KP.RIGHT_ELBOW,
                      KP.LEFT_WRIST, KP.RIGHT_WRIST, KP.LEFT_HIP, KP.RIGHT_HIP)
        return all(ok(k[i]) for i in joints)
