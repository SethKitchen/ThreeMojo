# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare float must not stand in for a focal length: three.js takes 50
and means millimeters, and nothing here says so."""

from cameras.perspective_camera import PerspectiveCamera
from units.si import Angle, DEGREE, Length, METER


def main() raises:
    var camera = PerspectiveCamera(
        Angle(50.0, DEGREE), 1.0, Length(0.1, METER), Length(100.0, METER)
    )
    camera.set_focal_length(50.0)
    print(camera.fov.value)
