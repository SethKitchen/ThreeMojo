# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare float must not stand in for a line width.

A width says whether it is in pixels or in the world, so a number alone
says too little: `LineWidth(pixels=...)` or `LineWidth(world=...)`.
"""

from materials.material import line_material
from render.framebuffer import Color


def main() raises:
    var material = line_material(Color(255, 0, 0), line_width=4.0)
    print(material.line_width.size)
