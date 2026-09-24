# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for an orthographic camera index."""

from animation.keyframe_track import (
    CAMERA_ZOOM,
    TrackTarget,
    orthographic_camera_target,
)


def make() raises -> TrackTarget:
    return orthographic_camera_target(0, CAMERA_ZOOM)


def main() raises:
    print("unreachable")
