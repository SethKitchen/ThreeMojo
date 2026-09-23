# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for an interpolation."""

from animation.keyframe_track import KeyframeTrack, POSITION
from core.object3d import NodeId
from units.si import Duration


def make(times: List[Duration]) raises -> KeyframeTrack:
    return KeyframeTrack(NodeId(0), POSITION, times, [0.0, 0.0, 0.0], 2)


def main() raises:
    print("unreachable")
