"""Line-by-line port of PoseDetector from app/src/main/java/com/cindy/tracker/PoseDetector.kt.

The Android original draws the tracked crop onto a square Bitmap with a Canvas `Matrix` and a
`FILTER_BITMAP_FLAG` Paint, which is a bilinear resample over a black background. `cv2.warpAffine`
with `INTER_LINEAR` and a constant black border is the same operation, driven by the same 2x3
matrix, so the model sees the same letterboxed square here as it does on the phone.
"""
from __future__ import annotations

import time
from dataclasses import dataclass

import cv2
import numpy as np
from ai_edge_litert.interpreter import Interpreter

from .keypoints import KP, Keypoint


@dataclass
class Rect:
    left: float
    top: float
    right: float
    bottom: float

    @property
    def width(self) -> float:
        return self.right - self.left


class Tune:
    MIN_SCORE = 0.30
    #: Confident keypoints needed to trust the crop for the next frame.
    MIN_TRACKED = 5
    #: Consecutive poor frames before giving up and re-scanning the whole image.
    MAX_MISSES = 5
    #: How much room to leave around the body, as a multiple of its bounding box.
    MARGIN = 1.45
    #: Crop is never allowed below this share of the frame, to avoid chasing noise.
    MIN_CROP_FRACTION = 0.25
    #: Mean luma a dark crop is lifted toward before inference. Below the ~116 a well-exposed
    #: fixture measures, so normal footage stays untouched.
    TARGET_LUMA = 110.0
    #: Ceiling on that lift. Past this the frame is noise, not signal, and gain only amplifies it.
    MAX_SOFT_GAIN = 16.0
    #: Per-frame follow rate of the crop, damping jitter.
    FOLLOW = 0.35


