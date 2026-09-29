"""Moves, scales and blinds the synthetic bodies in `pose_fixtures`, mirroring the JVM test
helper LockFixtures.kt. Kotlin does this arithmetic in Float, so every result goes through `f32`.
Unseen keypoints are left where they are: they carry no position.
"""
from __future__ import annotations

from typing import Sequence

from .keypoints import Keypoint
from .rep_counter import f32


def moved(k: Sequence[Keypoint], dx: float, dy: float) -> list[Keypoint]:
    return [Keypoint(f32(p.x + dx), f32(p.y + dy), p.score) if p.score > 0 else p for p in k]


def scaled(k: Sequence[Keypoint], factor: float) -> list[Keypoint]:
    return [Keypoint(f32(p.x * factor), f32(p.y * factor), p.score) if p.score > 0 else p for p in k]


def with_score(k: Sequence[Keypoint], score: float, *joints: int) -> list[Keypoint]:
    out = list(k)
    for j in joints:
        out[j] = Keypoint(out[j].x, out[j].y, f32(score))
    return out
