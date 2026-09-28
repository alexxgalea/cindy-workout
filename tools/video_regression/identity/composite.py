"""Two people, one frame: synthetic two-athlete composites for the identity harness.

A clean rewrite of the identity prototype's ``composite2.Scene`` (see the identity plan's
Appendix C for the method this ports). The base clip is one athlete's own Cindy footage; the
neighbour is cut out of a second clip against its own static-camera background and pasted in.
Every frame comes with the ground truth the metrics need: where the athlete's own silhouette is,
where the neighbour's is, and whether the neighbour is currently drawn over the athlete.

Five fixed placements reproduce the plan's layouts A-E (their (scale, at) pairs are recorded in
``run_identity.py``, which owns the named layout sets). This module adds what Phase 0 task 2 asks
for beyond the fixed layouts:

- ``Scene(..., frozen_at_s=...)`` and :func:`stationary_bystander_frames` -- a startup composite
  where the neighbour holds one position from the lead-in through the athlete's arrival, with no
  splice jump. v1's ``startup.py`` recovered the athlete only because its neighbour's video
  position reset at the splice, dropped out of the crop and triggered the whole-frame fallback
  (plan section 5.6); a real stationary bystander does not do that, so this rewrite never restarts
  the neighbour's position at all, and the lead-in is the clip's own empty background rather than
  a real frame with the athlete papered over -- there is no athlete pixel to leak.
- :func:`walk_through_scene` -- the neighbour crosses the frame twice, once behind the athlete and
  once in front. The in-front pass can occlude the athlete, which v1 never tested; ``Frame.occluded``
  says when it does.
- :func:`synchronised_pullups_scene` -- the neighbour's own pull-up-like activity at an adjacent
  position, aligned in time with the athlete's pull-ups (the group-class start).

Nothing here is graded on realism. Appendix A's judgement stands: the composite is fair for
ranking a fix against a same-time distractor, not for quoting its rates as real-world rates.
"""
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Iterator, NamedTuple, Union

import cv2
import numpy as np

ROOT = Path(__file__).resolve().parents[3]
FIXTURES = ROOT / "tests/fixtures/youtube/cindy"

#: The garage Cindy clip: pull-ups at the back, push-ups and squats close to the camera (plan
#: section 4.1). Cut from 16:9 to the phone's 3:4 around the athlete's stations.
BASE_CLIP = FIXTURES / "IGeeTmrkGDM.mp4"
#: The outdoor Cindy clip. Its athlete is cut out and pasted in as the neighbour.
NEIGHBOUR_CLIP = FIXTURES / "UxhKoj3jyQ4.mp4"
#: x-window of the 1280-wide garage clip that becomes the 480x640 output (Appendix C, method 1).
BASE_CROP = (498, 1038)
#: The neighbour's patch in the 1280x720 outdoor frame, before scaling.
NEIGHBOUR_BOX = (440, 200, 760, 720)
OUT_SIZE = (480, 640)  # (width, height), matching the phone's portrait analysis frame
#: Both source clips are 30 fps; the harness scores every second frame (15 fps -- plan section 5.1).
SOURCE_FPS = 30.0

MASK_THRESHOLD = 38  # per-pixel max-channel difference from the background that counts as "body"


class Box(NamedTuple):
    """A ground-truth rectangle in output-frame pixels (0..480, 0..640)."""

    left: float
    top: float
    right: float
    bottom: float

    def contains_point(self, x: float, y: float) -> bool:
        return self.left <= x <= self.right and self.top <= y <= self.bottom


Placement = Union[tuple[int, int], Callable[[float], "tuple[int, int] | None"]]
PasteOrder = Union[str, Callable[[float], "str | None"]]


