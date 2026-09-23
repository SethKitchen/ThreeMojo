# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for an ending mode."""

from animation.keyframe_track import KeyframeTrack
from units.si import Duration


def read(track: KeyframeTrack, at: Duration) raises -> List[Float32]:
    return track.sample(at, 1, 1)


def main() raises:
    print("unreachable")
