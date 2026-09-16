# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for an alpha mode."""

from render.srgb import SRGB
from render.texture import NEAREST, REPEAT, Texture


def main() raises:
    var pixels = List[UInt8](length=4, fill=255)
    var bad = Texture(1, 1, pixels^, REPEAT, NEAREST, SRGB, False, 1)
    print(bad.width)
