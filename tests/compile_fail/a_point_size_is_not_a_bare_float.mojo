# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare float must not stand in for a point size in pixels."""

from materials.material import points_material
from render.framebuffer import Color


def main() raises:
    var material = points_material(Color(255, 0, 0), size=4.0)
    print(material.size_attenuation)
