# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for the lights a material names: build
the mask with `lights_of`."""

from materials.material import Material
from render.framebuffer import Color


def main() raises:
    var material = Material(Color(255, 255, 255))
    material.lights = 3
    print(material.lights.bits)
