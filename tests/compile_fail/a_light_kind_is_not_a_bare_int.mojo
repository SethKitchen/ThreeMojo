# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for a light kind."""

from lights.light import ambient_light
from render.framebuffer import Color


def main() raises:
    var bad = ambient_light(Color(1, 1, 1))
    bad.kind = 7
    print(bad.intensity)