@dataclass(frozen=True)
class Frame:
    """One composited frame, plus everything the metrics need to grade it."""

    #: 1-based count of *source* frames read from the base clip, matching the prototype's ``i``
    #: so a cache keyed on it lines up frame-for-frame with ``docs/identity-prototype``'s pickles.
    index: int
    #: Seconds into the base clip (``index / SOURCE_FPS``).
    time_s: float
    #: 480x640x3 uint8, RGB -- what the detector is fed.
    rgb: np.ndarray
    #: The athlete's own silhouette, from background subtraction against the base clip's own
    #: empty plate. ``None`` when nothing differs from that background (nobody there yet, as in a
    #: lead-in frame). Not the pose detector's opinion -- it can be noisy where the neighbour's
    #: paste or a lighting flicker lands on the base frame, which is why the metrics' actual
    #: ground truth is the clean detector run, not this box.
    athlete_box: Box | None
    #: The neighbour's silhouette after scaling and placement, tight to the body. ``None`` when
    #: the neighbour is not placed this frame (absent, or between walk-through passes).
    neighbour_box: Box | None
    #: The full placement rectangle the neighbour's patch was scaled into this frame -- always
    #: at least as big as ``neighbour_box``. This is what section 5.1's "inside the neighbour's
    #: rectangle" theft definition means, and what layouts A-E were sized against; prefer it over
    #: ``neighbour_box`` when reproducing section 5.3.
    neighbour_cell: Box | None
    #: True only when the neighbour was pasted *over* the athlete (``paste_order="front"``) and
    #: its mask actually overlaps the athlete's silhouette in the shared region -- not merely
    #: whichever body is closer to the camera by construction.
    occluded: bool
    #: "athlete" for a normal frame; "lead" for a stationary-bystander lead-in frame, before the
    #: athlete's own clip has started (see :func:`stationary_bystander_frames`).
    phase: str = "athlete"


def _median_background(
    path: Path,
    crop: tuple[int, int] | None,
    size: tuple[int, int] | None,
    t0: float = 8.0,
    t1: float | None = None,
    n: int = 90,
) -> np.ndarray:
    """The empty-scene plate a clip is composited against: the per-pixel median of `n` frames
    spread evenly between `t0` and `t1` (default: 4s before the clip ends, dodging a trailing
    scoreboard card). BGR uint8, matching cv2's own frame format.
    """
    cap = cv2.VideoCapture(str(path))
    fps = cap.get(cv2.CAP_PROP_FPS)
    total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    end = int((t1 if t1 is not None else total / fps - 4) * fps)
    picks = np.linspace(int(t0 * fps), end, n).astype(int)
    stack = []
    for f in picks:
        cap.set(cv2.CAP_PROP_POS_FRAMES, int(f))
        ok, bgr = cap.read()
        if not ok:
            continue
        if crop:
            bgr = cv2.resize(bgr[:, crop[0]:crop[1]], size, interpolation=cv2.INTER_AREA)
        stack.append(bgr)
    cap.release()
    return np.median(np.stack(stack), axis=0).astype(np.uint8)


def _silhouette_mask(frame: np.ndarray, background: np.ndarray, keep_largest: bool = True) -> np.ndarray:
    """Where `frame` differs from its clip's empty `background` by more than
    ``MASK_THRESHOLD`` in any channel -- the moving body -- opened and closed to drop speckle.

    ``keep_largest`` keeps only the largest connected blob, which is right when the mask is meant
    to describe one whole body (the neighbour's cut-out). The athlete's own exclusion mask is
    built with it off: a torso whose clothing matches the background can otherwise split into
    disconnected limbs, and every one of them must still keep the neighbour off the athlete.
    """
    diff = cv2.absdiff(frame, background).max(axis=2)
    mask = (diff > MASK_THRESHOLD).astype(np.uint8)
    mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
    mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, np.ones((9, 9), np.uint8))
    if keep_largest:
        count, labels, stats, _ = cv2.connectedComponentsWithStats(mask)
        if count > 1:
            biggest = 1 + int(np.argmax(stats[1:, cv2.CC_STAT_AREA]))
            mask = (labels == biggest).astype(np.uint8)
    return mask.astype(bool)


