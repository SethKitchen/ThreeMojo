# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for what shapes a spot light's beam:
name `CONE_SPOT`, `IES_SPOT` or `PROJECTOR_SPOT`."""

from core.object3d import NodeId
from lights.light import spot_light
from render.framebuffer import Color


def main() raises:
    var light = spot_light(Color(255, 255, 255), NodeId(0))
    light.spot_shape = 2
    print(light.spot_shape.value)
