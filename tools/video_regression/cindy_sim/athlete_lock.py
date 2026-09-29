"""Who the athlete is, and whether each frame's skeleton is them. Mirrors
app/src/main/java/com/cindy/tracker/AthleteLock.kt line for line.

The Kotlin does this geometry in Double with sqrt, never Float or hypot, precisely so that this
port needs no `f32()` rounding to agree with it bit for bit. `lock_parity_check.py` proves that it
does. See the Kotlin class for why each rule exists.
"""
from __future__ import annotations

import math
from dataclasses import dataclass
from enum import Enum
from typing import Sequence

from . import pose_geometry
from .keypoints import KP, Keypoint
from .workout_engine import Exercise


class LockState(Enum):
    IDLE = "IDLE"
    ACQUIRING = "ACQUIRING"
    CALIBRATING = "CALIBRATING"
    LOCKED = "LOCKED"
    LOST = "LOST"


class Verdict(Enum):
    CONFIRMED = "CONFIRMED"
    UNCERTAIN = "UNCERTAIN"
    REFUSED = "REFUSED"


@dataclass(frozen=True)
class PoseBox:
    """An axis-aligned box in frame pixels. Kotlin stores the edges as Float."""

    left: float
    top: float
    right: float
    bottom: float

    def intersects(self, o: "PoseBox") -> bool:
        return self.left <= o.right and o.left <= self.right and self.top <= o.bottom and o.top <= self.bottom


@dataclass(frozen=True)
class LockContext:
    movement: Exercise
    frame_width: int
    frame_height: int
    bar_zone: object | None = None  # anything with left/right/top/bottom, e.g. BarZone bounds
    calibration_reps: int = 0
    workout_running: bool = False


def _f32(v: float) -> float:
    """Kotlin's Double.toFloat(), for the box edges it stores as Float."""
    import struct
    return struct.unpack("f", struct.pack("f", v))[0]


MIN_SCORE = pose_geometry.MIN_SCORE
GATE_TORSOS = 0.75
GATE_FRAME_MS = 70.0
GATE_MAX_TORSOS = 2.0
PREDICT_CAP_MS = 250.0
SCALE_RATIO = 1.5
FILTER_ALPHA = 0.85
FILTER_BETA = 0.3
MIN_VELOCITY_MS = 33.0
LOST_AFTER_MS = 1_500
PROBE_INTERVAL_MS = 500
CANDIDATE_EXPIRY_MS = 2_000
START_HOLD_MS = 500
SWITCH_AFTER_MS = 1_000
SIZE_ADVANTAGE = 1.25
CALIBRATING_UNSEEN_MS = 1_500
MATCH_TORSOS = 1.5
REACQUIRE_SCALE_MIN = 0.67
REACQUIRE_SCALE_MAX = 1.5
STATION_GROW_TORSOS = 1.0
NO_STATION_TORSOS = 3.0
OVERHEAD_NO_NOSE_TORSOS = 0.5
KNOWN_OTHER_MS = 2_000
KNOWN_OTHER_PAD = 0.3
PROTECT_PAD = 0.5
SECOND_LOOK_ONE_IN = 3
RATE_WINDOW_MS = 1_000
_TORSO = (KP.LEFT_SHOULDER, KP.RIGHT_SHOULDER, KP.LEFT_HIP, KP.RIGHT_HIP)
_DMAX = 1.7976931348623157e308


@dataclass
class _Torso:
    cx: float
    cy: float
    length: float
    full: bool


class _Candidate:
    def __init__(self, cid: int):
        self.id = cid
        self.pose: Sequence[Keypoint] = ()
        self.cx = 0.0
        self.cy = 0.0
        self.length = 0.0
        self.full = False
        self.complete = False
        self.in_start = False
        self.in_start_since = -1
        self.last_seen = 0
        self.seen_this_frame = False
        self.from_primary = False


class _KnownOther:
    def __init__(self, box: PoseBox, last_seen: int):
        self.box = box
        self.last_seen = last_seen


def _dist(ax: float, ay: float, bx: float, by: float) -> float:
    dx = ax - bx
    dy = ay - by
    return math.sqrt(dx * dx + dy * dy)


