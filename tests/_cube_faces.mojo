# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""One-color cube faces that the cube texture and environment suites share."""

from render.cube_texture import CubeTexture
from render.framebuffer import Color
from render.srgb import SRGB
from render.texture import CLAMP, NEAREST, Texture

comptime RED = Color(255, 0, 0)
comptime GREEN = Color(0, 255, 0)
comptime BLUE = Color(0, 0, 255)
comptime YELLOW = Color(255, 255, 0)
comptime CYAN = Color(0, 255, 255)
comptime MAGENTA = Color(255, 0, 255)


def face_colors() -> List[Color]:
    """Return the six face colors, in face order.

    Returns:
        Red, green, blue, yellow, cyan and magenta.
    """
    return [RED, GREEN, BLUE, YELLOW, CYAN, MAGENTA]


def solid(size: Int, color: Color) raises -> Texture:
    """Return a square texture of one color, clamped and nearest.

    Args:
        size: The side, in texels.
        color: The color of every texel.

    Returns:
        The texture.

    Raises:
        Error: If the texture refuses its size.
    """
    var pixels = List[UInt8]()
    for _ in range(size * size):
        pixels.append(color.r)
        pixels.append(color.g)
        pixels.append(color.b)
        pixels.append(color.a)
    return Texture(size, size, pixels^, CLAMP, NEAREST, SRGB, False)


def a_cube() raises -> CubeTexture:
    """Return a cube of six flat 2x2 faces in the colors of `face_colors`.

    Returns:
        The cube.

    Raises:
        Error: If the cube refuses its faces.
    """
    var faces = List[Texture]()
    for color in face_colors():
        faces.append(solid(2, color))
    return CubeTexture(faces^)
