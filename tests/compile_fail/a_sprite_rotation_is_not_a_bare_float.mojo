# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare float must not stand in for a sprite's rotation."""

from materials.material import sprite_material
from render.framebuffer import Color


def main() raises:
    var material = sprite_material(Color(255, 0, 0), rotation=1.5)
    print(material.size_attenuation)
