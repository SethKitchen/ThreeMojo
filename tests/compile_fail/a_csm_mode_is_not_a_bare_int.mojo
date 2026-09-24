# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for a CSM split mode."""

from cameras.perspective_camera import PerspectiveCamera
from core.scene import Scene
from lights.csm import CSM
from units.si import Angle, DEGREE, Length, METER


def main() raises:
    var scene = Scene()
    var camera = PerspectiveCamera(
        Angle(90.0, DEGREE), 1, Length(1.0, METER), Length(100.0, METER)
    )
    var csm = CSM(scene, camera, mode=1)
    print(csm.cascades)
