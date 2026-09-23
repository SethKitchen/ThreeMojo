# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for a light index."""

from animation.keyframe_track import LIGHT_INTENSITY, TrackTarget, light_target


def make() raises -> TrackTarget:
    return light_target(1, LIGHT_INTENSITY)


def main() raises:
    print("unreachable")