def _torso_of(k: Sequence[Keypoint]) -> _Torso | None:
    ls, rs, lh, rh = k[KP.LEFT_SHOULDER], k[KP.RIGHT_SHOULDER], k[KP.LEFT_HIP], k[KP.RIGHT_HIP]
    ls_ok, rs_ok = ls.score >= MIN_SCORE, rs.score >= MIN_SCORE
    lh_ok, rh_ok = lh.score >= MIN_SCORE, rh.score >= MIN_SCORE
    if ls_ok and rs_ok:
        sx, sy = (ls.x + rs.x) / 2.0, (ls.y + rs.y) / 2.0
    elif ls_ok:
        sx, sy = ls.x, ls.y
    elif rs_ok:
        sx, sy = rs.x, rs.y
    else:
        return None
    if lh_ok and rh_ok:
        hx, hy = (lh.x + rh.x) / 2.0, (lh.y + rh.y) / 2.0
    elif lh_ok:
        hx, hy = lh.x, lh.y
    elif rh_ok:
        hx, hy = rh.x, rh.y
    else:
        return None
    return _Torso((sx + hx) / 2.0, (sy + hy) / 2.0, max(_dist(sx, sy, hx, hy), 1.0),
                  ls_ok and rs_ok and lh_ok and rh_ok)


def _shoulder_y(k: Sequence[Keypoint]) -> float | None:
    l, r = k[KP.LEFT_SHOULDER], k[KP.RIGHT_SHOULDER]
    if l.score >= MIN_SCORE and r.score >= MIN_SCORE:
        return (l.y + r.y) / 2.0
    if l.score >= MIN_SCORE:
        return l.y
    if r.score >= MIN_SCORE:
        return r.y
    return None


def _box_of(k: Sequence[Keypoint], pad: float, torso: float) -> PoseBox:
    l, t, r, b = _DMAX, _DMAX, -_DMAX, -_DMAX
    for p in k:
        if p.score < MIN_SCORE:
            continue
        l, r = min(l, p.x), max(r, p.x)
        t, b = min(t, p.y), max(b, p.y)
    if l > r:
        return PoseBox(0.0, 0.0, 0.0, 0.0)
    g = pad * torso
    return PoseBox(_f32(l - g), _f32(t - g), _f32(r + g), _f32(b + g))


def _in_start(k: Sequence[Keypoint], movement: Exercise) -> bool:
    if movement is Exercise.PULLUP:
        l, r = k[KP.LEFT_WRIST], k[KP.RIGHT_WRIST]
        t = _torso_of(k)
        if l.score < MIN_SCORE or r.score < MIN_SCORE or t is None or not pose_geometry.upright(k):
            return False
        nose = k[KP.NOSE]
        if nose.score >= MIN_SCORE:
            return l.y < nose.y and r.y < nose.y
        sh = _shoulder_y(k)
        return (sh is not None and sh - l.y >= OVERHEAD_NO_NOSE_TORSOS * t.length
                and sh - r.y >= OVERHEAD_NO_NOSE_TORSOS * t.length)
    if movement is Exercise.PUSHUP:
        return _torso_of(k) is not None and not pose_geometry.upright(k)
    return pose_geometry.standing(k)


