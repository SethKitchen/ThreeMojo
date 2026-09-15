# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for a material side."""

from materials.material import NO_TEXTURE, Material
from render.framebuffer import Color


def main() raises:
    var bad = Material(Color(1, 2, 3), NO_TEXTURE, 2)
    print(bad.opacity)