def _mask_bbox(mask: np.ndarray, offset: tuple[float, float] = (0.0, 0.0)) -> Box | None:
    """The tight bounding box of a boolean mask, in frame pixels, or ``None`` if it is empty."""
    ys, xs = np.nonzero(mask)
    if xs.size == 0:
        return None
    ox, oy = offset
    return Box(ox + float(xs.min()), oy + float(ys.min()), ox + float(xs.max() + 1), oy + float(ys.max() + 1))


class Scene:
    """One athlete's clip, with a second athlete pasted in as a neighbour.

    `at` and `paste_order` may each be a fixed value (the layouts A-E sweep) or a callable of
    elapsed base-clip seconds, returning `None` when the neighbour should not be placed at all
    that frame (used by :func:`walk_through_scene`). `frozen_at_s`, when given, captures a single
    neighbour frame once at construction and pastes those same pixels every time instead of
    reading the neighbour clip live -- see :func:`stationary_bystander_frames`.
    """

    def __init__(
        self,
        scale: float = 0.62,
        at: Placement = (288, 262),
        offset_s: float = 20.0,
        base_clip: Path = BASE_CLIP,
        neighbour_clip: Path = NEIGHBOUR_CLIP,
        base_crop: tuple[int, int] = BASE_CROP,
        neighbour_box: tuple[int, int, int, int] = NEIGHBOUR_BOX,
        paste_order: PasteOrder = "behind",
        frozen_at_s: float | None = None,
    ) -> None:
        self.scale, self.at, self.offset_s = scale, at, offset_s
        self.base_clip, self.neighbour_clip = Path(base_clip), Path(neighbour_clip)
        self.base_crop, self.neighbour_box = base_crop, neighbour_box
        self.paste_order = paste_order
        self.frozen_at_s = frozen_at_s
        self.bg_base = _median_background(self.base_clip, base_crop, OUT_SIZE, t0=0.5)
        x0, y0, x1, y1 = neighbour_box
        full = _median_background(self.neighbour_clip, None, None, t0=8.0, t1=58.0)
        self.bg_neighbour = full[y0:y1, x0:x1]
        self._frozen: tuple[np.ndarray, np.ndarray] | None = None
        if frozen_at_s is not None:
            cap = cv2.VideoCapture(str(self.neighbour_clip))
            fps = cap.get(cv2.CAP_PROP_FPS)
            cap.set(cv2.CAP_PROP_POS_FRAMES, int(frozen_at_s * fps))
            ok, bgr = cap.read()
            cap.release()
            if not ok:
                raise ValueError(f"could not read the neighbour clip at {frozen_at_s}s")
            patch = bgr[y0:y1, x0:x1]
            self._frozen = (patch, _silhouette_mask(patch, self.bg_neighbour))

    def _placement_rect(self, x: int, y: int) -> Box:
        x0, y0, x1, y1 = self.neighbour_box
        w, h = round((x1 - x0) * self.scale), round((y1 - y0) * self.scale)
        return Box(float(x), float(y), float(min(x + w, OUT_SIZE[0])), float(min(y + h, OUT_SIZE[1])))

    #: Layout A's placement (the prototype's `composite2.Scene()` default), for callers that want
    #: a rect without stepping frames -- `run_identity.py` uses this to report a set's geometry.
    @property
    def rect(self) -> Box:
        at = self.at(0.0) if callable(self.at) else self.at
        if at is None:
            raise ValueError("this scene's placement is time-varying; there is no single rect")
        return self._placement_rect(*at)

    def frames(self, step: int = 2, neighbour: bool = True) -> Iterator[Frame]:
        """Yields every `step`-th base-clip frame (2 -> 15 fps from the 30 fps source), first to
        last. `neighbour=False` is the ground-truth run: the athlete alone, still reporting
        `athlete_box` so a caller never needs a second pass just for that.
        """
        base = cv2.VideoCapture(str(self.base_clip))
        live_neighbour = neighbour and self._frozen is None
        nb = cv2.VideoCapture(str(self.neighbour_clip)) if live_neighbour else None
        if nb is not None:
            nb_fps = nb.get(cv2.CAP_PROP_FPS)
            nb.set(cv2.CAP_PROP_POS_FRAMES, int(self.offset_s * nb_fps))
        x0, y0, x1, y1 = self.neighbour_box
        i = 0
        try:
            while True:
                ok, bgr = base.read()
                if nb is not None:
                    ok2, nbf = nb.read()
                    if not ok2 or nb.get(cv2.CAP_PROP_POS_FRAMES) > 58 * nb_fps:
                        nb.set(cv2.CAP_PROP_POS_FRAMES, int(8 * nb_fps))
                        ok2, nbf = nb.read()
                if not ok:
                    break
                i += 1
                if i % step:
                    continue
                t = i / SOURCE_FPS
                frame = cv2.resize(bgr[:, self.base_crop[0]:self.base_crop[1]], OUT_SIZE,
                                    interpolation=cv2.INTER_AREA)
                yield self._compose(frame, t, i, nbf if live_neighbour else None, neighbour, "athlete")
        finally:
            base.release()
            if nb is not None:
                nb.release()

    def _compose(
        self, frame: np.ndarray, t: float, index: int, live_patch: np.ndarray | None,
        neighbour_wanted: bool, phase: str,
    ) -> Frame:
        """Pastes the neighbour into `frame` (BGR, already cropped/resized) and turns it into a
        :class:`Frame`. `frame` is mutated in place, same as the prototype.
        """
        x0, y0, x1, y1 = self.neighbour_box
        athlete_mask = _silhouette_mask(frame, self.bg_base, keep_largest=False)
        athlete_box = _mask_bbox(athlete_mask)

        neighbour_box = neighbour_cell = None
        occluded = False
        at = (self.at(t) if callable(self.at) else self.at) if neighbour_wanted else None
        order = (self.paste_order(t) if callable(self.paste_order) else self.paste_order) if at else None
        if at is not None and order is not None:
            ax, ay = at
            rx0, ry0, rx1, ry1 = (int(v) for v in self._placement_rect(ax, ay))
            neighbour_cell = Box(float(rx0), float(ry0), float(rx1), float(ry1))
            patch = self._frozen[0] if self._frozen is not None else live_patch[y0:y1, x0:x1]
            mask = self._frozen[1] if self._frozen is not None else _silhouette_mask(patch, self.bg_neighbour)
            size = (rx1 - rx0, ry1 - ry0)
            patch = cv2.resize(patch, size, interpolation=cv2.INTER_AREA)
            mask = cv2.resize(mask.astype(np.uint8), size, interpolation=cv2.INTER_NEAREST).astype(bool)

            region = frame[ry0:ry1, rx0:rx1]
            athlete_here = cv2.dilate(athlete_mask.astype(np.uint8), np.ones((7, 7), np.uint8)).astype(bool)
            athlete_in_rect = athlete_here[ry0:ry1, rx0:rx1]
            if order == "front":
                paste = mask
                overlap = (mask & athlete_in_rect).sum()
                occluded = overlap > max(20, 0.02 * max(int(athlete_in_rect.sum()), 1))
            else:
                paste = mask & ~athlete_in_rect
            region[paste] = patch[paste]
            neighbour_box = _mask_bbox(mask, offset=(rx0, ry0))

        return Frame(index, t, cv2.cvtColor(frame, cv2.COLOR_BGR2RGB), athlete_box,
                     neighbour_box, neighbour_cell, occluded, phase)


