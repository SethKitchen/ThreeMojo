# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for the kind of a VXGI light record."""

from core.object3d import NO_PARENT
from lights.light import directional_light
from lights.vxgi_volume import light_record
from math.vector3 import Vector3
from render.framebuffer import Color


def main() raises:
    var sun = directional_light(Color(255, 255, 255), NO_PARENT)
    print(len(light_record(0, Vector3(0, 0, 0), Vector3(0, 1, 0), sun)))
