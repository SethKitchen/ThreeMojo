# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare float must not stand in for a dash length."""

from materials.material import line_dashed_material
from render.framebuffer import Color


def main() raises:
    var material = line_dashed_material(Color(255, 0, 0), dash_size=3.0)
    print(material.dash_scale)
