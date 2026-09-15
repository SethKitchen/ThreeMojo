# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for a light kind."""

from core.object3d import NO_PARENT
from lights.light import Light
from render.framebuffer import Color


def main() raises:
    var bad = Light(7, Color(1, 1, 1), 1.0, NO_PARENT, 0.0, 0.0)
    print(bad.intensity)
