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

    @property
    def model_label(self) -> str:
        """Short name for the debug readout."""
        return "thndr" if self.model_asset == self.THUNDER else "lite"

    def reset_roi(self) -> None:
        """Forgets the tracked crop -- call when the camera changes or a workout restarts."""
        self._roi = None
        self._misses = 0
        self.tracking = False

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
