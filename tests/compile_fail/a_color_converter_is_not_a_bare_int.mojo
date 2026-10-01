# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A color conversion must be a `ColorConverter`, not a bare integer."""

from extensions.carla.image_convert import convert_pixel
from render.framebuffer import Color


def main() raises:
    var color = convert_pixel(Color(0, 0, 0), 1)
    print(color.r)
