# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare float must not stand in for a rect area light's width: meters
and centimeters would be indistinguishable."""

from core.object3d import NodeId
from lights.light import rect_area_light
from render.framebuffer import Color


def main() raises:
    var bad = rect_area_light(Color(255, 255, 255), NodeId(0), width=4.0)
    print(bad.intensity)
