# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for a motion vector space."""

from extensions.streamline.constants import CameraSnapshot, frame_constants
from extensions.streamline.sizing import FrameSize
from math.matrix4 import Matrix4
from math.vector2 import Vector2
from units.si import Length, METER


def main() raises:
    var camera = CameraSnapshot(
        Matrix4(), Matrix4(), Length(0.1, METER), Length(1.0, METER)
    )
    var constants = frame_constants(
        camera, camera, FrameSize(64, 36), Vector2(0, 0), 1, False
    )
    print(constants.reset)