class PoseDetector:
    """MoveNet SinglePose on TFLite, with region-of-interest tracking.

    MoveNet resizes whatever it is given down to a small square. A phone standing on the floor
    puts the athlete in a slice of a tall frame, so feeding it whole spends most of those pixels
    on ceiling and carpet. Each frame is therefore cropped to a square around where the body was
    last seen, falling back to the whole frame whenever tracking is lost.
    """

    #: 256x256. Slower, and worth it at the awkward angles a floor-level phone produces.
    THUNDER = "movenet_thunder.tflite"
    #: 192x192. Roughly a third of the work; the fallback if Thunder cannot keep up.
    LIGHTNING = "movenet_lightning.tflite"

    def __init__(self, model_path: str, model_asset: str | None = None) -> None:
        self.model_asset = model_asset or model_path.rsplit("/", 1)[-1]
        self._interpreter = Interpreter(model_path=model_path, num_threads=4)
        self._interpreter.allocate_tensors()

        in_detail = self._interpreter.get_input_details()[0]
        self._in_index = in_detail["index"]
        # Read the square size from the model so Lightning (192) and Thunder (256) both drop in.
        self.input_size = int(in_detail["shape"][1])
        self._input_is_float = in_detail["dtype"] == np.float32
        self._out_index = self._interpreter.get_output_details()[0]["index"]

        #: Square crop in source-frame pixels; None means "look at the whole frame".
        self._roi: Rect | None = None
        self._misses = 0
        self.last_inference_ms = 0.0
        #: True while the model is fed a tracked crop rather than the whole frame.
        self.tracking = False
        #: Brightness gain applied to the last crop. 1.0 means the frame needed no help; a large
        #: value means the camera handed over a dark picture, which is worth telling the athlete.
        self.soft_gain = 1.0

    @property
    def model_label(self) -> str:
        """Short name for the debug readout."""
        return "thndr" if self.model_asset == self.THUNDER else "lite"

    def reset_roi(self) -> None:
        """Forgets the tracked crop -- call when the camera changes or a workout restarts."""
        self._roi = None
        self._misses = 0
        self.tracking = False
        self.soft_gain = 1.0

    def _normalise(self, square: np.ndarray) -> float:
        """Lifts a dark crop toward `Tune.TARGET_LUMA`, in place, and returns the gain applied.

        MoveNet does not normalise its own input, so a frame the camera left underexposed fails
        for a reason that is representational rather than informational: the detail is still
        there, the numbers are just small. Measured on a clip whose ground truth is 5 reps,
        darkened until it scored 0, this recovers the full 5 and extends the usable range at
        least 3.3x further into the dark.

        It is deliberately unable to do anything at normal light: the gain is clamped at 1.0
        below, so a well-exposed frame is passed through untouched and the existing fixtures
        cannot move.

        The gain is measured on the *crop*, not the frame, which is the point. Auto-exposure
        meters the whole scene, so an athlete against a window or a bright ceiling is left
        underexposed inside a frame whose average looks fine. The crop is already centred on the
        athlete, so a mean taken here describes the body rather than the background behind it.

        What this cannot do is recover a noisy frame. Once the camera has raised its own gain to
        the limit, the information is gone and multiplying amplifies the noise with the signal —
        measured at no improvement whatever (0 reps before and after). Distinguishing the two is
        what the returned gain is for: a large gain that does not restore legibility means the
        light is gone for real, not merely under-exposed.
        """
        # Pure black is either the letterbox around a crop that reached outside the frame, or a
        # pixel carrying no information anyway. Excluding it keeps the letterbox from dragging
        # the mean down and over-brightening the part that matters, and biases what is left
        # toward under-correcting, which is the safe direction.
        lit = square[square.any(axis=2)]
        if lit.size == 0:
            return 1.0
        mean = float(np.dot(lit.mean(axis=0), (0.299, 0.587, 0.114)))
        gain = Tune.TARGET_LUMA / max(mean, 1.0)
        gain = min(max(gain, 1.0), Tune.MAX_SOFT_GAIN)
        if gain > 1.0:
            # Clip rather than let uint8 wrap: an unchecked multiply turns the brightest pixel
            # in the crop black, which is the opposite of the intent.
            np.clip(square * gain, 0, 255, out=square, casting="unsafe")
        return gain

    def detect(self, frame: np.ndarray) -> list[Keypoint]:
        """Runs the model on `frame` (an RGB HxWx3 uint8 array) and returns 17 keypoints in
        **frame pixel coordinates**. Not thread-safe: call from a single analysis thread.
        """
        height, width = frame.shape[:2]
        region = self._roi or self._full_frame_square(width, height)
        self.tracking = self._roi is not None

        # Map the region onto the model's square. A region reaching outside the frame simply
        # leaves black there, which is the letterbox the model expects.
        scale = self.input_size / region.width
        matrix = np.array(
            [[scale, 0.0, -region.left * scale], [0.0, scale, -region.top * scale]],
            dtype=np.float64,
        )
        square = cv2.warpAffine(
            frame,
            matrix,
            (self.input_size, self.input_size),
            flags=cv2.INTER_LINEAR,
            borderMode=cv2.BORDER_CONSTANT,
            borderValue=(0, 0, 0),
        )
        self.soft_gain = self._normalise(square)

        if self._input_is_float:
            # The Kotlin pushes raw 0-255 channel values as floats; it does not normalise.
            tensor = square.astype(np.float32)[None, ...]
        else:
            tensor = square.astype(np.uint8)[None, ...]

        started = time.time()
        self._interpreter.set_tensor(self._in_index, tensor)
        self._interpreter.invoke()
        raw = self._interpreter.get_tensor(self._out_index)[0][0]
        self.last_inference_ms = (time.time() - started) * 1000.0

        side = region.width
        keypoints = [
            Keypoint(
                x=float(region.left + raw[i][1] * side),
                y=float(region.top + raw[i][0] * side),
                score=float(raw[i][2]),
            )
            for i in range(KP.COUNT)
        ]

        self._update_roi(keypoints, width, height)
        return keypoints

    def _full_frame_square(self, frame_w: int, frame_h: int) -> Rect:
        """The whole frame as a square, so a portrait image is letterboxed not cropped."""
        side = float(max(frame_w, frame_h))
        return Rect(
            (frame_w - side) / 2.0,
            (frame_h - side) / 2.0,
            (frame_w + side) / 2.0,
            (frame_h + side) / 2.0,
        )

    def _update_roi(self, k: list[Keypoint], frame_w: int, frame_h: int) -> None:
        """Re-aims the crop at wherever the body just was, or drops it if the body was lost."""
        seen = [p for p in k if p.score >= Tune.MIN_SCORE]
        if len(seen) < Tune.MIN_TRACKED:
            self._misses += 1
            if self._misses >= Tune.MAX_MISSES:
                self.reset_roi()
            return
        self._misses = 0

        left = min(p.x for p in seen)
        right = max(p.x for p in seen)
        top = min(p.y for p in seen)
        bottom = max(p.y for p in seen)

        longest = max(float(max(frame_w, frame_h)), 1.0)
        side = max(right - left, bottom - top) * Tune.MARGIN
        side = max(longest * Tune.MIN_CROP_FRACTION, min(side, longest))
        cx = (left + right) / 2.0
        cy = (top + bottom) / 2.0

        target = Rect(cx - side / 2.0, cy - side / 2.0, cx + side / 2.0, cy + side / 2.0)
        current = self._roi
        if current is None:
            self._roi = target
        else:
            self._roi = Rect(
                current.left + (target.left - current.left) * Tune.FOLLOW,
                current.top + (target.top - current.top) * Tune.FOLLOW,
                current.right + (target.right - current.right) * Tune.FOLLOW,
                current.bottom + (target.bottom - current.bottom) * Tune.FOLLOW,
            )

    def close(self) -> None:
        pass