def stationary_bystander_frames(scene: Scene, lead_s: float = 5.0, step: int = 2) -> Iterator[Frame]:
    """The startup composite (Phase 0 task 2): a bystander who holds one position from the
    lead-in through the athlete's arrival, with no splice jump (plan section 5.6).

    v1's `startup.py` spliced a lead-in built from one `Scene.frames()` generator onto an
    *athlete* phase built from a second, freshly-opened one -- restarting the neighbour clip's
    read position at the join. The recovery it measured came from that restart: the neighbour's
    frame jumped, dropped out of the crop, and tripped the 5-consecutive-miss whole-frame
    fallback right as the athlete arrived. This rewrite never restarts anything. `scene` must be
    built with `frozen_at_s` set, so the lead-in and the athlete phase paste the identical
    neighbour pixels -- there is no video position to jump.

    The lead-in is composited from the base clip's own empty background, not a real frame with
    the athlete masked out of it (v1's other bug: that mask only applied outside the neighbour's
    rectangle, leaking the athlete into the lead-in wherever a layout's rectangle overlapped
    them, which is what voided layout E). Background-subtracting a frame against itself leaves
    nothing, so `athlete_box` is `None` throughout the lead-in with no special-casing needed.
    """
    if scene._frozen is None:
        raise ValueError("stationary_bystander_frames needs a Scene built with frozen_at_s set")
    lead_frames = max(round(lead_s * SOURCE_FPS / step), 0)
    for j in range(lead_frames):
        index = -(lead_frames - j)  # negative, strictly increasing, before the athlete's index 1
        t = index / SOURCE_FPS
        background = scene.bg_base.copy()
        yield scene._compose(background, t, index, None, True, "lead")
    yield from scene.frames(step=step, neighbour=True)


