# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare color must not stand in for a scene background: say which of
the four kinds it is with `color_background`."""

from core.scene import Scene
from render.framebuffer import Color


def main() raises:
    var scene = Scene()
    scene.background = Color(30, 60, 90)
    print(scene.count())
