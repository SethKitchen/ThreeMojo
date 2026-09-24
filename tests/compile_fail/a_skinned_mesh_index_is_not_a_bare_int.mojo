# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for a skinned mesh index."""

from animation.keyframe_track import TrackTarget, skinned_morph_target


def make() raises -> TrackTarget:
    return skinned_morph_target(3, 0)


def main() raises:
    print("unreachable")