class AthleteLock:
    def __init__(self, predict: bool = False):
        self._predict = predict
        self.state = LockState.IDLE
        self.verdict = Verdict.UNCERTAIN
        self.reason = "idle"
        self.candidate_changed = False
        self.ambiguous = False
        self.steer: Sequence[Keypoint] | None = None
        self.probe_wanted = False
        self.second_look_wanted = False
        self.refused_box: PoseBox | None = None

        self._cx = self._cy = self._vx = self._vy = self._scale = 0.0
        self._last_confirmed_at = 0
        self._joint_x = [0.0] * KP.COUNT
        self._joint_y = [0.0] * KP.COUNT
        self._joint_seen = [False] * KP.COUNT
        self._tracking = False

        self._candidates: list[_Candidate] = []
        self._next_candidate_id = 1
        self._followed: _Candidate | None = None
        self._challenger: _Candidate | None = None
        self._challenge_since = 0
        self._last_probe_at = 0
        self._exclude_others_next = False
        self._movement = Exercise.PULLUP

        self._known_others: list[_KnownOther] = []
        self._scale_memory: dict[Exercise, float] = {}
        self._stations: dict[Exercise, list[float]] = {}
        self._locked_frames: list[int] = []
        self._second_looks: list[int] = []
        self._view_moved = False

    # ── control ──────────────────────────────────────────────────────────────

    def begin_acquiring(self, now: int) -> None:
        self._clear_acquisition()
        self._tracking = False
        self._known_others.clear()
        self.state = LockState.ACQUIRING
        self._last_probe_at = now
        self.verdict = Verdict.UNCERTAIN
        self.reason = "acquiring"

    def confirm(self, now: int) -> None:
        if self._followed is None:
            return
        self._lock_onto(self._followed, now)

    def lose(self, now: int, clear_stations: bool) -> None:
        if self.state is LockState.IDLE:
            return
        if clear_stations:
            self._stations.clear()
            self._scale_memory.clear()
            self._view_moved = True
        self._go_lost(now)
        self._last_probe_at = now - PROBE_INTERVAL_MS

    def reset(self) -> None:
        self._clear_acquisition()
        self._known_others.clear()
        self._scale_memory.clear()
        self._stations.clear()
        self._locked_frames.clear()
        self._second_looks.clear()
        self._tracking = False
        self._view_moved = False
        self.state = LockState.IDLE
        self.verdict = Verdict.UNCERTAIN
        self.reason = "idle"
        self.candidate_changed = False
        self.ambiguous = False
        self.steer = None
        self.probe_wanted = False
        self.second_look_wanted = False
        self.refused_box = None

    # ── per frame ────────────────────────────────────────────────────────────

    def on_frame(self, primary: Sequence[Keypoint], probes: Sequence[Sequence[Keypoint]], now: int,
                 ctx: LockContext) -> Verdict:
        self._movement = ctx.movement
        self.candidate_changed = False
        self.ambiguous = False
        self.steer = None
        self.second_look_wanted = False
        self.refused_box = None
        self._expire_known_others(now)

        if self.state is LockState.IDLE:
            self._set(Verdict.UNCERTAIN, "idle")
        elif self.state in (LockState.ACQUIRING, LockState.CALIBRATING):
            self._acquire(primary, probes, now, ctx)
        elif self.state is LockState.LOCKED:
            self._judge_locked(primary, now, ctx)
        else:
            self._reacquire(primary, probes, now, ctx)

        self.probe_wanted = False
        if self.state in (LockState.ACQUIRING, LockState.CALIBRATING, LockState.LOST):
            if now - self._last_probe_at >= PROBE_INTERVAL_MS:
                self.probe_wanted = True
                self._last_probe_at = now
        return self.verdict

    def probe_exclusions(self) -> list[PoseBox]:
        out: list[PoseBox] = []
        if self._followed is not None:
            out.append(_box_of(self._followed.pose, KNOWN_OTHER_PAD, self._followed.length))
        if self._exclude_others_next or self.state is LockState.LOST:
            out.extend(self.known_others())
        self._exclude_others_next = not self._exclude_others_next
        return out

    def known_others(self) -> list[PoseBox]:
        if not self._known_others:
            return []
        protect = self._protected_box()
        if protect is None:
            return [o.box for o in self._known_others]
        return [o.box for o in self._known_others if not o.box.intersects(protect)]

    def reconsider(self, second: Sequence[Keypoint], now: int) -> Verdict:
        self.second_look_wanted = False
        if self.state is not LockState.LOCKED or self.verdict is not Verdict.REFUSED:
            return self.verdict
        verdict, _, _, full = self._judge(second, now)
        if verdict is Verdict.CONFIRMED:
            self._confirm_frame(second, now, full)
            self._set(Verdict.CONFIRMED, "second-look")
        return self.verdict

    # ── LOCKED ───────────────────────────────────────────────────────────────

    def _judge_locked(self, primary, now, ctx) -> None:
        self._locked_frames.append(now)
        self._trim(self._locked_frames, now)
        self._trim(self._second_looks, now)
        verdict, reason, clear, full = self._judge(primary, now)
        self._set(verdict, reason)
        if verdict is Verdict.CONFIRMED:
            self._confirm_frame(primary, now, full)
        elif verdict is Verdict.REFUSED:
            t = _torso_of(primary)
            self.refused_box = _box_of(primary, KNOWN_OTHER_PAD, t.length if t is not None else self._scale)
            if clear:
                self._remember_other(self.refused_box, now)
            if (len(self._second_looks) + 1) * SECOND_LOOK_ONE_IN <= len(self._locked_frames):
                self.second_look_wanted = True
                self._second_looks.append(now)
        if self.verdict is not Verdict.CONFIRMED and now - self._last_confirmed_at > LOST_AFTER_MS:
            self._go_lost(now)
            self.second_look_wanted = False

    def _judge(self, k, now):
        t = _torso_of(k)
        if t is None:
            return Verdict.UNCERTAIN, "no-torso", False, False
        dt = float(now - self._last_confirmed_at)
        h = min(max(dt, 0.0), PREDICT_CAP_MS)
        gate = min(GATE_MAX_TORSOS, GATE_TORSOS * max(1.0, dt / GATE_FRAME_MS))
        if t.full:
            px = self._cx + self._vx * h
            py = self._cy + self._vy * h
            d = _dist(t.cx, t.cy, px, py) / self._scale
            ratio = t.length / self._scale
            scale_ok = 1.0 / SCALE_RATIO <= ratio <= SCALE_RATIO
            if d <= gate and scale_ok:
                return Verdict.CONFIRMED, "ok", False, True
            clear = d > 2.0 * gate or not scale_ok
            return Verdict.REFUSED, "jump" if scale_ok else "scale", clear, True
        within = 0
        far = over = False
        for j in _TORSO:
            p = k[j]
            if p.score < MIN_SCORE or not self._joint_seen[j]:
                continue
            d = _dist(p.x, p.y, self._joint_x[j] + self._vx * h, self._joint_y[j] + self._vy * h) / self._scale
            if d > 2.0 * gate:
                far = True
            if d <= gate:
                within += 1
            else:
                over = True
        if far:
            return Verdict.REFUSED, "partial-far", False, False
        if not over and within >= 2:
            return Verdict.CONFIRMED, "partial-ok", False, False
        return Verdict.UNCERTAIN, "partial", False, False

    def _confirm_frame(self, k, now, full: bool) -> None:
        dt = max(float(now - self._last_confirmed_at), 1.0)
        h = min(dt, PREDICT_CAP_MS)
        if full:
            t = _torso_of(k)
            px = self._cx + self._vx * h
            py = self._cy + self._vy * h
            rx = t.cx - px
            ry = t.cy - py
            if self._predict:
                self._cx = px + FILTER_ALPHA * rx
                self._cy = py + FILTER_ALPHA * ry
                dv = max(dt, MIN_VELOCITY_MS)
                self._vx += FILTER_BETA * rx / dv
                self._vy += FILTER_BETA * ry / dv
            else:
                self._cx = t.cx
                self._cy = t.cy
            self._scale = t.length
        else:
            self._cx += self._vx * h
            self._cy += self._vy * h
        self._store_joints(k)
        self._last_confirmed_at = now
        self._remember_station()
        mine = _box_of(k, 0.0, self._scale)
        self._known_others = [o for o in self._known_others if not o.box.intersects(mine)]

    # ── ACQUIRING / CALIBRATING ──────────────────────────────────────────────

    def _acquire(self, primary, probes, now, ctx) -> None:
        before = self._followed
        from_primary = self._observe(primary, probes, now, ctx)
        if (self.state is LockState.ACQUIRING and ctx.calibration_reps >= 1 and not ctx.workout_running
                and self._followed is not None):
            self.state = LockState.CALIBRATING
        f0 = self._followed
        if f0 is None:
            first = from_primary if from_primary is not None else (self._candidates[0] if self._candidates else None)
            if before is not None and first is not None:
                self.candidate_changed = True
                self.state = LockState.ACQUIRING
            self._followed = first
            self._challenger = None
        elif self.state is LockState.ACQUIRING:
            self._consider_switch(now, ctx)
        elif now - f0.last_seen > CALIBRATING_UNSEEN_MS:
            nxt = self._best([c for c in self._candidates if c is not f0], ctx)
            if nxt is not None:
                self._followed = nxt
                self.candidate_changed = True
                self.state = LockState.ACQUIRING
        self.ambiguous = sum(1 for c in self._candidates if c.seen_this_frame and c.in_start) >= 2

        if ctx.workout_running:
            held = [c for c in self._candidates if c.seen_this_frame and self._held(c, now)]
            top = None
            for c in held:  # maxWith(centrality, length): the first maximum wins
                if top is None or (self._centrality(c, ctx), c.length) > (self._centrality(top, ctx), top.length):
                    top = c
            if top is not None and top.full:
                self._lock_onto(top, now)
                if top is from_primary:
                    self._set(Verdict.CONFIRMED, "skip-lock")
                else:
                    self._set(Verdict.REFUSED, "skip-lock-elsewhere")
                    self.steer = top.pose
                return
            self._set(Verdict.UNCERTAIN if _torso_of(primary) is None else Verdict.REFUSED, "skip-waiting")
            return
        f = self._followed
        if _torso_of(primary) is None:
            self._set(Verdict.UNCERTAIN, "no-torso")
        elif f is not None and f is from_primary:
            self._set(Verdict.CONFIRMED, "followed")
        else:
            self._set(Verdict.REFUSED, "not-followed")
            if f is not None:
                self.steer = f.pose

    def _consider_switch(self, now, ctx) -> None:
        f = self._followed
        if f is None:
            return
        rival = self._best([c for c in self._candidates if c is not f and c.seen_this_frame], ctx)
        if rival is None or not self._beats(rival, f, now, ctx):
            self._challenger = None
            return
        if self._challenger is not rival:
            self._challenger = rival
            self._challenge_since = now
            return
        if now - self._challenge_since >= SWITCH_AFTER_MS:
            self._followed = rival
            self._challenger = None
            self.candidate_changed = True

    def _beats(self, a, b, now, ctx) -> bool:
        ha, hb = self._held(a, now), self._held(b, now)
        if ha != hb:
            return ha
        if a.complete != b.complete:
            return a.complete
        return self._size(a, ctx) >= SIZE_ADVANTAGE * self._size(b, ctx)

    def _best(self, pool, ctx):
        top = None
        for c in pool:
            if top is None:
                top = c
                continue
            hc, ht = c.in_start_since >= 0, top.in_start_since >= 0
            if hc != ht:
                better = hc
            elif c.complete != top.complete:
                better = c.complete
            else:
                better = self._size(c, ctx) > self._size(top, ctx)
            if better:
                top = c
        return top

    @staticmethod
    def _held(c, now) -> bool:
        return c.in_start_since >= 0 and now - c.in_start_since >= START_HOLD_MS

    @staticmethod
    def _centrality(c, ctx) -> float:
        half = ctx.frame_width / 2.0
        return min(max(1.0 - abs(c.cx - half) / half, 0.0), 1.0)

    def _size(self, c, ctx) -> float:
        return c.length * (0.5 + 0.5 * self._centrality(c, ctx))

    def _lock_onto(self, c, now) -> None:
        t = _torso_of(c.pose)
        if t is None:
            return
        self._cx, self._cy, self._vx, self._vy = t.cx, t.cy, 0.0, 0.0
        self._scale = t.length
        self._joint_seen = [False] * KP.COUNT
        self._store_joints(c.pose)
        self._last_confirmed_at = now
        self._tracking = True
        self._view_moved = False
        self._scale_memory[self._movement] = self._scale
        self.state = LockState.LOCKED
        self._clear_acquisition()
        self._locked_frames.clear()
        self._second_looks.clear()

    # ── LOST ─────────────────────────────────────────────────────────────────

    def _reacquire(self, primary, probes, now, ctx) -> None:
        from_primary = self._observe(primary, probes, now, ctx)
        qualifying = [c for c in self._candidates if c.seen_this_frame and self._qualifies(c, now, ctx)]
        self.ambiguous = len(qualifying) >= 2
        if len(qualifying) == 1:
            c = qualifying[0]
            self._lock_onto(c, now)
            if c is from_primary:
                self._set(Verdict.CONFIRMED, "reacquired")
            else:
                self._set(Verdict.REFUSED, "reacquired-elsewhere")
                self.steer = c.pose
            return
        self._set(Verdict.UNCERTAIN if _torso_of(primary) is None else Verdict.REFUSED,
                  "lost-ambiguous" if self.ambiguous else "lost")

    def _qualifies(self, c, now, ctx) -> bool:
        if not c.full or not c.complete or not self._held(c, now):
            return False
        if self._view_moved:
            return True
        remembered = self._scale_memory.get(ctx.movement, self._scale)
        if remembered <= 0.0:
            return False
        ratio = c.length / remembered
        if ratio < REACQUIRE_SCALE_MIN or ratio > REACQUIRE_SCALE_MAX:
            return False
        bar = ctx.bar_zone
        if ctx.movement is Exercise.PULLUP and bar is not None:
            l, r = c.pose[KP.LEFT_WRIST], c.pose[KP.RIGHT_WRIST]
            return (l.score >= MIN_SCORE and r.score >= MIN_SCORE
                    and bar.left <= l.x <= bar.right and bar.left <= r.x <= bar.right
                    and bar.top <= l.y <= bar.bottom and bar.top <= r.y <= bar.bottom)
        st = self._stations.get(ctx.movement)
        if st is not None and ctx.movement is not Exercise.PULLUP:
            grow = STATION_GROW_TORSOS * remembered
            return st[0] - grow <= c.cx <= st[2] + grow and st[1] - grow <= c.cy <= st[3] + grow
        if not self._tracking:
            return False
        return _dist(c.cx, c.cy, self._cx, self._cy) <= NO_STATION_TORSOS * remembered

    def _go_lost(self, now) -> None:
        self.state = LockState.LOST
        self._clear_acquisition()
        self._known_others.clear()
        self._locked_frames.clear()
        self._second_looks.clear()
        if self.verdict is Verdict.CONFIRMED:
            self._set(Verdict.REFUSED, "lost")

    # ── candidates ───────────────────────────────────────────────────────────

    def _observe(self, primary, probes, now, ctx):
        for c in self._candidates:
            c.seen_this_frame = False
            c.from_primary = False
        from_primary = self._match(primary, now, ctx, True)
        for p in probes:
            self._match(p, now, ctx, False)
        self._candidates = [c for c in self._candidates if now - c.last_seen <= CANDIDATE_EXPIRY_MS]
        if self._followed is not None and self._followed not in self._candidates:
            self._followed = None
        if self._challenger is not None and self._challenger not in self._candidates:
            self._challenger = None
        return from_primary

    def _match(self, k, now, ctx, is_primary):
        t = _torso_of(k)
        if t is None:
            return None
        best, best_d = None, _DMAX
        for c in self._candidates:
            if c.seen_this_frame:
                continue
            ratio = t.length / c.length
            if ratio < 1.0 / SCALE_RATIO or ratio > SCALE_RATIO:
                continue
            d = _dist(t.cx, t.cy, c.cx, c.cy) / c.length
            if d <= MATCH_TORSOS and d < best_d:
                best_d, best = d, c
        c = best
        if c is None:
            c = _Candidate(self._next_candidate_id)
            self._next_candidate_id += 1
            self._candidates.append(c)
        c.pose = k
        c.cx, c.cy, c.length, c.full = t.cx, t.cy, t.length, t.full
        c.complete = not pose_geometry.missing_joints(k, ctx.movement)
        c.in_start = _in_start(k, ctx.movement)
        if not c.in_start:
            c.in_start_since = -1
        elif c.in_start_since < 0:
            c.in_start_since = now
        c.last_seen = now
        c.seen_this_frame = True
        c.from_primary = is_primary
        return c

    def _clear_acquisition(self) -> None:
        self._candidates = []
        self._followed = None
        self._challenger = None

    # ── memory ───────────────────────────────────────────────────────────────

    def _remember_other(self, box: PoseBox, now: int) -> None:
        for o in self._known_others:
            if o.box.intersects(box):
                o.box = box
                o.last_seen = now
                return
        self._known_others.append(_KnownOther(box, now))

    def _expire_known_others(self, now: int) -> None:
        self._known_others = [o for o in self._known_others if now - o.last_seen <= KNOWN_OTHER_MS]

    def _remember_station(self) -> None:
        if self._movement is Exercise.PULLUP:
            return
        s = self._stations.get(self._movement)
        if s is None:
            self._stations[self._movement] = [self._cx, self._cy, self._cx, self._cy]
        else:
            s[0], s[1] = min(s[0], self._cx), min(s[1], self._cy)
            s[2], s[3] = max(s[2], self._cx), max(s[3], self._cy)
        self._scale_memory[self._movement] = self._scale

    def _protected_box(self) -> PoseBox | None:
        if not self._tracking:
            return None
        l, t, r, b = _DMAX, _DMAX, -_DMAX, -_DMAX
        any_seen = False
        for j in _TORSO:
            if not self._joint_seen[j]:
                continue
            any_seen = True
            l, r = min(l, self._joint_x[j]), max(r, self._joint_x[j])
            t, b = min(t, self._joint_y[j]), max(b, self._joint_y[j])
        if not any_seen:
            return None
        pad = PROTECT_PAD * self._scale
        return PoseBox(_f32(l - pad), _f32(t - pad), _f32(r + pad), _f32(b + pad))

    def _store_joints(self, k) -> None:
        for j in range(KP.COUNT):
            p = k[j]
            if p.score >= MIN_SCORE:
                self._joint_x[j] = p.x
                self._joint_y[j] = p.y
                self._joint_seen[j] = True

    @staticmethod
    def _trim(q: list[int], now: int) -> None:
        while q and now - q[0] >= RATE_WINDOW_MS:
            q.pop(0)

    def _set(self, v: Verdict, why: str) -> None:
        self.verdict = v
        self.reason = why
