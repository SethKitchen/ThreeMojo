# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare float must not stand in for a displacement scale or bias."""

from materials.material import Material
from render.framebuffer import Color
from render.texture_store import TextureId


def main() raises:
    var material = Material(Color(255, 255, 255))
    material.set_displacement(TextureId(0), 0.5, 0.1)
    print(material.has_displacement_map())
