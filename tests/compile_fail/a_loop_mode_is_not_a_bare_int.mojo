# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for a loop mode."""

from animation.animation_clip import AnimationClip
from animation.animation_mixer import AnimationAction


def make(var clip: AnimationClip) raises -> AnimationAction:
    return AnimationAction(clip^, 2)


def main() raises:
    print("unreachable")
