# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for a cube layout."""

from render.cube_texture import cube_texture_from
from render.png import DecodedImage


def main() raises:
    var images = List[DecodedImage]()
    var cube = cube_texture_from(images, layout=1)
    print(cube.size)