def walk_through_scene(
    scale: float = 0.75,
    y: int = 150,
    x_start: int = -80,
    x_end: int = 520,
    behind_window: tuple[float, float] = (6.0, 10.0),
    front_window: tuple[float, float] = (14.0, 18.0),
    offset_s: float = 20.0,
    **scene_kwargs,
) -> Scene:
    """A neighbour who crosses the frame twice: once behind the athlete (never drawn over them,
    same as every fixed layout), once in front (occludes them wherever the two silhouettes
    overlap). v1 never tested an occluding pass at all.

    Each crossing interpolates the placement's left edge linearly across `behind_window` /
    `front_window` (seconds into the base clip), from `x_start` to `x_end` -- off-frame at both
    ends on purpose, so the neighbour visibly enters and leaves rather than popping in. Outside
    both windows the neighbour is not placed.
    """
    def at(t: float) -> tuple[int, int] | None:
        for t0, t1 in (behind_window, front_window):
            if t0 <= t <= t1:
                frac = (t - t0) / max(t1 - t0, 1e-6)
                return (round(x_start + frac * (x_end - x_start)), y)
        return None

    def order(t: float) -> str | None:
        if behind_window[0] <= t <= behind_window[1]:
            return "behind"
        if front_window[0] <= t <= front_window[1]:
            return "front"
        return None

    return Scene(scale=scale, at=at, offset_s=offset_s, paste_order=order, **scene_kwargs)


def synchronised_pullups_scene(
    scale: float = 0.90, at: tuple[int, int] = (250, 140), offset_s: float = 9.0, **scene_kwargs,
) -> Scene:
    """The neighbour at (approximately) layout B's position, but started near the beginning of
    their own clip instead of 20s in -- their own pull-up-like activity at the rig, roughly
    concurrent with the athlete's pull-ups (the base clip's pull-up phase is its first ~24s,
    plan section 4.1). This is the group-class start.

    `offset_s=9.0` is judgement, not measurement (Appendix A): the neighbour clip has no
    independent phase labels the way the base clip does. A contact sheet shows an instructional
    title card for the first ~9s of the neighbour clip and sustained activity at the rig from
    there; a jump-and-hang pull-up style means the hang itself is often above the cropped patch,
    so this was not verified rep-by-rep the way the base clip's pull-ups were. It is close enough
    for Phase 0's purpose -- ranking a fix against a same-time distractor -- but should not be
    read as a claim about exactly what movement the neighbour is performing at every frame.
    """
    return Scene(scale=scale, at=at, offset_s=offset_s, paste_order="behind", **scene_kwargs)
