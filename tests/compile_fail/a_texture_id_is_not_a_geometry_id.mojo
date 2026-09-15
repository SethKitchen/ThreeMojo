# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Reading a geometry with a texture's id must not compile.

Both are indices into an append-only store, and both are small integers. Only
the types keep them apart.
"""

from core.assets import Assets
from geometries.box import cube
from render.framebuffer import Color
from render.texture import checkerboard
from units.si import Length, METER


def main() raises:
    var assets = Assets()
    _ = assets.geometries.add(cube(Length(1.0, METER)))
    var board = assets.textures.add(
        checkerboard(4, 2, Color(255, 255, 255), Color(0, 0, 0))
    )
    var bad = assets.geometries.get(board)
    print(bad.triangle_count())
