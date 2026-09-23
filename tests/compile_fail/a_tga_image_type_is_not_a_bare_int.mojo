# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for a TGA image type."""

from render.tga import unpack_pixels


def main() raises:
    var bytes = List[UInt8](length=3, fill=0)
    var pixels = unpack_pixels(2, bytes, 0, 1, 3)
    print(len(pixels))
