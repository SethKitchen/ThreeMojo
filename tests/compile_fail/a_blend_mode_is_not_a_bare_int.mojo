# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for an animation blend mode."""

from animation.animation_clip import AnimationClip
from animation.keyframe_track import KeyframeTrack


def make(var tracks: List[KeyframeTrack]) raises -> AnimationClip:
    return AnimationClip("clip", tracks^, 1)


def main() raises:
    print("unreachable")
